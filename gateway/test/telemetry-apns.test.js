// Real app <-> server latency (arrival telemetry, APNs bursts for device test T5) and the
// checks that stand between the gateway and real APNs (provider token, config errors).
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHmac, createPublicKey, generateKeyPairSync, verify } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import http from "node:http";
import http2 from "node:http2";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test, { mock } from "node:test";

import { createServer, loadConfig, monitorSignature, sensorKey } from "../src/server.js";

const SECRET = "test-secret";
const MONITOR_KEY = "monitor-key";
const KEY_PAIR = generateKeyPairSync("ec", { namedCurve: "P-256" });
const PRIVATE_KEY = KEY_PAIR.privateKey.export({ type: "pkcs8", format: "pem" });
const PHONE = "ab".repeat(32);
const OTHER_PHONE = "cd".repeat(32);
const SERVER_FILE = fileURLToPath(new URL("../src/server.js", import.meta.url));
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

// Fake APNs over cleartext HTTP/2; `answer` replies. Coverage pushes (a phone joining a sensor
// with no heartbeat hears "lost") always get 200 and stay out of `pushes`.
async function startApns(t, answer = stream => { stream.respond({ ":status": 200 }); stream.end(); }) {
  const apns = { pushes: [] };
  const server = http2.createServer();
  server.on("stream", (stream, headers) => {
    let body = "";
    stream.on("error", () => {});
    stream.on("data", chunk => { body += chunk; });
    stream.on("end", () => {
      const push = { token: headers[":path"].split("/").pop(), headers, payload: JSON.parse(body), at: Date.now(),
        session: stream.session };
      if (push.payload.kind === "coverage") {
        stream.respond({ ":status": 200 });
        stream.end();
        return;
      }
      apns.pushes.push(push);
      answer(stream, push);
    });
  });
  const sessions = new Set();
  server.on("session", session => sessions.add(session));
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise(resolve => {
    for (const session of sessions) session.destroy();
    server.close(resolve);
  }));
  apns.url = `http://127.0.0.1:${server.address().port}`;
  return apns;
}

const reject = (status, reason) => stream => {
  stream.respond({ ":status": status });
  stream.end(JSON.stringify({ reason }));
};

async function startGateway(t, overrides = {}) {
  const directory = await mkdtemp(join(tmpdir(), "relay-telemetry-"));
  const config = {
    hmacSecret: SECRET, teamId: "TEAM123456", keyId: "KEY1234567", bundleId: "com.example.relay",
    privateKey: PRIVATE_KEY, dryRun: false, monitorKey: MONITOR_KEY,
    evidenceFile: join(directory, "evidence.jsonl"), telemetryFile: join(directory, "telemetry.jsonl"),
    subscriptionsFile: join(directory, "subscriptions.json"), devicesFile: join(directory, "devices.json"),
    coverageFile: join(directory, "coverage.json"),
    sensors: [{ id: "chaparral", public: true }], vapid: null,
    ...overrides
  };
  const server = createServer(config);
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  t.after(() => rm(directory, { recursive: true, force: true, maxRetries: 5 }));
  return { config, directory, port: server.address().port };
}

function request(port, method, path, body = "", headers = {}) {
  return new Promise((resolve, rejectRequest) => {
    const outgoing = http.request({ hostname: "127.0.0.1", port, path, method, headers: {
      "content-type": "application/json", "content-length": Buffer.byteLength(body), ...headers } }, response => {
      let text = "";
      response.on("data", chunk => { text += chunk; });
      response.on("end", () => resolve({ status: response.statusCode, body: text }));
    });
    outgoing.on("error", rejectRequest);
    outgoing.end(body);
  });
}

function signed(port, method, path, payload) {
  const body = payload === undefined ? "" : JSON.stringify(payload);
  const timestamp = String(Math.floor(Date.now() / 1000));
  return request(port, method, path, body, {
    "x-monitor-timestamp": timestamp,
    "x-monitor-signature": monitorSignature(MONITOR_KEY, timestamp, method, path, body)
  });
}

const register = (port, token, extra = {}) => request(port, "POST", "/devices",
  JSON.stringify({ device_token: token, sensor_ids: ["chaparral"], platform: "ios", ...extra }));
const optIn = (port, token, enabled = true) =>
  signed(port, "POST", "/devices/telemetry", { device_token: token, enabled });
const upload = (port, token, arrivals) =>
  request(port, "POST", "/telemetry/arrivals", JSON.stringify({ device_token: token, arrivals }));
const burst = (port, token, n, intervalMs) =>
  signed(port, "POST", "/probe/apns-burst", { device_token: token, n, interval_ms: intervalMs });
const lines = async file => (await readFile(file, "utf8").catch(() => "")).split("\n").filter(Boolean)
  .map(line => JSON.parse(line));

function arrival(overrides = {}) {
  return { kind: "alert", event_id: "chaparral:t1:alert", sent_at_ms: 1_790_000_000_000,
    received_at_ms: 1_790_000_000_420, source: "nse", app_state: "background", ...overrides };
}

/** `originAgoS` apart by more than 30 s is another quake, which the per-phone dedup lets through. */
function sendAlert(port, { sensorId = "chaparral", originAgoS = 17 } = {}) {
  const now = Date.now();
  const raw = JSON.stringify({
    event_id: `${sensorId}:t${now}:${Math.random()}:alert`, source: "android_earthquake_alert_candidate",
    sensor_id: sensorId, captured_at: new Date(now).toISOString(),
    expires_at: new Date(now + 180_000).toISOString(), title: "Alerta de sismo", body: "Sismo.",
    interruption_level: "time-sensitive", time_occurred_s: Math.floor(now / 1000) - originAgoS
  });
  return request(port, "POST", "/events", raw,
    { "x-relay-signature": createHmac("sha256", sensorKey(SECRET, sensorId)).update(raw).digest("hex") });
}

async function until(condition, timeoutMs = 5000) {
  for (const deadline = Date.now() + timeoutMs; Date.now() < deadline; await wait(10)) {
    if (await condition()) return;
  }
  throw new Error("condition never met");
}

// --- Arrival telemetry -------------------------------------------------------------------

test("telemetry is switched on by the monitor key only, and survives the app re-registering", async t => {
  const apns = await startApns(t);
  const { port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE);

  const unsigned = await request(port, "POST", "/devices/telemetry",
    JSON.stringify({ device_token: PHONE, enabled: true }));
  const unknown = await optIn(port, OTHER_PHONE);
  const badFlag = await signed(port, "POST", "/devices/telemetry", { device_token: PHONE, enabled: "yes" });
  const selfEnabled = await register(port, PHONE, { telemetry: true });
  const on = await optIn(port, PHONE);
  const reRegistered = await register(port, PHONE);
  await optIn(port, PHONE, false);
  const afterOff = await register(port, PHONE);

  assert.equal(unsigned.status, 401);
  assert.deepEqual([unknown.status, JSON.parse(unknown.body)], [404, { error: "unknown device_token" }]);
  assert.equal(badFlag.status, 400);
  assert.equal(JSON.parse(selfEnabled.body).telemetry, undefined, "the app turned telemetry on itself");
  assert.deepEqual([on.status, JSON.parse(on.body)], [200, { telemetry: true }]);
  assert.equal(JSON.parse(reRegistered.body).telemetry, true, "re-registering dropped the opt-in");
  assert.equal(JSON.parse(afterOff.body).telemetry, undefined);
});

test("arrivals: stored append-only with the latency, deduped on (event_id, source), token kept out", async t => {
  const apns = await startApns(t);
  const { config, port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE);
  await register(port, OTHER_PHONE);
  await optIn(port, PHONE);

  const notOptedIn = await upload(port, OTHER_PHONE, [arrival()]);
  const unknown = await upload(port, "ef".repeat(32), [arrival()]);
  const first = await upload(port, PHONE, [arrival(), arrival({ source: "app", app_state: "foreground",
    received_at_ms: 1_790_000_000_900 })]);
  const again = await upload(port, PHONE, [arrival(), arrival({ kind: "test", event_id: "test:1" })]);

  assert.deepEqual([notOptedIn.status, JSON.parse(notOptedIn.body)],
    [404, { error: "unknown device_token or telemetry off" }]);
  assert.deepEqual(JSON.parse(unknown.body), JSON.parse(notOptedIn.body), "a guessed token learns something");
  assert.deepEqual([first.status, JSON.parse(first.body)], [202, { stored: 2, duplicates: 0 }]);
  assert.deepEqual([again.status, JSON.parse(again.body)], [202, { stored: 1, duplicates: 1 }]);
  const stored = await lines(config.telemetryFile);
  assert.deepEqual(stored.map(({ at, ...rest }) => rest), [
    { type: "ARRIVAL", token_suffix: PHONE.slice(-8), kind: "alert", event_id: "chaparral:t1:alert", source: "nse",
      app_state: "background", sent_at_ms: 1_790_000_000_000, received_at_ms: 1_790_000_000_420, latency_ms: 420 },
    { type: "ARRIVAL", token_suffix: PHONE.slice(-8), kind: "alert", event_id: "chaparral:t1:alert", source: "app",
      app_state: "foreground", sent_at_ms: 1_790_000_000_000, received_at_ms: 1_790_000_000_900, latency_ms: 900 },
    { type: "ARRIVAL", token_suffix: PHONE.slice(-8), kind: "test", event_id: "test:1", source: "nse",
      app_state: "background", sent_at_ms: 1_790_000_000_000, received_at_ms: 1_790_000_000_420, latency_ms: 420 }
  ]);
  assert.ok(stored.every(record => Number.isFinite(Date.parse(record.at))));
  assert.ok(!(await readFile(config.telemetryFile, "utf8")).includes(PHONE), "the full token was stored");
  assert.deepEqual(await lines(config.evidenceFile), [], "arrivals went into the alert evidence");

  const page = await signed(port, "GET", "/telemetry?since=1970-01-01T00:00:00.000Z");
  assert.equal(page.status, 200);
  assert.deepEqual(JSON.parse(page.body).records.map(record => record.event_id),
    ["chaparral:t1:alert", "chaparral:t1:alert", "test:1"]);
  assert.equal((await request(port, "GET", "/telemetry?since=1970-01-01T00:00:00.000Z")).status, 401);
});

test("arrivals: a bad item refuses the whole batch, 500 items fit, 501 do not", async t => {
  const apns = await startApns(t);
  const { config, port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE);
  await optIn(port, PHONE);

  const bad = [
    [], "x", [arrival({ kind: "coverage" })], [arrival({ source: "widget" })],
    [arrival({ app_state: "suspended" })], [arrival({ event_id: "" })], [arrival({ event_id: "e".repeat(201) })],
    [arrival({ sent_at_ms: null })], [arrival({ received_at_ms: 1.5 })], [arrival({ sent_at_ms: -1 })],
    [arrival(), null]
  ];
  for (const arrivals of bad) {
    const answer = await upload(port, PHONE, arrivals);
    assert.deepEqual([answer.status, JSON.parse(answer.body)], [400, { error: "invalid arrivals" }],
      JSON.stringify(arrivals).slice(0, 80));
  }
  assert.deepEqual(await lines(config.telemetryFile), [], "part of a refused batch was stored");

  const full = Array.from({ length: 500 }, (_, index) =>
    arrival({ event_id: `probe:00000000-0000-0000-0000-000000000000:${index}`, kind: "probe" }));
  const fits = await upload(port, PHONE, full);
  const tooMany = await upload(port, PHONE, [...full, arrival({ event_id: "one-more" })]);
  assert.ok(JSON.stringify({ device_token: PHONE, arrivals: full }).length > 16_384, "the test proves nothing");
  assert.deepEqual([fits.status, JSON.parse(fits.body)], [202, { stored: 500, duplicates: 0 }]);
  assert.equal(tooMany.status, 400);
});

test("arrivals: rate-limited per phone, and a failed write is retried, not deduped away", async t => {
  const apns = await startApns(t);
  const { config, directory, port } = await startGateway(t,
    { apnsHost: apns.url, telemetryFile: join(tmpdir(), "no-such-dir-telemetry", "telemetry.jsonl") });
  await register(port, PHONE);
  await optIn(port, PHONE);
  const errors = mock.method(console, "error", () => {});
  t.after(() => mock.restoreAll());

  const failed = await upload(port, PHONE, [arrival()]);
  assert.deepEqual([failed.status, JSON.parse(failed.body)], [503, { error: "telemetry not stored" }]);
  assert.ok(errors.mock.calls.some(call => /telemetry write failed/.test(call.arguments[0])));

  config.telemetryFile = join(directory, "telemetry.jsonl");
  const retried = await upload(port, PHONE, [arrival()]);
  assert.deepEqual(JSON.parse(retried.body), { stored: 1, duplicates: 0 }, "the failed upload was marked seen");

  let answers = [];
  for (let index = 0; index < 120; index += 1) {
    answers.push((await upload(port, PHONE, [arrival({ event_id: `e${index}` })])).status);
  }
  answers = [...new Set(answers)];
  // 1 failed + 1 retried + 118 more are the 120 of the window.
  assert.deepEqual(answers, [202, 429]);
  const limited = await upload(port, PHONE, [arrival({ event_id: "late" })]);
  assert.deepEqual([limited.status, JSON.parse(limited.body)], [429, { error: "too many uploads" }]);
});

test("arrivals stay out of the alert path: a broken telemetry file does not touch an alert", async t => {
  const apns = await startApns(t);
  const { port } = await startGateway(t,
    { apnsHost: apns.url, telemetryFile: join(tmpdir(), "no-such-dir-telemetry", "telemetry.jsonl") });
  mock.method(console, "error", () => {});
  t.after(() => mock.restoreAll());
  await register(port, PHONE);
  await optIn(port, PHONE);

  const uploads = Promise.all(Array.from({ length: 20 }, (_, index) =>
    upload(port, PHONE, [arrival({ event_id: `e${index}` })])));
  const sent = await sendAlert(port);
  await uploads;
  await until(() => apns.pushes.some(push => push.payload.kind === "alert"));

  assert.equal(sent.status, 202);
});

// --- APNs burst (device test T5) ---------------------------------------------------------

test("apns-burst: n pushes paced by interval_ms, each its own event_id and sent_at_ms, then evidence", async t => {
  const apns = await startApns(t);
  const { config, port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE);
  await optIn(port, PHONE);
  // The user's test button was just used: the burst is not held to its 10 min.
  await request(port, "POST", "/devices/test", JSON.stringify({ device_token: PHONE }));

  const answer = await burst(port, PHONE, 3, 1000);
  const busy = await burst(port, PHONE, 1, 1000);
  assert.equal(answer.status, 202);
  const { probe_id: probeId, n, interval_ms: intervalMs } = JSON.parse(answer.body);
  assert.match(probeId, /^[0-9a-f-]{36}$/);
  assert.deepEqual([n, intervalMs], [3, 1000]);
  assert.deepEqual([busy.status, JSON.parse(busy.body)], [409, { error: "burst already running" }]);

  const record = await (async () => {
    let found;
    await until(async () => {
      found = (await lines(config.evidenceFile)).find(entry => entry.type === "APNS_BURST");
      return found;
    }, 6000);
    return found;
  })();
  const pushes = apns.pushes.filter(push => push.payload.kind === "probe");
  assert.equal(pushes.length, 3);
  pushes.forEach((push, index) => {
    const seq = index + 1;
    const { sent_at_ms: sentAtMs, ...rest } = push.payload;
    assert.deepEqual(rest, {
      aps: { alert: { title: "Prueba de entrega", body: `Prueba ${seq} de 3. No es un sismo.` },
        sound: "default", "interruption-level": "active", "mutable-content": 1 },
      kind: "probe", event_id: `probe:${probeId}:${seq}`, probe_id: probeId, seq
    });
    assert.ok(Math.abs(push.at - sentAtMs) < 200, "sent_at_ms is not the send time");
    assert.equal(push.headers["apns-priority"], "10");
    assert.equal(push.headers["apns-push-type"], "alert");
    assert.equal(push.headers["apns-collapse-id"], `probe:${probeId}:${seq}`);
  });
  const gaps = pushes.slice(1).map((push, index) => push.payload.sent_at_ms - pushes[index].payload.sent_at_ms);
  assert.ok(gaps.every(gap => gap >= 990 && gap < 1300), `not paced: ${gaps}`);
  assert.deepEqual(
    { ...record, at: undefined, results: record.results.map(({ seq, event_id: id, status }) => ({ seq, id, status })) },
    { type: "APNS_BURST", at: undefined, probe_id: probeId, token_suffix: PHONE.slice(-8), n: 3, interval_ms: 1000,
      results: [1, 2, 3].map(seq => ({ seq, id: `probe:${probeId}:${seq}`, status: 200 })) });

  const next = await burst(port, PHONE, 1, 1000);
  assert.equal(next.status, 202, "a finished burst still blocks the phone");
});

test("apns-burst: monitor key and opt-in required, limits enforced, and it stops at a dead token", async t => {
  const apns = await startApns(t, reject(410, "Unregistered"));
  const { config, port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE);
  await register(port, OTHER_PHONE);
  await optIn(port, PHONE);

  const unsigned = await request(port, "POST", "/probe/apns-burst",
    JSON.stringify({ device_token: PHONE, n: 1, interval_ms: 1000 }));
  const notOptedIn = await burst(port, OTHER_PHONE, 1, 1000);
  const invalid = await Promise.all([[51, 1000], [0, 1000], [1.5, 1000], [1, 999], [1, 60_001], [1, "1000"]]
    .map(([count, interval]) => burst(port, PHONE, count, interval)));
  assert.equal(unsigned.status, 401);
  assert.equal(notOptedIn.status, 404);
  assert.deepEqual(invalid.map(answer => answer.status), [400, 400, 400, 400, 400, 400]);
  assert.equal(apns.pushes.length, 0);

  assert.equal((await burst(port, PHONE, 3, 1000)).status, 202);
  await until(async () => (await lines(config.evidenceFile)).some(entry => entry.type === "APNS_BURST"), 4000);
  assert.equal(apns.pushes.length, 1, "kept pushing to a token APNs called gone");
  assert.equal(JSON.parse(await readFile(config.devicesFile, "utf8"))[PHONE], undefined);
});

// --- Real APNs readiness -----------------------------------------------------------------

function decodeBearer(authorization) {
  const [header, claims, signature] = authorization.replace(/^bearer /, "").split(".");
  const valid = verify("sha256", Buffer.from(`${header}.${claims}`),
    { key: createPublicKey(PRIVATE_KEY), dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url"));
  return { header: JSON.parse(Buffer.from(header, "base64url")), claims: JSON.parse(Buffer.from(claims, "base64url")), valid };
}

test("provider token: ES256 signed by the .p8, reused within its TTL, a new one after it", async t => {
  const apns = await startApns(t);
  const { port } = await startGateway(t, { apnsHost: apns.url, providerTokenTtlMs: 1000 });
  await register(port, PHONE);

  await sendAlert(port);
  await sendAlert(port);
  await until(() => apns.pushes.filter(push => push.payload.kind === "alert").length === 1);
  await wait(1100);
  await sendAlert(port, { originAgoS: 60 });
  await until(() => apns.pushes.filter(push => push.payload.kind === "alert").length === 2);

  const bearers = apns.pushes.map(push => push.headers.authorization);
  const first = decodeBearer(bearers[0]);
  const last = decodeBearer(bearers.at(-1));
  assert.deepEqual(first.header, { alg: "ES256", kid: "KEY1234567" });
  assert.equal(first.claims.iss, "TEAM123456");
  assert.ok(Math.abs(first.claims.iat - Date.now() / 1000) < 5);
  assert.equal(first.valid, true, "not signed by the configured key");
  assert.equal(bearers[0], bearers.at(-2), "a new provider token per push: Apple throttles that");
  assert.notEqual(bearers[0], bearers.at(-1), "the provider token was never refreshed");
  assert.ok(last.claims.iat > first.claims.iat);
});

test("ExpiredProviderToken: one new token for all pushes in flight, and every phone still gets the alert", async t => {
  const tokens = Array.from({ length: 20 }, (_, index) => index.toString(16).padStart(2, "0").repeat(32));
  let firstBearer = null;
  const apns = await startApns(t, (stream, push) => {
    firstBearer ??= push.headers.authorization;
    if (push.headers.authorization === firstBearer) reject(403, "ExpiredProviderToken")(stream);
    else {
      stream.respond({ ":status": 200 });
      stream.end();
    }
  });
  const { config, port } = await startGateway(t, { apnsHost: apns.url });
  for (const token of tokens) await register(port, token);
  apns.pushes.length = 0;
  firstBearer = null;

  await sendAlert(port);
  let record;
  await until(async () => {
    record = (await lines(config.evidenceFile)).find(entry => entry.type === "WEB_PUSH_DISPATCH");
    return record;
  });

  assert.deepEqual(record.apns.map(result => result.status), tokens.map(() => 200));
  assert.equal(new Set(apns.pushes.map(push => push.headers.authorization)).size, 2,
    "each push in flight minted its own provider token");
});

test("DeviceTokenNotForTopic is our config: the phone is kept, the sensor degrades, the log says so once", async t => {
  const apns = await startApns(t, (stream, push) =>
    (push.token === PHONE ? reject(400, "DeviceTokenNotForTopic") : reject(410, "ExpiredToken"))(stream));
  const { config, port } = await startGateway(t, { apnsHost: apns.url });
  const errors = mock.method(console, "error", () => {});
  t.after(() => mock.restoreAll());
  await register(port, PHONE);
  await register(port, OTHER_PHONE);

  await sendAlert(port);
  await until(async () => (await lines(config.evidenceFile)).length === 1);
  await sendAlert(port, { originAgoS: 60 });
  await until(async () => (await lines(config.evidenceFile)).length === 2);

  const stored = JSON.parse(await readFile(config.devicesFile, "utf8"));
  assert.deepEqual(Object.keys(stored), [PHONE], "a config error deleted the phone, or ExpiredToken kept one");
  const status = JSON.parse((await request(port, "GET", "/status")).body).sensors[0];
  assert.equal(status.covered_apns, false, "a config error left the sensor green");
  const configLogs = errors.mock.calls.filter(call => /APNs rejects our configuration \(DeviceTokenNotForTopic\)/
    .test(call.arguments[0]));
  assert.equal(configLogs.length, 1);
});

// --- Startup ------------------------------------------------------------------------------

const baseEnv = { RELAY_HMAC_SECRET: "s", APNS_TEAM_ID: "TEAM123456", APNS_KEY_ID: "KEY1234567",
  APNS_BUNDLE_ID: "co.example.alertas" };

test("startup refuses a missing or broken APNs config instead of running blind", async t => {
  const directory = await mkdtemp(join(tmpdir(), "relay-config-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const keyFile = join(directory, "AuthKey_KEY1234567.p8");
  await writeFile(keyFile, PRIVATE_KEY);
  const rsaKey = generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey.export({ type: "pkcs8", format: "pem" });
  const p256k1Key = generateKeyPairSync("ec", { namedCurve: "secp256k1" }).privateKey
    .export({ type: "pkcs8", format: "pem" });

  const refusals = [
    [{}, /missing APNS_PRIVATE_KEY/],
    [{ APNS_PRIVATE_KEY: "not a key" }, /invalid APNS private key/],
    [{ APNS_PRIVATE_KEY: rsaKey }, /not an Apple \.p8/],
    [{ APNS_PRIVATE_KEY: p256k1Key }, /not an Apple \.p8/],
    [{ APNS_PRIVATE_KEY: PRIVATE_KEY, APNS_TEAM_ID: "unset" }, /invalid APNS_TEAM_ID/],
    [{ APNS_PRIVATE_KEY: PRIVATE_KEY, APNS_KEY_ID: "key1234567" }, /invalid APNS_KEY_ID/],
    [{ APNS_PRIVATE_KEY: PRIVATE_KEY, APNS_BUNDLE_ID: "unset" }, /invalid APNS_BUNDLE_ID/],
    [{ APNS_PRIVATE_KEY_FILE: join(directory, "missing.p8") }, /ENOENT/],
    [{ APNS_PRIVATE_KEY: PRIVATE_KEY, APNS_PRIVATE_KEY_FILE: keyFile }, /not both/]
  ];
  for (const [env, error] of refusals) {
    assert.throws(() => loadConfig({ ...baseEnv, ...env }), error, JSON.stringify(Object.keys(env)));
  }

  assert.equal(loadConfig({ ...baseEnv, APNS_PRIVATE_KEY_FILE: keyFile }).privateKey, PRIVATE_KEY);
  const inline = loadConfig({ ...baseEnv, APNS_PRIVATE_KEY: PRIVATE_KEY.replaceAll("\n", "\\n") });
  assert.equal(inline.privateKey, PRIVATE_KEY, "the systemd-style \\n escapes were not undone");
  const lab = loadConfig({ ...baseEnv, APNS_DRY_RUN: "1", APNS_TEAM_ID: "unset", APNS_BUNDLE_ID: "unset" });
  assert.equal(lab.dryRun, true, "the lab's dry-run env file no longer starts");
});

test("the gateway process exits loudly on a broken key, and /status says when APNs is a dry run", async t => {
  const started = spawnSync(process.execPath, [SERVER_FILE], {
    env: { ...baseEnv, PATH: process.env.PATH, APNS_PRIVATE_KEY: "garbage", PORT: "0" }, encoding: "utf8", timeout: 10_000
  });
  assert.notEqual(started.status, 0, "it started with a broken key");
  assert.match(started.stderr, /invalid APNS private key/);

  const { port } = await startGateway(t, { dryRun: true });
  assert.equal(JSON.parse((await request(port, "GET", "/status")).body).apns_dry_run, true);
  const live = await startGateway(t);
  assert.equal(JSON.parse((await request(live.port, "GET", "/status")).body).apns_dry_run, false);
});

// --- Scale -----------------------------------------------------------------------------------

test("the fanout spreads over 8 APNs connections", async t => {
  const apns = await startApns(t);
  const sessions = new Set();
  const { port } = await startGateway(t, { apnsHost: apns.url });
  const tokens = Array.from({ length: 16 }, (_, index) => (index + 16).toString(16).repeat(64).slice(0, 64));
  for (const token of tokens) await register(port, token);

  await sendAlert(port);
  await until(() => apns.pushes.filter(push => push.payload.kind === "alert").length === tokens.length);
  for (const push of apns.pushes) sessions.add(push.session);

  assert.equal(sessions.size, 8, "4 connections capped 100k pushes at 2.5 s of waiting (load.md)");
});

test("concurrent registrations all land in devices.json, each on disk before its 201", async t => {
  const apns = await startApns(t);
  const { config, port } = await startGateway(t, { apnsHost: apns.url });
  const tokens = Array.from({ length: 50 }, (_, index) => index.toString(16).padStart(64, "e"));

  await Promise.all(tokens.map(async (token, index) => {
    const answer = await request(port, "POST", "/devices", JSON.stringify({ device_token: token,
      sensor_ids: ["chaparral"], platform: "ios" }), { "x-forwarded-for": `10.0.0.${index}` });
    assert.equal(answer.status, 201);
    assert.ok(JSON.parse(await readFile(config.devicesFile, "utf8"))[token], "201 before the phone was on disk");
  }));

  assert.deepEqual(Object.keys(JSON.parse(await readFile(config.devicesFile, "utf8"))).sort(), [...tokens].sort());
});

// APNs per sensor: iPhones registered with POST /devices, alerts from signed sensor events.
// Failure paths where an alert is lost or pushed twice without anyone noticing; ids point
// to docs/qa/review.md.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHmac, generateKeyPairSync } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import http from "node:http";
import http2 from "node:http2";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { mock } from "node:test";

import webpush from "web-push";

import { createServer, quakeTag, sensorKey } from "../src/server.js";

const SECRET = "test-secret";
const PRIVATE_KEY = generateKeyPairSync("ec", { namedCurve: "P-256" })
  .privateKey.export({ type: "pkcs8", format: "pem" });
const PHONE = "ab".repeat(32);
const OTHER_PHONE = "cd".repeat(32);
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

/** Polls the evidence file until a record matches, instead of guessing a sleep. */
async function evidenceRecord(config, matches, timeoutMs = 5000) {
  for (const deadline = Date.now() + timeoutMs; Date.now() < deadline; await wait(10)) {
    const text = await readFile(config.evidenceFile, "utf8").catch(() => "");
    const found = text.trim().split("\n").filter(Boolean).map(line => JSON.parse(line)).find(matches);
    if (found) return found;
  }
  throw new Error("evidence record never written");
}

// Fake APNs over cleartext HTTP/2. `answer(stream, push)` replies; every push is recorded.
async function startApns(t, answer = stream => { stream.respond({ ":status": 200 }); stream.end(); }) {
  // Coverage pushes (QA-70 sends one on registration) are always answered 200 and kept in
  // `all`, so they never consume an answer a test scripted for its alerts.
  const apns = { pushes: [], all: [] };
  const server = http2.createServer();
  server.on("stream", (stream, headers) => {
    let body = "";
    stream.on("error", () => {});
    stream.on("data", chunk => { body += chunk; });
    stream.on("end", () => {
      const push = { token: headers[":path"].split("/").pop(), headers, payload: JSON.parse(body) };
      apns.all.push(push);
      if (push.payload.kind === "coverage") {
        stream.respond({ ":status": 200 });
        stream.end();
        return;
      }
      apns.pushes.push(push);
      answer(stream, push);
    });
  });
  // close() waits for open sessions, and the gateway keeps one alive on purpose.
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

async function startGateway(t, overrides) {
  const directory = await mkdtemp(join(tmpdir(), "relay-apns-"));
  const config = {
    hmacSecret: SECRET,
    teamId: "TEAM",
    keyId: "KEY",
    bundleId: "com.example.relay",
    privateKey: PRIVATE_KEY,
    dryRun: false,
    evidenceFile: join(directory, "evidence.jsonl"),
    subscriptionsFile: join(directory, "subscriptions.json"),
    devicesFile: join(directory, "devices.json"),
    coverageFile: join(directory, "coverage.json"),
    sensors: [{ id: "chaparral", public: true }, { id: "quibdo", public: true },
      { id: "bucaramanga-a", public: true }],
    vapid: null,
    ...overrides
  };
  const server = createServer(config);
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  // After the close (hooks run in order), with retries: a coverage check or evidence write
  // still in flight can add a file while the directory is removed (ENOTEMPTY on slow runners).
  t.after(() => rm(directory, { recursive: true, force: true, maxRetries: 5 }));
  return { config, port: server.address().port };
}

function request(port, method, path, body, headers = {}) {
  // Node only sends a DELETE body with an explicit length; URLSession always sets it.
  const length = body === undefined ? {} : { "content-length": Buffer.byteLength(body) };
  return new Promise((resolve, rejectRequest) => {
    const outgoing = http.request({ hostname: "127.0.0.1", port, path, method,
      headers: { "content-type": "application/json", ...length, ...headers } }, response => {
      let text = "";
      response.on("data", chunk => { text += chunk; });
      response.on("end", () => resolve({ status: response.statusCode, body: text }));
    });
    outgoing.on("error", rejectRequest);
    outgoing.end(body);
  });
}

function sendEvent(port, event) {
  const raw = JSON.stringify(event);
  const signature = createHmac("sha256", sensorKey(SECRET, event.sensor_id)).update(raw).digest("hex");
  return request(port, "POST", "/events", raw, { "x-relay-signature": signature });
}

const register = (port, token, sensorIds, extra = {}) => request(port, "POST", "/devices",
  JSON.stringify({ device_token: token, sensor_ids: sensorIds, platform: "ios", ...extra }));

const sensorStatus = async (port, id) =>
  JSON.parse((await request(port, "GET", "/status")).body).sensors.find(sensor => sensor.id === id);

function alertFrom(sensorId, overrides = {}) {
  const now = Date.now();
  return {
    event_id: `${sensorId}:t${now}:${Math.random()}:alert`,
    source: "android_earthquake_alert_candidate",
    sensor_id: sensorId,
    captured_at: new Date(now).toISOString(),
    expires_at: new Date(now + 180_000).toISOString(),
    title: "Alerta de sismo",
    body: "Sismo M4.5 cerca de su zona. Protéjase ahora.",
    interruption_level: "time-sensitive",
    magnitude: 4.5,
    distance_km: 19,
    time_occurred_s: Math.floor(now / 1000) - 17,
    ...overrides
  };
}

// Expires in 2 s, so the gateway's own retries (0, 0.5, 1 s) are over quickly.
const shortLived = sensorId => alertFrom(sensorId, { expires_at: new Date(Date.now() + 2_000).toISOString() });

test("/devices keeps only a valid token and its sensors, never a location", async t => {
  const { config, port } = await startGateway(t, { apnsHost: "http://127.0.0.1:1" });
  const invalid = [
    { device_token: PHONE, sensor_ids: ["chaparral"], platform: "android" },
    { device_token: "zz".repeat(32), sensor_ids: ["chaparral"], platform: "ios" },
    { device_token: "ab".repeat(31), sensor_ids: ["chaparral"], platform: "ios" },
    { device_token: PHONE, sensor_ids: [], platform: "ios" },
    { device_token: PHONE, sensor_ids: ["chaparral", "chaparral"], platform: "ios" },
    { device_token: PHONE, sensor_ids: ["atlantis"], platform: "ios" },
    { device_token: PHONE, sensor_ids: ["chaparral", "quibdo", "bucaramanga-a", "hinatuan"], platform: "ios" }
  ];
  for (const body of invalid) {
    assert.equal((await request(port, "POST", "/devices", JSON.stringify(body))).status, 400,
      JSON.stringify(body));
  }

  const accepted = await register(port, PHONE.toUpperCase(), ["chaparral", "quibdo"],
    { lat: 3.7236, lon: -75.4836 });
  assert.equal(accepted.status, 201);
  const replaced = await register(port, PHONE, ["quibdo"]);
  assert.deepEqual(JSON.parse(replaced.body).sensor_ids, ["quibdo"]);
  const stored = JSON.parse(await readFile(config.devicesFile, "utf8"));
  assert.deepEqual(Object.keys(stored), [PHONE], "token not lowercased, or stored twice");
  assert.deepEqual(stored[PHONE].sensor_ids, ["quibdo"], "the sensor set was not replaced");
  assert.doesNotMatch(JSON.stringify(stored), /"lat"|"lon"|3\.72|75\.48/);
});

test("an alert reaches only the phones following that sensor, with the agreed headers", async t => {
  const apns = await startApns(t);
  const { port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE, ["chaparral"]);
  await register(port, OTHER_PHONE, ["quibdo"]);
  const event = alertFrom("chaparral");

  const response = await sendEvent(port, event);
  await wait(150);

  assert.equal(response.status, 202);
  assert.equal(JSON.parse(response.body).queued, 1);
  assert.deepEqual(apns.pushes.map(push => push.token), [PHONE]);
  const [{ headers, payload }] = apns.pushes;
  assert.equal(headers["apns-push-type"], "alert");
  assert.equal(headers["apns-priority"], "10");
  assert.equal(headers["apns-topic"], "com.example.relay");
  assert.equal(headers["apns-collapse-id"], quakeTag(event.time_occurred_s * 1000));
  assert.equal(Number(headers["apns-expiration"]), Math.floor(Date.parse(event.expires_at) / 1000));
  assert.equal(payload.aps["interruption-level"], "time-sensitive");
  assert.equal(payload.aps["mutable-content"], 1);
  assert.deepEqual([payload.kind, payload.sensor_id, payload.late, payload.magnitude],
    ["alert", "chaparral", false, 4.5]);
});

test("a late alert reaches the phone as active, never time-sensitive", async t => {
  const apns = await startApns(t);
  const { port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE, ["chaparral"]);

  await sendEvent(port, alertFrom("chaparral", { time_occurred_s: Math.floor(Date.now() / 1000) - 150 }));
  await wait(150);

  const [{ payload }] = apns.pushes;
  assert.equal(payload.late, true);
  assert.equal(payload.aps["interruption-level"], "active");
  assert.doesNotMatch(payload.aps.alert.body, /Protéjase/);
  assert.deepEqual(payload.aps.alert, { title: "Aviso de sismo atrasado",
    body: "El sismo ocurrió hace 3 min. Ya no es un aviso anticipado.",
    "title-loc-key": "LATE_ALERT_TITLE", "loc-key": "LATE_ALERT_BODY", "loc-args": ["3"] });
});

test("a phone following two sensors that saw one quake is woken once", async t => {
  const apns = await startApns(t);
  const { port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE, ["chaparral", "quibdo"]);
  const origin = Math.floor(Date.now() / 1000) - 17;

  await sendEvent(port, alertFrom("chaparral", { time_occurred_s: origin }));
  await sendEvent(port, alertFrom("quibdo", { time_occurred_s: origin + 4 }));
  await wait(150);

  assert.equal(apns.pushes.length, 1, "woken once per sensor");
});

test("if one sensor's push fails, the same quake from another sensor still gets through", async t => {
  let first = true;
  const apns = await startApns(t, (stream, push) => {
    if (first) {
      first = false;
      reject(400, "BadMessageId")(stream, push);
      return;
    }
    stream.respond({ ":status": 200 });
    stream.end();
  });
  const { port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE, ["chaparral", "quibdo"]);
  const origin = Math.floor(Date.now() / 1000) - 17;

  await sendEvent(port, alertFrom("chaparral", { time_occurred_s: origin }));
  await wait(150);
  await sendEvent(port, alertFrom("quibdo", { time_occurred_s: origin }));
  await wait(150);

  assert.equal(apns.pushes.length, 2, "the failed quake stayed claimed");
});

test("a token APNs calls gone is deleted, whether by 410 or by reason", async t => {
  const apns = await startApns(t, (stream, push) =>
    (push.token === PHONE ? reject(410, "Unregistered") : reject(400, "BadDeviceToken"))(stream, push));
  const { config, port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE, ["chaparral"]);
  await register(port, OTHER_PHONE, ["chaparral"]);

  await sendEvent(port, alertFrom("chaparral"));
  await wait(150);
  await sendEvent(port, alertFrom("chaparral", { time_occurred_s: Math.floor(Date.now() / 1000) - 5 }));
  await wait(150);

  assert.equal(apns.pushes.length, 2, "a dead token was pushed to again");
  assert.deepEqual(JSON.parse(await readFile(config.devicesFile, "utf8")), {});
  assert.equal((await sensorStatus(port, "chaparral")).degraded_since, null, "uninstalls degraded it");
});

test("QA-01 APNs unreachable is a failed alert, not a dead gateway", async t => {
  const crashes = [];
  const onCrash = error => crashes.push(error);
  process.on("uncaughtException", onCrash);
  t.after(() => process.off("uncaughtException", onCrash));
  const { port } = await startGateway(t, { apnsHost: "http://127.0.0.1:1" });
  await register(port, PHONE, ["chaparral"]);

  await sendEvent(port, shortLived("chaparral"));
  await wait(2_200);

  assert.deepEqual(crashes.map(error => error.message), [], "gateway process would die");
  assert.notEqual((await sensorStatus(port, "chaparral")).degraded_since, null);
});

test("QA-02 APNs rejecting every phone marks the sensor degraded, without retrying a 403",
  async t => {
    const apns = await startApns(t, reject(403, "InvalidProviderToken"));
    const { port } = await startGateway(t, { apnsHost: apns.url });
    await register(port, PHONE, ["chaparral"]);

    await sendEvent(port, alertFrom("chaparral"));
    await wait(150);

    const status = await sensorStatus(port, "chaparral");
    assert.notEqual(status.degraded_since, null, "nobody got it and the page stays green");
    assert.equal(status.covered, false);
    assert.equal(apns.pushes.length, 1);
  });

test("QA-03 an APNs attempt that drops is retried by the gateway itself", async t => {
  let dropNext = true;
  const apns = await startApns(t, stream => {
    if (dropNext) {
      dropNext = false;
      stream.close(http2.constants.NGHTTP2_INTERNAL_ERROR);
      return;
    }
    stream.respond({ ":status": 200 });
    stream.end();
  });
  const { port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE, ["chaparral"]);

  await sendEvent(port, alertFrom("chaparral"));
  await wait(900);

  assert.equal(apns.pushes.length, 2);
  assert.equal((await sensorStatus(port, "chaparral")).degraded_since, null);
});

test("latency stamps: an APNs push is stamped when it leaves, not when APNs answers", async t => {
  const apns = await startApns(t, stream => setTimeout(() => { stream.respond({ ":status": 200 }); stream.end(); }, 150));
  const { config, port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE, ["chaparral"]);

  await sendEvent(port, alertFrom("chaparral"));
  await wait(400);

  const records = (await readFile(config.evidenceFile, "utf8")).trim().split("\n").map(line => JSON.parse(line));
  const dispatch = records.find(record => record.apns?.length);
  const [result] = dispatch.apns;
  assert.ok(Date.parse(dispatch.accepted_at) <= Date.parse(result.sent_at), JSON.stringify(dispatch));
  assert.ok(Date.parse(result.delivered_at) - Date.parse(result.sent_at) >= 140, JSON.stringify(result));
  // The NSE measures the APNs leg against it: the same instant, in the payload, per phone.
  const [push] = apns.pushes;
  assert.equal(push.payload.sent_at_ms, Date.parse(result.sent_at));
  assert.equal(push.payload.kind, "alert");
  assert.equal(push.payload.aps["mutable-content"], 1);
});

test("QA-04 a failed evidence write does not push twice when the sensor retries", async t => {
  const apns = await startApns(t);
  const { port } = await startGateway(t, {
    apnsHost: apns.url,
    evidenceFile: join(tmpdir(), "no-such-dir-relay-qa", "evidence.jsonl")
  });
  await register(port, PHONE, ["chaparral"]);
  const event = alertFrom("chaparral");

  await sendEvent(port, event);
  await wait(150);
  const retry = await sendEvent(port, event);
  await wait(150);

  assert.equal(JSON.parse(retry.body).duplicate, true);
  assert.equal(apns.pushes.length, 1, "every retry wakes the user again");
});

// Heartbeats as the listener and the host watcher send them, so the sensor starts covered.
async function beatHealthy(port, sensorId) {
  for (const extra of [{}, { aea_ok: true }]) {
    const raw = JSON.stringify({ sensor_id: sensorId, sent_at: new Date().toISOString(), ...extra });
    await request(port, "POST", "/heartbeat", raw,
      { "x-relay-signature": createHmac("sha256", sensorKey(SECRET, sensorId)).update(raw).digest("hex") });
  }
}

test("QA-24 a coverage loss reaches the iPhones of that sensor once", async t => {
  const apns = await startApns(t);
  const { config, port } = await startGateway(t,
    { apnsHost: apns.url, startupGraceMs: 0, coverageCheckMs: 20 });
  await beatHealthy(port, "chaparral");
  await register(port, PHONE, ["chaparral"]);
  await wait(100);
  assert.deepEqual(apns.all, [], "a covered sensor warned on registration");

  config.killSwitch = true;
  await wait(150);

  const coverage = apns.all.filter(push => push.payload.kind === "coverage");
  assert.equal(coverage.length, 1, "none, or repeated on every check");
  assert.equal(coverage[0].headers["apns-collapse-id"], "coverage:chaparral");
  assert.deepEqual([coverage[0].payload.sensor_id, coverage[0].payload.covered], ["chaparral", false]);
});

test("QA-57 iPhones all failing is degraded even if a web push got through, per channel",
  async t => {
    let apnsKeyValid = false;
    const apns = await startApns(t, (stream, push) => {
      if (apnsKeyValid) {
        stream.respond({ ":status": 200 });
        stream.end();
      } else {
        reject(403, "InvalidProviderToken")(stream, push);
      }
    });
    mock.method(webpush, "sendNotification", async () => ({ statusCode: 201 }));
    t.after(() => mock.restoreAll());
    const { port } = await startGateway(t, {
      apnsHost: apns.url,
      vapid: { subject: "mailto:qa@example.com", publicKey: "public", privateKey: "private" }
    });
    await register(port, PHONE, ["chaparral"]);
    await request(port, "POST", "/subscribe", JSON.stringify({ sensor_id: "chaparral", subscription: {
      endpoint: "https://fcm.googleapis.com/fcm/send/pwa-phone",
      keys: { p256dh: Buffer.alloc(65, 4).toString("base64url"), auth: Buffer.alloc(16, 1).toString("base64url") }
    } }));

    await sendEvent(port, alertFrom("chaparral"));
    await wait(150);
    const broken = await sensorStatus(port, "chaparral");
    assert.notEqual(broken.degraded.apns, null, "every iPhone lost the alert and nothing says so");
    assert.equal(broken.degraded.webpush, null, "the healthy channel was blamed too");
    assert.equal(broken.covered, false);

    apnsKeyValid = true;
    await sendEvent(port, alertFrom("chaparral", { time_occurred_s: Math.floor(Date.now() / 1000) - 5 }));
    await wait(150);
    assert.deepEqual((await sensorStatus(port, "chaparral")).degraded, { apns: null, webpush: null },
      "a good delivery did not clear the channel");
  });

test("QA-19 an oversized body gets 413 instead of a hung request", async t => {
  const { port } = await startGateway(t, { apnsHost: "http://127.0.0.1:1" });
  const response = await request(port, "POST", "/events", JSON.stringify({ padding: "x".repeat(20_000) }));
  assert.equal(response.status, 413);
});

test("QA-57 a broken channel that nobody uses any more does not block coverage", async t => {
  const apns = await startApns(t, reject(403, "InvalidProviderToken"));
  const { port } = await startGateway(t, { apnsHost: apns.url });
  const beat = extra => {
    const raw = JSON.stringify({ sensor_id: "chaparral", sent_at: new Date().toISOString(), ...extra });
    const signature = createHmac("sha256", sensorKey(SECRET, "chaparral")).update(raw).digest("hex");
    return request(port, "POST", "/heartbeat", raw, { "x-relay-signature": signature });
  };
  await beat({});
  await beat({ aea_ok: true });
  await register(port, PHONE, ["chaparral"]);

  await sendEvent(port, alertFrom("chaparral"));
  await wait(150);
  assert.equal((await sensorStatus(port, "chaparral")).covered, false);

  // The only iPhone moves to another sensor: nobody is left on the broken channel here.
  await register(port, PHONE, ["quibdo"]);
  assert.equal((await sensorStatus(port, "chaparral")).covered, true);
});

test("QA-59 an APNs-only outage warns the iPhones and leaves the web alone", async t => {
  const apns = await startApns(t, reject(403, "InvalidProviderToken"));
  const webPushes = [];
  mock.method(webpush, "sendNotification", async (subscription, payload) => {
    webPushes.push(JSON.parse(payload));
    return { statusCode: 201 };
  });
  t.after(() => mock.restoreAll());
  // The grace keeps the coverage check quiet until the sensor is set up. Without it, a check
  // before the heartbeats sees the sensor down, and the next one tells the new web phone
  // "restored" (a CI failure on a slow runner).
  const graceMs = 1000;
  const startedAt = Date.now();
  const { port, config } = await startGateway(t, {
    apnsHost: apns.url, startupGraceMs: graceMs, coverageCheckMs: 20,
    vapid: { subject: "mailto:qa@example.com", publicKey: "public", privateKey: "private" }
  });
  for (const extra of [{}, { aea_ok: true }]) {
    const raw = JSON.stringify({ sensor_id: "chaparral", sent_at: new Date().toISOString(), ...extra });
    await request(port, "POST", "/heartbeat", raw,
      { "x-relay-signature": createHmac("sha256", sensorKey(SECRET, "chaparral")).update(raw).digest("hex") });
  }
  await register(port, PHONE, ["chaparral"]);
  await request(port, "POST", "/subscribe", JSON.stringify({ sensor_id: "chaparral", subscription: {
    endpoint: "https://fcm.googleapis.com/fcm/send/pwa-phone",
    keys: { p256dh: Buffer.alloc(65, 4).toString("base64url"), auth: Buffer.alloc(16, 1).toString("base64url") }
  } }));
  assert.ok(Date.now() - startedAt < graceMs, "setup took longer than the grace: this run proves nothing");

  await sendEvent(port, alertFrom("chaparral"));
  await evidenceRecord(config, record => record.type === "COVERAGE_LOST" && record.sensor_id === "chaparral"
    && record.channel === "apns");

  const status = await sensorStatus(port, "chaparral");
  assert.deepEqual([status.covered_apns, status.covered_webpush], [false, true]);
  assert.deepEqual(apns.all.filter(push => push.payload.kind === "coverage").map(push => push.payload.aps.alert),
    [{ title: "Servicio interrumpido", body: "Ahora mismo no podemos avisarle.",
      "title-loc-key": "SERVICE_DOWN_TITLE", "loc-key": "SERVICE_DOWN_BODY", "loc-args": [] }],
    "the iPhones were not told");
  assert.deepEqual(webPushes.filter(message => message.kind === "coverage"), [],
    "the web got a false 'no coverage' push");
});

// The coverage check decides "down", then waits on its state file. A phone that registers in
// that gap registered against a sensor that is up again: it must not get the old "lost".
// A FIFO as the temp file holds the check inside that wait for as long as the test needs.
test("a phone that registers while a coverage check is mid-way does not get its stale news", async t => {
  const apns = await startApns(t);
  const directory = await mkdtemp(join(tmpdir(), "relay-coverage-race-"));
  const coverageFile = join(directory, "coverage.json");
  execFileSync("mkfifo", [`${coverageFile}.tmp`]);
  const { port, config } = await startGateway(t, {
    apnsHost: apns.url, startupGraceMs: 0, coverageCheckMs: 20, coverageFile
  });
  t.after(() => rm(directory, { recursive: true, force: true, maxRetries: 5 }));
  // No heartbeat yet: the first check finds chaparral down and blocks writing that down.
  await wait(100);
  for (const extra of [{}, { aea_ok: true }]) {
    const raw = JSON.stringify({ sensor_id: "chaparral", sent_at: new Date().toISOString(), ...extra });
    await request(port, "POST", "/heartbeat", raw,
      { "x-relay-signature": createHmac("sha256", sensorKey(SECRET, "chaparral")).update(raw).digest("hex") });
  }
  await register(port, PHONE, ["chaparral"]);

  const heldWrite = JSON.parse(await readFile(`${coverageFile}.tmp`, "utf8"));
  // The web channel is written first; the APNs "down" for chaparral follows it.
  assert.equal(heldWrite["chaparral:webpush"], "down", "the check was not held mid-way: this run proves nothing");
  await evidenceRecord(config, record => record.type === "COVERAGE_LOST" && record.sensor_id === "chaparral"
    && record.channel === "apns");
  await evidenceRecord(config, record => record.type === "COVERAGE_RESTORED" && record.sensor_id === "chaparral"
    && record.channel === "apns");
  assert.deepEqual(apns.all.filter(push => push.payload.kind === "coverage").map(push => push.payload.covered), [],
    "the phone heard news older than its registration");
});

// docs/ios-contract.md, the APNs push, alert and per-quake dedup sections: what an iPhone app is
// built against. Exact key sets, so a renamed, missing or extra field breaks this test.
test("contract: a fake iPhone following 2 sensors gets ONE alert, shaped as the contract says",
  async t => {
    const apns = await startApns(t);
    const { port } = await startGateway(t, { apnsHost: apns.url });
    const registered = await register(port, PHONE.toUpperCase(), ["chaparral", "quibdo"]);
    assert.equal(registered.status, 201);
    assert.deepEqual(JSON.parse(registered.body), { sensor_ids: ["chaparral", "quibdo"], apns_env: "production" });
    const origin = Math.floor(Date.now() / 1000) - 17;
    const fromA = alertFrom("chaparral", { time_occurred_s: origin, magnitude: 4.8, distance_km: 40.2 });

    await sendEvent(port, fromA);
    await sendEvent(port, alertFrom("quibdo", { time_occurred_s: origin + 3, magnitude: 4.7, distance_km: 90 }));
    await wait(200);

    assert.equal(apns.pushes.length, 1, "the phone was woken once per sensor");
    const [{ token, headers, payload }] = apns.pushes;
    assert.equal(token, PHONE, "token not stored in lowercase");
    assert.equal(headers["apns-push-type"], "alert");
    assert.equal(headers["apns-priority"], "10");
    assert.equal(headers["apns-topic"], "com.example.relay");
    assert.equal(Number(headers["apns-expiration"]), Math.floor(Date.parse(fromA.expires_at) / 1000));
    assert.equal(headers["apns-collapse-id"], `quake:${Math.round(origin * 1000 / 60_000)}`);
    assert.deepEqual(Object.keys(payload).sort(), ["aps", "distance_km", "event_id", "expires_at",
      "kind", "late", "magnitude", "sensor_id", "sent_at_ms", "time_occurred_s"]);
    assert.deepEqual(payload.aps, {
      // The gateway writes the text itself; the receiver's title and body are never shown.
      alert: { title: "Alerta de sismo", body: "Sismo M4.8 cerca de su zona. Protéjase ahora.",
        "title-loc-key": "ALERT_TITLE", "loc-key": "ALERT_BODY_MAGNITUDE", "loc-args": ["4.8"] },
      sound: "default",
      "interruption-level": "time-sensitive",
      "thread-id": "earthquake-alerts",
      "mutable-content": 1
    });
    assert.deepEqual(
      [payload.kind, payload.event_id, payload.sensor_id, payload.magnitude, payload.distance_km,
        payload.time_occurred_s, payload.late, payload.expires_at],
      ["alert", fromA.event_id, "chaparral", 4.8, 40.2, origin, false, fromA.expires_at]);
  });

// docs/ios-contract.md, "DELETE /devices": 204 whether or not the token exists.
test("DELETE /devices is idempotent and the phone stops hearing alerts", async t => {
  const apns = await startApns(t);
  const { config, port } = await startGateway(t, { apnsHost: apns.url });
  await beatHealthy(port, "chaparral");
  await register(port, PHONE, ["chaparral"]);
  const remove = token => request(port, "DELETE", "/devices", JSON.stringify({ device_token: token }));

  const removals = [await remove(PHONE.toUpperCase()), await remove(PHONE), await remove(OTHER_PHONE)];
  const malformed = await remove("zz".repeat(32));
  await sendEvent(port, alertFrom("chaparral"));
  await wait(150);

  assert.deepEqual(removals.map(response => response.status), [204, 204, 204]);
  assert.equal(malformed.status, 400);
  assert.deepEqual(apns.pushes, [], "a removed token still got the alert");
  assert.deepEqual(JSON.parse(await readFile(config.devicesFile, "utf8")), {});
});

// "apns_env": each token goes to its own APNs, so production never sees (and never deletes)
// a development build's token.
test("apns_env routes each token to its own APNs and a sandbox token is never deleted by production",
  async t => {
    const production = await startApns(t, reject(400, "BadDeviceToken"));
    const sandbox = await startApns(t);
    const { config, port } = await startGateway(t,
      { apnsHosts: { production: production.url, sandbox: sandbox.url } });
    await beatHealthy(port, "chaparral");
    const sandboxRegistration = await register(port, OTHER_PHONE, ["chaparral"], { apns_env: "sandbox" });
    const defaultRegistration = await register(port, PHONE, ["chaparral"]);
    const invalid = await register(port, PHONE, ["chaparral"], { apns_env: "staging" });

    await sendEvent(port, alertFrom("chaparral"));
    await wait(150);

    assert.equal(JSON.parse(sandboxRegistration.body).apns_env, "sandbox");
    assert.equal(JSON.parse(defaultRegistration.body).apns_env, "production");
    assert.equal(invalid.status, 400);
    assert.deepEqual(sandbox.pushes.map(push => push.token), [OTHER_PHONE]);
    assert.deepEqual(production.pushes.map(push => push.token), [PHONE]);
    const stored = JSON.parse(await readFile(config.devicesFile, "utf8"));
    assert.deepEqual(Object.keys(stored), [OTHER_PHONE], "the sandbox token was deleted, or the bad one kept");
    assert.equal(stored[OTHER_PHONE].apns_env, "sandbox");
  });

test("QA-69 /devices and /subscribe have separate limits per IP", async t => {
  const { port } = await startGateway(t, {
    apnsHost: "http://127.0.0.1:1",
    vapid: { subject: "mailto:qa@example.com", publicKey: "public", privateKey: "private" }
  });
  const subscribe = i => request(port, "POST", "/subscribe", JSON.stringify({ sensor_id: "chaparral",
    subscription: { endpoint: `https://fcm.googleapis.com/fcm/send/phone-${i}`, keys: {
      p256dh: Buffer.alloc(65, 4).toString("base64url"), auth: Buffer.alloc(16, 1).toString("base64url") } } }));
  const deviceStatuses = [];
  for (let i = 0; i < 121; i += 1) {
    const token = i.toString(16).padStart(64, "0");
    deviceStatuses.push((i % 2 ? await request(port, "DELETE", "/devices", JSON.stringify({ device_token: token }))
      : await register(port, token, ["chaparral"])).status);
  }
  const subscribeStatuses = [];
  for (let i = 0; i < 31; i += 1) subscribeStatuses.push((await subscribe(i)).status);

  assert.equal(deviceStatuses.slice(0, 120).every(status => status === 201 || status === 204), true);
  assert.equal(deviceStatuses[120], 429, "POST and DELETE /devices share 120");
  assert.deepEqual(subscribeStatuses.slice(0, 30), Array(30).fill(201), "/devices used up /subscribe's room");
  assert.equal(subscribeStatuses[30], 429);
});

// Behind CloudFront + Caddy (infra/https): CloudFront appends the viewer's IP to whatever the
// viewer sent, and Caddy passes the header through. Only the last entry can be trusted.
test("the rate limit keys on CloudFront's last X-Forwarded-For entry, not on what the viewer wrote", async t => {
  const { port } = await startGateway(t, {
    apnsHost: "http://127.0.0.1:1",
    vapid: { subject: "mailto:qa@example.com", publicKey: "public", privateKey: "private" }
  });
  const subscribe = (i, forwardedFor) => request(port, "POST", "/subscribe", JSON.stringify({ sensor_id: "chaparral",
    subscription: { endpoint: `https://fcm.googleapis.com/fcm/send/xff-${i}`, keys: {
      p256dh: Buffer.alloc(65, 4).toString("base64url"), auth: Buffer.alloc(16, 1).toString("base64url") } } }),
    { "x-forwarded-for": forwardedFor });
  const statuses = [];
  // One viewer rotating a spoofed first entry on every request.
  for (let i = 0; i < 31; i += 1) statuses.push((await subscribe(i, `10.9.${i}.1, 203.0.113.7`)).status);

  assert.deepEqual(statuses.slice(0, 30), Array(30).fill(201));
  assert.equal(statuses[30], 429, "a spoofed first entry escaped the limit");
  assert.equal((await subscribe(99, "10.9.0.1, 198.51.100.9")).status, 201, "another viewer was limited too");
});

test("QA-76 /devices refuses a sensor that is not public, fail closed", async t => {
  const { port } = await startGateway(t, { apnsHost: "http://127.0.0.1:1",
    sensors: [{ id: "chaparral", public: true }, { id: "hinatuan", public: false }, { id: "unlisted" }] });

  const statuses = [];
  for (const ids of [["hinatuan"], ["unlisted"], ["chaparral", "hinatuan"]]) {
    statuses.push((await register(port, PHONE, ids)).status);
  }

  assert.deepEqual(statuses, [400, 400, 400]);
  assert.equal((await register(port, PHONE, ["chaparral"])).status, 201);
});

test("QA-70 a phone joining a sensor that is down hears it once per new sensor", async t => {
  const apns = await startApns(t);
  const { port } = await startGateway(t, { apnsHost: apns.url });
  await beatHealthy(port, "quibdo");
  const coverageNotices = () => apns.all.filter(push => push.payload.kind === "coverage")
    .map(push => [push.payload.sensor_id, push.payload.covered, push.headers["apns-collapse-id"]]);

  await register(port, PHONE, ["chaparral", "quibdo"]);
  await wait(100);
  await register(port, PHONE, ["quibdo", "chaparral"]);
  await wait(100);
  assert.deepEqual(coverageNotices(), [["chaparral", false, "coverage:chaparral"]],
    "none, repeated on re-registration, or sent for the covered sensor");

  await register(port, PHONE, ["chaparral", "bucaramanga-a"]);
  await wait(100);
  assert.deepEqual(coverageNotices().at(-1), ["bucaramanga-a", false, "coverage:bucaramanga-a"]);
  assert.equal(coverageNotices().length, 2);
});

test("QA-77 each phone hears each coverage change once, and 'restored' only if it heard 'lost'",
  async t => {
    const apns = await startApns(t);
    const { port } = await startGateway(t,
      { apnsHost: apns.url, startupGraceMs: 0, coverageCheckMs: 20 });
    const heard = token => apns.all.filter(push => push.token === token && push.payload.kind === "coverage")
      .map(push => push.payload.covered);

    await register(port, PHONE, ["chaparral"]);
    await wait(150);
    assert.deepEqual(heard(PHONE), [false], "none, or 'Sin cobertura' twice (registration + transition)");

    await beatHealthy(port, "chaparral");
    await register(port, OTHER_PHONE, ["chaparral"]);
    await wait(150);
    assert.deepEqual(heard(PHONE), [false, true]);
    assert.deepEqual(heard(OTHER_PHONE), [], "'restored' to a phone that never heard 'lost'");
    const restored = apns.all.find(push => push.token === PHONE && push.payload.covered === true);
    assert.deepEqual(restored.payload.aps.alert, { title: "Cobertura restablecida",
      body: "Las alertas de su zona vuelven a funcionar.", "title-loc-key": "COVERAGE_RESTORED_TITLE",
      "loc-key": "COVERAGE_RESTORED_BODY", "loc-args": [] });
  });

// The receiver's own title and body never reach a phone, and no text carries a distance:
// the distance is from the receiver, not from the phone (bug of the real quake of 24-sep).
test("the gateway writes the alert text, whatever the receiver sent", async t => {
  const apns = await startApns(t);
  const { port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE, ["chaparral"]);
  await register(port, OTHER_PHONE, ["quibdo"]);

  await sendEvent(port, alertFrom("chaparral", { title: "hackeado", body: "hola ~99 km", magnitude: 4.45852 }));
  await sendEvent(port, alertFrom("quibdo", { title: "x", body: "y ~5 km", magnitude: null }));
  await wait(150);

  const byToken = Object.fromEntries(apns.pushes.map(push => [push.token, push.payload.aps.alert]));
  assert.deepEqual(byToken[PHONE], { title: "Alerta de sismo", body: "Sismo M4.5 cerca de su zona. Protéjase ahora.",
    "title-loc-key": "ALERT_TITLE", "loc-key": "ALERT_BODY_MAGNITUDE", "loc-args": ["4.5"] });
  assert.deepEqual(byToken[OTHER_PHONE], { title: "Alerta de sismo", body: "Posible sismo cerca de su zona. Protéjase ahora.",
    "title-loc-key": "ALERT_TITLE", "loc-key": "ALERT_BODY_NO_MAGNITUDE", "loc-args": [] });
  assert.equal(apns.pushes.some(push => /km/.test(JSON.stringify(push.payload.aps))), false, "a distance reached a phone");
});

// The phone renders the text in its own language from these keys (docs/ios-contract.md).
test("magnitude args are locale-neutral strings with a dot and one decimal", async t => {
  const apns = await startApns(t);
  const { port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE, ["chaparral"]);
  const origin = Math.floor(Date.now() / 1000);

  for (const [index, magnitude] of [5, 6.25, 4.04].entries()) {
    await sendEvent(port, alertFrom("chaparral", { magnitude, time_occurred_s: origin - 100 + index * 40 }));
    await wait(100);
  }

  assert.deepEqual(apns.pushes.map(push => push.payload.aps.alert["loc-args"]), [["5.0"], ["6.3"], ["4.0"]]);
});

test("demand: a phone outside coverage leaves only its 0.1° cell, counted after one APNs 200", async t => {
  const apns = await startApns(t);
  const { port, config } = await startGateway(t, { apnsHost: apns.url });
  const stored = async () => JSON.parse(await readFile(config.devicesFile, "utf8"));
  const withCell = (token, cell) => request(port, "POST", "/devices",
    JSON.stringify({ device_token: token, demand_cell: cell, platform: "ios" }));

  const answer = await withCell(PHONE, "37,-755");
  assert.equal(answer.status, 201);
  assert.deepEqual(JSON.parse(answer.body), { sensor_ids: [], demand_cell: "37,-755", apns_env: "production" });
  await wait(200);
  const told = apns.all.filter(push => push.token === PHONE);
  assert.equal(told.length, 1);
  assert.deepEqual(told[0].payload, {
    aps: { alert: { title: "Sin cobertura en su zona", body: "Su zona todavía no tiene cobertura.",
      "title-loc-key": "NO_COVERAGE_TITLE", "loc-key": "NO_COVERAGE_BODY", "loc-args": [] },
      sound: "default", "interruption-level": "active" },
    kind: "coverage", sensor_id: null, covered: false, reason: "no_receptor"
  });
  let device = (await stored())[PHONE];
  assert.equal(device.demand_cell, "37,-755");
  assert.ok(Date.parse(device.verified_at), "an accepted push did not verify the token");
  assert.equal(JSON.stringify(device).includes("3.7"), false, "more than the cell was stored");

  // The app registers again on every move: no second notice, and one cell per phone.
  await withCell(PHONE, "38,-755");
  await wait(200);
  assert.equal(apns.all.filter(push => push.token === PHONE).length, 1);
  assert.equal((await stored())[PHONE].demand_cell, "38,-755");

  // Into coverage: the cell goes away, the verification stays.
  await register(port, PHONE, ["chaparral"]);
  device = (await stored())[PHONE];
  assert.equal(device.demand_cell, null);
  assert.ok(device.verified_at);

  for (const cell of ["37.5,-755", "900,0", "0,1800", "a,b", 37, ""]) {
    assert.equal((await withCell(OTHER_PHONE, cell)).status, 400, String(cell));
  }

  // A demand-only phone can leave too.
  await withCell(OTHER_PHONE, "-1,-800");
  assert.equal((await request(port, "DELETE", "/devices", JSON.stringify({ device_token: OTHER_PHONE }))).status, 204);
  assert.equal(OTHER_PHONE in (await stored()), false, "DELETE kept a demand-only phone");
});

test("demand: a token APNs never accepts is stored but never verified", async t => {
  const { port, config } = await startGateway(t, { apnsHost: "http://127.0.0.1:1" });
  await request(port, "POST", "/devices",
    JSON.stringify({ device_token: PHONE, demand_cell: "37,-755", platform: "ios" }));
  await wait(300);
  const device = JSON.parse(await readFile(config.devicesFile, "utf8"))[PHONE];
  assert.equal(device.demand_cell, "37,-755");
  assert.equal(device.verified_at, null);
});

// "Limited" tier: receptors far away, only strong quakes reach the phone. It follows them for
// alerts and also asks for a closer receptor with its cell.
test("demand: a limited phone sends sensor_ids and demand_cell; alerts follow the sensors, the cell counts", async t => {
  const apns = await startApns(t);
  const { port, config } = await startGateway(t, { apnsHost: apns.url });
  const limited = cell => request(port, "POST", "/devices", JSON.stringify(
    { device_token: PHONE, sensor_ids: ["chaparral"], demand_cell: cell, platform: "ios" }));

  const answer = await limited("37,-755");
  assert.equal(answer.status, 201);
  assert.deepEqual(JSON.parse(answer.body), { sensor_ids: ["chaparral"], demand_cell: "37,-755", apns_env: "production" });
  await wait(200);
  // Verified by a push that shows nothing: "no coverage yet" would be false for this phone.
  // chaparral is not reporting in this test, so the phone also gets its "Sin cobertura".
  const notCoverage = () => apns.all.filter(push => push.token === PHONE && push.payload.kind !== "coverage");
  const [verify, ...more] = notCoverage();
  assert.equal(more.length, 0, JSON.stringify(more));
  assert.deepEqual(verify.payload, { aps: { "content-available": 1 }, kind: "verify" });
  assert.equal(verify.headers["apns-push-type"], "background");
  assert.equal(verify.headers["apns-priority"], "5");
  const device = JSON.parse(await readFile(config.devicesFile, "utf8"))[PHONE];
  assert.deepEqual([device.sensor_ids, device.demand_cell], [["chaparral"], "37,-755"]);
  assert.ok(Date.parse(device.verified_at), "an accepted push did not verify the token");

  // Once verified, registering again sends nothing more.
  await limited("38,-755");
  await wait(200);
  assert.equal(notCoverage().length, 1);

  await sendEvent(port, alertFrom("chaparral"));
  await wait(300);
  const alerts = apns.all.filter(push => push.payload.kind === "alert");
  assert.deepEqual(alerts.map(push => push.token), [PHONE]);
  assert.equal(alerts[0].headers["apns-push-type"], "alert");

  // Both fields are still validated.
  assert.equal((await limited("37.5,-755")).status, 400);
  const unknownSensor = await request(port, "POST", "/devices", JSON.stringify(
    { device_token: PHONE, sensor_ids: ["atlantis"], demand_cell: "37,-755", platform: "ios" }));
  assert.equal(unknownSensor.status, 400);
});

test("demand: a limited phone APNs never accepts is not verified", async t => {
  const { port, config } = await startGateway(t, { apnsHost: "http://127.0.0.1:1" });
  await request(port, "POST", "/devices", JSON.stringify(
    { device_token: PHONE, sensor_ids: ["chaparral"], demand_cell: "37,-755", platform: "ios" }));
  await wait(300);
  assert.equal(JSON.parse(await readFile(config.devicesFile, "utf8"))[PHONE].verified_at, null);
});

// A far phone follows a receptor for strong quakes only: the weak ones it would not feel are
// false alarms. Unknown magnitude still goes out: when unsure, alert.
test("min_magnitude: a far phone skips weaker alerts from that receptor, never an unknown one", async t => {
  const apns = await startApns(t);
  const { port, config } = await startGateway(t, { apnsHost: apns.url });
  const answer = await register(port, PHONE, ["chaparral", "quibdo"], { min_magnitude: { chaparral: 5.5 } });
  assert.equal(answer.status, 201);
  assert.deepEqual(JSON.parse(answer.body),
    { sensor_ids: ["chaparral", "quibdo"], min_magnitude: { chaparral: 5.5 }, apns_env: "production" });
  await register(port, OTHER_PHONE, ["chaparral"]);
  assert.deepEqual(JSON.parse(await readFile(config.devicesFile, "utf8"))[PHONE].min_magnitude, { chaparral: 5.5 });

  const now = Math.floor(Date.now() / 1000);
  const alertedFor = async event => {
    apns.pushes.length = 0;
    await sendEvent(port, event);
    await wait(250);
    return apns.pushes.filter(push => push.payload.kind === "alert").map(push => push.token).sort();
  };
  assert.deepEqual(await alertedFor(alertFrom("chaparral", { time_occurred_s: now - 270, magnitude: 5.49 })), [OTHER_PHONE]);
  assert.deepEqual(await alertedFor(alertFrom("chaparral", { time_occurred_s: now - 230, magnitude: 5.5 })), [OTHER_PHONE, PHONE].sort());
  assert.deepEqual(await alertedFor(alertFrom("chaparral", { time_occurred_s: now - 190, magnitude: null })), [OTHER_PHONE, PHONE].sort());
  // The skip does not use up the quake: the same weak quake from a receptor with no minimum gets through.
  const origin = now - 150;
  assert.deepEqual(await alertedFor(alertFrom("chaparral", { time_occurred_s: origin, magnitude: 4.6 })), [OTHER_PHONE]);
  assert.deepEqual(await alertedFor(alertFrom("quibdo", { time_occurred_s: origin + 2, magnitude: 4.6 })), [PHONE]);

  // Registering without it clears it.
  await register(port, PHONE, ["chaparral"]);
  assert.deepEqual(await alertedFor(alertFrom("chaparral", { time_occurred_s: now - 60, magnitude: 4.5 })), [OTHER_PHONE, PHONE].sort());

  for (const bad of [{ chaparral: 3.9 }, { chaparral: 7.1 }, { chaparral: "5.5" }, { chaparral: null },
    { quibdo: 5.5 }, [5.5], null, 5.5]) {
    assert.equal((await register(port, PHONE, ["chaparral"], { min_magnitude: bad })).status, 400, JSON.stringify(bad));
  }
  assert.equal((await register(port, PHONE, ["chaparral"], { min_magnitude: { chaparral: 4.0 } })).status, 201);
  assert.equal((await register(port, PHONE, ["chaparral"], { min_magnitude: { chaparral: 7.0 } })).status, 201);
  const cellOnly = await request(port, "POST", "/devices", JSON.stringify(
    { device_token: PHONE, demand_cell: "37,-755", min_magnitude: {}, platform: "ios" }));
  assert.equal(cellOnly.status, 400, "min_magnitude without sensors");
});

// "Enviar alerta de prueba" (App Review cannot wait for a quake). Sounds like an alert but is
// not a quake: nothing a real alert depends on may notice it.
test("devices/test: one test alert per phone per 10 min, shaped as the contract says", async t => {
  const apns = await startApns(t);
  const { port, config } = await startGateway(t, { apnsHost: apns.url });
  const testPush = token => request(port, "POST", "/devices/test", JSON.stringify({ device_token: token }));
  await register(port, PHONE, ["chaparral"]);

  const before = Date.now();
  const answer = await testPush(PHONE);
  assert.equal(answer.status, 202);
  const { sent_at_ms: sentAtMs, event_id: eventId } = JSON.parse(answer.body);
  assert.ok(sentAtMs >= before && sentAtMs <= Date.now());
  assert.match(eventId, /^test:[0-9a-f-]{36}$/, "no unique event_id for arrival telemetry to dedup on");
  await wait(150);
  const [push, ...more] = apns.pushes;
  assert.equal(more.length, 0);
  assert.deepEqual(push.payload, {
    aps: { alert: { title: "Alerta de prueba", body: "Así sonará una alerta de sismo. Esto es solo una prueba.",
      "title-loc-key": "TEST_ALERT_TITLE", "loc-key": "TEST_ALERT_BODY", "loc-args": [] },
      sound: "default", "interruption-level": "time-sensitive", "mutable-content": 1 },
    kind: "test", event_id: eventId, sent_at_ms: sentAtMs
  });
  assert.equal(push.headers["apns-push-type"], "alert");
  assert.equal(push.headers["apns-priority"], "10");
  assert.equal(push.headers["apns-collapse-id"], `test:${PHONE.slice(0, 8)}`);
  assert.equal(Number(push.headers["apns-expiration"]), Math.floor((sentAtMs + 60_000) / 1000));

  assert.equal((await testPush(PHONE)).status, 429, "a second test inside 10 min");
  // Real alerts off: the test must not ring, and must not use up the phone's slot.
  await register(port, OTHER_PHONE, ["chaparral"]);
  config.killSwitch = true;
  const paused = await testPush(OTHER_PHONE);
  assert.deepEqual([paused.status, JSON.parse(paused.body)], [503, { error: "relay paused" }]);
  await wait(100);
  assert.equal(apns.pushes.length, 1, "a test push went out with the relay paused");
  config.killSwitch = false;
  assert.equal((await testPush(OTHER_PHONE)).status, 202, "the paused attempt did not use up the slot");
  assert.equal((await testPush("ef".repeat(32))).status, 404, "unknown token");
  assert.equal((await testPush("not-a-token")).status, 400);
  await wait(100);
  assert.deepEqual(apns.pushes.map(push => push.token), [PHONE, OTHER_PHONE]);
});

test("devices/test: a failed test push degrades nothing, records nothing and leaves the quake unclaimed", async t => {
  const apns = await startApns(t, (stream, push) => (push.payload.kind === "test"
    ? reject(403, "InvalidProviderToken")(stream)
    : (stream.respond({ ":status": 200 }), stream.end())));
  const { port, config } = await startGateway(t, { apnsHost: apns.url });
  for (const extra of [{}, { aea_ok: true }]) {
    const raw = JSON.stringify({ sensor_id: "chaparral", sent_at: new Date().toISOString(), ...extra });
    await request(port, "POST", "/heartbeat", raw,
      { "x-relay-signature": createHmac("sha256", sensorKey(SECRET, "chaparral")).update(raw).digest("hex") });
  }
  await register(port, PHONE, ["chaparral"]);
  assert.equal((await request(port, "POST", "/devices/test", JSON.stringify({ device_token: PHONE }))).status, 202);
  await wait(150);

  const status = await sensorStatus(port, "chaparral");
  assert.deepEqual([status.covered_apns, status.degraded_since], [true, null], "a test push degraded the channel");
  const evidence = await readFile(config.evidenceFile, "utf8").catch(() => "");
  assert.equal(evidence, "", "a test push reached the evidence the certifier reads");

  await sendEvent(port, alertFrom("chaparral"));
  await wait(250);
  assert.deepEqual(apns.pushes.map(push => push.payload.kind), ["test", "alert"]);
});

// Demand-driven siting: a phone outside coverage registers only its 0.1° cell. It must never be
// woken by an alert for a receptor it did not ask for, and it must not disturb the covered phones.
test("a demand-only phone never gets an alert, and a covered phone still does", async t => {
  const apns = await startApns(t);
  const { port } = await startGateway(t, { apnsHost: apns.url });
  await register(port, PHONE, ["chaparral"]);
  const demand = await request(port, "POST", "/devices",
    JSON.stringify({ device_token: OTHER_PHONE, demand_cell: "37,-755", platform: "ios" }));
  assert.equal(demand.status, 201);
  await sendEvent(port, alertFrom("chaparral"));
  await wait(300);
  assert.deepEqual(apns.all.filter(push => push.payload.kind === "alert").map(push => push.token), [PHONE]);
});

test("GET /health serves the status page, unauthenticated like /status", async t => {
  const { port } = await startGateway(t);
  const response = await request(port, "GET", "/health");
  assert.equal(response.status, 200);
  assert.match(response.body, /health\.js/, "the page must load the health-state module");
  const script = await request(port, "GET", "/health.js");
  assert.equal(script.status, 200, "the module the page imports must actually be served");
});

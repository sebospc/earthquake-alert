// Web push per sensor, kill switch, heartbeat, coverage and /status (docs/qa/review.md, phase 2).
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createHmac } from "node:crypto";
import http from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { mock } from "node:test";

import webpush from "web-push";

import { coverageState } from "../public/coverage.js";
import { createServer, sensorKey } from "../src/server.js";

const SECRET = "test-secret";
const CHAPARRAL = "https://fcm.googleapis.com/fcm/send/chaparral-phone";
const QUIBDO = "https://web.push.apple.com/quibdo-phone";
const VALID_KEYS = {
  p256dh: Buffer.alloc(65, 4).toString("base64url"),
  auth: Buffer.alloc(16, 1).toString("base64url")
};

async function tempDir(t) {
  const directory = await mkdtemp(join(tmpdir(), "relay-webpush-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

async function startGateway(t, overrides = {}) {
  const directory = await tempDir(t);
  const config = {
    hmacSecret: SECRET,
    teamId: "TEAM",
    keyId: "KEY",
    bundleId: "com.example.relay",
    privateKey: "",
    dryRun: true,
    evidenceFile: join(directory, "evidence.jsonl"),
    subscriptionsFile: join(directory, "subscriptions.json"),
    coverageFile: join(directory, "coverage.json"),
    sensors: [{ id: "chaparral", public: true }, { id: "quibdo", public: true }],
    vapid: { subject: "mailto:qa@example.com", publicKey: "public", privateKey: "private" },
    ...overrides
  };
  const server = createServer(config);
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const close = () => new Promise(resolve => server.listening ? server.close(resolve) : resolve());
  t.after(close);
  return { config, port: server.address().port, close };
}

// Records every push instead of sending it. `answer(endpoint)` may throw to fail one.
function mockPushService(t, answer = () => ({ statusCode: 201 })) {
  const pushed = [];
  // Not enumerable, so deepEqual on the endpoint list ignores it.
  Object.defineProperty(pushed, "messages", { value: [] });
  mock.method(webpush, "sendNotification", async (subscription, payload) => {
    pushed.push(subscription.endpoint);
    pushed.messages.push(JSON.parse(payload));
    return answer(subscription.endpoint);
  });
  t.after(() => mock.restoreAll());
  return pushed;
}

const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

function request(port, method, path, body, signature) {
  const headers = { "content-type": "application/json" };
  if (signature !== undefined) headers["x-relay-signature"] = signature;
  return new Promise((resolve, reject) => {
    const outgoing = http.request({ hostname: "127.0.0.1", port, path, method, headers }, response => {
      let text = "";
      response.on("data", chunk => { text += chunk; });
      response.on("end", () => resolve({ status: response.statusCode, body: text }));
    });
    outgoing.on("error", reject);
    outgoing.end(body);
  });
}

// Signs like a sensor does: with HMAC(master, sensor_id), unless another key is forced.
function signed(port, path, payload, key = sensorKey(SECRET, payload.sensor_id)) {
  const raw = JSON.stringify(payload);
  return request(port, "POST", path, raw, createHmac("sha256", key).update(raw).digest("hex"));
}

const subscribe = (port, sensorId, endpoint, extra = {}) => request(port, "POST", "/subscribe",
  JSON.stringify({ sensor_id: sensorId, subscription: { endpoint, keys: VALID_KEYS }, ...extra }));

const status = async port => JSON.parse((await request(port, "GET", "/status")).body);
const sensorStatus = async (port, id) => (await status(port)).sensors.find(sensor => sensor.id === id);

const listenerBeat = sensorId => ({ sensor_id: sensorId, sent_at: new Date(Date.now()).toISOString() });
const watcherBeat = (sensorId, ok) => ({ ...listenerBeat(sensorId), aea_ok: ok });

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
    ...overrides
  };
}

test("/subscribe only accepts real push services and stores no location", async t => {
  const { config, port } = await startGateway(t);
  const notPushServices = [
    "http://fcm.googleapis.com/fcm/send/x",
    "https://fcm.googleapis.com.evil.test/x",
    "https://evil.test/fcm.googleapis.com",
    "https://fcm.googleapis.com@evil.test/x",
    "https://127.0.0.1/x",
    "https://169.254.169.254/latest/meta-data",
    "not a url"
  ];
  for (const endpoint of notPushServices) {
    assert.equal((await subscribe(port, "chaparral", endpoint)).status, 400, endpoint);
  }
  assert.equal((await subscribe(port, "atlantis", CHAPARRAL)).status, 400, "unknown sensor");
  // Junk keys make every send throw without a status, so they would never be cleaned up.
  for (const keys of [{ ...VALID_KEYS, p256dh: "k" }, { ...VALID_KEYS, auth: "a" }]) {
    const junk = await request(port, "POST", "/subscribe", JSON.stringify({
      sensor_id: "chaparral", subscription: { endpoint: CHAPARRAL, keys }
    }));
    assert.equal(junk.status, 400, JSON.stringify(keys));
  }

  const accepted = await subscribe(port, "chaparral", CHAPARRAL,
    { lat: 3.7236, lon: -75.4836, subscription_extra: "x" });
  assert.equal(accepted.status, 201);
  const stored = await readFile(config.subscriptionsFile, "utf8");
  assert.doesNotMatch(stored, /lat|lon|3\.72|75\.48/, stored);
});

test("QA-26 one client cannot fill the subscription table", async t => {
  const { port } = await startGateway(t);
  const statuses = [];
  for (let i = 0; i < 31; i += 1) {
    statuses.push((await subscribe(port, "chaparral", `${CHAPARRAL}-${i}`)).status);
  }
  assert.deepEqual(statuses.slice(0, 30), Array(30).fill(201));
  assert.equal(statuses[30], 429);
});

test("/subscribe answers 503 when web push is not configured", async t => {
  const { port } = await startGateway(t, { vapid: null });
  assert.equal((await subscribe(port, "chaparral", CHAPARRAL)).status, 503);
});

test("an alert reaches only the subscribers of its own sensor", async t => {
  const pushed = mockPushService(t);
  const { port } = await startGateway(t);
  assert.equal((await subscribe(port, "chaparral", CHAPARRAL)).status, 201);
  assert.equal((await subscribe(port, "quibdo", QUIBDO)).status, 201);

  const response = await signed(port, "/events", alertFrom("chaparral"));

  assert.equal(response.status, 202);
  assert.deepEqual(pushed, [CHAPARRAL]);
});

test("a phone that re-subscribes to another sensor stops hearing the old one", async t => {
  const pushed = mockPushService(t);
  const { port } = await startGateway(t);
  assert.equal((await subscribe(port, "chaparral", CHAPARRAL)).status, 201);
  assert.equal((await subscribe(port, "quibdo", CHAPARRAL)).status, 201);

  await signed(port, "/events", alertFrom("chaparral"));
  await signed(port, "/events", alertFrom("quibdo"));

  assert.deepEqual(pushed, [CHAPARRAL], "pushed twice, or once from the old sensor");
  assert.equal(pushed.messages[0].tag.startsWith("quibdo:"), true);
});

test("a 410 from the push service deletes the subscription", async t => {
  const pushed = mockPushService(t, () => {
    throw Object.assign(new Error("gone"), { statusCode: 410 });
  });
  const { config, port } = await startGateway(t);
  await subscribe(port, "chaparral", CHAPARRAL);

  await signed(port, "/events", alertFrom("chaparral"));
  await wait(50);
  await signed(port, "/events", alertFrom("chaparral"));

  assert.deepEqual(pushed, [CHAPARRAL], "second alert still pushed to a dead endpoint");
  assert.doesNotMatch(await readFile(config.subscriptionsFile, "utf8"), /chaparral-phone/);
});

test("the kill switch blocks dispatch without burning the event id", async t => {
  const pushed = mockPushService(t);
  const { config, port } = await startGateway(t, { killSwitch: true });
  await subscribe(port, "chaparral", CHAPARRAL);
  const alert = alertFrom("chaparral");

  const blocked = await signed(port, "/events", alert);
  const whileBlocked = await status(port);
  config.killSwitch = false;
  const afterwards = await signed(port, "/events", alert);

  assert.equal(blocked.status, 503);
  assert.equal(whileBlocked.relay_enabled, false);
  assert.equal(afterwards.status, 202);
  assert.equal(JSON.parse(afterwards.body).accepted, true, "retry swallowed as duplicate");
  assert.deepEqual(pushed, [CHAPARRAL], "pushed while the switch was on");
});

test("QA-14 a sensor cannot sign for another sensor, and the master key is not a sensor key",
  async t => {
    const pushed = mockPushService(t);
    const { port } = await startGateway(t);
    await subscribe(port, "quibdo", QUIBDO);
    const chaparralKey = sensorKey(SECRET, "chaparral");

    const forged = await signed(port, "/events", alertFrom("quibdo"), chaparralKey);
    const withMaster = await signed(port, "/events", alertFrom("quibdo"), SECRET);
    const forgedBeat = await signed(port, "/heartbeat", listenerBeat("quibdo"), chaparralKey);
    const forgedWatcher = await signed(port, "/heartbeat", watcherBeat("quibdo", true), SECRET);
    const own = await signed(port, "/events", alertFrom("quibdo"));
    // The master signs nothing any more: an event without sensor_id has no key at all.
    const { sensor_id: _, ...legacy } = alertFrom("quibdo");
    const unsigned = await signed(port, "/events", legacy, SECRET);

    assert.deepEqual([forged.status, withMaster.status, forgedBeat.status, forgedWatcher.status],
      [401, 401, 401, 401]);
    assert.equal(own.status, 202);
    assert.equal(unsigned.status, 401, "the legacy path came back");
    assert.deepEqual(pushed, [QUIBDO]);
  });

test("QA-06 a canary proves the path per sensor and never wakes anyone", async t => {
  const pushed = mockPushService(t);
  const { port } = await startGateway(t);
  await subscribe(port, "chaparral", CHAPARRAL);

  const response = await signed(port, "/events",
    alertFrom("chaparral", { canary: true, title: "Canario", interruption_level: "active" }));
  await wait(50);

  assert.equal(response.status, 202);
  assert.equal(JSON.parse(response.body).canary, true);
  assert.deepEqual(pushed, [], "a canary reached a phone");
  assert.notEqual((await sensorStatus(port, "chaparral")).last_canary_ok_at, null);
  assert.equal((await sensorStatus(port, "quibdo")).last_canary_ok_at, null);
});

test("QA-13 the server marks an alert late from the quake origin, not from capture", async t => {
  const pushed = mockPushService(t);
  const { port } = await startGateway(t);
  await subscribe(port, "chaparral", CHAPARRAL);
  const nowS = Math.floor(Date.now() / 1000);

  await signed(port, "/events", alertFrom("chaparral", { time_occurred_s: nowS - 30 }));
  await signed(port, "/events", alertFrom("chaparral", { time_occurred_s: nowS - 150 }));
  const tooOld = await signed(port, "/events", alertFrom("chaparral", { time_occurred_s: nowS - 301 }));
  const critical = await signed(port, "/events",
    alertFrom("chaparral", { interruption_level: "critical" }));

  const [onTime, late] = pushed.messages;
  assert.equal(onTime.late, false);
  assert.match(onTime.body, /Protéjase/);
  assert.equal(late.late, true);
  assert.equal(late.title, "Aviso de sismo atrasado");
  assert.doesNotMatch(late.body, /Protéjase/);
  assert.equal(tooOld.status, 400, "past origin + 5 min it is no warning at all");
  assert.equal(critical.status, 400, "critical needs an entitlement we do not have");
  assert.equal(pushed.length, 2);
});

test("heartbeat needs its key and a fresh sent_at, and shows up in /status", async t => {
  const { port } = await startGateway(t);
  const stale = { sensor_id: "chaparral", sent_at: new Date(Date.now() - 6 * 60_000).toISOString() };

  const unsigned = await request(port, "POST", "/heartbeat", JSON.stringify(listenerBeat("chaparral")));
  const old = await signed(port, "/heartbeat", stale);
  const unknown = await signed(port, "/heartbeat", listenerBeat("atlantis"));
  const before = await sensorStatus(port, "chaparral");
  const good = await signed(port, "/heartbeat", listenerBeat("chaparral"));
  const after = await sensorStatus(port, "chaparral");

  assert.deepEqual([unsigned.status, old.status, unknown.status, good.status], [401, 400, 400, 204]);
  assert.equal(before.last_heartbeat_at, null, "a rejected beat counted as alive");
  assert.ok(Math.abs(Date.parse(after.last_heartbeat_at) - Date.now()) < 5_000);
  assert.equal((await sensorStatus(port, "quibdo")).last_heartbeat_at, null);
});

test("QA-23 covered needs a fresh listener AND a fresh aea_ok=true, each on its own", async t => {
  const { port } = await startGateway(t);
  const coveredNow = async () => {
    const snapshot = await status(port);
    return [snapshot.sensors[0].covered, coverageState(snapshot, "chaparral").healthy];
  };

  await signed(port, "/heartbeat", watcherBeat("chaparral", true));
  assert.deepEqual(await coveredNow(), [false, false], "a watcher beat counted as the listener");

  await signed(port, "/heartbeat", listenerBeat("chaparral"));
  assert.deepEqual(await coveredNow(), [true, true]);

  await signed(port, "/heartbeat", watcherBeat("chaparral", false));
  assert.deepEqual(await coveredNow(), [false, false], "aea_ok=false still green");

  await signed(port, "/heartbeat", watcherBeat("chaparral", true));
  // The watcher dies; the listener keeps beating for 16 more minutes.
  const realNow = Date.now();
  mock.method(Date, "now", () => realNow + 16 * 60_000);
  t.after(() => mock.restoreAll());
  await signed(port, "/heartbeat", listenerBeat("chaparral"));
  const watcherDead = await sensorStatus(port, "chaparral");
  assert.equal(watcherDead.stale, false);
  assert.equal(watcherDead.aea_stale, true);
  assert.deepEqual(await coveredNow(), [false, false], "a dead watcher left its last true standing");
});

test("QA-24 lost and restored coverage is pushed once per transition, even across a restart",
  async t => {
    const pushed = mockPushService(t);
    const directory = await tempDir(t);
    const files = {
      subscriptionsFile: join(directory, "subscriptions.json"),
      coverageFile: join(directory, "coverage.json"),
      startupGraceMs: 0,
      coverageCheckMs: 20
    };
    const coveragePushes = () => pushed.messages.filter(message => message.kind === "coverage")
      .map(message => message.title);
    const first = await startGateway(t, files);
    await subscribe(first.port, "chaparral", CHAPARRAL);

    await wait(150);
    assert.deepEqual(coveragePushes(), ["Sin cobertura en su zona"]);

    await first.close();
    const restarted = await startGateway(t, files);
    await wait(150);
    assert.deepEqual(coveragePushes(), ["Sin cobertura en su zona"], "repeated after restart");

    await signed(restarted.port, "/heartbeat", listenerBeat("chaparral"));
    await signed(restarted.port, "/heartbeat", watcherBeat("chaparral", true));
    await wait(150);
    assert.deepEqual(coveragePushes(), ["Sin cobertura en su zona", "Cobertura restablecida"]);
    assert.ok(pushed.every(endpoint => endpoint === CHAPARRAL));
  });

test("QA-22 a transient push failure is retried while the alert is still useful", async t => {
  let failuresLeft = 1;
  const pushed = mockPushService(t, () => {
    if (failuresLeft-- > 0) throw Object.assign(new Error("busy"), { statusCode: 503 });
    return { statusCode: 201 };
  });
  const { port } = await startGateway(t);
  await subscribe(port, "chaparral", CHAPARRAL);

  await signed(port, "/events", alertFrom("chaparral"));
  await wait(1_000);

  assert.equal(pushed.length, 2, "one 503 at the push service and this phone never hears it");
});

test("QA-22 retries stop when the alert expires, and never on a config error", async t => {
  const pushed = mockPushService(t, endpoint => {
    const statusCode = endpoint === CHAPARRAL ? 503 : 403;
    throw Object.assign(new Error("fail"), { statusCode });
  });
  const { port } = await startGateway(t);
  await subscribe(port, "chaparral", CHAPARRAL);
  await subscribe(port, "quibdo", QUIBDO);
  const now = Date.now();

  // Backoff 0, 0.5, 1 s: the third try would land after expiry.
  await signed(port, "/events", alertFrom("chaparral", { expires_at: new Date(now + 1_200).toISOString() }));
  await signed(port, "/events", alertFrom("quibdo"));
  await wait(2_500);

  assert.equal(pushed.filter(endpoint => endpoint === CHAPARRAL).length, 2, "retried past expiry");
  assert.equal(pushed.filter(endpoint => endpoint === QUIBDO).length, 1, "retried a 403");
});

test("QA-33 without time_occurred_s the post time is the origin", async t => {
  const pushed = mockPushService(t);
  const { port } = await startGateway(t);
  await subscribe(port, "chaparral", CHAPARRAL);
  const now = Date.now();

  await signed(port, "/events", alertFrom("chaparral", { post_time_ms: now - 30_000 }));
  await signed(port, "/events", alertFrom("chaparral", { post_time_ms: now - 150_000 }));
  // The quake origin wins over the post time when both are there.
  await signed(port, "/events", alertFrom("chaparral",
    { time_occurred_s: Math.floor(now / 1000) - 30, post_time_ms: now - 150_000 }));
  const tooOld = await signed(port, "/events", alertFrom("chaparral", { post_time_ms: now - 301_000 }));
  const garbage = await signed(port, "/events", alertFrom("chaparral", { post_time_ms: "soon" }));

  assert.deepEqual(pushed.messages.map(message => message.late), [false, true, false]);
  assert.equal(tooOld.status, 400);
  assert.equal(garbage.status, 400);
});

test("QA-34 when every push of an alert fails the sensor stops showing covered", async t => {
  let pushServiceUp = false;
  const pushed = mockPushService(t, () => {
    if (!pushServiceUp) throw Object.assign(new Error("bad vapid"), { statusCode: 403 });
    return { statusCode: 201 };
  });
  const { port } = await startGateway(t, { startupGraceMs: 0, coverageCheckMs: 20 });
  await signed(port, "/heartbeat", listenerBeat("chaparral"));
  await signed(port, "/heartbeat", watcherBeat("chaparral", true));
  await wait(60);
  await subscribe(port, "chaparral", CHAPARRAL);
  const coveragePushes = () => pushed.messages.filter(message => message.kind === "coverage")
    .map(message => message.title);
  assert.equal((await sensorStatus(port, "chaparral")).covered, true);

  await signed(port, "/events", alertFrom("chaparral"));
  await wait(150);
  const degraded = await sensorStatus(port, "chaparral");
  assert.equal(degraded.covered, false, "every push failed and the page stays green");
  assert.notEqual(degraded.degraded_since, null);
  assert.deepEqual(coveragePushes(), ["Sin cobertura en su zona"]);

  pushServiceUp = true;
  await signed(port, "/events", alertFrom("chaparral"));
  await wait(150);
  assert.equal((await sensorStatus(port, "chaparral")).covered, true);
  assert.deepEqual(coveragePushes(), ["Sin cobertura en su zona", "Cobertura restablecida"]);
});

test("QA-36 users who left do not degrade a sensor, a broken push service does", async t => {
  const SECOND = "https://fcm.googleapis.com/fcm/send/chaparral-second-phone";
  let answers = {};
  mockPushService(t, endpoint => {
    throw Object.assign(new Error("fail"), { statusCode: answers[endpoint] });
  });
  const { port } = await startGateway(t);
  await signed(port, "/heartbeat", listenerBeat("chaparral"));
  await signed(port, "/heartbeat", watcherBeat("chaparral", true));
  const degradedAfter = async statuses => {
    answers = statuses;
    for (const endpoint of Object.keys(statuses)) await subscribe(port, "chaparral", endpoint);
    await signed(port, "/events", alertFrom("chaparral"));
    await wait(100);
    return (await sensorStatus(port, "chaparral")).degraded_since !== null;
  };

  assert.equal(await degradedAfter({ [CHAPARRAL]: 410, [SECOND]: 404 }), false, "uninstalls turned it red");
  // 400/413 mean our own payload is broken: that is the system failing, not the user leaving.
  assert.equal(await degradedAfter({ [CHAPARRAL]: 410, [SECOND]: 400 }), true);
});

test("QA-68 every phone gets a first try before anyone is retried", async t => {
  // More failing phones than the 500 in flight: every lane is busy retrying at once.
  const endpoints = Array.from({ length: 1_000 }, (_, i) => `https://fcm.googleapis.com/fcm/send/phone-${i}`);
  const failOnce = new Set(endpoints.slice(0, 500));
  const pushed = mockPushService(t, endpoint => {
    if (failOnce.delete(endpoint)) throw Object.assign(new Error("busy"), { statusCode: 503 });
    return { statusCode: 201 };
  });
  const directory = await tempDir(t);
  const subscriptionsFile = join(directory, "preloaded.json");
  await writeFile(subscriptionsFile, JSON.stringify({ chaparral: Object.fromEntries(
    endpoints.map(endpoint => [endpoint, { endpoint, keys: VALID_KEYS }])) }));
  const { port } = await startGateway(t, { subscriptionsFile });

  await signed(port, "/events", alertFrom("chaparral"));
  await wait(1_500);

  const firstRetry = pushed.findIndex((endpoint, index) => pushed.indexOf(endpoint) < index);
  assert.equal(pushed.length, 1_500, "not every failed phone was retried");
  assert.ok(pushed.indexOf(endpoints.at(-1)) < firstRetry,
    "the last phone waited behind the retries for its first try");
});

// QA-80: a restart must not paint every sensor red until they report again, and QA-81:
// /status tells the certifier when the process started.
test("QA-80 a restarted gateway keeps the last reports, and started_at moves", async t => {
  const pushed = mockPushService(t);
  const directory = await tempDir(t);
  const files = { heartbeatsFile: join(directory, "heartbeats.json"),
    subscriptionsFile: join(directory, "subscriptions.json"), coverageFile: join(directory, "coverage.json") };
  const first = await startGateway(t, files);
  await signed(first.port, "/heartbeat", listenerBeat("chaparral"));
  await signed(first.port, "/heartbeat", watcherBeat("chaparral", true));
  await subscribe(first.port, "chaparral", CHAPARRAL);
  const firstStart = (await status(first.port)).started_at;
  await first.close();
  await wait(20);

  const second = await startGateway(t, { ...files, startupGraceMs: 0, coverageCheckMs: 20 });
  await wait(150);
  const after = await status(second.port);

  assert.ok(Date.parse(after.started_at) > Date.parse(firstStart), "started_at did not move with the restart");
  assert.equal(after.sensors.find(sensor => sensor.id === "chaparral").covered, true, "red after every restart");
  assert.deepEqual(pushed.messages.filter(message => message.kind === "coverage"), [],
    "a restart told users coverage was lost");

  // Saved reports are still held to the 15 min rule: a sensor dead before the restart stays red.
  const old = Date.now() - 20 * 60_000;
  // Only the listener's beat is old: the watcher's fresh report must not cover for it.
  await writeFile(files.heartbeatsFile, JSON.stringify({ chaparral: { heartbeat_at: old, aea: { ok: true, at: Date.now() } } }));
  await second.close();
  const third = await startGateway(t, files);
  assert.equal((await sensorStatus(third.port, "chaparral")).covered, false, "a stale saved heartbeat counted as alive");
});

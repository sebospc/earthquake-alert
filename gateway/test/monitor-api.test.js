// The certifier's API (monitor/): signed /subscribe monitor:true, /probe and /evidence.
// Spec agreed with developer; see docs/qa/review.md, fase 9.
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import http from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { mock } from "node:test";

import webpush from "web-push";

import { createServer, monitorSignature, sensorKey } from "../src/server.js";

const SECRET = "test-secret";
const MONITOR_KEY = "monitor-key";
const KEYS = { p256dh: Buffer.alloc(65, 4).toString("base64url"), auth: Buffer.alloc(16, 1).toString("base64url") };
const MONITOR_ENDPOINT = "https://updates.push.services.mozilla.com/wpush/v2/monitor-chaparral";
const USER_ENDPOINT = "https://fcm.googleapis.com/fcm/send/user-chaparral";
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

async function startGateway(t, overrides = {}) {
  const directory = await mkdtemp(join(tmpdir(), "relay-monitor-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const config = {
    hmacSecret: SECRET, teamId: "TEAM", keyId: "KEY", bundleId: "com.example.relay", privateKey: "",
    dryRun: true, monitorKey: MONITOR_KEY,
    evidenceFile: join(directory, "evidence.jsonl"), subscriptionsFile: join(directory, "subscriptions.json"),
    devicesFile: join(directory, "devices.json"), coverageFile: join(directory, "coverage.json"),
    sensors: [{ id: "chaparral", public: true }, { id: "quibdo", public: true }],
    vapid: { subject: "mailto:qa@example.com", publicKey: "public", privateKey: "private" },
    ...overrides
  };
  const server = createServer(config);
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  return { config, port: server.address().port };
}

function mockPushService(t, answer = () => ({ statusCode: 201 })) {
  const pushed = [];
  mock.method(webpush, "sendNotification", async (subscription, payload) => {
    pushed.push({ endpoint: subscription.endpoint, message: JSON.parse(payload) });
    return answer(subscription.endpoint);
  });
  t.after(() => mock.restoreAll());
  return pushed;
}

function request(port, method, path, body = "", headers = {}) {
  return new Promise((resolve, reject) => {
    const outgoing = http.request({ hostname: "127.0.0.1", port, path, method, headers: {
      "content-type": "application/json", "content-length": Buffer.byteLength(body), ...headers } }, response => {
      let text = "";
      response.on("data", chunk => { text += chunk; });
      response.on("end", () => resolve({ status: response.statusCode, body: text }));
    });
    outgoing.on("error", reject);
    outgoing.end(body);
  });
}

// As monitor/monitor.py signs: seconds, METHOD, path with query, raw body.
function signed(port, method, path, payload, { key = MONITOR_KEY, skewS = 0 } = {}) {
  const body = payload === undefined ? "" : JSON.stringify(payload);
  const timestamp = String(Math.floor(Date.now() / 1000) + skewS);
  return request(port, method, path, body, {
    "x-monitor-timestamp": timestamp,
    "x-monitor-signature": monitorSignature(key, timestamp, method, path, body)
  });
}

const subscription = (endpoint, sensorId, extra = {}) =>
  ({ sensor_id: sensorId, subscription: { endpoint, keys: KEYS }, ...extra });

function sendAlert(port, sensorId, overrides = {}) {
  const now = Date.now();
  const raw = JSON.stringify({
    event_id: `${sensorId}:t${now}:${Math.random()}:alert`, source: "android_earthquake_alert_candidate",
    sensor_id: sensorId, captured_at: new Date(now).toISOString(),
    expires_at: new Date(now + 180_000).toISOString(), title: "Alerta de sismo", body: "Sismo.",
    interruption_level: "time-sensitive", time_occurred_s: Math.floor(now / 1000) - 17, ...overrides
  });
  return request(port, "POST", "/events", raw,
    { "x-relay-signature": createHmac("sha256", sensorKey(SECRET, sensorId)).update(raw).digest("hex") });
}

test("monitor routes answer 503 without MONITOR_KEY, 401 without a fresh valid signature", async t => {
  const unconfigured = await startGateway(t, { monitorKey: undefined });
  const configured = await startGateway(t);
  const probe = { probe_id: "p1", sent_at: new Date().toISOString() };

  assert.equal((await signed(unconfigured.port, "POST", "/probe", probe)).status, 503);
  assert.equal((await signed(unconfigured.port, "GET", "/evidence?since=2026-09-24T00:00:00Z")).status, 503);
  assert.equal((await signed(unconfigured.port, "POST", "/subscribe",
    subscription(MONITOR_ENDPOINT, "chaparral", { monitor: true }))).status, 503);

  const port = configured.port;
  assert.equal((await request(port, "POST", "/probe", JSON.stringify(probe))).status, 401, "unsigned");
  assert.equal((await signed(port, "POST", "/probe", probe, { key: "wrong" })).status, 401, "wrong key");
  assert.equal((await signed(port, "POST", "/probe", probe, { skewS: -61 })).status, 401, "replayed after 60 s");
  assert.equal((await signed(port, "POST", "/probe", probe, { skewS: 59 })).status, 202);
  // The query is signed too: a captured /evidence call cannot be widened.
  const timestamp = String(Math.floor(Date.now() / 1000));
  const widened = await request(port, "GET", "/evidence?since=2000-01-01T00:00:00Z", "", {
    "x-monitor-timestamp": timestamp,
    "x-monitor-signature": monitorSignature(MONITOR_KEY, timestamp, "GET", "/evidence?since=2026-09-24T00:00:00Z", "")
  });
  assert.equal(widened.status, 401);
  assert.equal((await request(port, "POST", "/subscribe",
    JSON.stringify(subscription(MONITOR_ENDPOINT, "chaparral", { monitor: true })))).status, 401,
  "anyone could mark themselves as monitor");
});

test("a probe reaches only the monitor subscriptions, through the real web push path", async t => {
  const pushed = mockPushService(t);
  const { config, port } = await startGateway(t);
  await request(port, "POST", "/subscribe", JSON.stringify(subscription(USER_ENDPOINT, "chaparral")));
  const monitorQuibdo = MONITOR_ENDPOINT.replace("chaparral", "quibdo");
  for (const [endpoint, sensorId] of [[MONITOR_ENDPOINT, "chaparral"], [monitorQuibdo, "quibdo"]]) {
    assert.equal((await signed(port, "POST", "/subscribe",
      subscription(endpoint, sensorId, { monitor: true }))).status, 201);
  }
  const sentAt = new Date().toISOString();

  const oneSensor = await signed(port, "POST", "/probe", { probe_id: "p-1", sent_at: sentAt, sensor_id: "chaparral" });
  await wait(50);
  const everySensor = await signed(port, "POST", "/probe", { probe_id: "p-2", sent_at: sentAt });
  await wait(50);

  assert.deepEqual(JSON.parse(oneSensor.body), { queued: 1 });
  assert.deepEqual(JSON.parse(everySensor.body), { queued: 2 });
  assert.equal(pushed.some(push => push.endpoint === USER_ENDPOINT), false, "a user got a probe");
  assert.deepEqual(pushed[0], { endpoint: MONITOR_ENDPOINT, message: {
    kind: "probe", probe_id: "p-1", sensor_id: "chaparral", sent_at: sentAt, tag: "probe:chaparral" } });
  assert.deepEqual(pushed.slice(1).map(push => [push.message.probe_id, push.message.sensor_id]).sort(),
    [["p-2", "chaparral"], ["p-2", "quibdo"]]);
  await assert.rejects(readFile(config.evidenceFile, "utf8"), /ENOENT/, "a probe left evidence");
  for (const bad of [{ probe_id: "", sent_at: sentAt }, { probe_id: "x".repeat(65), sent_at: sentAt },
    { probe_id: "p", sent_at: "yesterday" }, { probe_id: "p", sent_at: sentAt, sensor_id: "atlantis" }]) {
    assert.equal((await signed(port, "POST", "/probe", bad)).status, 400, JSON.stringify(bad));
  }
});

test("a failing probe never degrades a sensor: the monitor must not certify itself", async t => {
  mockPushService(t, () => { throw Object.assign(new Error("gone wrong"), { statusCode: 403 }); });
  const { port } = await startGateway(t);
  await signed(port, "POST", "/subscribe", subscription(MONITOR_ENDPOINT, "chaparral", { monitor: true }));

  await signed(port, "POST", "/probe", { probe_id: "p", sent_at: new Date().toISOString() });
  await wait(100);

  const status = JSON.parse((await request(port, "GET", "/status")).body);
  assert.deepEqual(status.sensors.find(sensor => sensor.id === "chaparral").degraded, { apns: null, webpush: null });
});

test("monitor subscriptions skip the IP limit and still get real alerts", async t => {
  const pushed = mockPushService(t);
  const { port } = await startGateway(t);
  const statuses = [];
  for (let i = 0; i < 35; i += 1) {
    statuses.push((await signed(port, "POST", "/subscribe",
      subscription(`${MONITOR_ENDPOINT}-${i}`, "chaparral", { monitor: true }))).status);
  }
  assert.deepEqual(statuses, Array(35).fill(201));

  await sendAlert(port, "chaparral");
  await wait(100);
  assert.equal(pushed.filter(push => push.message.kind === "alert").length, 35);
});

test("/evidence pages the records with accepted_at and delivered_at, signed per query", async t => {
  mockPushService(t, endpoint => {
    if (endpoint.endsWith("down")) throw Object.assign(new Error("down"), { statusCode: 500 });
    return { statusCode: 201 };
  });
  const { port } = await startGateway(t);
  await signed(port, "POST", "/subscribe", subscription(MONITOR_ENDPOINT, "chaparral", { monitor: true }));
  await request(port, "POST", "/subscribe", JSON.stringify(subscription(`${USER_ENDPOINT}-down`, "chaparral")));
  const before = new Date().toISOString();

  const posted = Date.now();
  await sendAlert(port, "chaparral", { expires_at: new Date(Date.now() + 1_500).toISOString() });
  await sendAlert(port, "quibdo");
  await wait(1_700);

  const all = JSON.parse((await signed(port, "GET", `/evidence?since=${before}`)).body);
  assert.deepEqual(all.records.map(record => record.type).sort(), ["NO_RECIPIENTS", "WEB_PUSH_DISPATCH"]);
  const dispatch = all.records.find(record => record.type === "WEB_PUSH_DISPATCH");
  assert.ok(Math.abs(Date.parse(dispatch.accepted_at) - posted) < 1_000, "accepted_at is not the arrival");
  assert.ok(Date.parse(dispatch.accepted_at) <= Date.parse(dispatch.at));
  const delivered = dispatch.web_push.find(result => result.status === 201);
  const failed = dispatch.web_push.find(result => result.status === 500);
  assert.ok(Date.parse(delivered.delivered_at) >= Date.parse(dispatch.accepted_at));
  assert.equal(failed.delivered_at, null);
  assert.equal(JSON.stringify(all).includes(USER_ENDPOINT), false, "a full endpoint leaked");

  const first = JSON.parse((await signed(port, "GET", `/evidence?since=${before}&limit=1`)).body);
  const second = JSON.parse((await signed(port, "GET", `/evidence?since=${encodeURIComponent(first.next_since)}&limit=1`)).body);
  assert.equal(first.records.length, 1);
  assert.deepEqual([...first.records, ...second.records].map(record => record.at), all.records.map(record => record.at));
  const later = JSON.parse((await signed(port, "GET", `/evidence?since=${encodeURIComponent(all.next_since)}`)).body);
  assert.deepEqual(later.records, [], "the last page's next_since repeats a record");
  for (const query of ["?since=yesterday", `?since=${before}&limit=0`, `?since=${before}&limit=x`]) {
    assert.equal((await signed(port, "GET", `/evidence${query}`)).status, 400, query);
  }
});

test("latency stamps: received_at <= accepted_at, 202 before the fanout, sent_at per push", async t => {
  let release;
  const pushServiceHeld = new Promise(resolve => { release = resolve; });
  const pushed = mockPushService(t, async () => { await pushServiceHeld; return { statusCode: 201 }; });
  const { port } = await startGateway(t);
  await signed(port, "POST", "/subscribe", subscription(MONITOR_ENDPOINT, "chaparral", { monitor: true }));
  await request(port, "POST", "/devices",
    JSON.stringify({ device_token: "ab".repeat(32), sensor_ids: ["chaparral"], platform: "ios" }));
  const before = new Date().toISOString();

  const answer = await sendAlert(port, "chaparral");
  assert.equal(answer.status, 202);
  await wait(50);
  assert.equal(pushed.length, 1, "the push had not started");
  release();
  await wait(200);

  const { records } = JSON.parse((await signed(port, "GET", `/evidence?since=${before}`)).body);
  const dispatch = records.find(record => record.type === "WEB_PUSH_DISPATCH");
  assert.ok(Date.parse(dispatch.received_at) <= Date.parse(dispatch.accepted_at));
  const [webPush] = dispatch.web_push;
  const [apns] = dispatch.apns;
  for (const result of [webPush, apns]) {
    assert.ok(Date.parse(dispatch.accepted_at) <= Date.parse(result.sent_at), JSON.stringify(result));
    assert.ok(Date.parse(result.sent_at) <= Date.parse(result.delivered_at), JSON.stringify(result));
  }
  // The push service held the answer, so only delivered_at can carry that wait.
  assert.ok(Date.parse(webPush.delivered_at) - Date.parse(webPush.sent_at) >= 40);
});

test("QA-78 /evidence moves on when one 'at' has more records than the page", async t => {
  const { config, port } = await startGateway(t);
  const at = "2026-09-24T10:00:00.000Z";
  await writeFile(config.evidenceFile, [1, 2, 3].map(n => JSON.stringify({ type: "COVERAGE_LOST", at, n })).join("\n") + "\n");

  const seen = [];
  let since = "2026-09-24T00:00:00.000Z";
  for (let page = 0; page < 5 && seen.length < 3; page += 1) {
    const body = JSON.parse((await signed(port, "GET", `/evidence?since=${encodeURIComponent(since)}&limit=2`)).body);
    seen.push(...body.records.map(record => record.n));
    since = body.next_since;
  }
  assert.deepEqual(seen, [1, 2, 3], "the client loops on the first record of the group");
});

// QA-79: a public sensor with no receiver behind it was offered to users as coverage.
test("QA-79 a public sensor that never reported is flagged once, and only that one", async t => {
  const { port } = await startGateway(t, {
    startupGraceMs: 0, coverageCheckMs: 20, silentSensorAfterMs: 100,
    sensors: [{ id: "chaparral", public: true }, { id: "quibdo", public: true }, { id: "hinatuan", public: false }]
  });
  const raw = JSON.stringify({ sensor_id: "chaparral", sent_at: new Date().toISOString() });
  await request(port, "POST", "/heartbeat", raw,
    { "x-relay-signature": createHmac("sha256", sensorKey(SECRET, "chaparral")).update(raw).digest("hex") });

  await wait(400);

  const { records } = JSON.parse((await signed(port, "GET", "/evidence?since=2000-01-01T00:00:00Z")).body);
  const silent = records.filter(record => record.type === "PUBLIC_SENSOR_SILENT");
  assert.deepEqual(silent.map(record => record.sensor_id), ["quibdo"],
    "missed the silent one, flagged a reporting or non-public one, or repeated it every check");
});

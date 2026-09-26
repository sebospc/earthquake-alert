import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";

import { sendAllWithRetry, validateEvent, verifyHmac } from "../src/server.js";

function event(overrides = {}) {
  const now = Date.now();
  return {
    event_id: "event-1",
    source: "android_earthquake_alert_candidate",
    captured_at: new Date(now).toISOString(),
    expires_at: new Date(now + 60_000).toISOString(),
    title: "Earthquake nearby",
    body: "Drop, cover and hold on",
    interruption_level: "time-sensitive",
    ...overrides
  };
}

test("HMAC verification rejects altered bodies", () => {
  const body = Buffer.from('{"ok":true}');
  const signature = createHmac("sha256", "secret").update(body).digest("hex");
  assert.equal(verifyHmac(body, signature, "secret"), true);
  assert.equal(verifyHmac(Buffer.from('{"ok":false}'), signature, "secret"), false);
});

test("event validation rejects expired and untrusted sources", () => {
  assert.equal(validateEvent(event()).event_id, "event-1");
  assert.throws(() => validateEvent(event({ source: "synthetic" })), /source/);
  assert.throws(() => validateEvent(event({
    expires_at: new Date(Date.now() - 1).toISOString()
  })), /expired/);
});

test("a retryable failure gets a second try", async () => {
  let calls = 0;
  const results = await sendAllWithRetry([1], 1, async () => {
    calls += 1;
    return calls === 1 ? { status: 503 } : { status: 201 };
  }, Date.now() + 60_000);
  assert.equal(calls, 2, "one retry, then success");
  assert.equal(results[0].status, 201);
});

// CI flake on "QA-22 a transient push failure...": a coverage-check retry from a gateway a
// prior test had already closed landed on the next test's mocked push service, because
// nothing stopped a later round once the server was gone. isClosed() is that stop.
test("isClosed() stops a later round instead of retrying past a closed gateway", async () => {
  let calls = 0;
  let closed = false;
  const results = await sendAllWithRetry([1], 1, async () => {
    calls += 1;
    closed = true; // the gateway closes while this first send is still in flight
    return { status: 503 };
  }, Date.now() + 60_000, () => closed);
  assert.equal(calls, 1, "no second round once the gateway reports closed");
  assert.equal(results[0].status, 503, "the one attempt's real result is kept, not overwritten");
});

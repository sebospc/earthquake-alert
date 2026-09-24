import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";

import { validateEvent, verifyHmac } from "../src/server.js";

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

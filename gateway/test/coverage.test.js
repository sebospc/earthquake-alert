// QA-25 / QA-31: which sensor a phone gets, and when the page may show green.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { coverageState, coverageTier, nearestSensor } from "../public/coverage.js";

const sensorsJson = JSON.parse(readFileSync(new URL("../public/sensors.json", import.meta.url)));
const thresholds = sensorsJson.coverage;
const publicSensor = { id: "chaparral", public: true };

test("tiers follow the Allen radii at the exact borders", () => {
  assert.deepEqual(thresholds, { ...thresholds, full_km: 31, partial_km: 78 });
  assert.equal(coverageTier(31, publicSensor, thresholds), "full");
  assert.equal(coverageTier(31.01, publicSensor, thresholds), "partial");
  assert.equal(coverageTier(78, publicSensor, thresholds), "partial");
  assert.equal(coverageTier(78.01, publicSensor, thresholds), "none");
  assert.equal(coverageTier(0, { id: "x", public: false }, thresholds), "none");
  assert.equal(coverageTier(0, { id: "x" }, thresholds), "none", "a missing flag must fail closed");
});

test("the control sensor is never offered, even standing next to it", () => {
  const inHinatuan = nearestSensor({ lat: 8.3667, lon: 126.3333 }, sensorsJson);
  assert.notEqual(inHinatuan.id, "hinatuan");
  assert.equal(inHinatuan.tier, "none");

  const inChaparral = nearestSensor({ lat: 3.72, lon: -75.48 }, sensorsJson);
  assert.equal(inChaparral.id, "chaparral");
  assert.equal(inChaparral.tier, "full");

  // Bogotá is ~190 km from Chaparral: nearest, but not covered.
  assert.equal(nearestSensor({ lat: 4.711, lon: -74.0721 }, sensorsJson).tier, "none");
});

test("the page shows green only when the server says covered, and red when it cannot ask", () => {
  const healthy = {
    id: "chaparral", covered: true, covered_webpush: true, covered_apns: true,
    stale: false, aea_ok: true, aea_stale: false,
    last_heartbeat_at: "2026-09-24T10:00:00.000Z", aea_checked_at: "2026-09-24T10:02:00.000Z"
  };
  const status = sensor => ({ now: "2026-09-24T10:05:00.000Z", relay_enabled: true, sensors: [sensor] });

  assert.equal(coverageState(status(healthy), "chaparral").healthy, true);
  assert.match(coverageState(status(healthy), "chaparral").text, /5 min/, "age from the older check");
  assert.equal(coverageState(null, "chaparral").healthy, false, "/status down still green");
  assert.equal(coverageState({ ...status(healthy), relay_enabled: false }, "chaparral").healthy, false);
  assert.equal(coverageState(status(healthy), "quibdo").healthy, false, "unknown sensor");
  // QA-59: the page follows its own channel. A cut only on APNs leaves the web green.
  assert.equal(coverageState(status({ ...healthy, covered: false, covered_apns: false }), "chaparral")
    .healthy, true, "an APNs-only outage turned the web page red");
  for (const broken of [{ stale: true }, { aea_stale: true }, { aea_ok: false }, { aea_ok: null },
    { covered_webpush: false }]) {
    assert.equal(coverageState(status({ ...healthy, ...broken }), "chaparral").healthy, false,
      JSON.stringify(broken));
  }
});

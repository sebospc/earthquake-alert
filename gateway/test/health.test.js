// QA-116: an unreachable gateway must turn the health page red, never leave the last banner green.
import assert from "node:assert/strict";
import test from "node:test";

import { healthState } from "../public/health.js";

const sensorConfig = { sensors: [
  { id: "chaparral", name: "Chaparral", public: true },
  { id: "quibdo", name: "Quibdó", public: true }
] };

function status(overrides = {}) {
  return {
    started_at: "2026-09-26T08:00:00.000Z",
    apns_dry_run: true,
    sensors: [
      { id: "chaparral", covered: true, aea_ok: true, last_heartbeat_at: "2026-09-26T09:59:00.000Z" },
      { id: "quibdo", covered: true, aea_ok: true, last_heartbeat_at: "2026-09-26T09:58:00.000Z" }
    ],
    ...overrides
  };
}

const NOW = Date.parse("2026-09-26T10:00:00.000Z");

test("all receptors covered banners green, with names and heartbeat age", () => {
  const state = healthState(status(), sensorConfig, NOW, NOW);
  assert.equal(state.bannerClass, "ok");
  assert.equal(state.bannerText, "All receptors healthy");
  assert.deepEqual(state.rows.map(row => row.name), ["Chaparral", "Quibdó"]);
  assert.equal(state.rows[0].heartbeatAgo, "1m ago");
  assert.match(state.meta, /Uptime: 2h 0m/);
});

test("one receptor down degrades the banner, none covered turns it fully down", () => {
  const oneDown = status({ sensors: [
    { id: "chaparral", covered: true, aea_ok: true, last_heartbeat_at: "2026-09-26T09:59:00.000Z" },
    { id: "quibdo", covered: false, aea_ok: false, last_heartbeat_at: null }
  ] });
  const degraded = healthState(oneDown, sensorConfig, NOW, NOW);
  assert.equal(degraded.bannerClass, "warn");
  assert.equal(degraded.bannerText, "Degraded: 1 of 2 receptors down");
  assert.equal(degraded.rows[1].heartbeatAgo, "never");

  const allDown = status({ sensors: oneDown.sensors.map(sensor => ({ ...sensor, covered: false })) });
  assert.equal(healthState(allDown, sensorConfig, NOW, NOW).bannerClass, "bad");
});

test("an unreachable gateway turns the banner red and shows the last good answer's age", () => {
  const stale = healthState(null, null, NOW + 90_000, NOW);
  assert.equal(stale.bannerClass, "bad");
  assert.match(stale.bannerText, /Cannot reach the gateway/);
  assert.match(stale.bannerText, /2m ago/);
  assert.deepEqual(stale.rows, []);

  const neverLoaded = healthState(null, null, NOW, null);
  assert.equal(neverLoaded.bannerText, "Cannot reach the gateway");
});

// A sensor in /status with no matching entry in sensors.json (deleted mid-poll) falls back
// to its id, rather than showing "undefined".
test("a sensor missing from sensors.json falls back to its id", () => {
  const state = healthState(status(), { sensors: [] }, NOW, NOW);
  assert.deepEqual(state.rows.map(row => row.name), ["chaparral", "quibdo"]);
});

// QA-117: green receptors say nothing about iPhones while APNs is in dry run.
test("dry run always warns, even with every receptor green; live APNs does not", () => {
  const dryRun = healthState(status({ apns_dry_run: true }), sensorConfig, NOW, NOW);
  assert.equal(dryRun.bannerClass, "ok");
  assert.match(dryRun.warning, /not live/);

  assert.equal(healthState(status({ apns_dry_run: false }), sensorConfig, NOW, NOW).warning, "");
  assert.equal(healthState(null, null, NOW, NOW).warning, "", "unreachable: the banner already says it");
});

test("a canary down does not degrade the banner, but keeps its row", () => {
  const config = { sensors: [
    { id: "chaparral", name: "Chaparral", public: true },
    { id: "general-santos", name: "General Santos", public: false }
  ] };
  const state = healthState(status({ sensors: [
    { id: "chaparral", covered: true, aea_ok: true, last_heartbeat_at: "2026-09-26T09:59:00.000Z" },
    { id: "general-santos", covered: false, aea_ok: false, last_heartbeat_at: null }
  ] }), config, NOW, NOW);
  assert.equal(state.bannerClass, "ok");
  assert.equal(state.rows.length, 2, "the canary stays listed");
  assert.equal(state.rows[1].covered, false);

  const publicDown = healthState(status({ sensors: [
    { id: "chaparral", covered: false, aea_ok: true, last_heartbeat_at: null },
    { id: "general-santos", covered: true, aea_ok: true, last_heartbeat_at: null }
  ] }), config, NOW, NOW);
  assert.equal(publicDown.bannerClass, "bad", "a healthy canary must not hide a public outage");
});

test("no sensors to judge is 'No receptor data', never green", () => {
  const empty = healthState(status({ sensors: [] }), sensorConfig, NOW, NOW);
  assert.equal(empty.bannerClass, "warn");
  assert.equal(empty.bannerText, "No receptor data");
  const onlyCanaries = healthState(status(), { sensors: sensorConfig.sensors.map(s => ({ ...s, public: false })) }, NOW, NOW);
  assert.equal(onlyCanaries.bannerText, "No receptor data");
});

// QA-118: unknown must not hide an outage.
test("a down sensor absent from sensors.json still counts in the banner", () => {
  const state = healthState(status({ sensors: [
    { id: "chaparral", covered: true, aea_ok: true, last_heartbeat_at: "2026-09-26T09:59:00.000Z" },
    { id: "ghost", covered: false, aea_ok: false, last_heartbeat_at: null }
  ] }), { sensors: [{ id: "chaparral", name: "Chaparral", public: true }] }, NOW, NOW);
  assert.equal(state.bannerClass, "warn");
  assert.equal(state.bannerText, "Degraded: 1 of 2 receptors down");
});

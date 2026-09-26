// Health-page decisions, kept free of DOM so they can be tested with node.

function ago(iso, now) {
  if (!iso) return "never";
  const seconds = Math.max(0, Math.round((now - Date.parse(iso)) / 1000));
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  return `${Math.round(minutes / 60)}h ago`;
}

function duration(ms) {
  const minutes = Math.max(0, Math.round(ms / 60_000));
  const hours = Math.floor(minutes / 60);
  return hours > 0 ? `${hours}h ${minutes % 60}m` : `${minutes}m`;
}

/**
 * { bannerClass, bannerText, warning, rows, meta } for the page. `status`/`sensorConfig` are the
 * /status and /sensors.json bodies, or null when that fetch failed: an unreachable gateway
 * must turn the banner red, never keep the last "healthy" one standing (QA-116).
 */
export function healthState(status, sensorConfig, now, lastGoodAt) {
  if (!status || !sensorConfig) {
    return {
      bannerClass: "bad",
      bannerText: lastGoodAt
        ? `Cannot reach the gateway (last update ${ago(new Date(lastGoodAt).toISOString(), now)})`
        : "Cannot reach the gateway",
      rows: [],
      warning: "",
      meta: ""
    };
  }
  const names = new Map(sensorConfig.sensors.map(sensor => [sensor.id, sensor.name]));
  // A canary (public: false) going down is an internal signal, not lost coverage for visitors.
  // A sensor missing from sensors.json counts: unknown must not hide an outage.
  const privateIds = new Set(sensorConfig.sensors.filter(sensor => sensor.public === false).map(sensor => sensor.id));
  const bannerSensors = status.sensors.filter(sensor => !privateIds.has(sensor.id));
  const covered = bannerSensors.filter(sensor => sensor.covered).length;
  const total = bannerSensors.length;
  // Nothing to judge is missing data or a bad config, never "all healthy".
  const bannerClass = total === 0 ? "warn" : covered === total ? "ok" : covered === 0 ? "bad" : "warn";
  const bannerText = total === 0
    ? "No receptor data"
    : covered === total
      ? "All receptors healthy"
      : covered === 0
        ? "All receptors down"
        : `Degraded: ${total - covered} of ${total} receptors down`;
  return {
    bannerClass,
    bannerText,
    rows: status.sensors.map(sensor => ({
      id: sensor.id,
      name: names.get(sensor.id) ?? sensor.id,
      covered: sensor.covered,
      aeaOk: sensor.aea_ok === true,
      heartbeatAgo: ago(sensor.last_heartbeat_at, now)
    })),
    // Green receptors say nothing about iPhones: in dry run no push is sent to any phone.
    warning: status.apns_dry_run ? "Push notifications are not live: APNs is in dry run, no iPhone gets alerts." : "",
    meta: `APNs dry run: ${status.apns_dry_run ? "yes" : "no"} `
      + `· Uptime: ${duration(now - Date.parse(status.started_at))}`
  };
}

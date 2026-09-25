import { createHash, createHmac, createPrivateKey, randomUUID, sign, timingSafeEqual } from "node:crypto";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { appendFile, readFile, rename, writeFile } from "node:fs/promises";
import http from "node:http";
import http2 from "node:http2";
import https from "node:https";
import { extname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import webpush from "web-push";

const seen = new Map();
const MAX_BODY_BYTES = 16_384;
const MAX_FUTURE_MS = 5 * 60_000;
const MAX_SUBSCRIPTIONS = 10_000;
const MAX_DEVICES = 10_000;
const MAX_SENSORS_PER_DEVICE = 3;
// A far phone follows a receptor for strong quakes only; below 4.0 or above 7.0 is a bug.
const MIN_MAGNITUDE_RANGE = [4.0, 7.0];
// Two sensors that saw one quake report origins a few seconds apart at most.
const SAME_QUAKE_WINDOW_MS = 30_000;
// Apple rejects provider tokens older than an hour and throttles fresher refreshes than 20 min.
const PROVIDER_TOKEN_TTL_MS = 40 * 60_000;
// The app has to be reinstalled for these; the token will never work again. Not
// DeviceTokenNotForTopic: a wrong APNS_BUNDLE_ID gives it for every phone, and deleting them
// all would hide that config error behind "no active recipients".
const APNS_GONE_REASONS = new Set(["BadDeviceToken", "Unregistered", "ExpiredToken"]);
// Our side is wrong, not the phone: logged loudly, and the failed alerts degrade the sensor.
const APNS_CONFIG_REASONS = new Set(["InvalidProviderToken", "MissingProviderToken", "BadTopic",
  "MissingTopic", "TopicDisallowed", "DeviceTokenNotForTopic", "BadCertificateEnvironment"]);
const APNS_CONFIG_LOG_EVERY_MS = 10 * 60_000;
const PUSH_TIMEOUT_MS = 5_000;
// Apple allows ~1000 concurrent streams per connection. More in flight only queue inside
// Node, where they time out and get resent (measured: QA-61).
const APNS_STREAMS_PER_CONNECTION = 1000;
// Several connections, as Apple suggests for volume: at ~130 ms to APNs one connection
// tops out near 7700 pushes/s, and a sensor may have tens of thousands of iPhones.
// 4 capped 100k pushes at 2.5 s of pure waiting at 100 ms; 8 took them from 3.7 to 3.1 s.
const APNS_CONNECTIONS = 8;
// Web push: one socket per send in flight. Also bounds how much encryption runs before the
// event loop gets a turn (heartbeats, /status).
const WEB_PUSH_MAX_IN_FLIGHT = 500;
// A VAPID JWT may live 12 h; renewed well before so no push ever carries an expired one.
const VAPID_JWT_LIFETIME_S = 12 * 60 * 60;
const VAPID_REFRESH_MS = 60 * 60_000;
// Events expire within 5 min, so an older id can only come back as an expired replay.
const SEEN_TTL_MS = 15 * 60_000;
const LATE_AFTER_ORIGIN_MS = 120_000;
const MAX_EXPIRY_AFTER_ORIGIN_MS = 5 * 60_000;
// Three missed 5-min beats. Past this a sensor is shown and announced as uncovered.
const STALE_AFTER_MS = 15 * 60_000;
const COVERAGE_PUSH_TTL_MS = 12 * 60 * 60_000;
const REGISTRATION_WINDOW_MS = 10 * 60_000;
// Per IP and endpoint. The app calls /devices on every significant location change, and
// mobile CGNAT puts many phones behind one IP, so it gets far more room than /subscribe.
const REGISTRATIONS_PER_IP = { subscribe: 30, devices: 120 };
const MONITOR_CLOCK_SKEW_S = 60;
const PROBE_TTL_MS = 60_000;
// The test button: one per phone per window, so a leaked token cannot be used to buzz a phone.
const TEST_PUSH_WINDOW_MS = 10 * 60_000;
const TEST_PUSH_TTL_MS = 60_000;
const MAX_PROBE_ID_LENGTH = 64;
// Arrival telemetry, test phones only: a batch per upload, the app retries on 429.
const MAX_ARRIVALS_PER_UPLOAD = 500;
const TELEMETRY_BODY_BYTES = 131_072;
const TELEMETRY_UPLOADS_PER_WINDOW = 120;
const MAX_ARRIVAL_EVENT_ID_LENGTH = 200;
const ARRIVAL_KINDS = new Set(["alert", "test", "probe"]);
const ARRIVAL_SOURCES = new Set(["nse", "app"]);
const ARRIVAL_APP_STATES = new Set(["foreground", "background", "unknown"]);
// Device test T5: 50 pushes, at least a second apart, so APNs sees a phone and not a flood.
const MAX_BURST_PUSHES = 50;
const BURST_INTERVAL_RANGE_MS = [1000, 60_000];
// Dedup memory per test phone; a few hundred pushes a day, so this is weeks of them.
const MAX_TELEMETRY_KEYS_PER_TOKEN = 20_000;
const MAX_EVIDENCE_PAGE = 1000;
const APNS_HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com"
};
const PUBLIC_DIR = fileURLToPath(new URL("../public/", import.meta.url));
const SENSORS_FILE = join(PUBLIC_DIR, "sensors.json");
const STATIC_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json",
  ".webmanifest": "application/manifest+json",
  ".png": "image/png"
};
// The gateway POSTs to every stored endpoint, so an arbitrary URL would let anyone
// point it at internal addresses. Only the browsers' real push services are accepted.
const PUSH_SERVICE_HOSTS = [
  "web.push.apple.com",
  "fcm.googleapis.com",
  "push.services.mozilla.com",
  "notify.windows.com"
];

export function verifyHmac(rawBody, supplied, secret) {
  if (!secret || !supplied) return false;
  const expected = createHmac("sha256", secret).update(rawBody).digest("hex");
  const actual = supplied.replace(/^sha256=/, "");
  if (!/^[0-9a-f]{64}$/i.test(actual) || actual.length !== expected.length) return false;
  return timingSafeEqual(Buffer.from(actual, "hex"), Buffer.from(expected, "hex"));
}

/**
 * The monitor (certifier) signs method, path with query, body and a timestamp with its own
 * key, so a captured request cannot be replayed after a minute or pointed at another route.
 */
export function monitorSignature(monitorKey, timestamp, method, pathWithQuery, rawBody) {
  return createHmac("sha256", monitorKey)
    .update(`${timestamp}\n${method} ${pathWithQuery}\n${rawBody}`).digest("hex");
}

/** Per-sensor key, HMAC(master, sensor_id): a leaked sensor secret cannot sign for another. */
export function sensorKey(masterSecret, sensorId) {
  return createHmac("sha256", masterSecret).update(sensorId).digest("hex");
}

// Every sensor signs with its own key; the master secret itself signs nothing.
function signingKey(body, masterSecret) {
  return typeof body?.sensor_id === "string" ? sensorKey(masterSecret, body.sensor_id) : null;
}

function parseJson(raw) {
  try {
    return JSON.parse(raw.toString("utf8"));
  } catch {
    return null;
  }
}

// The quake's origin when the sensor knows it. Otherwise the moment Play Services posted
// the warning, the latest the quake can have happened: a warning replayed after a
// reconnect must still be judged by its age, not by when it was re-sent.
export function originOf(event) {
  for (const [key, toMs] of [["time_occurred_s", 1000], ["post_time_ms", 1]]) {
    const value = event[key];
    if (value === undefined || value === null) continue;
    if (!Number.isFinite(value)) throw new Error(`invalid ${key}`);
    return value * toMs;
  }
  return null;
}

export function validateEvent(event, now = Date.now()) {
  const required = ["event_id", "captured_at", "expires_at", "title", "body"];
  for (const key of required) {
    if (typeof event[key] !== "string" || event[key].length === 0) {
      throw new Error(`invalid ${key}`);
    }
  }
  if (event.source !== "android_earthquake_alert_candidate") {
    throw new Error("invalid source");
  }
  const capturedAt = Date.parse(event.captured_at);
  let expiresAt = Date.parse(event.expires_at);
  if (!Number.isFinite(capturedAt) || !Number.isFinite(expiresAt)) {
    throw new Error("invalid timestamps");
  }
  let late = false;
  let originAgeMs = 0;
  const originMs = originOf(event);
  if (originMs !== null) {
    if (originMs - now > MAX_FUTURE_MS) throw new Error("origin in the future");
    // The sensor's TTL counts from capture; a capture that was itself late would still
    // say "take cover" long after the shaking. The quake's origin is the real clock.
    expiresAt = Math.min(expiresAt, originMs + MAX_EXPIRY_AFTER_ORIGIN_MS);
    originAgeMs = now - originMs;
    late = originAgeMs > LATE_AFTER_ORIGIN_MS;
  }
  if (expiresAt <= now) throw new Error("expired event");
  if (expiresAt - now > MAX_FUTURE_MS) throw new Error("expiry too far in future");
  if (Math.abs(now - capturedAt) > MAX_FUTURE_MS) throw new Error("stale captured_at");
  if (event.title.length > 180 || event.body.length > 500) {
    throw new Error("alert text too long");
  }
  // "critical" needs Apple's Critical Alerts entitlement, which has not been granted.
  if (!["active", "time-sensitive"].includes(event.interruption_level)) {
    throw new Error("invalid interruption_level");
  }
  return { ...event, expires_at: new Date(expiresAt).toISOString(), late, ...userText(event, late, originAgeMs) };
}

/**
 * The only place the words a user reads are made. The sensor's own title and body are
 * still required, for old senders, but never shown: an old or compromised receptor cannot
 * put words on phones. No distance either: AEA's is from the receptor, not from the phone.
 */
function userText(event, late, originAgeMs) {
  if (late) {
    const minutes = String(Math.round(originAgeMs / 60_000));
    return {
      title: "Aviso de sismo atrasado",
      body: `El sismo ocurrió hace ${minutes} min. Ya no es un aviso anticipado.`,
      interruption_level: "active",
      loc: { titleKey: "LATE_ALERT_TITLE", bodyKey: "LATE_ALERT_BODY", args: [minutes] }
    };
  }
  const magnitude = Number.isFinite(event.magnitude) ? event.magnitude.toFixed(1) : null;
  return {
    title: "Alerta de sismo",
    body: magnitude === null
      ? "Posible sismo cerca de su zona. Protéjase ahora."
      : `Sismo M${magnitude} cerca de su zona. Protéjase ahora.`,
    loc: magnitude === null
      ? { titleKey: "ALERT_TITLE", bodyKey: "ALERT_BODY_NO_MAGNITUDE", args: [] }
      : { titleKey: "ALERT_TITLE", bodyKey: "ALERT_BODY_MAGNITUDE", args: [magnitude] }
  };
}

/**
 * iOS renders the loc keys in the phone's language from the app's String Catalog; the keys
 * and their args are listed in docs/ios-contract.md. Args are locale-neutral strings ("4.8"
 * with a dot), the app formats them. title and body stay, in Spanish, for builds without keys.
 */
function localizedAlert(message, { titleKey, bodyKey, args = [] }) {
  return { title: message.title, body: message.body, "title-loc-key": titleKey, "loc-key": bodyKey, "loc-args": args };
}

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

export function createProviderToken({ teamId, keyId, privateKey }, now = Date.now()) {
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: Math.floor(now / 1000) }));
  const unsigned = `${header}.${claims}`;
  const signature = sign("sha256", Buffer.from(unsigned), {
    key: createPrivateKey(privateKey),
    dsaEncoding: "ieee-p1363"
  });
  return `${unsigned}.${signature.toString("base64url")}`;
}

/**
 * Never rejects: { token_suffix, status, reason, sent_at, delivered_at }, status -1 when APNs
 * never answered. `payload` is a string, or a function of the send time in epoch ms.
 */
function apnsRequest(client, token, headers, payload) {
  return new Promise(resolve => {
    const sentAtMs = Date.now();
    const sentAt = new Date(sentAtMs).toISOString();
    let request;
    try {
      request = client.request({ ":method": "POST", ":path": `/3/device/${token}`, ...headers });
    } catch (error) {
      resolve({ token_suffix: token.slice(-8), status: -1, reason: error.message, sent_at: sentAt });
      return;
    }
    let responseBody = "";
    let status = -1;
    // A push that never answers must not keep the event claimed forever. Counted again
    // from when the stream really goes out ("ready"), not from when it was queued.
    const cancel = () => request.close(http2.constants.NGHTTP2_CANCEL);
    let timer = setTimeout(cancel, PUSH_TIMEOUT_MS);
    request.on("ready", () => {
      clearTimeout(timer);
      timer = setTimeout(cancel, PUSH_TIMEOUT_MS);
    });
    request.setEncoding("utf8");
    request.on("response", responseHeaders => { status = responseHeaders[":status"]; });
    request.on("data", chunk => { responseBody += chunk; });
    // The outcome is read on close; an error only means this token got nothing.
    request.on("error", () => {});
    request.on("close", () => {
      clearTimeout(timer);
      let reason = null;
      // A 200 has no body; a throw per push cost 0.4 s of CPU on 100k pushes.
      if (responseBody) {
        try {
          reason = JSON.parse(responseBody).reason ?? null;
        } catch {}
      }
      // Reported as 410 so every caller treats a dead token like a dead web push endpoint.
      if (APNS_GONE_REASONS.has(reason)) status = 410;
      resolve({ token_suffix: token.slice(-8), status, reason, sent_at: sentAt, delivered_at: deliveredAt(status) });
    });
    request.end(typeof payload === "function" ? payload(sentAtMs) : payload);
  });
}

// Same collapse id and web push tag for every sensor that saw the quake, so the phone
// replaces rather than stacks. Buckets by minute; the per-token memory does the exact match.
export function quakeTag(originMs) {
  return `quake:${Math.round(originMs / 60_000)}`;
}

const finiteOrNull = value => (Number.isFinite(value) ? value : null);
// When the push service accepted it, for the certifier's "accepted to first delivery".
const deliveredAt = status => (status >= 200 && status < 300 ? new Date().toISOString() : null);

/**
 * The structured fields are there so the app can decide on AlarmKit by itself. `sent_at_ms`
 * is stamped per phone as its request goes out: the NSE logs arrival against it (APNs leg).
 */
function apnsAlertPayload(event) {
  const withoutClosingBrace = JSON.stringify({
    aps: {
      alert: localizedAlert(event, event.loc),
      sound: "default",
      "interruption-level": event.interruption_level,
      "thread-id": "earthquake-alerts",
      // The app's Notification Service Extension rewrites or upgrades the alert.
      "mutable-content": 1
    },
    kind: "alert",
    event_id: event.event_id,
    sensor_id: event.sensor_id,
    magnitude: finiteOrNull(event.magnitude),
    distance_km: finiteOrNull(event.distance_km),
    time_occurred_s: finiteOrNull(event.time_occurred_s),
    late: event.late,
    expires_at: event.expires_at
  }).slice(0, -1);
  // ponytail: string splice, not a JSON.stringify per phone; it runs 10k times per quake.
  return sentAtMs => `${withoutClosingBrace},"sent_at_ms":${sentAtMs}}`;
}

function isPushServiceEndpoint(endpoint) {
  let url;
  try {
    url = new URL(endpoint);
  } catch {
    return false;
  }
  return url.protocol === "https:" && PUSH_SERVICE_HOSTS.some(
    host => url.hostname === host || url.hostname.endsWith(`.${host}`)
  );
}

const base64urlBytes = value => Buffer.from(value, "base64url").length;

/** Keeps only the push endpoint and its keys: nothing else the phone sends is stored. */
export function validateSubscription(request, knownSensorIds) {
  const { sensor_id: sensorId, subscription } = request;
  if (!knownSensorIds.has(sensorId)) throw new Error("unknown sensor_id");
  if (!subscription || !isPushServiceEndpoint(subscription.endpoint)) {
    throw new Error("invalid subscription endpoint");
  }
  const { p256dh, auth } = subscription.keys ?? {};
  // Garbage keys make every send throw without a status, so they would never be cleaned up.
  if (typeof p256dh !== "string" || base64urlBytes(p256dh) !== 65
      || typeof auth !== "string" || base64urlBytes(auth) !== 16) {
    throw new Error("invalid subscription keys");
  }
  return { sensorId, subscription: { endpoint: subscription.endpoint, keys: { p256dh, auth } } };
}

function validateDeviceToken(token) {
  // APNs tokens are hex, 32 bytes today; Apple says the length may grow.
  if (typeof token !== "string" || !/^([0-9a-f]{2}){32,100}$/i.test(token)) {
    throw new Error("invalid device_token");
  }
  return token.toLowerCase();
}

/** All or nothing: a batch with one bad item is refused whole, and the app drops it. */
export function validateArrivals(arrivals) {
  if (!Array.isArray(arrivals) || arrivals.length === 0 || arrivals.length > MAX_ARRIVALS_PER_UPLOAD) {
    throw new Error("invalid arrivals");
  }
  const isEpochMs = value => Number.isSafeInteger(value) && value > 0;
  return arrivals.map(arrival => {
    const { kind, event_id: eventId, sent_at_ms: sentAtMs, received_at_ms: receivedAtMs, source,
      app_state: appState } = arrival ?? {};
    if (!ARRIVAL_KINDS.has(kind) || !ARRIVAL_SOURCES.has(source) || !ARRIVAL_APP_STATES.has(appState)
        || typeof eventId !== "string" || eventId.length === 0 || eventId.length > MAX_ARRIVAL_EVENT_ID_LENGTH
        || !isEpochMs(sentAtMs) || !isEpochMs(receivedAtMs)) {
      throw new Error("invalid arrivals");
    }
    return { kind, eventId, sentAtMs, receivedAtMs, source, appState };
  });
}

/**
 * The app sends its token and the sensors it picked on the phone; never a location.
 * Only public sensors: a control or unlisted one would look like coverage and is not.
 */
export function validateDevice(request, publicSensorIds) {
  const { device_token: token, sensor_ids: ids, demand_cell: demandCell, platform,
    apns_env: apnsEnv = "production", min_magnitude: minMagnitude } = request;
  if (platform !== "ios") throw new Error("invalid platform");
  // A development build's token only works against the sandbox, and the other way round.
  if (!Object.hasOwn(APNS_HOSTS, apnsEnv)) throw new Error("invalid apns_env");
  // Outside coverage the phone sends only its 0.1° cell, never coordinates or sensors. With
  // "limited" coverage it sends both: alerts follow the sensors, the cell asks for a closer one.
  if (demandCell !== undefined && ids === undefined) {
    if (minMagnitude !== undefined) throw new Error("invalid min_magnitude");
    return { token: validateDeviceToken(token), sensorIds: [], demandCell: validateDemandCell(demandCell), apnsEnv };
  }
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > MAX_SENSORS_PER_DEVICE
      || new Set(ids).size !== ids.length || !ids.every(id => publicSensorIds.has(id))) {
    throw new Error("invalid sensor_ids");
  }
  return { token: validateDeviceToken(token), sensorIds: ids,
    demandCell: demandCell === undefined ? null : validateDemandCell(demandCell), apnsEnv,
    minMagnitude: validateMinMagnitude(minMagnitude, ids) };
}

/** `{ sensorId: magnitude }` over a subset of the device's sensors; {} when absent. */
function validateMinMagnitude(minMagnitude, sensorIds) {
  if (minMagnitude === undefined) return {};
  const [lowest, highest] = MIN_MAGNITUDE_RANGE;
  const valid = minMagnitude !== null && typeof minMagnitude === "object" && !Array.isArray(minMagnitude)
    && Object.entries(minMagnitude).every(([sensorId, magnitude]) => sensorIds.includes(sensorId)
      && typeof magnitude === "number" && magnitude >= lowest && magnitude <= highest);
  if (!valid) throw new Error("invalid min_magnitude");
  return { ...minMagnitude };
}

/** "floor(lat*10),floor(lon*10)", e.g. "37,-755": a cell of about 11 km. */
export function validateDemandCell(cell) {
  const match = typeof cell === "string" ? /^(-?\d{1,3}),(-?\d{1,4})$/.exec(cell) : null;
  const [lat10, lon10] = match ? [Number(match[1]), Number(match[2])] : [NaN, NaN];
  if (!(lat10 >= -900 && lat10 < 900 && lon10 >= -1800 && lon10 < 1800)) {
    throw new Error("invalid demand_cell");
  }
  return `${lat10},${lon10}`;
}

/** Returns { sensorId, aeaOk }; aeaOk is undefined for the listener's own beat. */
export function validateHeartbeat(heartbeat, knownSensorIds, now = Date.now()) {
  if (!knownSensorIds.has(heartbeat.sensor_id)) throw new Error("unknown sensor_id");
  const sentAt = Date.parse(heartbeat.sent_at);
  // Bounds how long a captured heartbeat could be replayed to fake a live sensor.
  if (!Number.isFinite(sentAt) || Math.abs(now - sentAt) > MAX_FUTURE_MS) {
    throw new Error("stale sent_at");
  }
  if (heartbeat.aea_ok !== undefined && typeof heartbeat.aea_ok !== "boolean") {
    throw new Error("invalid aea_ok");
  }
  return { sensorId: heartbeat.sensor_id, aeaOk: heartbeat.aea_ok };
}

// ponytail: the whole file lives in memory and is rewritten atomically on each change.
// Fine for one process and a few thousand phones; move to SQLite past that.
/**
 * One write at a time, to a temp file then renamed, so a crash leaves the old or the new file,
 * never half of one. Every persist() made while a write runs shares the single next write,
 * which snapshots when it starts: with 100k phones a write per call queued 20 copies of a
 * 22 MB file and held the event loop, alerts included, for 1.2 s (docs/qa/load.md).
 * Each caller's promise settles once a write that includes its change is on disk.
 */
export function createJsonFile(file, initial) {
  const data = file && existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : initial;
  let running = null;
  let queued = null;
  function write() {
    queued = null;
    const snapshot = JSON.stringify(data);
    running = (async () => {
      await writeFile(`${file}.tmp`, snapshot, { mode: 0o600 });
      await rename(`${file}.tmp`, file);
    })().finally(() => { running = null; });
    return running;
  }
  return {
    data,
    persist() {
      if (!file) return Promise.resolve();
      if (queued) return queued;
      if (!running) return write();
      queued = running.catch(() => {}).then(write);
      return queued;
    }
  };
}

function createSubscriptionStore(file) {
  const store = createJsonFile(file, {});
  const bySensor = store.data;

  function removeEverywhere(endpoint) {
    for (const endpoints of Object.values(bySensor)) delete endpoints[endpoint];
  }

  return {
    list: sensorId => Object.values(bySensor[sensorId] ?? {}),
    /** [{ sensorId, subscription }] of the certifier's own subscriptions. */
    monitors: sensorId => Object.entries(bySensor)
      .filter(([id]) => sensorId === undefined || id === sensorId)
      .flatMap(([id, endpoints]) => Object.values(endpoints)
        .filter(subscription => subscription.monitor === true)
        .map(subscription => ({ sensorId: id, subscription }))),
    add(sensorId, subscription) {
      // A phone that moved re-subscribes to its new sensor and must stop hearing the old one.
      // Done before the limit check on purpose: at the limit that phone loses its old sensor
      // and gets a 400, which the page shows. Only reachable if the limit is ever hit.
      removeEverywhere(subscription.endpoint);
      const total = Object.values(bySensor)
        .reduce((sum, endpoints) => sum + Object.keys(endpoints).length, 0);
      if (total >= MAX_SUBSCRIPTIONS) throw new Error("subscription limit reached");
      bySensor[sensorId] ??= {};
      bySensor[sensorId][subscription.endpoint] = subscription;
      return store.persist();
    },
    remove(sensorId, endpoint) {
      delete bySensor[sensorId]?.[endpoint];
      return store.persist();
    }
  };
}

// ponytail: tokensFor scans every device per event. Fine for a few thousand; index by sensor
// when that shows up in the alert latency.
function createDeviceStore(file) {
  const store = createJsonFile(file, {});
  const byToken = store.data;
  return {
    tokensFor: sensorId => Object.keys(byToken)
      .filter(token => byToken[token].sensor_ids.includes(sensorId)),
    sensorsOf: token => byToken[token]?.sensor_ids ?? [],
    has: token => Object.hasOwn(byToken, token),
    apnsEnvOf: token => byToken[token]?.apns_env ?? "production",
    /** When APNs first accepted a push to this token; demand only counts after it. */
    verifiedAt: token => byToken[token]?.verified_at ?? null,
    minMagnitudeOf: (token, sensorId) => byToken[token]?.min_magnitude?.[sensorId] ?? null,
    /** Test phones the monitor opted in; only they may upload arrival telemetry. */
    telemetryEnabled: token => byToken[token]?.telemetry === true,
    // Replaces the whole set: the app calls this every time the phone moves. One demand
    // cell per token at most, so one phone can only ever weigh one.
    put(token, sensorIds, apnsEnv, demandCell = null, minMagnitude = {}) {
      if (!byToken[token] && Object.keys(byToken).length >= MAX_DEVICES) {
        throw new Error("device limit reached");
      }
      // What this phone was last told about each sensor survives re-registering it.
      const told = Object.fromEntries(Object.entries(byToken[token]?.coverage_told ?? {})
        .filter(([sensorId]) => sensorIds.includes(sensorId)));
      byToken[token] = { platform: "ios", sensor_ids: sensorIds, apns_env: apnsEnv, coverage_told: told,
        demand_cell: demandCell, min_magnitude: minMagnitude, verified_at: byToken[token]?.verified_at ?? null,
        // Set by the monitor only: re-registering from the app must not drop it.
        ...(byToken[token]?.telemetry === true && { telemetry: true }) };
      return store.persist();
    },
    setTelemetry(token, enabled) {
      if (enabled) byToken[token].telemetry = true;
      else delete byToken[token].telemetry;
      return store.persist();
    },
    setVerified(token, at) {
      if (!byToken[token] || byToken[token].verified_at) return Promise.resolve();
      byToken[token].verified_at = at;
      return store.persist();
    },
    /** The last coverage state this phone was told for this sensor; undefined if never. */
    coverageTold: (token, sensorId) => byToken[token]?.coverage_told?.[sensorId],
    setCoverageTold(token, sensorId, covered) {
      if (!byToken[token]) return Promise.resolve();
      byToken[token].coverage_told = { ...byToken[token].coverage_told, [sensorId]: covered };
      return store.persist();
    },
    remove(token) {
      delete byToken[token];
      return store.persist();
    }
  };
}

const isDelivered = status => status >= 200 && status < 300;
// The phone unsubscribed or the app was removed: the user left, the system is fine.
const isGone = status => status === 404 || status === 410;
// 429, 5xx, timeout and network errors can pass; 400/403/413 will fail the same way again.
const isRetryable = status => status === 429 || status >= 500 || status === -1;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
// For waits that must not keep a closing process alive.
const sleepUnref = ms => new Promise(resolve => setTimeout(resolve, Math.max(0, ms)).unref());

/**
 * Runs `work(item, lane)` over `items` with at most `limit` at once; results keep the
 * items' order. `lane` is the worker number, stable for everything that worker runs.
 */
async function mapLimited(items, limit, work) {
  const results = new Array(items.length);
  let next = 0;
  async function worker(lane) {
    while (next < items.length) {
      const index = next++;
      results[index] = await work(items[index], lane);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, (_, lane) => worker(lane)));
  return results;
}

/**
 * Sends to every item, `limit` at once, then retries only what can pass on a second try,
 * in rounds with backoff, while the TTL lasts. Every item gets its first try before any
 * retry: a passing 429/5xx on a few must not hold back the phones not yet tried.
 * `send(item, lane)` resolves { status, ... }; results keep the items' order, and an item
 * never tried in time reads as status -1.
 */
async function sendAllWithRetry(items, limit, send, deadlineMs) {
  const results = items.map(() => ({ status: -1 }));
  let pending = items.map((_, index) => index);
  for (const backoff of [0, 500, 1000, 2000, 4000]) {
    if (pending.length === 0 || Date.now() + backoff >= deadlineMs) break;
    if (backoff > 0) await sleep(backoff);
    await mapLimited(pending, limit, async (index, lane) => {
      // A long round must not send past the TTL either.
      if (Date.now() < deadlineMs) results[index] = await send(items[index], lane);
    });
    pending = pending.filter(index => isRetryable(results[index].status));
  }
  return results;
}

function loadSensors() {
  return JSON.parse(readFileSync(SENSORS_FILE, "utf8")).sensors;
}

/** The .p8 from Apple, as a file path (simplest in a systemd env file) or inline with literal \\n escapes. */
function readApnsKey(env) {
  if (env.APNS_PRIVATE_KEY && env.APNS_PRIVATE_KEY_FILE) {
    throw new Error("set APNS_PRIVATE_KEY or APNS_PRIVATE_KEY_FILE, not both");
  }
  if (env.APNS_PRIVATE_KEY_FILE) return readFileSync(env.APNS_PRIVATE_KEY_FILE, "utf8");
  return (env.APNS_PRIVATE_KEY || "").replaceAll("\\n", "\n");
}

/**
 * APNs only judges the key at the first push, which may be the first quake. Everything that
 * can be checked here stops the start instead.
 */
export function checkApnsConfig({ teamId, keyId, bundleId, privateKey }) {
  if (!/^[A-Z0-9]{10}$/.test(teamId)) throw new Error("invalid APNS_TEAM_ID: 10 letters or digits");
  if (!/^[A-Z0-9]{10}$/.test(keyId)) throw new Error("invalid APNS_KEY_ID: 10 letters or digits");
  if (!/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(bundleId)) throw new Error("invalid APNS_BUNDLE_ID");
  let key;
  try {
    key = createPrivateKey(privateKey);
  } catch (error) {
    throw new Error(`invalid APNS private key: ${error.message}`);
  }
  if (key.asymmetricKeyType !== "ec" || key.asymmetricKeyDetails?.namedCurve !== "prime256v1") {
    throw new Error("invalid APNS private key: not an Apple .p8 (EC P-256) key");
  }
  createProviderToken({ teamId, keyId, privateKey });
}

export function loadConfig(env = process.env) {
  const required = ["RELAY_HMAC_SECRET", "APNS_TEAM_ID", "APNS_KEY_ID", "APNS_BUNDLE_ID"];
  const dryRun = env.APNS_DRY_RUN === "1";
  if (!dryRun && !env.APNS_PRIVATE_KEY_FILE) required.push("APNS_PRIVATE_KEY");
  // Web push is optional, but half a VAPID config would fail only when an alert arrives.
  if (env.VAPID_PUBLIC_KEY) required.push("VAPID_PRIVATE_KEY", "VAPID_SUBJECT");
  for (const key of required) if (!env[key]) throw new Error(`missing ${key}`);
  const config = {
    hmacSecret: env.RELAY_HMAC_SECRET,
    teamId: env.APNS_TEAM_ID,
    keyId: env.APNS_KEY_ID,
    bundleId: env.APNS_BUNDLE_ID,
    privateKey: dryRun ? "" : readApnsKey(env),
    dryRun,
    evidenceFile: env.EVIDENCE_FILE || "gateway-evidence.jsonl",
    telemetryFile: env.TELEMETRY_FILE || "telemetry.jsonl",
    // Optional: without it /probe, /evidence and monitor subscriptions answer 503.
    monitorKey: env.MONITOR_KEY || null,
    killSwitch: env.RELAY_KILL_SWITCH === "1",
    sensors: loadSensors(),
    subscriptionsFile: env.SUBSCRIPTIONS_FILE || "subscriptions.json",
    devicesFile: env.DEVICES_FILE || "devices.json",
    coverageFile: env.COVERAGE_STATE_FILE || "coverage-state.json",
    heartbeatsFile: env.HEARTBEATS_FILE || "heartbeats.json",
    vapid: env.VAPID_PUBLIC_KEY
      ? {
          subject: env.VAPID_SUBJECT,
          publicKey: env.VAPID_PUBLIC_KEY,
          privateKey: env.VAPID_PRIVATE_KEY
        }
      : null
  };
  if (!dryRun) checkApnsConfig(config);
  return config;
}

// Evidence is for us, delivery is for the user: a failed write must never turn an alert
// that went out into a retry that wakes everyone again.
async function recordEvidence(evidenceFile, record) {
  try {
    await appendFile(evidenceFile, `${JSON.stringify(record)}\n`, { mode: 0o600 });
  } catch (error) {
    console.error(`evidence write failed: ${error.message}`);
  }
}

function pruneSeen(now) {
  for (const [eventId, at] of seen) if (now - at > SEEN_TTL_MS) seen.delete(eventId);
}

function sendJson(response, status, body) {
  response.writeHead(status, { "content-type": "application/json" }).end(JSON.stringify(body));
}

/** Resolves null as soon as the body is too big. */
function readBody(request, maxBytes = MAX_BODY_BYTES) {
  return new Promise(resolve => {
    const chunks = [];
    let size = 0;
    request.on("data", chunk => {
      size += chunk.length;
      if (size > maxBytes) resolve(null);
      else chunks.push(chunk);
    });
    request.on("end", () => resolve(Buffer.concat(chunks)));
  });
}

// The gateway only listens on loopback, so a proxy is always in front for phones. The
// last X-Forwarded-For entry is the one our proxy added; earlier ones are client-supplied.
function clientIp(request) {
  const forwarded = request.headers["x-forwarded-for"];
  return forwarded ? forwarded.split(",").at(-1).trim() : request.socket.remoteAddress;
}

export function createServer(config) {
  const sensors = config.sensors ?? [];
  const sensorIds = new Set(sensors.map(sensor => sensor.id));
  const publicSensorIds = new Set(sensors.filter(sensor => sensor.public === true).map(sensor => sensor.id));
  const subscriptions = createSubscriptionStore(config.subscriptionsFile);
  const devices = createDeviceStore(config.devicesFile);
  // device token -> quakes it was already told about, so two sensors seeing one quake wake
  // the phone once. In memory: a restart can at worst repeat one alert.
  const notifiedQuakes = new Map();
  // ponytail: in RAM, a restart resets it; bounded by the registered tokens (MAX_DEVICES).
  const lastTestPushAt = new Map();
  // ponytail: in RAM, a restart forgets them; the reader dedups on the same key anyway.
  const telemetrySeen = new Map();
  const telemetryUploads = new Map();
  const burstsRunning = new Set();
  let closed = false;
  // "env:slot" -> live HTTP/2 session. Sandbox and production are separate hosts.
  const apnsSessions = new Map();
  let providerToken = null;
  const lastConfigRejectionLog = new Map();
  // Without keep-alive every web push pays its own TCP+TLS handshake and a socket (QA-63).
  const webPushAgent = new https.Agent({ keepAlive: true, maxSockets: WEB_PUSH_MAX_IN_FLIGHT });
  const vapidHeaders = new Map();
  // "sensor_id:channel" -> "down" once that channel's users were told coverage is lost.
  // Persisted so a restart neither repeats that push nor forgets the "restored" one.
  const announcedCoverage = createJsonFile(config.coverageFile, {});
  // Persisted so a short restart does not paint every sensor red until its next report. The
  // 15 min freshness rule still runs on the stored times, so a sensor already dead before
  // the restart stays red.
  const heartbeats = createJsonFile(config.heartbeatsFile, {});
  const lastHeartbeatAt = new Map(Object.entries(heartbeats.data)
    .filter(([, entry]) => entry.heartbeat_at !== undefined)
    .map(([sensorId, entry]) => [sensorId, entry.heartbeat_at]));
  const aeaReports = new Map(Object.entries(heartbeats.data)
    .filter(([, entry]) => entry.aea !== undefined)
    .map(([sensorId, entry]) => [sensorId, entry.aea]));
  const lastCanaryOkAt = new Map();
  // sensor_id -> { apns, webpush }: when that channel's last alert reached nobody through
  // our own fault. Per channel, or a working web push would hide every iPhone failing.
  const degradedSince = new Map();
  const startedAt = Date.now();
  // ponytail: fixed window per IP in memory. Mobile CGNAT puts many phones behind one IP,
  // hence the loose limit; a per-install token if abuse ever outgrows it.
  const registrationsPerIp = { subscribe: new Map(), devices: new Map() };
  let registrationWindowStart = startedAt;
  // Only files present at startup are served, so a request path can never leave public/.
  const staticFiles = new Map(readdirSync(PUBLIC_DIR)
    .filter(name => STATIC_TYPES[extname(name)])
    .map(name => [`/${name}`, name]));
  staticFiles.set("/", "index.html");

  function sensorHealth(sensorId, now) {
    const heartbeatAt = lastHeartbeatAt.get(sensorId);
    const aea = aeaReports.get(sensorId);
    const isFresh = at => at !== undefined && now - at <= STALE_AFTER_MS;
    const listenerFresh = isFresh(heartbeatAt);
    // The host watcher reports on its own clock: a dead watcher must turn red, not
    // leave its last "true" standing.
    const aeaFresh = isFresh(aea?.at);
    const iso = at => at === undefined ? null : new Date(at).toISOString();
    const degraded = degradedSince.get(sensorId) ?? {};
    // A channel that nobody uses any more cannot fail anyone.
    const brokenChannels = degradedChannels(sensorId).filter(channel => hasRecipients(sensorId, channel));
    const degradedTimes = Object.values(degraded);
    const sensorWorks = !config.killSwitch && listenerFresh && aeaFresh && aea.ok === true;
    return {
      id: sensorId,
      // A sensor whose last alert reached nobody on some channel is not coverage for the
      // people on that channel, however healthy it looks. Per channel too, so an APNs
      // outage does not paint the web page red and the other way round.
      covered: sensorWorks && brokenChannels.length === 0,
      covered_apns: sensorWorks && degraded.apns === undefined,
      covered_webpush: sensorWorks && degraded.webpush === undefined,
      stale: !listenerFresh,
      last_heartbeat_at: iso(heartbeatAt),
      aea_ok: aea?.ok ?? null,
      aea_stale: !aeaFresh,
      aea_checked_at: iso(aea?.at),
      last_canary_ok_at: iso(lastCanaryOkAt.get(sensorId)),
      degraded_since: degradedTimes.length ? iso(Math.min(...degradedTimes)) : null,
      degraded: { apns: iso(degraded.apns), webpush: iso(degraded.webpush) }
    };
  }

  function degradedChannels(sensorId) {
    return Object.keys(degradedSince.get(sensorId) ?? {});
  }

  function hasRecipients(sensorId, channel) {
    return channel === "apns"
      ? devices.tokensFor(sensorId).length > 0
      : subscriptions.list(sensorId).length > 0;
  }

  /** Marks or clears one channel from one alert's results. Uninstalls say nothing. */
  function updateDegraded(sensorId, channel, results) {
    if (results.length === 0 || results.every(result => isGone(result.status))) return;
    const channels = degradedSince.get(sensorId) ?? {};
    if (results.some(result => isDelivered(result.status))) delete channels[channel];
    else channels[channel] ??= Date.now();
    if (Object.keys(channels).length > 0) degradedSince.set(sensorId, channels);
    else degradedSince.delete(sensorId);
  }

  async function sendWebPush(subscription, payload, options, deadlineMs) {
    const ttl = Math.max(0, Math.floor((deadlineMs - Date.now()) / 1000));
    // Before encryption: the push service may deliver before it answers, so delivered_at
    // alone does not say when the push left (QA hop 3).
    const sentAt = new Date().toISOString();
    let status;
    try {
      status = (await webpush.sendNotification(subscription, payload, { ...options, TTL: ttl })).statusCode;
    } catch (error) {
      status = error.statusCode ?? -1;
    }
    return { status, sent_at: sentAt, delivered_at: deliveredAt(status) };
  }

  /**
   * The VAPID signature is 65% of a web push's CPU and only depends on the push service,
   * so it is made once per service and hour instead of once per phone.
   */
  function vapidOptions(endpoint) {
    const audience = new URL(endpoint).origin;
    const cached = vapidHeaders.get(audience);
    if (cached && Date.now() - cached.at < VAPID_REFRESH_MS) return cached.options;
    let options;
    try {
      const headers = webpush.getVapidHeaders(audience, config.vapid.subject, config.vapid.publicKey,
        config.vapid.privateKey, "aes128gcm", Math.floor(Date.now() / 1000) + VAPID_JWT_LIFETIME_S);
      options = { vapidDetails: null, headers };
    } catch {
      // Keys the helper rejects: let web-push sign per send, which reports the same error.
      options = { vapidDetails: config.vapid };
    }
    vapidHeaders.set(audience, { options, at: Date.now() });
    return options;
  }

  /** Never rejects. `deadlineMs` also bounds the TTL: past it the push service drops it. */
  function pushToSensor(sensorId, message, deadlineMs) {
    return pushTo(subscriptions.list(sensorId).map(subscription => ({ sensorId, subscription })),
      message, deadlineMs);
  }

  /** `targets` is [{ sensorId, subscription }]. Never rejects. */
  async function pushTo(targets, message, deadlineMs) {
    if (!config.vapid) return [];
    const options = {
      urgency: "high",
      // A resent message replaces the copy still queued at the push service.
      topic: createHash("sha256").update(message.tag).digest("base64url").slice(0, 32),
      timeout: PUSH_TIMEOUT_MS,
      agent: webPushAgent
    };
    const payload = JSON.stringify(message);
    const results = await sendAllWithRetry(targets, WEB_PUSH_MAX_IN_FLIGHT, ({ subscription }) =>
      sendWebPush(subscription, payload, { ...options, ...vapidOptions(subscription.endpoint) },
        deadlineMs), deadlineMs);
    return Promise.all(targets.map(async ({ sensorId, subscription }, index) => {
      const { status, sent_at: sentAt, delivered_at: delivered } = results[index];
      if (isGone(status)) {
        await subscriptions.remove(sensorId, subscription.endpoint)
          .catch(error => console.error(`subscription cleanup failed: ${error.message}`));
      }
      return { endpoint_suffix: subscription.endpoint.slice(-8), status, sent_at: sentAt ?? null,
        delivered_at: delivered ?? null };
    }));
  }

  // One live HTTP/2 session for every push, as Apple asks; reopened when APNs drops it.
  function apnsClient(apnsEnv, slot) {
    const key = `${apnsEnv}:${slot}`;
    const current = apnsSessions.get(key);
    if (current && !current.closed && !current.destroyed) return current;
    // Node's default 10 MB session memory resets streams from ~7000 queued pushes on
    // (ENHANCE_YOUR_CALM), which turned into duplicates and lost alerts (QA-60).
    // Tests point config.apnsHost (both environments) or config.apnsHosts at fake servers.
    const host = config.apnsHost ?? (config.apnsHosts ?? APNS_HOSTS)[apnsEnv];
    const session = http2.connect(host, { maxSessionMemory: 1000 });
    // Without a listener a refused or dropped APNs connection is an uncaught error that
    // kills the gateway. Each stream already reports its own failure on close.
    session.on("error", () => {});
    session.on("close", () => {
      if (apnsSessions.get(key) === session) apnsSessions.delete(key);
    });
    // An idle session must not keep the process (or a test run) alive.
    session.unref();
    apnsSessions.set(key, session);
    return session;
  }

  function currentProviderToken() {
    if (!providerToken || Date.now() - providerToken.at > (config.providerTokenTtlMs ?? PROVIDER_TOKEN_TTL_MS)) {
      providerToken = { value: createProviderToken(config), at: Date.now() };
    }
    return providerToken.value;
  }

  function reportApnsConfigRejection(reason) {
    const now = Date.now();
    if (now - (lastConfigRejectionLog.get(reason) ?? -Infinity) < APNS_CONFIG_LOG_EVERY_MS) return;
    lastConfigRejectionLog.set(reason, now);
    console.error(`APNs rejects our configuration (${reason}): check APNS_TEAM_ID, APNS_KEY_ID, `
      + "APNS_BUNDLE_ID and the .p8 key; iPhones get nothing until it is fixed");
  }

  async function sendApns(token, payload, collapseId, deadlineMs, slot, pushType = "alert") {
    if (config.dryRun) {
      return { token_suffix: token.slice(-8), status: 200, dry_run: true,
        sent_at: new Date().toISOString(), delivered_at: deliveredAt(200) };
    }
    const send = async () => {
      let bearer;
      try {
        bearer = currentProviderToken();
      } catch (error) {
        return { result: { token_suffix: token.slice(-8), status: -1, reason: error.message } };
      }
      const result = await apnsRequest(apnsClient(devices.apnsEnvOf(token), slot), token, {
        authorization: `bearer ${bearer}`,
        "apns-topic": config.bundleId,
        "apns-push-type": pushType,
        // Apple rejects priority 10 on a background push.
        "apns-priority": pushType === "background" ? "5" : "10",
        // Absolute time: APNs drops it once the warning is useless instead of delivering late.
        "apns-expiration": String(Math.floor(deadlineMs / 1000)),
        "apns-collapse-id": collapseId
      }, payload);
      return { result, bearer };
    };
    let { result, bearer } = await send();
    // Apple's answer to a stale provider token: make a new one. Only if it is still the one
    // in use, or a thousand pushes in flight would each mint one (TooManyProviderTokenUpdates).
    if (result.reason === "ExpiredProviderToken") {
      if (providerToken?.value === bearer) providerToken = null;
      ({ result } = await send());
    }
    if (APNS_CONFIG_REASONS.has(result.reason)) reportApnsConfigRejection(result.reason);
    return result;
  }

  /**
   * True the first time this token hears of a quake within the same-quake window.
   * Accepted races: while sensor A's send to a token is in flight, sensor B's report of the
   * same quake skips that token; if A then fails for good, B's chance is gone (it would most
   * likely have failed the same way, same token and same APNs). And two real quakes less than
   * 30 s apart reach the phone as one; the first already said "take cover".
   */
  function claimQuake(token, originMs, now) {
    const recent = (notifiedQuakes.get(token) ?? []).filter(entry => now - entry.at <= SEEN_TTL_MS);
    if (recent.some(entry => Math.abs(entry.originMs - originMs) <= SAME_QUAKE_WINDOW_MS)) {
      notifiedQuakes.set(token, recent);
      return false;
    }
    notifiedQuakes.set(token, [...recent, { originMs, at: now }]);
    return true;
  }

  function releaseQuake(token, originMs) {
    notifiedQuakes.set(token, (notifiedQuakes.get(token) ?? [])
      .filter(entry => entry.originMs !== originMs));
  }

  /**
   * Never rejects. With `originMs`, a token already told about that quake is skipped. A token
   * whose `min_magnitude` for this sensor is above `magnitude` is skipped before it claims the
   * quake, so a closer sensor can still reach it. Unknown magnitude: sent, when unsure we alert.
   */
  function apnsToSensor(sensorId, payload, collapseId, deadlineMs, originMs = null, magnitude = null) {
    const now = Date.now();
    const wantsMagnitude = token => {
      const minimum = devices.minMagnitudeOf(token, sensorId);
      return minimum === null || !Number.isFinite(magnitude) || magnitude >= minimum;
    };
    return apnsToTokens(devices.tokensFor(sensorId).filter(wantsMagnitude)
      .filter(token => originMs === null || claimQuake(token, originMs, now)),
    payload, collapseId, deadlineMs, originMs);
  }

  /**
   * Never rejects. With `originMs`, a failed send releases that quake for the token.
   * ponytail: one thread. Measured 25-sep (load.md), 100 ms to APNs: 10k in 0.46 s, 100k in
   * 2.8-3.1 s, CPU-bound. So ~100k iPhones per sensor is the ceiling for the 3 s target; past
   * that, split the tokens across worker processes.
   */
  async function apnsToTokens(tokens, payload, collapseId, deadlineMs, originMs = null) {
    // Each worker keeps to one connection, so none carries more than Apple's stream limit.
    const results = await sendAllWithRetry(tokens, APNS_STREAMS_PER_CONNECTION * APNS_CONNECTIONS,
      (token, lane) => sendApns(token, payload, collapseId, deadlineMs, lane % APNS_CONNECTIONS),
      deadlineMs);
    return Promise.all(tokens.map(async (token, index) => {
      const result = results[index];
      // A failed send must not stop the same quake from another sensor reaching this phone.
      if (originMs !== null && !isDelivered(result.status)) releaseQuake(token, originMs);
      if (isGone(result.status)) {
        await devices.remove(token)
          .catch(error => console.error(`device cleanup failed: ${error.message}`));
      }
      return { token_suffix: token.slice(-8), ...result };
    }));
  }

  async function deliverAlert(event, receivedAt, acceptedAt) {
    const originMs = originOf(event);
    // Without an origin there is no way to tell two sensors' reports of one quake apart.
    const tag = originMs === null ? event.event_id : quakeTag(originMs);
    const deadlineMs = Date.parse(event.expires_at);
    const message = {
      kind: "alert",
      tag,
      title: event.title,
      body: event.body,
      // Decided here, on the server's clock; the phone's clock may be off.
      late: event.late
    };
    const [webPush, apns] = await Promise.all([
      pushToSensor(event.sensor_id, message, deadlineMs),
      apnsToSensor(event.sensor_id, apnsAlertPayload(event), tag, deadlineMs, originMs, event.magnitude)
    ]);
    updateDegraded(event.sensor_id, "webpush", webPush);
    updateDegraded(event.sensor_id, "apns", apns);
    const attempts = [...webPush, ...apns];
    let type = "WEB_PUSH_DISPATCH";
    if (attempts.length === 0) type = "NO_RECIPIENTS";
    else if (attempts.every(result => isGone(result.status))) type = "NO_ACTIVE_RECIPIENTS";
    else if (!attempts.some(result => isDelivered(result.status))) type = "DISPATCH_FAILED_ALL";
    await recordEvidence(config.evidenceFile, {
      type, at: new Date().toISOString(), received_at: receivedAt, accepted_at: acceptedAt, event,
      web_push: webPush, apns,
      degraded_channels: degradedChannels(event.sensor_id)
    });
  }

  async function handleEvent(request, response, raw, receivedAt) {
    const body = parseJson(raw);
    if (!verifyHmac(raw, request.headers["x-relay-signature"], signingKey(body, config.hmacSecret))) {
      response.writeHead(401).end();
      return;
    }
    if (body === null) throw new Error("invalid json");
    const event = validateEvent(body);
    const acceptedAt = new Date().toISOString();
    if (!sensorIds.has(event.sensor_id)) throw new Error("unknown sensor_id");
    // Proves config, key, sensor_id, network and clock of the relay path end to end,
    // without waking anyone.
    if (event.canary === true) {
      lastCanaryOkAt.set(event.sensor_id, Date.now());
      sendJson(response, 202, { canary: true });
      return;
    }
    if (config.killSwitch) {
      await recordEvidence(config.evidenceFile,
        { type: "RELAY_DISABLED", at: new Date().toISOString(), event });
      sendJson(response, 503, { error: "relay disabled" });
      return;
    }
    pruneSeen(Date.now());
    if (seen.has(event.event_id)) {
      sendJson(response, 202, { duplicate: true });
      return;
    }
    // Validated and queued is what the sensor needs to know; the gateway retries each
    // phone on its own, which must not hold the sensor past its 5 s timeout.
    seen.set(event.event_id, Date.now());
    const queued = subscriptions.list(event.sensor_id).length
      + devices.tokensFor(event.sensor_id).length;
    sendJson(response, 202, { accepted: true, queued });
    // After the answer: encrypting thousands of web pushes first held the 202 past the
    // sensor's 5 s timeout (QA-62).
    setImmediate(() => deliverAlert(event, receivedAt, acceptedAt)
      .catch(error => console.error(`alert delivery failed: ${error.message}`)));
  }

  function handleHeartbeat(request, response, raw) {
    const body = parseJson(raw);
    if (!verifyHmac(raw, request.headers["x-relay-signature"], signingKey(body, config.hmacSecret))) {
      response.writeHead(401).end();
      return;
    }
    if (body === null) throw new Error("invalid json");
    const { sensorId, aeaOk } = validateHeartbeat(body, sensorIds);
    // aea_ok comes from the host watcher, which can read dumpsys. It must not count as the
    // listener's own beat, or a dead listener behind a live watcher would look healthy.
    const entry = heartbeats.data[sensorId] ??= {};
    if (aeaOk === undefined) {
      entry.heartbeat_at = Date.now();
      lastHeartbeatAt.set(sensorId, entry.heartbeat_at);
    } else {
      entry.aea = { ok: aeaOk, at: Date.now() };
      aeaReports.set(sensorId, entry.aea);
    }
    heartbeats.persist().catch(error => console.error(`heartbeat state write failed: ${error.message}`));
    response.writeHead(204).end();
  }

  /** Answers 429 itself and returns false when this IP is over the endpoint's limit. */
  function allowRegistration(request, response, endpoint) {
    const now = Date.now();
    if (now - registrationWindowStart > REGISTRATION_WINDOW_MS) {
      for (const counts of Object.values(registrationsPerIp)) counts.clear();
      registrationWindowStart = now;
    }
    const counts = registrationsPerIp[endpoint];
    const ip = clientIp(request);
    const count = (counts.get(ip) ?? 0) + 1;
    counts.set(ip, count);
    if (count <= REGISTRATIONS_PER_IP[endpoint]) return true;
    sendJson(response, 429, { error: "too many subscriptions" });
    return false;
  }

  function coveragePayload(sensorId, covered) {
    const message = covered
      ? { title: "Cobertura restablecida", body: "Las alertas de su zona vuelven a funcionar." }
      : { title: "Servicio interrumpido", body: "Ahora mismo no podemos avisarle." };
    const loc = covered
      ? { titleKey: "COVERAGE_RESTORED_TITLE", bodyKey: "COVERAGE_RESTORED_BODY" }
      : { titleKey: "SERVICE_DOWN_TITLE", bodyKey: "SERVICE_DOWN_BODY" };
    return {
      message,
      // A phone may follow up to 3 sensors: sensor_id and covered let the app decide
      // whether its zone as a whole lost coverage.
      apnsPayload: JSON.stringify({
        aps: { alert: localizedAlert(message, loc), sound: "default", "interruption-level": "active",
          "mutable-content": 1 },
        kind: "coverage", sensor_id: sensorId, covered
      })
    };
  }

  /**
   * A phone that joins a sensor already down is told so now, once for that sensor, so the
   * later "restored" push is not the first thing it hears. Only sensors new to this token:
   * the app registers again on every move, and that must not repeat it.
   */
  /**
   * Coverage news for `tokens` of one sensor, each phone told only when it changes for that
   * phone: "lost" to whoever was not told so yet, "restored" only to whoever heard "lost".
   * A phone that got "lost" on registering does not get it again from the transition.
   */
  async function tellCoverage(sensorId, tokens, covered, deadlineMs) {
    const recipients = tokens.filter(token => (covered
      ? devices.coverageTold(token, sensorId) === false
      : devices.coverageTold(token, sensorId) !== false));
    const results = await apnsToTokens(recipients, coveragePayload(sensorId, covered).apnsPayload,
      `coverage:${sensorId}`, deadlineMs);
    await Promise.all(recipients.filter((_, index) => isDelivered(results[index].status))
      .map(token => devices.setCoverageTold(token, sensorId, covered)))
      .catch(error => console.error(`coverage state write failed: ${error.message}`));
    return results;
  }

  /** A phone that follows a sensor already down is told so now, so "restored" makes sense. */
  function tellNewDeviceAboutLostCoverage(token, sensorIdsOfToken) {
    const now = Date.now();
    for (const sensorId of sensorIdsOfToken) {
      if (sensorHealth(sensorId, now).covered_apns) continue;
      tellCoverage(sensorId, [token], false, now + COVERAGE_PUSH_TTL_MS)
        .catch(error => console.error(`coverage notice failed: ${error.message}`));
    }
  }

  async function handleDevice(request, response, raw) {
    if (!allowRegistration(request, response, "devices")) return;
    const device = validateDevice(JSON.parse(raw.toString("utf8")), publicSensorIds);
    await devices.put(device.token, device.sensorIds, device.apnsEnv, device.demandCell, device.minMagnitude);
    sendJson(response, 201, {
      sensor_ids: device.sensorIds,
      ...(device.demandCell && { demand_cell: device.demandCell }),
      ...(Object.keys(device.minMagnitude ?? {}).length > 0 && { min_magnitude: device.minMagnitude }),
      apns_env: device.apnsEnv,
      ...(devices.telemetryEnabled(device.token) && { telemetry: true })
    });
    if (device.sensorIds.length === 0) tellNoCoverageYet(device.token);
    else tellNewDeviceAboutLostCoverage(device.token, device.sensorIds);
    if (device.demandCell && device.sensorIds.length > 0) verifySilently(device.token);
  }

  /**
   * A "limited" phone has receptors, so "no coverage yet" would be false. A background push
   * shows nothing and its APNs 200 verifies the token just the same. Retried on the next
   * registration while unverified.
   */
  function verifySilently(token) {
    if (devices.verifiedAt(token)) return;
    const payload = JSON.stringify({ aps: { "content-available": 1 }, kind: "verify" });
    sendApns(token, payload, "verify", Date.now() + COVERAGE_PUSH_TTL_MS, 0, "background")
      .then(result => isDelivered(result.status)
        ? devices.setVerified(token, new Date().toISOString()) : undefined)
      .catch(error => console.error(`verify push failed: ${error.message}`));
  }

  /**
   * Once per token: "no coverage yet". Its APNs 200 is also what makes the demand count, so
   * an invented token (APNs rejects it) never weighs in placing a receptor.
   */
  function tellNoCoverageYet(token) {
    if (devices.verifiedAt(token)) return;
    const message = { title: "Sin cobertura en su zona", body: "Su zona todavía no tiene cobertura." };
    const payload = JSON.stringify({
      aps: {
        alert: localizedAlert(message, { titleKey: "NO_COVERAGE_TITLE", bodyKey: "NO_COVERAGE_BODY" }),
        sound: "default",
        "interruption-level": "active"
      },
      kind: "coverage", sensor_id: null, covered: false, reason: "no_receptor"
    });
    apnsToTokens([token], payload, "coverage:none", Date.now() + COVERAGE_PUSH_TTL_MS)
      .then(([result]) => isDelivered(result.status)
        ? devices.setVerified(token, new Date().toISOString()) : undefined)
      .catch(error => console.error(`no-coverage notice failed: ${error.message}`));
  }

  /**
   * "Enviar alerta de prueba": how a real alert sounds, on demand (App Review cannot wait for a
   * quake). Not a quake: no dedup entry, no evidence record (the certifier never sees it), and
   * its outcome never degrades a channel.
   */
  function handleTestPush(request, response, raw) {
    if (!allowRegistration(request, response, "devices")) return;
    // A test that rings while real alerts are off would tell the user they are protected.
    if (config.killSwitch) {
      sendJson(response, 503, { error: "relay paused" });
      return;
    }
    const token = validateDeviceToken(JSON.parse(raw.toString("utf8")).device_token);
    if (!devices.has(token)) {
      sendJson(response, 404, { error: "unknown device_token" });
      return;
    }
    const now = Date.now();
    if (now - (lastTestPushAt.get(token) ?? -Infinity) < TEST_PUSH_WINDOW_MS) {
      sendJson(response, 429, { error: "one test alert per 10 min" });
      return;
    }
    lastTestPushAt.set(token, now);
    const eventId = `test:${randomUUID()}`;
    const payload = JSON.stringify({
      aps: {
        alert: localizedAlert(
          { title: "Alerta de prueba", body: "Así sonará una alerta de sismo. Esto es solo una prueba." },
          { titleKey: "TEST_ALERT_TITLE", bodyKey: "TEST_ALERT_BODY" }),
        sound: "default",
        // Never critical: a test must not get past the silent switch the way a quake might.
        "interruption-level": "time-sensitive",
        "mutable-content": 1
      },
      kind: "test",
      // Unique, so the phone's arrival telemetry dedups on it like on an alert's.
      event_id: eventId,
      sent_at_ms: now
    });
    sendJson(response, 202, { sent_at_ms: now, event_id: eventId });
    sendApns(token, payload, `test:${token.slice(0, 8)}`, now + TEST_PUSH_TTL_MS, 0)
      .catch(error => console.error(`test push failed: ${error.message}`));
  }

  /** Monitor only: opts a test phone in to arrival telemetry and APNs bursts, or out. */
  async function handleTelemetrySwitch(request, response, raw) {
    if (!monitorAuthorized(request, response, raw)) return;
    const { device_token: deviceToken, enabled } = JSON.parse(raw.toString("utf8"));
    const token = validateDeviceToken(deviceToken);
    if (typeof enabled !== "boolean") throw new Error("invalid enabled");
    if (!devices.has(token)) {
      sendJson(response, 404, { error: "unknown device_token" });
      return;
    }
    await devices.setTelemetry(token, enabled);
    sendJson(response, 200, { telemetry: enabled });
  }

  function allowTelemetryUpload(token) {
    const now = Date.now();
    const window = telemetryUploads.get(token);
    if (!window || now - window.start > REGISTRATION_WINDOW_MS) {
      telemetryUploads.set(token, { start: now, count: 1 });
      return true;
    }
    window.count += 1;
    return window.count <= TELEMETRY_UPLOADS_PER_WINDOW;
  }

  /**
   * When each push reached a test iPhone, against the gateway's sent_at_ms: the APNs leg of the
   * certifier's chain. Own file, no state shared with the fanout, so nothing a phone uploads
   * can slow or break an alert.
   */
  async function handleArrivals(request, response, raw) {
    const body = JSON.parse(raw.toString("utf8"));
    const token = validateDeviceToken(body.device_token);
    // One answer for unknown and not opted in: a guessed token learns nothing.
    if (!devices.telemetryEnabled(token)) {
      sendJson(response, 404, { error: "unknown device_token or telemetry off" });
      return;
    }
    if (!allowTelemetryUpload(token)) {
      sendJson(response, 429, { error: "too many uploads" });
      return;
    }
    const arrivals = validateArrivals(body.arrivals);
    const seenKeys = telemetrySeen.get(token) ?? new Set();
    telemetrySeen.set(token, seenKeys);
    const fresh = [];
    for (const arrival of arrivals) {
      const key = `${arrival.eventId}\n${arrival.source}`;
      if (seenKeys.has(key)) continue;
      seenKeys.add(key);
      fresh.push({ key, arrival });
    }
    for (const oldest of seenKeys) {
      if (seenKeys.size <= MAX_TELEMETRY_KEYS_PER_TOKEN) break;
      seenKeys.delete(oldest);
    }
    const at = new Date().toISOString();
    const lines = fresh.map(({ arrival }) => `${JSON.stringify({
      type: "ARRIVAL", at, token_suffix: token.slice(-8), kind: arrival.kind, event_id: arrival.eventId,
      source: arrival.source, app_state: arrival.appState, sent_at_ms: arrival.sentAtMs,
      received_at_ms: arrival.receivedAtMs, latency_ms: arrival.receivedAtMs - arrival.sentAtMs
    })}\n`).join("");
    if (lines) {
      try {
        await appendFile(config.telemetryFile, lines, { mode: 0o600 });
      } catch (error) {
        // Not stored, so not seen: the app's retry must be able to store it.
        for (const { key } of fresh) seenKeys.delete(key);
        console.error(`telemetry write failed: ${error.message}`);
        sendJson(response, 503, { error: "telemetry not stored" });
        return;
      }
    }
    sendJson(response, 202, { stored: fresh.length, duplicates: arrivals.length - fresh.length });
  }

  /**
   * Device test T5: `n` pushes to one opted-in test phone, `interval_ms` apart, each with its
   * own event_id so the phone's arrivals pair with them. Skips the test button's 10 min limit;
   * the monitor key and the opt-in are the guard. One burst per phone at a time.
   */
  async function handleApnsBurst(request, response, raw) {
    if (!monitorAuthorized(request, response, raw)) return;
    const { device_token: deviceToken, n, interval_ms: intervalMs } = JSON.parse(raw.toString("utf8"));
    const token = validateDeviceToken(deviceToken);
    if (!Number.isInteger(n) || n < 1 || n > MAX_BURST_PUSHES) throw new Error("invalid n");
    const [minIntervalMs, maxIntervalMs] = BURST_INTERVAL_RANGE_MS;
    if (!Number.isInteger(intervalMs) || intervalMs < minIntervalMs || intervalMs > maxIntervalMs) {
      throw new Error("invalid interval_ms");
    }
    if (!devices.telemetryEnabled(token)) {
      sendJson(response, 404, { error: "unknown device_token or telemetry off" });
      return;
    }
    if (burstsRunning.has(token)) {
      sendJson(response, 409, { error: "burst already running" });
      return;
    }
    const probeId = randomUUID();
    burstsRunning.add(token);
    sendJson(response, 202, { probe_id: probeId, n, interval_ms: intervalMs });
    runBurst(token, probeId, n, intervalMs)
      .catch(error => console.error(`apns burst failed: ${error.message}`))
      .finally(() => burstsRunning.delete(token));
  }

  /** Paced from the start, not from each answer: a slow APNs reply must not stretch the burst. */
  async function runBurst(token, probeId, n, intervalMs) {
    const startMs = Date.now();
    const sends = [];
    for (let seq = 1; seq <= n; seq += 1) {
      await sleepUnref(startMs + (seq - 1) * intervalMs - Date.now());
      // Stops once the token is gone (APNs said so on an earlier push) or the gateway closes.
      if (closed || !devices.has(token)) break;
      const eventId = `probe:${probeId}:${seq}`;
      const withoutClosingBrace = JSON.stringify({
        aps: {
          alert: { title: "Prueba de entrega", body: `Prueba ${seq} de ${n}. No es un sismo.` },
          sound: "default",
          "interruption-level": "active",
          "mutable-content": 1
        },
        kind: "probe",
        event_id: eventId,
        probe_id: probeId,
        seq
      }).slice(0, -1);
      sends.push(apnsToTokens([token], sentAtMs => `${withoutClosingBrace},"sent_at_ms":${sentAtMs}}`,
        eventId, Date.now() + PROBE_TTL_MS)
        .then(([result]) => ({ seq, event_id: eventId, ...result })));
    }
    const results = await Promise.all(sends);
    // The APNs side of T5; the phone side comes through /telemetry/arrivals.
    await recordEvidence(config.evidenceFile, {
      type: "APNS_BURST", at: new Date().toISOString(), probe_id: probeId, token_suffix: token.slice(-8),
      n, interval_ms: intervalMs, results
    });
  }

  // Idempotent: 204 whether or not the token was registered, so the app can simply retry.
  async function handleDeviceRemoval(request, response, raw) {
    if (!allowRegistration(request, response, "devices")) return;
    const token = validateDeviceToken(JSON.parse(raw.toString("utf8")).device_token);
    if (devices.has(token)) await devices.remove(token);
    response.writeHead(204).end();
  }

  /**
   * Answers 503 or 401 itself and returns false unless the request carries a fresh, valid
   * monitor signature.
   */
  function monitorAuthorized(request, response, raw) {
    if (!config.monitorKey) {
      sendJson(response, 503, { error: "monitor not configured" });
      return false;
    }
    const timestamp = request.headers["x-monitor-timestamp"];
    const fresh = /^\d+$/.test(timestamp ?? "")
      && Math.abs(Date.now() / 1000 - Number(timestamp)) <= MONITOR_CLOCK_SKEW_S;
    const expected = fresh && monitorSignature(config.monitorKey, timestamp, request.method, request.url,
      raw.toString("utf8"));
    const supplied = request.headers["x-monitor-signature"] ?? "";
    if (fresh && supplied.length === expected.length
        && timingSafeEqual(Buffer.from(supplied), Buffer.from(expected))) {
      return true;
    }
    response.writeHead(401).end();
    return false;
  }

  async function handleSubscribe(request, response, raw) {
    const body = JSON.parse(raw.toString("utf8"));
    const monitor = body.monitor === true;
    // The certifier's own subscriptions: signed, and outside the per-IP limit.
    if (monitor ? !monitorAuthorized(request, response, raw)
      : !allowRegistration(request, response, "subscribe")) {
      return;
    }
    if (!config.vapid) {
      sendJson(response, 503, { error: "web push not configured" });
      return;
    }
    // Users only follow public receptors; the certifier also follows canaries and controls.
    const { sensorId, subscription } = validateSubscription(body, monitor ? sensorIds : publicSensorIds);
    await subscriptions.add(sensorId, monitor ? { ...subscription, monitor: true } : subscription);
    sendJson(response, 201, { sensor_id: sensorId });
  }

  /**
   * A test push to the certifier's subscriptions only, never to users, through the same
   * pool, VAPID cache and agent as a real alert. No evidence and no degraded: a probe is not
   * an alert, and counting it would have the monitor certify itself.
   */
  async function handleProbe(request, response, raw) {
    if (!monitorAuthorized(request, response, raw)) return;
    const { probe_id: probeId, sent_at: sentAt, sensor_id: sensorId } = JSON.parse(raw.toString("utf8"));
    if (typeof probeId !== "string" || probeId.length === 0 || probeId.length > MAX_PROBE_ID_LENGTH) {
      throw new Error("invalid probe_id");
    }
    if (typeof sentAt !== "string" || !Number.isFinite(Date.parse(sentAt))) throw new Error("invalid sent_at");
    if (sensorId !== undefined && !sensorIds.has(sensorId)) throw new Error("unknown sensor_id");
    const targets = subscriptions.monitors(sensorId);
    sendJson(response, 202, { queued: targets.length });
    const deadlineMs = Date.now() + PROBE_TTL_MS;
    // One message per sensor: each probe says which sensor's path it went through.
    const bySensor = new Map();
    for (const target of targets) bySensor.set(target.sensorId, [...(bySensor.get(target.sensorId) ?? []), target]);
    for (const [targetSensorId, group] of bySensor) {
      pushTo(group, {
        kind: "probe", probe_id: probeId, sensor_id: targetSensorId, sent_at: sentAt,
        tag: `probe:${targetSensorId}`
      }, deadlineMs).catch(error => console.error(`probe failed: ${error.message}`));
    }
  }

  // ponytail: reads the whole evidence file per call. Fine for a certifier polling every
  // minute; an index or rotation when the file gets big.
  async function handleEvidence(request, response, file) {
    if (!monitorAuthorized(request, response, Buffer.alloc(0))) return;
    const query = new URL(request.url, "http://gateway").searchParams;
    const since = Date.parse(query.get("since") ?? "");
    if (!Number.isFinite(since)) throw new Error("invalid since");
    const limit = Math.min(Number(query.get("limit") ?? MAX_EVIDENCE_PAGE), MAX_EVIDENCE_PAGE);
    if (!Number.isInteger(limit) || limit < 1) throw new Error("invalid limit");
    let lines = [];
    try {
      lines = (await readFile(file, "utf8")).split("\n");
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    const matching = lines.filter(Boolean).map(line => JSON.parse(line))
      .filter(record => Date.parse(record.at) >= since)
      .sort((a, b) => Date.parse(a.at) - Date.parse(b.at));
    let end = Math.min(limit, matching.length);
    // Never split records that share one "at": the next page starts at that time again.
    // A group that alone is bigger than the page goes out whole, or the client never advances.
    const sameAt = index => index < matching.length && matching[index].at === matching[index - 1].at;
    let groupStart = end;
    while (groupStart > 0 && sameAt(groupStart)) groupStart -= 1;
    if (groupStart > 0) end = groupStart;
    else while (sameAt(end)) end += 1;
    const records = matching.slice(0, end);
    const nextSince = end < matching.length
      ? matching[end].at
      : new Date((records.length ? Date.parse(records.at(-1).at) : since - 1) + 1).toISOString();
    sendJson(response, 200, { records, next_since: nextSince });
  }

  function handleStatus(response) {
    const now = Date.now();
    sendJson(response, 200, {
      now: new Date(now).toISOString(),
      // Lets the certifier see every restart of this process from outside.
      started_at: new Date(startedAt).toISOString(),
      relay_enabled: !config.killSwitch,
      // True means no iPhone gets anything: fine in the lab, an outage in production.
      apns_dry_run: config.dryRun === true,
      web_push_public_key: config.vapid?.publicKey ?? null,
      // Heartbeats live in memory on purpose: after a restart every sensor shows as
      // uncovered until it reports again, which errs on the visible side.
      sensors: sensors.map(sensor => sensorHealth(sensor.id, now))
    });
  }

  const reportedSilent = new Set();

  /**
   * A public sensor that never reported is offered to users without anything behind it (a
   * receptor that was never deployed). Once per sensor and process, after startup grace plus
   * one full staleness window: the log for the operator, the evidence for the certifier.
   */
  async function reportSilentPublicSensors(now) {
    const silentAfterMs = config.silentSensorAfterMs ?? (config.startupGraceMs ?? STALE_AFTER_MS) + STALE_AFTER_MS;
    if (now - startedAt < silentAfterMs) return;
    for (const sensorId of publicSensorIds) {
      if (lastHeartbeatAt.has(sensorId) || reportedSilent.has(sensorId)) continue;
      reportedSilent.add(sensorId);
      console.error(`public sensor ${sensorId} never reported: set "public": false until it runs`);
      await recordEvidence(config.evidenceFile,
        { type: "PUBLIC_SENSOR_SILENT", at: new Date(now).toISOString(), sensor_id: sensorId });
    }
  }

  // A user who never opens the page still has to learn that coverage is gone.
  async function announceCoverageChanges() {
    const now = Date.now();
    // Heartbeats are not persisted: until one full window has passed since startup every
    // sensor would look dead. The kill switch needs no heartbeats to be known.
    if (!config.killSwitch && now - startedAt < (config.startupGraceMs ?? STALE_AFTER_MS)) return;
    for (const sensor of sensors) {
      const health = sensorHealth(sensor.id, now);
      // Taken in the same tick as `health`: a phone that registers during the awaits below
      // registered against a newer state and must not get this one.
      const webTargets = subscriptions.list(sensor.id).map(subscription => ({ sensorId: sensor.id, subscription }));
      const apnsTokens = devices.tokensFor(sensor.id);
      // Per channel: only the people whose channel changed hear about it.
      for (const channel of ["webpush", "apns"]) {
        const covered = health[`covered_${channel}`];
        const key = `${sensor.id}:${channel}`;
        const announcedDown = announcedCoverage.data[key] === "down";
        if (covered !== announcedDown) continue;
        if (covered) delete announcedCoverage.data[key];
        else announcedCoverage.data[key] = "down";
        await announcedCoverage.persist()
          .catch(error => console.error(`coverage state write failed: ${error.message}`));
        const { message } = coveragePayload(sensor.id, covered);
        const tag = `coverage:${sensor.id}`;
        // Sent even on a degraded channel: it may have recovered. If it has not, its users
        // cannot be told this way; gateway-watchdog tells the operator, naming the channel.
        const results = channel === "webpush"
          ? await pushTo(webTargets, { kind: "coverage", tag, late: false, ...message },
            now + COVERAGE_PUSH_TTL_MS)
          : await tellCoverage(sensor.id, apnsTokens, covered, now + COVERAGE_PUSH_TTL_MS);
        await recordEvidence(config.evidenceFile, {
          type: covered ? "COVERAGE_RESTORED" : "COVERAGE_LOST",
          at: new Date(now).toISOString(), sensor_id: sensor.id, channel, results
        });
      }
    }
  }

  async function serveStatic(response, fileName) {
    const content = await readFile(join(PUBLIC_DIR, fileName));
    response.writeHead(200, {
      "content-type": STATIC_TYPES[extname(fileName)],
      // The service worker and sensor list must never be served stale.
      "cache-control": "no-cache"
    }).end(content);
  }

  const bodyRoutes = {
    "POST /events": handleEvent,
    "POST /heartbeat": handleHeartbeat,
    "POST /subscribe": handleSubscribe,
    "POST /devices": handleDevice,
    "DELETE /devices": handleDeviceRemoval,
    "POST /devices/test": handleTestPush,
    "POST /devices/telemetry": handleTelemetrySwitch,
    "POST /telemetry/arrivals": handleArrivals,
    "POST /probe": handleProbe,
    "POST /probe/apns-burst": handleApnsBurst
  };
  // Up to 500 arrivals per upload; every other body stays small.
  const bodyLimits = { "POST /telemetry/arrivals": TELEMETRY_BODY_BYTES };

  const server = http.createServer(async (request, response) => {
    const path = new URL(request.url, "http://gateway").pathname;
    try {
      if (request.method === "GET" && path === "/status") {
        handleStatus(response);
      } else if (request.method === "GET" && path === "/evidence") {
        await handleEvidence(request, response, config.evidenceFile);
      } else if (request.method === "GET" && path === "/telemetry") {
        // Same paging as /evidence, over the arrivals test phones uploaded.
        await handleEvidence(request, response, config.telemetryFile);
      } else if (request.method === "GET" && staticFiles.has(path)) {
        await serveStatic(response, staticFiles.get(path));
      } else if (bodyRoutes[`${request.method} ${path}`]) {
        // Headers in, body not yet read: accepted_at minus this is the upload plus validation.
        const receivedAt = new Date().toISOString();
        const raw = await readBody(request, bodyLimits[`${request.method} ${path}`]);
        if (raw === null) {
          response.writeHead(413, { connection: "close" }).end();
          return;
        }
        await bodyRoutes[`${request.method} ${path}`](request, response, raw, receivedAt);
      } else {
        response.writeHead(404).end();
      }
    } catch (error) {
      if (!response.headersSent) sendJson(response, 400, { error: error.message });
    }
  });

  let checking = false;
  const coverageTimer = setInterval(() => {
    // One check at a time: a slow push round must not overlap the next and push twice.
    if (checking) return;
    checking = true;
    announceCoverageChanges()
      .then(() => reportSilentPublicSensors(Date.now()))
      .catch(error => console.error(`coverage check failed: ${error.message}`))
      .finally(() => { checking = false; });
  }, config.coverageCheckMs ?? 60_000);
  coverageTimer.unref();
  server.on("close", () => {
    closed = true;
    clearInterval(coverageTimer);
    for (const session of apnsSessions.values()) session.destroy();
    webPushAgent.destroy();
  });
  return server;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const config = loadConfig();
  if (config.dryRun) console.error("APNS_DRY_RUN=1: every APNs push is faked, no iPhone gets anything");
  const port = Number(process.env.PORT || 8787);
  createServer(config).listen(port, "127.0.0.1", () => {
    console.log(`gateway listening on http://127.0.0.1:${port}`);
  });
}

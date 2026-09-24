// Load driver: one alert to N recipients of one sensor, per channel, timed end to end.
// Results and method: docs/qa/load.md. Runs the gateway from this repo, never a live one.
//
//   node docs/qa/load/run.mjs [apns,webpush] [1000,10000] [10,100]
//
// Keep web push under ~15.000 on a Mac: each push opens its own connection (QA-63) and
// 50.000 exhausted the host's ephemeral ports, adb to the local fleet included.
import { execFileSync, spawn } from "node:child_process";
import { createECDH, createHmac, generateKeyPairSync, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import webpush from "../../../gateway/node_modules/web-push/src/index.js";

const HERE = new URL(".", import.meta.url).pathname;
const WORK = mkdtempSync(`${tmpdir()}/relay-load-`);
execFileSync("openssl", ["req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes",
  "-keyout", `${WORK}/key.pem`, "-out", `${WORK}/cert.pem`, "-days", "1", "-subj", "/CN=127.0.0.1",
  "-addext", "subjectAltName=IP:127.0.0.1"], { stdio: "ignore" });
const [WEB_PORT, APNS_PORT, CTL_PORT, GW_PORT, STATS_PORT] = [19101, 19102, 19103, 19104, 19105];
const vapid = webpush.generateVAPIDKeys();
const apnsKey = generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey.export({ type: "pkcs8", format: "pem" });
const ecdh = createECDH("prime256v1"); ecdh.generateKeys();
const keys = { p256dh: ecdh.getPublicKey().toString("base64url"), auth: randomBytes(16).toString("base64url") };
const get = async (port, path) => (await fetch(`http://127.0.0.1:${port}${path}`)).json();
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

const children = new Set();
process.on("exit", () => { for (const child of children) child.kill(); });
process.on("uncaughtException", error => { console.error(error); process.exit(1); });

function startProcess(script, env) {
  const child = spawn("nice", ["-n", "10", process.execPath, script], {
    cwd: HERE, env: { ...process.env, ...env }, stdio: ["ignore", "pipe", "pipe"] });
  children.add(child);
  child.on("exit", () => children.delete(child));
  child.stderr.on("data", chunk => { child.errors = (child.errors ?? "") + chunk; });
  return new Promise(resolve => child.stdout.on("data", chunk => {
    if (String(chunk).includes("ready")) resolve(child);
  }));
}

const pct = (sorted, p) => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];

async function runOnce(channel, n, latency) {
  const dir = `${WORK}/${channel}-${n}-${latency}`;
  rmSync(dir, { recursive: true, force: true }); mkdirSync(dir, { recursive: true });
  if (channel === "apns") {
    const devices = {};
    for (let i = 0; i < n; i += 1) devices[i.toString(16).padStart(64, "0")] = { platform: "ios", sensor_ids: ["chaparral"] };
    writeFileSync(`${dir}/devices.json`, JSON.stringify(devices));
  } else {
    const subs = {};
    for (let i = 0; i < n; i += 1) {
      const endpoint = `https://127.0.0.1:${WEB_PORT}/push/${i}`;
      subs[endpoint] = { endpoint, keys };
    }
    writeFileSync(`${dir}/subscriptions.json`, JSON.stringify({ chaparral: subs }));
  }
  const gateway = await startProcess("gw.mjs", { RUN_DIR: dir, GW_PORT, STATS_PORT, APNS_PORT,
    APNS_KEY: apnsKey, VAPID_PUBLIC: vapid.publicKey, VAPID_PRIVATE: vapid.privateKey,
    NODE_EXTRA_CA_CERTS: `${WORK}/cert.pem` });
  await fetch(`http://127.0.0.1:${CTL_PORT}/reset?latency=${latency}`);
  const before = await get(STATS_PORT, "/");
  const now = Date.now();
  const event = { event_id: `chaparral:load:${now}`, source: "android_earthquake_alert_candidate",
    sensor_id: "chaparral", captured_at: new Date(now).toISOString(),
    expires_at: new Date(now + 180_000).toISOString(), title: "Alerta de sismo",
    body: "Sismo M4.5 a ~19 km. Protéjase ahora.", interruption_level: "time-sensitive",
    time_occurred_s: Math.floor(now / 1000) - 17 };
  const raw = JSON.stringify(event);
  const key = createHmac("sha256", "load-secret").update("chaparral").digest("hex");
  // A blocked event loop shows up here first: /status is what the page and the watchdog read.
  let probing = true;
  let statusMaxMs = 0;
  const probe = (async () => {
    while (probing) {
      const started = Date.now();
      await fetch(`http://127.0.0.1:${GW_PORT}/status`).then(r => r.text()).catch(() => {});
      statusMaxMs = Math.max(statusMaxMs, Date.now() - started);
      await sleep(50);
    }
  })();
  const t0 = Date.now();
  const response = await fetch(`http://127.0.0.1:${GW_PORT}/events`, { method: "POST", body: raw,
    headers: { "content-type": "application/json", "x-relay-signature": createHmac("sha256", key).update(raw).digest("hex") } });
  const ackMs = Date.now() - t0;
  let evidenceMs = null;
  while (Date.now() - t0 < 200_000) {
    // A 50k-result line takes a while to write: done only once it ends in a newline.
    if (existsSync(`${dir}/evidence.jsonl`) && readFileSync(`${dir}/evidence.jsonl`, "utf8").endsWith("\n")) {
      evidenceMs = Date.now() - t0; break;
    }
    await sleep(100);
  }
  probing = false;
  await probe;
  const push = await get(CTL_PORT, "/stats");
  const after = await get(STATS_PORT, "/");
  gateway.kill();
  const record = evidenceMs === null ? null : JSON.parse(readFileSync(`${dir}/evidence.jsonl`, "utf8").split("\n")[0]);
  const results = record ? (channel === "apns" ? record.apns : record.web_push) : [];
  const delivered = results.filter(r => r.status >= 200 && r.status < 300).length;
  const failures = {};
  for (const r of results) if (!(r.status >= 200 && r.status < 300)) failures[r.status] = (failures[r.status] ?? 0) + 1;
  const deltas = push.answeredAt.map(at => at - t0).sort((a, b) => a - b);
  rmSync(dir, { recursive: true, force: true });
  return { channel, n, latency, http: response.status, ackMs, delivered, requests: push.requests,
    retries: push.requests - n, failures, p50: pct(deltas, 0.5), p95: pct(deltas, 0.95),
    lastAnswerMs: deltas.at(-1), evidenceMs, cpuMs: Math.round(after.cpuMs - before.cpuMs),
    maxRssMb: Math.round(after.maxRssMb), statusMaxMs, gatewayErrors: (gateway.errors ?? "").slice(0, 300) };
}

const pushServer = await startProcess("push-server.mjs", { WEB_PORT, APNS_PORT, CTL_PORT, WORK_DIR: WORK });
const plan = (process.argv[2] ?? "apns,webpush").split(",");
const sizes = (process.argv[3] ?? "1000,10000,50000").split(",").map(Number);
const latencies = (process.argv[4] ?? "10,100").split(",").map(Number);
for (const channel of plan) for (const n of sizes) for (const latency of latencies) {
  console.log(JSON.stringify(await runOnce(channel, n, latency)));
}
pushServer.kill();
rmSync(WORK, { recursive: true, force: true });

// POST /devices with a big store: every registration rewrites devices.json whole.
// Results and method: docs/qa/load.md. Runs the gateway from this repo, never a live one.
//
//   node docs/qa/load/devices.mjs [10000,100000]
import { execFileSync, spawn } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { mkdirSync, mkdtempSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";

const HERE = new URL(".", import.meta.url).pathname;
const WORK = mkdtempSync(`${tmpdir()}/relay-devices-`);
execFileSync("openssl", ["req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes",
  "-keyout", `${WORK}/key.pem`, "-out", `${WORK}/cert.pem`, "-days", "1", "-subj", "/CN=127.0.0.1",
  "-addext", "subjectAltName=IP:127.0.0.1"], { stdio: "ignore" });
const [WEB_PORT, APNS_PORT, CTL_PORT, GW_PORT, STATS_PORT] = [19111, 19112, 19113, 19114, 19115];
const apnsKey = generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey.export({ type: "pkcs8", format: "pem" });
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const get = async (port, path) => (await fetch(`http://127.0.0.1:${port}${path}`)).json();
const pct = (sorted, p) => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];

const children = new Set();
process.on("exit", () => { for (const child of children) child.kill(); });

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

const token = index => index.toString(16).padStart(64, "0");

// Shaped as the gateway stores a registered phone today.
function storedDevice(index) {
  return { platform: "ios", sensor_ids: ["chaparral"], apns_env: "production", coverage_told: { chaparral: false },
    demand_cell: null, min_magnitude: {}, verified_at: index % 10 === 0 ? "2026-09-25T00:00:00.000Z" : null };
}

// Each phone behind its own IP, as through CloudFront: the per-IP limit is not what is measured.
async function registerOnce(index) {
  const started = performance.now();
  const response = await fetch(`http://127.0.0.1:${GW_PORT}/devices`, { method: "POST",
    headers: { "content-type": "application/json", "x-forwarded-for": `10.${index >> 16 & 255}.${index >> 8 & 255}.${index & 255}` },
    body: JSON.stringify({ device_token: token(index), sensor_ids: ["chaparral"], platform: "ios" }) });
  await response.text();
  return { ms: performance.now() - started, status: response.status };
}

async function measure(label, calls, concurrency) {
  let next = 0;
  const results = [];
  const started = performance.now();
  await Promise.all(Array.from({ length: concurrency }, async () => {
    while (next < calls.length) results.push(await registerOnce(calls[next++]));
  }));
  const wallMs = performance.now() - started;
  const sorted = results.map(result => result.ms).sort((a, b) => a - b);
  const statuses = {};
  for (const { status } of results) statuses[status] = (statuses[status] ?? 0) + 1;
  return { label, calls: calls.length, concurrency, statuses, p50: Math.round(pct(sorted, 0.5)),
    p95: Math.round(pct(sorted, 0.95)), max: Math.round(sorted.at(-1)), wallMs: Math.round(wallMs) };
}

async function runStore(n) {
  const dir = `${WORK}/store-${n}`;
  mkdirSync(dir, { recursive: true });
  const devices = {};
  for (let index = 0; index < n; index += 1) devices[token(index)] = storedDevice(index);
  writeFileSync(`${dir}/devices.json`, JSON.stringify(devices));
  const fileMb = statSync(`${dir}/devices.json`).size / 2 ** 20;
  const gateway = await startProcess("gw.mjs", { RUN_DIR: dir, GW_PORT, STATS_PORT, APNS_PORT, APNS_KEY: apnsKey,
    VAPID_PUBLIC: "", VAPID_PRIVATE: "", NODE_EXTRA_CA_CERTS: `${WORK}/cert.pem` });
  const idle = await get(STATS_PORT, "/");

  // The longest a /status waits while registrations run: that is how long the loop is blocked.
  let probing = true;
  let statusMaxMs = 0;
  const probe = (async () => {
    while (probing) {
      const started = performance.now();
      await fetch(`http://127.0.0.1:${GW_PORT}/status`).then(response => response.text()).catch(() => {});
      statusMaxMs = Math.max(statusMaxMs, performance.now() - started);
      await sleep(20);
    }
  })();
  // Existing phones moving (the common call), then a burst of them at once.
  const existing = Array.from({ length: 200 }, (_, index) => (index * 7919) % Math.max(n, 1));
  const rows = [
    await measure("re-register, one at a time", existing, 1),
    await measure("re-register, 20 at once", existing, 20),
    await measure("new phone", [n + 1, n + 2, n + 3, n + 4, n + 5], 1)
  ];
  probing = false;
  await probe;
  const after = await get(STATS_PORT, "/");
  gateway.kill();
  rmSync(dir, { recursive: true, force: true });
  return { n, fileMb: Number(fileMb.toFixed(1)), idleRssMb: Math.round(idle.rssMb),
    maxRssMb: Math.round(after.maxRssMb), statusMaxMs: Math.round(statusMaxMs), rows,
    gatewayErrors: (gateway.errors ?? "").slice(0, 300) };
}

const pushServer = await startProcess("push-server.mjs", { WEB_PORT, APNS_PORT, CTL_PORT, WORK_DIR: WORK });
for (const n of (process.argv[2] ?? "10000,100000").split(",").map(Number)) {
  console.log(JSON.stringify(await runStore(n)));
}
pushServer.kill();
rmSync(WORK, { recursive: true, force: true });

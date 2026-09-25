// The real gateway (copy) with a side port that reports its own CPU and memory.
import http from "node:http";
import { createServer } from "../../../gateway/src/server.js";

const env = process.env;
const server = createServer({
  hmacSecret: "load-secret", teamId: "TEAM", keyId: "KEY", bundleId: "com.example.relay",
  privateKey: env.APNS_KEY, dryRun: false, apnsHost: `https://127.0.0.1:${env.APNS_PORT}`,
  evidenceFile: `${env.RUN_DIR}/evidence.jsonl`, subscriptionsFile: `${env.RUN_DIR}/subscriptions.json`,
  devicesFile: `${env.RUN_DIR}/devices.json`, coverageFile: `${env.RUN_DIR}/coverage.json`,
  // Public, so POST /devices accepts it (devices.mjs).
  sensors: [{ id: "chaparral", public: true }],
  vapid: { subject: "mailto:qa@example.com", publicKey: env.VAPID_PUBLIC, privateKey: env.VAPID_PRIVATE }
});
server.listen(Number(env.GW_PORT), "127.0.0.1");
http.createServer((req, res) => {
  const cpu = process.cpuUsage();
  res.end(JSON.stringify({ cpuMs: (cpu.user + cpu.system) / 1000, rssMb: process.memoryUsage().rss / 2 ** 20,
    maxRssMb: process.resourceUsage().maxRSS / (process.platform === "darwin" ? 2 ** 20 : 1024) }));
}).listen(Number(env.STATS_PORT), "127.0.0.1", () => console.log("gateway ready"));

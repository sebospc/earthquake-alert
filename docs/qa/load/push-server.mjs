// Fake push services: HTTPS/1.1 like FCM/Apple web push, HTTP/2 over TLS like APNs.
// Answers 201/200 after LATENCY_MS and records when each answer went out.
import { readFileSync } from "node:fs";
import http from "node:http";
import http2 from "node:http2";
import https from "node:https";

const tls = { key: readFileSync(`${process.env.WORK_DIR}/key.pem`), cert: readFileSync(`${process.env.WORK_DIR}/cert.pem`) };
let latencyMs = Number(process.env.LATENCY_MS ?? 10);
let answeredAt = [];
let requests = 0;
const reply = send => { requests += 1; setTimeout(() => { answeredAt.push(Date.now()); send(); }, latencyMs); };

const web = https.createServer(tls, (req, res) => {
  req.resume();
  req.on("end", () => reply(() => res.writeHead(201).end()));
});
web.listen(Number(process.env.WEB_PORT), "127.0.0.1", 65535);

// Apple's APNs lets ~1000 streams run at once on a connection.
const apns = http2.createSecureServer({ ...tls, maxSessionMemory: Number(process.env.SERVER_SESSION_MB ?? 10), settings: { maxConcurrentStreams: Number(process.env.MAX_STREAMS ?? 1000) } });
apns.on("stream", stream => {
  stream.on("error", () => {});
  stream.resume();
  stream.on("end", () => reply(() => { if (!stream.closed) { stream.respond({ ":status": 200 }); stream.end(); } }));
});
apns.listen(Number(process.env.APNS_PORT), "127.0.0.1", 65535);

http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  if (url.pathname === "/reset") {
    answeredAt = []; requests = 0; latencyMs = Number(url.searchParams.get("latency") ?? latencyMs);
    res.end("ok");
  } else {
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({ requests, answered: answeredAt.length, answeredAt }));
  }
}).listen(Number(process.env.CTL_PORT), "127.0.0.1", () => console.log("push-server ready"));

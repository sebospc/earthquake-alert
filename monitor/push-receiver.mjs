#!/usr/bin/env node
// The certifier's own web push subscriptions, without a browser: Mozilla autopush's
// WebSocket protocol (what Firefox speaks) plus RFC 8291 aes128gcm decryption.
//
//   node monitor/push-receiver.mjs <data-dir> <vapid-public-key> <sensor_id>...
//
// Writes <data-dir>/push-state.json (0600: channel keys) and appends every push it gets to
// <data-dir>/pushes.jsonl with the time it arrived. monitor.py registers the endpoints at
// the gateway and reads pushes.jsonl. Needs Node 22 (global WebSocket).
import { createECDH, createDecipheriv, createHmac, randomBytes, randomUUID } from "node:crypto";
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const AUTOPUSH_URL = "wss://push.services.mozilla.com/";
// A probe lives 60 s at the push service (gateway PROBE_TTL_MS). A socket that stops answering
// was only noticed when TCP gave up, up to 16 min later (25-sep: one probe lost, one 23 s late).
// Autopush answers the "{}" ping in ~150 ms, so an unanswered ping means a dead socket.
const PING_EVERY_MS = 60_000;
const PONG_WITHIN_MS = 10_000;
// Autopush's side cuts every connection ~20 min in, going deaf seconds before the close.
// Reconnecting ourselves first keeps the gap under a second.
const RECYCLE_AFTER_MS = 15 * 60_000;
const RECONNECT_MS = 10_000;

const hmac = (key, data) => createHmac("sha256", key).update(data).digest();

/** RFC 8291 + 8188, one record: what web-push (and so the gateway) sends. */
export function decrypt(body, { privateKey, publicKey, auth }) {
  const salt = body.subarray(0, 16);
  const idLength = body[20];
  const senderKey = body.subarray(21, 21 + idLength);
  const ciphertext = body.subarray(21 + idLength);
  const ecdh = createECDH("prime256v1");
  ecdh.setPrivateKey(privateKey);
  const secret = ecdh.computeSecret(senderKey);
  const keyInfo = Buffer.concat([Buffer.from("WebPush: info\0"), publicKey, senderKey, Buffer.from([1])]);
  const ikm = hmac(hmac(auth, secret), keyInfo);
  const prk = hmac(salt, ikm);
  const cek = hmac(prk, Buffer.from("Content-Encoding: aes128gcm\0\x01", "latin1")).subarray(0, 16);
  const nonce = hmac(prk, Buffer.from("Content-Encoding: nonce\0\x01", "latin1")).subarray(0, 12);
  const decipher = createDecipheriv("aes-128-gcm", cek, nonce);
  decipher.setAuthTag(ciphertext.subarray(-16));
  const padded = Buffer.concat([decipher.update(ciphertext.subarray(0, -16)), decipher.final()]);
  // Last record: content, then the 0x02 delimiter, then zero padding.
  let end = padded.length - 1;
  while (end > 0 && padded[end] === 0) end -= 1;
  if (padded[end] !== 2) throw new Error("bad padding delimiter");
  return padded.subarray(0, end).toString("utf8");
}

function newChannel() {
  const ecdh = createECDH("prime256v1");
  ecdh.generateKeys();
  return { channelID: randomUUID(), privateKey: ecdh.getPrivateKey("base64url"),
    publicKey: ecdh.getPublicKey("base64url"), auth: randomBytes(16).toString("base64url"), endpoint: null };
}

function keysOf(channel) {
  return { privateKey: Buffer.from(channel.privateKey, "base64url"),
    publicKey: Buffer.from(channel.publicKey, "base64url"), auth: Buffer.from(channel.auth, "base64url") };
}

export function run(dataDir, vapidPublicKey, sensorIds, { Socket = WebSocket, pingEveryMs = PING_EVERY_MS,
  pongWithinMs = PONG_WITHIN_MS, recycleAfterMs = RECYCLE_AFTER_MS, reconnectMs = RECONNECT_MS } = {}) {
  const statePath = `${dataDir}/push-state.json`;
  const pushesPath = `${dataDir}/pushes.jsonl`;
  const state = existsSync(statePath) ? JSON.parse(readFileSync(statePath, "utf8")) : { uaid: "", channels: {} };
  const save = () => writeFileSync(statePath, JSON.stringify(state, null, 2), { mode: 0o600 });
  // A new VAPID key makes old endpoints useless: start those sensors over.
  for (const sensorId of sensorIds) {
    if (!state.channels[sensorId] || state.channels[sensorId].vapid !== vapidPublicKey) {
      state.channels[sensorId] = { ...newChannel(), vapid: vapidPublicKey };
    }
  }
  save();
  const bySensorChannel = () => new Map(Object.entries(state.channels).map(([sensorId, c]) => [c.channelID, sensorId]));

  function connect() {
    // No subprotocol: autopush does not echo "push-notification" back and undici then drops
    // the connection before it opens.
    const socket = new Socket(AUTOPUSH_URL);
    let pinger, pongCheck, recycler;
    const stopTimers = () => { clearInterval(pinger); clearTimeout(pongCheck); clearTimeout(recycler); };
    // A dead socket may never fire onclose: drop it and connect again without waiting for it.
    const reconnectNow = reason => {
      console.log(`${new Date().toISOString()} ${reason}, reconnecting`);
      stopTimers();
      socket.onclose = socket.onmessage = null;
      socket.close();
      setTimeout(connect, 0);
    };
    const send = message => socket.send(JSON.stringify(message));
    socket.onopen = () => {
      console.log(`${new Date().toISOString()} connected`);
      send({ messageType: "hello", uaid: state.uaid, use_webpush: true,
        channelIDs: Object.values(state.channels).filter(c => c.endpoint).map(c => c.channelID) });
      pinger = setInterval(() => {
        send({});
        pongCheck ??= setTimeout(() => reconnectNow("no answer to ping"), pongWithinMs);
      }, pingEveryMs);
      recycler = setTimeout(() => reconnectNow("planned recycle"), recycleAfterMs);
    };
    socket.onmessage = ({ data }) => {
      clearTimeout(pongCheck);
      pongCheck = undefined;
      const message = JSON.parse(data);
      if (message.messageType === "hello") {
        // A different uaid means the server forgot us: every channel must register again.
        if (state.uaid && message.uaid !== state.uaid) {
          for (const channel of Object.values(state.channels)) channel.endpoint = null;
        }
        state.uaid = message.uaid;
        save();
        for (const channel of Object.values(state.channels).filter(c => !c.endpoint)) {
          send({ messageType: "register", channelID: channel.channelID, key: channel.vapid });
        }
      } else if (message.messageType === "register" && message.status === 200) {
        const sensorId = bySensorChannel().get(message.channelID);
        if (sensorId) state.channels[sensorId].endpoint = message.pushEndpoint;
        save();
        console.log(`${new Date().toISOString()} registered ${sensorId}`);
      } else if (message.messageType === "notification") {
        const receivedAt = new Date().toISOString();
        const sensorId = bySensorChannel().get(message.channelID);
        let payload = null;
        let error = null;
        try {
          payload = JSON.parse(decrypt(Buffer.from(message.data ?? "", "base64url"), keysOf(state.channels[sensorId])));
        } catch (caught) {
          error = caught.message;
        }
        appendFileSync(pushesPath, `${JSON.stringify({ received_at: receivedAt, channel_sensor: sensorId, payload, error })}\n`);
        send({ messageType: "ack", updates: [{ channelID: message.channelID, version: message.version, code: 100 }] });
      }
    };
    socket.onclose = ({ code }) => {
      console.log(`${new Date().toISOString()} closed ${code}, reconnecting`);
      stopTimers();
      setTimeout(connect, reconnectMs);
    };
    socket.onerror = event => console.log(`${new Date().toISOString()} error ${event.message ?? ""}`);
  }
  connect();
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [dataDir, vapidPublicKey, ...sensorIds] = process.argv.slice(2);
  if (!dataDir || !vapidPublicKey || sensorIds.length === 0) {
    console.error("usage: push-receiver.mjs <data-dir> <vapid-public-key> <sensor_id>...");
    process.exit(2);
  }
  run(dataDir, vapidPublicKey, sensorIds);
}

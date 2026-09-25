// Offline check of the receiver's decryption against the same web-push the gateway uses.
// Run: node monitor/test_push_receiver.mjs
import assert from "node:assert/strict";
import { createECDH, randomBytes } from "node:crypto";

import webpush from "../gateway/node_modules/web-push/src/index.js";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { decrypt, run } from "./push-receiver.mjs";

const ecdh = createECDH("prime256v1");
ecdh.generateKeys();
const auth = randomBytes(16);
const keys = { privateKey: ecdh.getPrivateKey(), publicKey: ecdh.getPublicKey(), auth };
const message = JSON.stringify({ kind: "probe", probe_id: "p-1", sensor_id: "chaparral", sent_at: "2026-09-24T10:00:00Z" });

const { cipherText } = webpush.encrypt(ecdh.getPublicKey("base64url"), auth.toString("base64url"), message, "aes128gcm");
assert.equal(decrypt(cipherText, keys), message);

const tampered = Buffer.from(cipherText);
tampered[tampered.length - 20] ^= 1;
assert.throws(() => decrypt(tampered, keys), "a tampered push was accepted");

const other = createECDH("prime256v1");
other.generateKeys();
assert.throws(() => decrypt(cipherText, { ...keys, privateKey: other.getPrivateKey() }), "decrypted with the wrong key");
console.log("PASS aes128gcm decryption matches web-push");

// Keepalive: a socket that stops answering pings is replaced within a ping plus the grace, not
// when TCP gives up; a healthy one is still replaced on schedule, before autopush cuts it.
function fakeServer({ answersPings }) {
  const sockets = [];
  class FakeSocket {
    constructor() {
      sockets.push(this);
      this.closed = false;
      setTimeout(() => this.onopen?.(), 1);
    }
    send(text) {
      const message = JSON.parse(text);
      if (message.messageType === "hello") setTimeout(() => this.onmessage?.({ data: JSON.stringify({ messageType: "hello", uaid: "u-1" }) }), 1);
      else if (answersPings && text === "{}") setTimeout(() => this.onmessage?.({ data: "{}" }), 1);
    }
    close() { this.closed = true; }
  }
  return { sockets, FakeSocket };
}
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const timings = { pingEveryMs: 30, pongWithinMs: 20, recycleAfterMs: 400, reconnectMs: 60_000 };
console.log = () => {};  // the receiver logs every reconnect

const deaf = fakeServer({ answersPings: false });
run(mkdtempSync(join(tmpdir(), "receiver-")), "vapid-key", ["chaparral"], { Socket: deaf.FakeSocket, ...timings });
await sleep(120);
assert.ok(deaf.sockets.length >= 2, "a socket that never answered a ping was kept");
assert.ok(deaf.sockets[0].closed, "the deaf socket was not closed");

const healthy = fakeServer({ answersPings: true });
run(mkdtempSync(join(tmpdir(), "receiver-")), "vapid-key", ["chaparral"], { Socket: healthy.FakeSocket, ...timings });
await sleep(250);
assert.equal(healthy.sockets.length, 1, "a socket answering its pings was replaced before the recycle");
await sleep(300);
assert.equal(healthy.sockets.length, 2, "no planned recycle before autopush's cut");
console.info("PASS a deaf push socket is replaced after one unanswered ping, a healthy one on schedule");
process.exit(0);

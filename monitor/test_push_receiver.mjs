// Offline check of the receiver's decryption against the same web-push the gateway uses.
// Run: node monitor/test_push_receiver.mjs
import assert from "node:assert/strict";
import { createECDH, randomBytes } from "node:crypto";

import webpush from "../gateway/node_modules/web-push/src/index.js";
import { decrypt } from "./push-receiver.mjs";

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

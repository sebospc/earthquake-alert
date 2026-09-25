# Delivery load test

24-sep-2026. Local, no AWS and no real pushes. Question: how long the gateway takes from the moment
`POST /events` arrives until the last delivery, depending on how many users follow a sensor.

## Conclusion

Before the fixes (below, the new measurement: APNs over 50,000 and web push ~12,000).
With the code at that time, delivery finishes in under 3 s up to:

- **APNs: ~6,000 iPhones per sensor.** From ~7,000 duplicate resends start. With
  10,000 it takes 8.6-9.2 s, and with 50,000 it reaches only 9 %.
- **Web push: ~2,500 subscriptions per sensor.** 2,000 take 2.3 s and 3,000 take 3.25 s.
  Also, the event's 202 already takes 1.2 s with 2,000.

This is on an M3 Pro Mac with the push servers on the same machine. The EC2 r8i.large has
2 vCPU shared with the emulator, so the numbers there will be worse, not better.
Take these values as a ceiling.

With two small fixes (QA-60 measured; QA-62 and QA-63 estimated), APNs reaches ~20,000
iPhones per sensor in under 3 s at 100 ms latency, and 50,000 in 1.6 s at 10 ms.

## After fixes QA-60..63 (measured again, 24-sep)

Same harness, repo gateway untouched. I added a probe to `/status` every 50 ms during the
delivery: its worst response tells whether the event loop got blocked.

| channel | recipients | latency | 202 | delivered | requests | p50 | p95 | last | CPU | max RSS | worst `/status` |
|---|---|---|---|---|---|---|---|---|---|---|---|
| APNs | 1,000 | 100 ms | 3 ms | 1,000 | 1,000 | 149 ms | 155 ms | 155 ms | 0.11 s | 84 MB | 2 ms |
| APNs | 10,000 | 100 ms | 3 ms | 10,000 | 10,000 | 410 ms | 557 ms | 591 ms | 0.70 s | 215 MB | 29 ms |
| APNs | 50,000 | 10 ms | 10 ms | 50,000 | 50,000 | 701 ms | 1.2 s | 1.2 s | 1.9 s | 430 MB | 57 ms |
| APNs | 50,000 | 100 ms | 10 ms | 50,000 | 50,000 | 1.1 s | 1.8 s | 2.0 s | 1.8 s | 421 MB | 81 ms |
| web push | 1,000 | 100 ms | 2 ms | 1,000 | 1,000 | 483 ms | 592 ms | 606 ms | 0.65 s | 136 MB | 127 ms |
| web push | 10,000 | 100 ms | 4 ms | 10,000 | 10,000 | 1.4 s | 2.3 s | 2.4 s | 2.6 s | 196 MB | 131 ms |
| web push | 15,000 | 100 ms | 6 ms | 15,000 | 15,000 | 1.9 s | 3.3 s | 3.5 s | 3.5 s | 220 MB | 139 ms |
| web push | 50,000 | 10 ms | 10 ms | 50,000 | 50,000 | 4.6 s | 8.4 s | 8.8 s | 10.2 s | 315 MB | 190 ms |
| web push | 50,000 | 100 ms | 10 ms | 50,000 | 50,000 | 5.5 s | 10.1 s | 10.6 s | 10.0 s | 295 MB | 143 ms |

No retries or duplicates in any run. The 202 no longer depends on how many users
there are, `/status` never went above 190 ms, and 50,000 web pushes no longer exhaust the ports (at most 500
sockets with keep-alive). It matches what developer measured.

New threshold to finish in under 3 s: **APNs, more than 50,000 iPhones per sensor**
(2.0 s at 100 ms). **Web push, ~12,000 subscriptions per sensor** (10,000 → 2.4 s,
15,000 → 3.5 s). The cost left in web push is the per-user encryption (~0.2 ms of CPU
each): it cannot be cached, because each phone has its own key.

The cached VAPID header was verified separately, against a real push captured from the gateway:
scheme `vapid`, `k` = the public key, `aud` = the endpoint origin, `exp` at 12 h
(the limit is 24 h) and a valid ES256 signature with the public key.

Still not measured: the combined case (APNs and web push on the same sensor) and the EC2.

## How it was measured

- The real gateway code, copied to the scratchpad, running in a separate process with
  `nice -n 10`. Subscriptions and tokens loaded directly into its files, so the
  10,000 cap does not apply and no code had to change.
- Fake push in another process: HTTPS/1.1 for web push (like FCM) and HTTP/2 over TLS for
  APNs, with 1,000 concurrent streams per connection, as Apple announces. It answers 201/200
  after a fixed latency (10 or 100 ms) and records when each response went out.
- One event signed with the sensor key. Time per delivery = from the POST to the
  response of that delivery. "Last" = the last response. "Evidence" = when the gateway
  finished writing the record (includes retries). CPU and max RSS are from the gateway
  process.
- Web push with real P-256 keys: each send does the real encryption and VAPID signature.

## APNs (current code)

| iPhones | latency | 202 | delivered | requests to APNs | p50 | p95 | last | CPU | max RSS |
|---|---|---|---|---|---|---|---|---|---|
| 1,000 | 10 ms | 22 ms | 1,000 | 1,000 | 69 ms | 72 ms | 72 ms | 0.09 s | 83 MB |
| 1,000 | 100 ms | 19 ms | 1,000 | 1,000 | 146 ms | 149 ms | 149 ms | 0.09 s | 83 MB |
| 3,000 | 100 ms | 42 ms | 3,000 | 3,000 | 295 ms | 411 ms | 412 ms | 0.27 s | 135 MB |
| 5,000 | 100 ms | 61 ms | 5,000 | 5,000 | 464 ms | 687 ms | 687 ms | 0.40 s | 175 MB |
| 6,000 | 100 ms | 79 ms | 6,000 | 6,000 | 548 ms | 830 ms | 831 ms | 0.48 s | 196 MB |
| 7,000 | 100 ms | 72 ms | 7,000 | **8,000** | 638 ms | 1.0 s | 1.0 s | 0.61 s | 223 MB |
| 8,000 | 100 ms | 85 ms | 8,000 | **11,001** | 1.4 s | 2.4 s | 2.4 s | 1.2 s | 287 MB |
| 10,000 | 10 ms | 84 ms | 10,000 | **14,745** | 4.4 s | 4.7 s | 8.6 s | 2.1 s | 483 MB |
| 10,000 | 100 ms | 93 ms | 10,000 | **17,005** | 4.8 s | 9.2 s | 9.2 s | 2.5 s | 478 MB |
| 50,000 | 10 ms | 346 ms | **4,553** | 12,875 | 16.6 s | 46 s | 57 s | 54 s | 1.2 GB |
| 50,000 | 100 ms | 334 ms | **4,386** | 12,486 | 5.7 s | 15 s | 26 s | 22 s | 1.9 GB |

"Requests to APNs" above the number of iPhones are resends that reached APNs: the iPhone
gets the same notice more than once (with the same `collapse-id` it replaces the
notification, but it can sound again). With 50,000, the 45,447 missing ones end in `-1`
after all retries.

### APNs with `maxSessionMemory: 1000` on the client session (only in the copy)

| iPhones | latency | delivered | requests | p50 | p95 | last | CPU | max RSS |
|---|---|---|---|---|---|---|---|---|
| 8,000 | 10 ms | 8,000 | 8,000 | — | — | 319 ms | — | — |
| 10,000 | 10 ms | 10,000 | 10,000 | 301 ms | 391 ms | 393 ms | 0.58 s | 250 MB |
| 10,000 | 100 ms | 10,000 | 10,000 | 782 ms | 1.3 s | 1.3 s | 0.67 s | 252 MB |
| 20,000 | 10 ms | 20,000 | 20,000 | 517 ms | 693 ms | 705 ms | 1.0 s | 448 MB |
| 20,000 | 100 ms | 20,000 | 20,000 | 1.4 s | 2.4 s | 2.5 s | 1.1 s | 447 MB |
| 50,000 | 10 ms | 50,000 | 50,000 | 1.1 s | 1.6 s | 1.6 s | 1.9 s | 982 MB |
| 50,000 | 100 ms | 50,000 | **51,203** | 3.4 s | 6.4 s | 6.7 s | 3.1 s | 965 MB |

## Web push (current code)

| subscriptions | latency | 202 | delivered | p50 | p95 | last | CPU | max RSS |
|---|---|---|---|---|---|---|---|---|
| 1,000 | 10 ms | 593 ms | 1,000 | 867 ms | 1.1 s | 1.1 s | 1.3 s | 202 MB |
| 1,000 | 100 ms | 586 ms | 1,000 | 951 ms | 1.1 s | 1.2 s | 1.3 s | 197 MB |
| 2,000 | 100 ms | 1.2 s | 2,000 | 1.8 s | 2.3 s | 2.3 s | 2.7 s | 319 MB |
| 3,000 | 100 ms | 1.7 s | 3,000 | 2.6 s | 3.1 s | 3.3 s | 3.9 s | 440 MB |
| 10,000 | 10 ms | **5.4 s** | 10,000 | 9.2 s | 11.3 s | 11.5 s | 13.9 s | 1.2 GB |
| 10,000 | 100 ms | **5.5 s** | 10,000 | 9.4 s | 11.5 s | 11.7 s | 14.0 s | 1.2 GB |
| 50,000 | 10 ms | — | — | — | — | — | — | — |

With 50,000 the Mac's ephemeral ports ran out (16,384): `EADDRNOTAVAIL` for the whole
host, including the test control. I did not repeat it, because the live fleet uses adb over
localhost on the same machine.

CPU cost per push, without network: VAPID signature 0.26 ms, encryption 0.12 ms (0.4 ms total, all
synchronous). The rest, ~1 ms per push, is the TLS handshake of a new connection per send.

## Findings

| id | sev | scenario | where | state |
|---|---|---|---|---|
| QA-60 | critical | The HTTP/2 session to APNs uses Node's default `maxSessionMemory` (10 MB). With more than ~6,000 iPhones on a sensor, the queued streams exceed it and Node closes them with `ERR_HTTP2_STREAM_ERROR` (ENHANCE_YOUR_CALM): 7,000 → +1,000 duplicate pushes, 10,000 → +47-70 %, 50,000 → only 9 % delivered, 54 s of CPU and 1.9 GB. One-line fix, measured: `http2.connect(apnsHost, { maxSessionMemory: 1000 })` → 50,000 in 1.6 s without duplicates at 10 ms. | `server.js` `apnsClient` | confirmed |
| QA-61 | high | The 5 s timeout per stream starts when the stream is created, not when it goes out. With 1,000 concurrent streams, the ones waiting in the queue expire if N/1,000 × latency goes over ~5 s, and they are resent: 50,000 at 100 ms give 1,203 duplicates and 6.7 s, even with QA-60 fixed. São Paulo → APNs (US) is around 120-150 ms round trip. Fix: send with a bounded pool (≤ 1,000 in flight) and start the timer when the stream goes out. | `server.js` `apnsRequest`, `apnsToSensor` | confirmed |
| QA-62 | high | Web push does the VAPID signature and the encryption of all subscriptions synchronously, before answering `/events`. The 202 takes 0.6 s with 1,000, 1.2 s with 2,000 and 5.4 s with 10,000, which goes over Forwarder's 5 s read timeout. All that time the event loop is blocked: APNs, heartbeats, `/status` and the watchdog wait. On a sensor with web push and APNs, the iPhones wait until all web pushes are encrypted (inferred, not measured). Fix: answer first and split into batches that yield the loop, and cache the VAPID header per audience (the JWT is valid up to 24 h): −65 % of the synchronous part. | `server.js` `pushToSensor`, `handleEvent` | confirmed |
| QA-63 | high | web-push opens a new TCP+TLS connection for each push, without keep-alive: ~1 ms of extra CPU per push and one socket each. With 50,000 the host's ephemeral ports ran out. On Linux there are ~28,000 per destination, and all of FCM usually resolves to a few IPs. Fix: an `https.Agent({ keepAlive: true, maxSockets })` passed in web-push's `agent` option. | `server.js` `pushToSensor` | confirmed |

## Limits of this test

- Loopback: without the real TLS handshake latency to Apple or Google. APNs reuses one
  session, so for APNs it weighs little. For web push without keep-alive it weighs much more in
  reality than here.
- The fake servers answer in a fixed time and never return 429. It does not measure the
  real rate limit of FCM or APNs.
- Not measured: the combined case (web push and APNs on the same sensor), or several sensors
  with the same quake at once. Because of QA-62, the combined case will be worse than each channel alone.
- The figures depend on the machine. Repeat on the EC2 before promising capacity.

To repeat it, with the repo gateway, without touching anything live:

```bash
node docs/qa/load/run.mjs apns,webpush 1000,10000 10,100
```

Certificates and the files of each run go to a temporary directory that is deleted
at the end. To measure a fix before merging it, run against a copy of
`gateway/src` (that is how QA-60 was measured).

## Real alert, hop by hop (2026-09-24 16:46 UTC, AWS chaparral)

Event `chaparral:t1790268393:alert`, one web push subscription (the monitor), no APNs.
Read only from what was already recorded: the gateway evidence, the monitor's `pushes.jsonl` and the
listener's `notification-evidence.jsonl` on the emulator (`run-as`).

Clocks, all converted to true UTC:

| clock | offset | how it was measured |
|---|---|---|
| EC2 host (gateway) | 0 (chrony: 0.1 µs) | `chronyc tracking` |
| emulator chaparral (no NTP) | 1.70 s behind, ±0.06 | adb `date` vs host: 1.70 s on 24-sep (QA-86), 1.76 s at 18:51 UTC. It drifts, so ±0.06 |
| Mac (monitor) | 0.185 s behind, ±0.11 | `sntp time.apple.com` x4 at 18:50 UTC, two hours after the quake |

Timeline, seconds after 16:46:00 UTC:

| moment | recorded | true UTC | source |
|---|---|---|---|
| quake origin | 33 | 33 | Google `time_occurred_s`, whole seconds only |
| Google posts the notification | 49.373 | 51.073 | `post_time_ms` (emulator) |
| listener callback, event built | 49.614 | 51.314 | `captured_at` (emulator) |
| gateway accepted (body read and validated) | 51.552 | 51.552 | `accepted_at` (EC2) |
| monitor receives the push | 51.664 | 51.849 | `pushes.jsonl` `received_at` (Mac) |
| push service answers 201 to the gateway | 51.926 | 51.926 | `web_push[].delivered_at` (EC2) |
| listener gets the 202 | 50.418 | 52.118 | `RELAY_ATTEMPT.captured_at_ms` (emulator) |

Hops:

| # | hop | time | notes |
|---|---|---|---|
| 1 | notification posted → listener sees it | **0.241 s** | Emulator clock only, no correction needed. Includes the signer check and building the event |
| 2 | listener → gateway accepted | **0.238 s** ±0.06 | No timestamp for "request sent" on the device or "request arrived" on the gateway (before the body is read). The device POST took 0.804 s end to end (device clock only), so the 202 came back 0.57 s after `accepted_at`. That is off the critical path, but unexplained |
| 3 | gateway → push dispatched | **no timestamp** | Nothing is stamped when `sendNotification` starts. Only accepted → 201 from the push service: 0.374 s |
| 4 | dispatch → push received | **no timestamp** for the start | accepted → monitor received: 0.297 s ±0.11. The monitor had the push 77 ms before the gateway got the 201, so `delivered_at` is not the dispatch time |
| | **posted → monitor received** | **0.78 s** ±0.13 | |

The "~2 s added by us" figure (and "alert at +16.6 s") came from the emulator clock without the
1.70 s correction. Corrected: Google posted at about origin +18.1 s and our part is about 0.8 s.
Origin→monitor stays 18.8 s (18.66 s raw from the Mac clock).

Missing timestamps, in order of value:

1. Gateway: a timestamp when the request arrives (before the body read), and one per push when it is sent (before `sendNotification` / the APNs stream). Without them hops 3 and 4 cannot be split.
2. Listener: a timestamp when the POST is written and when the response comes back, in `RELAY_ATTEMPT`. Today there is only the second one, stamped after the call returns.
3. Emulator clock offset reported with every health run (QA-86: `sensor-health` can do the adb `date` vs host check above in 20 ms). Every hop that crosses the emulator depends on it.
4. Monitor: record the Mac's NTP offset with each received push (developer-qa, monitor code).
5. Origin: Google gives whole seconds. For origin → posted use the SGC/USGS origin with milliseconds.

## Canaries on the Colombia host: contention baseline (before)

Plan ($0): the canaries general-santos and glan run as emulators 3 and 4 on the same r8i.large
(2 vCPU) as chaparral and quibdo. There is no synthetic alert, so the "before and after" compares what
CPU contention would show on the alert path. Read-only, 2026-09-25 00:31 UTC, 2 emulators running:

| measure | before (2 emulators) | after (4 emulators) |
|---|---|---|
| host load average (1/5/15 min) | 0.24 / 0.23 / 0.19 | |
| host CPU (vmstat, 5 s samples) | us 2–10 %, idle 82–92 %, steal 0 | |
| host memory used / available | 7.6 GB / 8.1 GB | |
| RSS per emulator, qemu, after 10.7 h (chaparral / quibdo) | 3.42 GB / 3.71 GB | |
| busiest emulator (top) | 10 % of a vCPU | |
| adb shell round trip, p50 of 5 (chaparral / quibdo) | 13 ms / 14 ms | |
| full GMS dumpsys (chaparral / quibdo) | 0.20 s / 0.12 s | |
| certifier probe, monitor → gateway → push → monitor, 24 h (n=10) | p50 0.67 s, p95 0.76 s | |
| real alert, listener → monitor corrected (24-sep, one sample) | 0.52 s | |

What would say the canaries hurt Colombia: steal > 0 or idle < 50 % in steady state, an adb round
trip over ~50 ms, a GMS dump over 1 s, or a real alert's listener → monitor over the certifier's 2 s
rule (which then turns the day DEGRADED on its own). Boot is the known weak point: 2 vCPU cannot boot
2 emulators at once (STATUS, known traps), so the canaries must boot one at a time, never alongside
a Colombia receptor.

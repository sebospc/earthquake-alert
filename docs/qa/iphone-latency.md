# iPhone latency plan

Owner: developer-qa. Status: plan, not yet run — needs a telemetry-opted-in iPhone on iOS 26
(blocked on the user: Apple Developer account, physical device). This doc is the methodology;
results go in a dated file under `docs/qa/cert/` once measured, same as the certifier's daily
certificates.

## What we already know, what is missing

Proven on a real quake (2026-09-24 16:46 UTC): origin → our push sent ≈ 18.8 s, of which
~0.78 s is our own chain (AEA → listener → gateway → APNs request). See `docs/findings.md`.
That is the leg we control end to end and it is measured.

What is not measured: push sent → APNs → iPhone. `docs/qa/load.md`'s synthetic load test
gives a proxy (São Paulo → APNs US round trip ~120-150 ms, loopback numbers only) but that is
gateway-to-APNs latency under synthetic load, not APNs-to-device delivery on a real phone on
real Wi-Fi or cellular, and it says nothing about NSE wake time or app-state effects. This plan
closes that gap with two tools that already exist: `POST /probe/apns-burst` (synthetic, safe,
repeatable) and `POST /telemetry/arrivals` (real-quake, opt-in only, already live per
`docs/STATUS.md`).

## T5: probe burst (synthetic, no quake needed)

Use `POST /probe/apns-burst {device_token, n<=50, interval_ms 1000..60000}` against one
telemetry-opted-in test phone (contract: `docs/ios-contract.md` "Probe push (device test
T5)"). Each push carries `sent_at_ms` at the moment the gateway sends it; the NSE logs
`received_at_ms` and uploads it via `/telemetry/arrivals` with `source: "nse"`,
`app_state`.

Run it twice per condition, 50 pushes at 2 s apart (fast enough to get a distribution, slow
enough to stay clear of APNs coalescing and clear of any single push landing during another's
processing):

| condition | how |
|---|---|
| Wi-Fi, foreground | phone unlocked, app open, home Wi-Fi |
| Wi-Fi, background | phone locked, app backgrounded |
| Cellular, background | Wi-Fi off, phone locked |
| Cellular, Low Power Mode | Wi-Fi off, Low Power Mode on, phone locked |
| Killed (force-quit) | app force-quit from the app switcher before the burst |

The killed case matters because the NSE still runs even when the app process is dead (it is a
separate extension process); if pushes stop arriving there, that is the finding, not a test
bug — write it up as-is.

Each run: 50 pushes in, count what `/telemetry/arrivals` actually recorded (a probe burst does
not degrade or dedup, so any gap is a real drop, not our own dedup logic hiding it), and note
whether it matches `docs/ios-contract.md`'s expectation that a probe write never touches the
alert path.

## Real-quake chain (once ≥ 1 telemetry phone exists)

No separate test needed: the moment a telemetry-opted-in phone is subscribed to a receptor
that alerts for real, `/telemetry/arrivals` gets `kind: "alert"` entries the same as any probe,
`event_id` matching the real alert's. Pull those alongside the existing real-quake proof
(`docs/findings.md`) to get one end-to-end number: origin → receptor → gateway → APNs →
iPhone. Nothing to build; this is a "wait for a quake and go look" step once the device
exists.

## Clock offset

`received_at_ms - sent_at_ms` mixes two clocks (`docs/ios-contract.md` says this explicitly).
`sent_at_ms` comes from the gateway host's clock; per `docs/decision.md` / devops setup the
EC2 host is NTP-disciplined (cloud-init default, not something we've separately audited —
flag as an assumption, not a proven fact, if it matters for a specific number). `received_at_ms`
is the iPhone's system clock, which iOS keeps synced via NTP whenever it has any connectivity
and is usually within low hundreds of ms of true time, worse right after a cold boot or a long
stretch with no network.

Do not trust a single delta. Read the **median over the 50-push burst**, per condition: a
constant clock offset shifts every point in a run by the same amount, so it moves the median
but not the spread (p95 − p50, max − p50), and the spread is what tells us about APNs and NSE
wake time rather than clock skew. If the median jumps between two runs on the same phone with
no reason to expect a real latency change, that is clock drift, not a delivery regression —
say so in the writeup rather than treating it as a finding.

## App state

`app_state` on each arrival (`"foreground"`, `"background"`, `"unknown"`) plus the condition
we set up (killed, Low Power) tells us which delivery paths exist and how fast each is:

- **Foreground:** app is running, NSE still fires first (mutable-content), fastest and most
  reliable path.
- **Background:** NSE wakes on push, should be close to foreground timing; iOS can throttle
  background wake budget under battery pressure — watch for outliers, not just the median.
- **Killed:** NSE is a separate process from the main app, so it should still fire; this run
  exists specifically to confirm that, since it is easy to assume incorrectly that a killed app
  means no delivery.
- **Low Power Mode:** iOS is documented to delay some background activity; APNs alerts with
  `apns-priority: 10` and `interruption-level: active` are supposed to be exempted from most of
  that throttling, but this is the one condition worth actually measuring rather than trusting
  the platform docs, since a life-safety alert delayed by Low Power Mode is exactly the kind of
  silent failure this project is built to avoid.

## Analysis

One script, not yet written (next step after the first burst is captured), that:

1. Reads `GET /telemetry?since=` (monitor-signed, same paging as `/evidence` per
   `docs/ios-contract.md`) for a given `probe_id` or event_id prefix.
2. Computes `received_at_ms - sent_at_ms` per arrival, grouped by condition and `app_state`.
3. Reports p50 / p95 / max per group, plus count-in vs count-out (delivery rate) per burst.
4. Flags any arrival with a negative delta (clock skew large enough to invert order) instead of
   silently including it in the stats.

Lives under `docs/qa/load/` next to the existing analysis scripts (`gw.mjs`, `devices.mjs`),
same conventions: reads recorded data, does not talk to APNs or the gateway's write path
itself.

## Certifier integration (after the first T5 numbers exist)

Per `monitor/README.md`'s existing verdict model (CERTIFIED / DEGRADED / FAIL, one rule per
cause):

- **APNs leg p95 over a threshold → DEGRADED.** The threshold itself is not guessed here: it
  gets set from the T5 background-cellular p95 (the realistic worst normal case, not the
  best-case foreground-Wi-Fi number) once that data exists, with headroom. Do not hardcode a
  number in this doc before the measurement exists.
- **A telemetry phone subscribed to an alerting receptor, no arrival within 5 min → DEGRADED.**
  5 min matches the existing coverage-outage grace window (`CoverageTracker`, iOS side, and the
  certifier's own 15 min DEGRADED / 60 min FAIL uncovered-receptor rule is the closest existing
  precedent, but 5 min here is tighter on purpose: an alert that took 5 min to reach a phone
  already failed at its job, unlike routine coverage flapping).
- Both rules only fire for opted-in telemetry phones (never a real user's data), same privacy
  boundary as `/telemetry/arrivals` itself.
- Canary precedent applies: per `monitor/README.md`, a telemetry-phone miss should not make the
  day worse than DEGRADED on its own, same reasoning as a canary miss — it is a measurement
  signal, not proof the public alerting path is broken, unless it corroborates a receptor-side
  FAIL.

## Open questions

- Real device and Apple Developer account: blocked on the user (`docs/STATUS.md` "Open").
- Whether the EC2 host's NTP discipline is actually verified anywhere, or just assumed — worth
  a one-line check (`chronyc tracking` or `timedatectl`, read-only) before trusting `sent_at_ms`
  to the ms; does not block starting T5, since the median-over-a-burst method tolerates a
  constant offset either way.
- APNs behavior under Low Power Mode is a platform claim, not yet ours to verify until a device
  exists.

# QA review: current state

Updated: 2026-09-24 18:30 UTC. Only what is current. Everything closed, with its detail, is in
`review-archive.md` (QA-NN → phase index at the top; search with `grep -n "QA-NN"`).

## Tests

`npm test` (gateway) 55/55, 0 `todo`. `scripts/e2e-relay.sh`, `monitor/test_verify.py`,
`monitor/test_push_receiver.mjs`, `scripts/test_sensor_health.py`, `scripts/test_lab.py` and
JUnit, all green. Every new test was verified with mutations.

## Open

| id | sev | what is missing |
|---|---|---|
| QA-67 | medium | CPU of the gateway and the emulators on the EC2 during an event. The coordinator measures it at the next quake (checklist, item 10) |
| QA-84 | critical, in progress | Fixed in `sensor-health.py` (aea_ok=false with location > 20 h or null, plus a preventive reboot). The root fix, `GpsKeeperService`, is only on AWS quibdo since 18:04 UTC; still to confirm over hours the `earthquake_alerting` deliveries (item 12: the certifier measures them every 30 min, "GMS location on the AWS receptors" section; 18:35 UTC quibdo 38 s and 4 deliveries) before taking it to chaparral and the Mac |
| QA-87 | high, before the canary hosts | `infra/cloudwatch`: the metrics have no host dimension. With 2+ hosts, `GatewayUp` (Minimum) stays 1 while one host's probe is dead, and `UncoveredReceptors` (Minimum) stays 0 while another host has receptors down. Fix: an `InstanceId` dimension and one alarm per host. `infra/cloudwatch/stack.yml:34`, `aea-cw-probe.py:59` |
| QA-88 | high | `DeliveriesFlatSeconds` can go missing without an alarm, because it has `notBreaching`. Two cases: the slow pass raises (log dir, disk), or the GpsKeeper receptor is not in that host's map (default `quibdo` on every host). Then the only GpsKeeper check is silent forever. Fix: send the fast metrics first, wrap the slow pass, always emit the metric where `AEA_CW_GPSKEEPER` is set, and `breaching`. `aea-cw-probe.py:110-131`, `stack.yml:66` |
| QA-89 | medium | `test_cw_probe.py`: `GatewayUp` hard-wired to 1 passes, and so does dropping the GpsKeeper filter. `main()` has no test. |
| QA-90 | critical, hypothesis to confirm | GMS's `earthquake_alerting` request has `minUpdateDistance=1000` m: AEA gets a location only at boot (+5 min) and when the receptor moves ≥ 1 km. GpsKeeper keeps the GPS provider fresh, which is what `sensor-health` (`scripts/sensor-health.py:75-92`, the 20 h reboot) looks at. AEA's own copy still ages from its last delivery (quibdo 18:11 UTC 24-sep). If Google's ~24 h limit (QA-84) applies to that copy, quibdo goes blind around 18:11 UTC on 25-sep with aea_ok=true and no reboot. Signal: time since the last delivery to `earthquake_alerting`, > 20 h = stale; optional nudge of the geo fix by 1.1 km. The 'deliveries flat 2 h' rule was wrong (a stationary receptor never grows the counter): taken out of the certifier. |
| QA-90b | open question | Does Google's ~24 h limit apply to AEA's copy or to the GPS provider? A controlled experiment, later: one receptor with the GPS provider fresh and AEA's copy > 24 h (GpsKeeper, no nudge, no reboot), and see whether a real quake in its radius alerts it. It decides whether the nudge is needed or only the reboot. |
| QA-91 | fixed (re-reviewed 25-sep; test with 2 MB of adb output) | `infra/deploy/remote.sh`: under `set -o pipefail`, `cmd \| grep -q X` returns 141 when grep exits first (reproduced). The `GPS_KEEPER_FAILED` check misses a failure that is there; the checks on `granted=true`, `GpsKeeper` and `Success` fail falsely. `test_remote.sh`'s fakes do not trigger it. Fix: capture the output, then grep. |
| QA-92 | high, fixed on disk | The certifier saw quibdo uncovered from 21:15:31 to 23:25:26 UTC on 24-sep (EC2 clock) and told no one: only the midnight certificate and the notices for MISS/FALSE, with ntfy off. Now a live notice at 15 min (DEGRADED) and 60 min (FAIL), once per outage, plus RESTORED; a macOS notification and `data/live-alerts.jsonl`, nothing external. Loads at the next restart. The cause of the gap (`aea_ok` counting event-log lines that GpsKeeper rolls) was fixed by developer and has its regression test. |
| QA-93 | high, before glan | $0 canaries: after 10.7 h each Colombia emulator uses 3.4/3.7 GB of host RSS (not the guest's 2.5 GB), and the host has 8.3 GB available with 2. At steady state, 4 emulators leave ~0.9 GB (swap). The MemAvailable gates, measured right after boot, pass and the squeeze arrives hours later. Measure at ≥ 8 h, or use a smaller guest RAM for the canaries, or the second host. |
| QA-94 | fixed 25-sep, account move | rebuild.sh and the new-account README never repoint the certifier. It finds the host by `MONITOR_INSTANCE`, `MONITOR_SSH_KEY` (rebuild makes `aea-lab-<account>.pem`) and the default AWS credentials, all still the old account. After the move `instance()` fails: health reads `aws-cli` (loud), but `poll_aws_location` returns without a word, so the location checks stop. Add it to the printed leftovers and the README (new-account read-only creds for describe-instances). |
| QA-95 | fixed 25-sep, account move | rebuild.sh:204-208: zero alarms found reads as all OK. `not_ok` is empty when `describe-alarms` returns nothing (alarms stack failed, wrong prefix), so REBUILD_DONE lists no alarm leftover. Require the 7 host alarms by name. Mutation `alarm_states=""` passes the test. |
| QA-96 | fixed 25-sep, account move | test_rebuild.sh gaps, each with a surviving mutation: the passphrase check only sees the faked aws/gh/ssh, so `-pass pass:$AEA_BACKUP_PASS` on the real openssl passes; no run has an uncovered receptor, so dropping the coverage leftover passes. |
| QA-97 | fixed 25-sep, account move | backup.sh:35-38: if ssh or tar fails mid-stream, pipefail exits before the check, and a truncated `aea-backup-<utc>.tar.gz.enc` stays next to the good ones, with a valid envelope (the sha covers what arrived). rebuild rejects it (gzip), but only at move time. Remove `$out` on any failure (trap). Fixed; the trap is proven by hand only (fake ssh dying mid-stream: file removed, and left without it), no test yet. Also: old and new hosts share the subscriptions and VAPID keys, so both push every alert until the old one stops; stop and disable the old gateway (and its watchdog) once the new one verifies. Not the kill switch: server.js:635/1171 make it tell those same users "uncovered" at once. |
| QA-98 | medium, before ios-core lands on main | ci.yml `ios-core` gates the relay deploy: deploy.yml needs the whole ci run to be success. A missing `macos-26` label leaves the job queued up to 24 h. A hung `swift test` (server.js that never answers) runs to the 6 h default, since no job has `timeout-minutes`. A macOS runner outage blocks every gateway deploy, hotfixes included. Keeping the gate is right, since a contract break must block. Needed: `timeout-minutes: 20`; the first run on a branch or PR before main; a line in the deploy runbook on how to ship a hotfix when macOS runners are down. The log check itself is sound: real pass, 1 test, all skipped and 0 tests all behave. |

## Accepted (nothing to do)

| id | reason |
|---|---|
| QA-10 | single-thread `SENDER`: each emulator has its own Forwarder; optimization candidate |
| QA-20 | a renamed `eew_*` channel is not forwarded: on purpose (comment in `isRelayable`) |
| QA-32 | re-subscribing at the cap drops the old sensor: documented in `subscriptions.add` |
| QA-55 | first boot without geo fix: runbook note |
| QA-58 | dedup race per token and a doublet < 30 s apart: documented in `claimQuake` |
| QA-64 | number of emulators: solved in operations (`EMULATOR_COUNT`) |
| QA-86 | emulators without NTP (1.70 s / 0.31 s): noted in the certificate |

## Current checklist on the EC2

Before the redeploy, on the EC2 and without changing anything:

1. `systemctl status aea-emulator@1`: the live emulator has to be that unit (QA-44).
2. `sudo -u aea -H /opt/android-sdk/platform-tools/adb devices` has to say `device`. If
   it says `unauthorized`, the emulator started before the `aea` key existed, and
   it has to be restarted once (the login lives in userdata and is not lost).
3. Run the bootstrap and right after it `listener <apk> chaparral` (QA-49).
4. `systemctl list-timers sensor-health.timer gateway-watchdog.timer`: NEXT with a time.
5. After 5 min, in `/status`, `chaparral` with `aea_ok: true` and `covered: true`.
6. Listener → real gateway over cleartext HTTP, from the emulator: in `/status`,
   `last_heartbeat_at` and `last_canary_ok_at` of `chaparral` with a recent time. If not:
   `sudo -u aea -H adb -s emulator-5554 exec-out run-as com.earthquakes.relay cat
   files/notification-evidence.jsonl | grep -E 'HEARTBEAT_FAILED|RELAY_CANARY' | tail`.
7. No `-1` without a reason in the listener evidence. It has to give 0:
   `... cat files/notification-evidence.jsonl | python3 -c 'import json,sys; print(sum(1 for l in sys.stdin if (e:=json.loads(l)).get("http_status")==-1 and not e.get("error")))'`

Checklist on the EC2, in addition to items 1-7:

8. With one emulator booting, the ones already up keep heartbeat and `aea_ok` in `/status`
   (requested by developer; could not be measured without the EC2).
9. Full cold boot time (`systemctl list-units 'aea-emulator@*'` until
   all are `active` and with `sys.boot_completed=1`): it has to stay under the cap of
   15 min per unit (QA-65).
10. `top` during a canary: CPU of the gateway and the emulators when an event arrives.

Result on the EC2 (reported by the coordinator, 24-sep; I did not measure it):

- 8: 2 emulators in sequence, no GOODBYE. `chaparral` stayed healthy while the second one booted. Covered.
- 9: cold boot of ~60 s per emulator, far from the 15 min cap. Covered.
- Also seen: self-repair from drift on `quibdo` (QA-53/55 in practice).
- 10: CPU of the gateway and the emulators during an event: not reported. Stays pending
  together with QA-67.

## GpsKeeper checklist

QA-84, root fix: the listener keeps the GPS open (`GpsKeeperService`, process `:gps`, location
FGS, `requestLocationUpdates(GPS, 60 s)`), and `sensor-health` does a geo fix on every
run. To measure on device (the coordinator, on quibdo):

11. Age of the gps "last location" (`/proc/uptime` − `et`) over hours: it has to
    stay < 2 min if the emulator repeats the last fix with the HAL active. If it does not repeat it,
    it will reach ~5 min (the `sensor-health` interval). Both are fine against
    the ~24 h of QA-84, but we need to know which one it is.
12. `earthquake_alerting` deliveries every ~30 min in `dumpsys activity service
    com.google.android.gms`, not only the 2 from boot.
13. Change of lat/lon on the map → GMS with the new location in < 2 min, without reboot.
14. `dumpsys package com.earthquakes.relay`: FINE, COARSE and BACKGROUND_LOCATION with
    `granted=true`.
15. `dumpsys activity services com.earthquakes.relay`: `GpsKeeperService` in foreground.
    No `GPS_KEEPER_FAILED` in the listener evidence.
16. Kill the `:gps` process (`am kill` or `kill` of the pid): the listener stays alive, with
    heartbeat, and the keeper comes back at the next heartbeat (≤ 5 min).

QA notes on this design:
- With the GPS open and the geo fix right before `check()`, the drift check almost always
  measures our own injection (as in QA-48). While the keeper works, that is fine,
  because GMS follows the GPS. The signal that matters becomes the age and the deliveries.
  The "stale" reboot stays as a safety net if the keeper fails.
- The control Mac does not have the new APK: it will keep going stale at ~24 h and the
  certifier will mark it "no control" (QA-85) until it is updated or rebooted.

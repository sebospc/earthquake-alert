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

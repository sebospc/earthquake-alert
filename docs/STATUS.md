# Current status

Updated: 2026-09-24 18:40 UTC. Whoever finishes a piece of work updates this file.

## What is running

| where | what | how to see it |
|---|---|---|
| AWS EC2 `i-0d1c0b6dd02e0ae61`, sa-east-1, spot r8i.large | receptors `chaparral` (emulator-5554) and `quibdo` (emulator-5556), gateway, sensor-health, watchdog | `ssh -i ~/.ssh/aea-lab.pem ubuntu@$(aws ec2 describe-instances --region sa-east-1 --instance-ids i-0d1c0b6dd02e0ae61 --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)`; `curl -s 127.0.0.1:8787/status`. The IP changes with every spot interruption |
| Mac | control fleet: bucaramanga-a, hinatuan, chaparral, quibdo (lab.py under launchd) | `python3 ~/Library/Application\ Support/aea-lab/scripts/lab.py report` |
| Mac | certifier `monitor/monitor.py`, started by hand (not a service) | `docs/qa/cert/AAAA-MM-DD.md` |

adb on the EC2: always `sudo -u aea -H /opt/android-sdk/platform-tools/adb`.
Deploy: rsync the repo + `sudo EMULATOR_COUNT=2 VAPID_SUBJECT=mailto:alertas@example.com ./aws-bootstrap.sh`
and, if the APK changed, `./aws-bootstrap.sh listener ~/listener.apk chaparral quibdo`.

## Proven

- Real quake 2026-09-24 16:46 UTC: AWS chaparral HIT at +18.1 s; origin to push ≈ 18.8 s, of which ~0.78 s is ours.
- No Google account, x86_64 image, Brazil IP: works.
- Tests: gateway 55/55, JUnit, test_sensor_health, test_lab and test_verify, all green.

## In progress

- **GPS always on** (GpsKeeperService). Installed ONLY on AWS quibdo since 18:04 UTC.
  Moving the location without a reboot works and the location age stays in seconds.
  Still to confirm over hours that `earthquake_alerting` deliveries keep arriving.
  If it passes, it goes on chaparral and on the Mac.
- Every 30 min the certifier measures, over read-only ssh, the GMS location age and the
  deliveries to `earthquake_alerting` of each AWS receptor ("GMS location on the AWS receptors" section of the
  certificate). 18:35 UTC: quibdo 38 s and 4 deliveries (growing); chaparral 4.5 h and 2.
  The verdict already uses it: DEGRADED if > 1 h or deliveries flat > 2 h with GpsKeeper
  (`MONITOR_GPSKEEPER`, today `quibdo`), or > 20 h / none without it. Applied in the live process 30727 since 18:39 UTC.
- Certifier, on disk and not loaded yet (next natural restart): DEGRADED if a real alert's listener → monitor
  time goes over 2 s, with the emulator skew and the Mac NTP offset corrected (24-sep: 0.52 s). Origin in ms
  from USGS when it has the quake; SGC and Google give whole seconds only.
- The Mac was rebooted at ~17:40 UTC to refresh the location. Without GpsKeeper it goes
  blind again at ~24 h (QA-84).

- **English migration (24-sep):** docs, comments, logs, test names and certificate template are now English; tests green. Alert text for Colombian users, the PWA UI and `docs/outreach/senadora-villalba.md` stay Spanish on purpose.
  Certifier labels are now CERTIFIED/DEGRADED/FAIL on disk, but live pid 30727 keeps the Spanish ones until it restarts; listener APK changed (UI strings only), not deployed.

## Open

- Pending deploy (after QA review; APK only after the quibdo GpsKeeper measurement): latency timestamps (gateway received_at/sent_at, listener request_written_at_ms + streaming mode, sensor-health CLOCK_OFFSET) and BootReceiver MY_PACKAGE_REPLACED. After `install -r` on a guest, with no reboot: `dumpsys activity services com.earthquakes.relay | grep GpsKeeper` must show it running, and no GPS_KEEPER_FAILED in evidence.

- Domain with HTTPS: waiting for the user's decision (DuckDNS or other).
- Retire the Mac fleet or keep it as control: user's decision.
- QA-67: EC2 CPU during an event, measured at the next quake.
- Native iOS app (AlarmKit): after Xcode, the Apple Developer account and the developer-ios agent.
- Extreme optimization (decision.md §9): only when everything is stable.

## Known traps (do not re-investigate)

- The geo fix only lands with the GNSS HAL active. Without GpsKeeper, that is only during boot.
- GMS seems not to alert with a location older than ~24 h (QA-84).
- `cmd location set-location-enabled false` wipes the location. Do not use it.
- 2 vCPU cannot handle 2 emulators booting at the same time: boot them in sequence.
- targetSdk 35 blocks plain HTTP: cleartext allowed only to 10.0.2.2.

## Handoff per role (before a compact: each one leaves here where it stopped, 2-3 lines)

- **coordinator:** CLAUDE.md, STATUS.md and docs/roles/* created. Measuring GpsKeeper on AWS quibdo (installed 18:04 UTC): still to confirm over hours the earthquake_alerting deliveries. If it passes, install it on chaparral (AWS) and on the Mac. Decisions waiting for the user: HTTPS domain, retire or keep the Mac, local git init.
- **developer:** nothing half done. gateway 55/55, test_sensor_health 9/9, JUnit and APK green. Last change: GpsKeeperService (process `:gps`) + geo fix on every sensor-health run. Waiting for the earthquake_alerting measurement. Traps not in any other doc: `Map.groupBy` does not exist in Node 18; `node -e` breaks when importing server.js (the main check uses argv[1]), so a .mjs is used. Script tests must never let the real `lab.adb` through, because on the Mac emulator-5554 is the live fleet.
- **developer-qa:** review.md split (5.8 KB current + review-archive.md 64 KB, complete, with a QA-NN → phase index). Tests green (gateway 55/55); open QA-67 (EC2 CPU during a quake) and QA-84 in progress. Certifier running by hand on the Mac, pid 30727 (`nohup python3 monitor/monitor.py run`; stop it with `kill 30727`, it takes the tunnel and the receptor with it), with the certificate of the 24th in docs/qa/cert/2026-09-24.md. GpsKeeper: the certifier already measures every 30 min the GMS location age and the earthquake_alerting deliveries per AWS receptor, and the verdict already uses it (DEGRADED: > 1 h or flat deliveries 2 h with GpsKeeper; > 20 h or none without it). Still to add receptors to MONITOR_GPSKEEPER when they get the new APK.
- **comunicacion-humano** (session closed; coordinator's line): drafts in docs/outreach/ for google-aea (with the variant for Richard Allen), aws-device-farm and senadora-villalba. NONE sent; all wait for the user's decision. Outdated since the 24-sep quake, which validated AWS without an account: that capture and the measured latency (≈18.8 s, ~0.78 s ours origin to push) must be added.

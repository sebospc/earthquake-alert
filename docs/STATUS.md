# Current status

Updated: 2026-09-24 18:40 UTC. Whoever finishes a piece of work updates this file.

## What is running

| where | what | how to see it |
|---|---|---|
| AWS EC2 `i-0d1c0b6dd02e0ae61`, sa-east-1, spot r8i.large | receptors `chaparral` (emulator-5554) and `quibdo` (emulator-5556), gateway, sensor-health, watchdog | `ssh -i ~/.ssh/aea-lab.pem ubuntu@56.126.124.1` (Elastic IP since 2026-09-25 ~00:18Z, survives spot stop/start); `curl -s 127.0.0.1:8787/status`. Public HTTPS (staging): https://d1o3i68tksfjqi.cloudfront.net → Caddy :80 → gateway |
| Mac | control fleet RETIRED 2026-09-24 19:15 UTC: launchd job removed (plist kept as `aea-lab/com.earthquakes.aea-lab.plist.retired`), 4 emulators shut down. AVDs (with the personal Google account) still on disk | - |
| Mac | certifier `monitor/monitor.py`, started by hand (not a service) | `docs/qa/cert/AAAA-MM-DD.md` |
| AWS | CloudWatch (since 25-sep 00:30): logs + 5 alarms to SNS email (gateway down, receptor uncovered 10 min, AEA location > 21 h, AEA_NOT_OK, NUDGE_FAILED). Stacks aea-lab-cloudwatch, aea-lab-alarms-i-0d1c0b6dd02e0ae61 | CloudWatch console, sa-east-1 |

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
  The verdict uses it: DEGRADED if the GPS age is > 1 h with GpsKeeper, or > 20 h / none without it, and
  if AEA's own location is > 21 h on any receptor (QA-90; 21 h = after the planned 20 h reboot had its chance).
  The "deliveries flat 2 h" rule was wrong and is gone: AEA only gets a location on a move of ≥ 1 km.
- Certifier, on disk and not loaded yet (next natural restart): DEGRADED if a real alert's listener → monitor
  time goes over 2 s, with the emulator skew and the Mac NTP offset corrected (24-sep: 0.52 s). Origin in ms
  from USGS when it has the quake; SGC and Google give whole seconds only.
- Certifier, on disk, loads at next natural restart: Mac control retired at 19:11 UTC. Catalog-only
  ground truth; an unexplained AWS miss is FAIL, labelled "Mac control retired", no Mac rows or downtime.
  Guard: 3 explained misses on one receptor in 7 days with no hit in between = DEGRADED.
- Certifier, live in pid 30920 since 23:33 UTC: live notice when a
  receptor is uncovered ≥ 15 min (DEGRADED) / ≥ 60 min (FAIL), then RESTORED, as a macOS notification plus
  monitor/data/live-alerts.jsonl (QA-92). Also: AEA's delivery remembered across a log roll, and rolled-back
  deploys not excused.
- Canaries decided (docs/siting-canaries.md): General Santos + Glan (pair, 32 km), La Serena, San Salvador,
  ~5.7 alerts/month. Certifier pair rule on disk (`MONITOR_CANARY_PAIRS`), loads at next natural restart.
- The Mac was rebooted at ~17:40 UTC to refresh the location. Without GpsKeeper it goes
  blind again at ~24 h (QA-84).

- **English migration (24-sep):** docs, comments, logs, test names and certificate template are now English; tests green. Alert text for Colombian users, the PWA UI and `docs/outreach/senadora-villalba.md` stay Spanish on purpose.
  Certifier labels are now CERTIFIED/DEGRADED/FAIL on disk, and live since the restart (pid 71395, 19:33 UTC); listener APK changed (UI strings only), not deployed.

- **devops (25-sep):** LIVE: CloudWatch (stacks `aea-lab-cloudwatch`, `aea-lab-alarms-i-0d1c0b6dd02e0ae61`; 5 alarms per host → SNS email: gateway down, receptor uncovered, location age > 21 h, AEA_NOT_OK x3 in 15 min, NUDGE_FAILED; ≈ $2/month) and HTTPS staging (stack `aea-lab-https`: EIP + CloudFront with secret origin header → Caddy allowlist; `infra/https/verify.sh` passes). Deploy role/bucket/instance profile from `aea-lab-deploy`. Not yet used: `deploy.yml` (needs the push), `deploy-apk.yml` (held by `APK_DEPLOY_ENABLED`). Trap: `aws-bootstrap.sh listener` maps serials by argument position and rewrites the whole sensor map: never run it for one receptor.

## Open

- **Canaries (user, 25-sep):** $0 plan approved: general-santos + glan (pair) as emulators 3-4 on the main host, after a green CI APK and a CPU check. Dedicated canary hosts (La Serena, San Salvador too, ~$66/month) later, when there is money.

- **24-sep 23:10–23:25 (EC2 clock):** sensor-health with QA-90 steps 1+2 deployed (checksum ok), then the aea_ok fix at 23:25. quibdo was falsely uncovered 21:15→23:25 (aea_ok's deliveries>0 reads the event log GpsKeeper rolls over); rebooted by the coordinator at 23:23; covered again 23:25. Open: the nudge falsely confirmed a leg across that reboot (developer fixing).

- **QA-90 (critical, 24-sep 19:40):** earthquake_alerting only gets a location on a ≥1 km move. GpsKeeper keeps the GPS provider fresh, but AEA's copy ages (quibdo: last delivery 18:11 UTC), and sensor-health's 20 h reboot reads the GPS provider, so it never fires on quibdo. In progress: AEA location age drives aea_ok and the reboot (deadline 25-sep 17:00 UTC), plus a 1.1 km nudge-and-return. Fallback: manual reboot of quibdo before 25-sep 18:00 UTC. "Deliveries flat" is NOT a fault signal.

- Pending deploy (after QA review; APK only after the quibdo GpsKeeper measurement): latency timestamps (gateway received_at/sent_at, listener request_written_at_ms + streaming mode, sensor-health CLOCK_OFFSET) and BootReceiver MY_PACKAGE_REPLACED. After `install -r` on a guest, with no reboot: `dumpsys activity services com.earthquakes.relay | grep GpsKeeper` must show it running, and no GPS_KEEPER_FAILED in evidence.

- Domain with HTTPS: waiting for the user's decision (DuckDNS or other).
- Retire the Mac fleet or keep it as control: user's decision.
- QA-67: EC2 CPU during an event, measured at the next quake.
- Native iOS app (AlarmKit): after Xcode, the Apple Developer account and the developer-ios agent.
- Extreme optimization (decision.md §9): only when everything is stable.

## Known traps (do not re-investigate)

- zsh: `ubuntu@$IP:earthquakes-project` expands `$IP:e` as a modifier (extension). rsync/scp then copy to a LOCAL dir and the deploy silently lands stale code (24-sep 19:06). Always write `${IP}:`.

- The geo fix only lands with the GNSS HAL active. Without GpsKeeper, that is only during boot.
- GMS seems not to alert with a location older than ~24 h (QA-84).
- `cmd location set-location-enabled false` wipes the location. Do not use it.
- 2 vCPU cannot handle 2 emulators booting at the same time: boot them in sequence.
- targetSdk 35 blocks plain HTTP: cleartext allowed only to 10.0.2.2.

## Handoff per role (before a compact: each one leaves here where it stopped, 2-3 lines)

- **coordinator:** CLAUDE.md, STATUS.md and docs/roles/* created. Measuring GpsKeeper on AWS quibdo (installed 18:04 UTC): still to confirm over hours the earthquake_alerting deliveries. If it passes, install it on chaparral (AWS) and on the Mac. Decisions waiting for the user: HTTPS domain, retire or keep the Mac, local git init.
- **developer:** nothing half done. gateway 55/55, test_sensor_health 9/9, JUnit and APK green. Last change: GpsKeeperService (process `:gps`) + geo fix on every sensor-health run. Waiting for the earthquake_alerting measurement. Traps not in any other doc: `Map.groupBy` does not exist in Node 18; `node -e` breaks when importing server.js (the main check uses argv[1]), so a .mjs is used. Script tests must never let the real `lab.adb` through, because on the Mac emulator-5554 is the live fleet.
- **developer-qa:** certifier pid 30920 since 23:33 UTC, all rules loaded (clocks, Mac retired 19:11, canary pairs, AEA age 21 h, live coverage notices QA-92); stop with `kill 30920`. QA-90 critical: sensor-health reboot must use AEA's location age; if developer's step 1 is not live by 25-sep 16:00 UTC, tell the coordinator (manual quibdo reboot before 18:00). Pending reviews: developer's AEA age + 1.1 km nudge. Tests: gateway 58/58, test_verify 21, test_sensor_health 16.
- **devops-earthquake:** CloudWatch and HTTPS live and verified (25-sep 00:25Z). CI/deploy workflows wait for the push; first gateway deploy should log seconds-to-covered (QA: < 90 s → cut the 7 min cap to 3). APK deploy on hold (`APK_DEPLOY_ENABLED`).
- **comunicacion-humano** (session closed): outreach dropped by the user on 2026-09-24. Drafts stay in docs/outreach/ as history; nothing is sent.

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

- **Location freshness (QA-84/QA-90), settled design:** sensor-health reads AEA's own location age (GMS event log, remembered across log rolls), reboots at > 20 h, and on GpsKeeper receptors nudges 2 km out and back at > 6 h. Proven on quibdo 25-sep 05:30–05:40. quibdo has GpsKeeper; chaparral gets it with the next APK rollout, until then it relies on the 20 h reboot.
- **Certifier** (pid 30920 since 23:33 UTC): catalog-only ground truth (Mac retired), AEA age > 21 h = DEGRADED, live notice when a receptor is uncovered ≥ 15 min (DEGRADED) / ≥ 60 min (FAIL). On disk for the next restart: latency > 2 s rule, tunnel retry, lone-canary support (MONITOR_CANARIES).
- **devops (25-sep):** LIVE: CloudWatch (stacks `aea-lab-cloudwatch`, `aea-lab-alarms-i-0d1c0b6dd02e0ae61`; 5 alarms per host → SNS email: gateway down, receptor uncovered, location age > 21 h, AEA_NOT_OK x3 in 15 min, NUDGE_FAILED; ≈ $2/month) and HTTPS staging (stack `aea-lab-https`: EIP + CloudFront with secret origin header → Caddy allowlist; `infra/https/verify.sh` passes). Deploy role/bucket/instance profile from `aea-lab-deploy`. Not yet working: `deploy.yml` (needs the stack update), `deploy-apk.yml` (held by `APK_DEPLOY_ENABLED`). `aws-bootstrap.sh listener` now takes explicit `emulator-NNNN=id` pairs and merges the map.

## Open

- **First pipeline deploy:** blocked until the user updates the aea-lab-deploy stack (OIDC trust with the immutable subject), then re-runs deploy 36094274491 (7534fa9) and approves. After it lands, devops runs, one step at a time: swap.sh → probe install → host-alarms (7 alarms) → general-santos as emulator 3 (then STATUS deploy line EMULATOR_COUNT=3, certifier MONITOR_CANARIES=general-santos).
- **APK rollout** (pipeline, one receptor at a time, key switch to the CI key): chaparral gets GpsKeeper, quibdo the latest APK. Held until the first deploy works.
- **Canaries:** general-santos alone for now (4 emulators don't fit in 15.7 GB). glan, La Serena, San Salvador wait for dedicated hosts (~$33/month each) when there is money.
- **QA-67:** EC2 CPU during an event, measured at the next quake.
- **Native iOS app (AlarmKit):** later, after Xcode, the Apple Developer account and the developer-ios agent.
- **Custom domain:** optional and cosmetic. Staging HTTPS works at https://d1o3i68tksfjqi.cloudfront.net; the user buys a domain when ready.
- **Auto receptor growth:** built, propose-only (AUTO_RECEPTOR_BUDGET_USD=0) until the user sets a cap.
- **Extreme optimization (decision.md §9):** only when everything is stable.

Closed on 24/25-sep: Mac fleet retired (19:11 UTC); QA-90 (AEA location age + nudge, proven 25-sep 05:30–05:40 on quibdo); false uncovered on quibdo 21:15–23:25 fixed; outreach emails dropped.

## Known traps (do not re-investigate)

- zsh: `ubuntu@$IP:earthquakes-project` expands `$IP:e` as a modifier (extension). rsync/scp then copy to a LOCAL dir and the deploy silently lands stale code (24-sep 19:06). Always write `${IP}:`.

- The geo fix only lands with the GNSS HAL active. Without GpsKeeper, that is only during boot.
- GMS seems not to alert with a location older than ~24 h (QA-84).
- `cmd location set-location-enabled false` wipes the location. Do not use it.
- 2 vCPU cannot handle 2 emulators booting at the same time: boot them in sequence.
- targetSdk 35 blocks plain HTTP: cleartext allowed only to 10.0.2.2.

## Handoff per role (before a compact: each one leaves here where it stopped, 2-3 lines)

- **coordinator:** CLAUDE.md, STATUS.md and docs/roles/* created. Measuring GpsKeeper on AWS quibdo (installed 18:04 UTC): still to confirm over hours the earthquake_alerting deliveries. If it passes, install it on chaparral (AWS) and on the Mac. Decisions waiting for the user: HTTPS domain, retire or keep the Mac, local git init.
- **developer:** nothing half done. All green: gateway 63/63, test_sensor_health, test_receptor_placement, test_bootstrap_listener, JUnit + APK. QA-approved and waiting for the coordinator's deploy: demand-driven siting (`demand_cell` on /devices, `scripts/receptor-placement.py` + daily timer, budget default 0), canaries general-santos/glan (public:false), /subscribe public-only for users. APK (latency stamps, MY_PACKAGE_REPLACED) waits for its own deploy. Open follow-ups: `new_receptor` push and sensors.json reload without restart (not built). Traps: gradle needs `JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home`; `Map.groupBy` does not exist in Node 18; `node -e` breaks importing server.js, use a .mjs; script tests must never reach the real `lab.adb`.
- **developer-qa:** certifier pid 30920 (manual, `kill 30920`; restart = kill + `nohup python3 monitor/monitor.py run`, tell the coordinator first). On disk, loads at the next restart: tunnel retry before blaming the gateway, canaries certified and capped at DEGRADED (MONITOR_CANARIES). When general-santos runs: restart with MONITOR_CANARIES=general-santos, then the "after" column in docs/qa/load.md at >= 8 h after its boot. devops' ssm-run.sh stdin fix reviewed and approved 25-sep (test_ssm_run.sh 2/2 under dash; both mutations caught). Open QA: QA-67, QA-90b, QA-93. Tests: gateway 63/63, test_verify 24, test_sensor_health 16, test_remote 13, placement PASS.
- **devops-earthquake:** CloudWatch and HTTPS live and verified (25-sep 00:25Z). CI/deploy workflows wait for the push; first gateway deploy should log seconds-to-covered (QA: < 90 s → cut the 7 min cap to 3). APK deploy on hold (`APK_DEPLOY_ENABLED`).
- **comunicacion-humano** (session closed): outreach dropped by the user on 2026-09-24. Drafts stay in docs/outreach/ as history; nothing is sent.

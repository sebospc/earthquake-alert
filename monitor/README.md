# Certifier

Independent verifier of the alert system. It does not import gateway code: it talks to it
over HTTP like any external client, through an SSH tunnel to the EC2, because the
gateway only listens on 127.0.0.1. Every day it writes `docs/qa/cert/AAAA-MM-DD.md` (UTC day)
with a verdict CERTIFIED, DEGRADED or FAIL and the rule that decided it.

```bash
python3 monitor/monitor.py run          # loop; started by hand, not installed as a service
python3 monitor/monitor.py once         # one pass of everything
python3 monitor/monitor.py cert 2026-09-24
python3 monitor/test_verify.py          # classification and verdict, with real quakes
node monitor/test_push_receiver.mjs     # web push decryption (Node 22)
```

## What it watches

| every | what | from where |
|---|---|---|
| 60 s | coverage per receptor and per channel, heartbeat, `aea_ok`, canary, `degraded` | `GET /status` |
| 5 min | dispatched alerts, with `accepted_at` and `delivered_at` | `GET /evidence` (signed) |
| 30 min | quakes from M4.0 in the Colombia box | USGS (FDSN) and SGC |
| 1 h | end-to-end probe | `POST /probe` (signed) → push → this monitor |
| 30 min | GMS location age, deliveries to `earthquake_alerting` (QA-84) and emulator clock skew | ssh to the EC2, read-only |
| 30 min | the Mac's NTP offset | `sntp`, read-only |

The gateway keeps coverage only in RAM; `data/health.jsonl` is the persistent
history. The minutes without coverage and the outages come from there.

The control is the Mac emulator fleet: `lab-log.jsonl` and `lab-state.json` in
`~/Library/Application Support/aea-lab/evidence`, read-only. If the Mac captured and AWS did not,
with AWS covered, it is FAIL. If the Mac was down, it stays "no control" and does not count.
The user retired the Mac fleet on 2026-09-24 19:11 UTC, EC2 clock (`MONITOR_MAC_RETIRED_AT`). From then on
the catalogs are the only ground truth: an expected quake with no AWS capture is a MISS judged by
the catalog causes alone (FAIL when unexplained), labelled "the Mac control is retired", and the
Mac makes no rows or downtime of its own. The control poll stops at the same moment. Without a control, 3 explained
misses on one AWS receptor in 7 days, with no hit in between, is DEGRADED: "near threshold" can
hide a real failure once, not every week. Canary pairs (`MONITOR_CANARY_PAIRS=a:b`,
docs/siting-canaries.md) control each other. If the partner was covered and inside the radius:
both missing is "Google did not alert", only one missing is FAIL. Canaries (`MONITOR_CANARIES`, plus the ids of
any pair) are not public but are certified; a canary never makes the day worse than DEGRADED, because
nobody gets alerts through it. List a canary only once it runs: a listed canary that is down reads as
uncovered.

The rules and thresholds ("expected", the radius, NEAR) come from `scripts/lab.py`, which is
imported without touching it. The GPS location lowers the verdict to DEGRADED if it is older than 1 h on a receptor with
GpsKeeper (`MONITOR_GPSKEEPER`, default `quibdo,general-santos`), or older than 21 h or null on one without it.
The AWS receptors polled are read over ssh from the host's `/etc/earthquake-sensors.map`, serial and id
only (the keys stay there); `MONITOR_AWS_SERIALS=emulator-5554:chaparral,...` overrides it. An unreadable map
is a notification, never an empty poll.
AEA's own copy (the last location GMS delivered to `earthquake_alerting`) over 21 h is DEGRADED on
any receptor. AEA only gets a new one on a move of 1 km or more, so a flat delivery counter is
normal (QA-90). A real alert whose listener → monitor time, with both clocks
corrected, goes over 2 s (or never reaches the monitor) is DEGRADED too. The classification is in `verify.py`, which is pure and has the tests.

## External services

- **USGS** and **SGC**: GET only. The SGC is `api.sgc.gov.co/biweekly/biweekly_earthquakes`,
  with dates in Bogotá time, a 14-day window at most and coordinates
  `[lon, lat, prof]`. Errors arrive as 200 with an `error` object, and the code never
  takes them as "no quakes". It is mandatory: the Chaparral quakes of 23-sep are not
  in USGS.
- **Mozilla autopush** (`wss://push.services.mozilla.com`): `push-receiver.mjs` keeps there
  the monitor's web push subscriptions, without a browser. Only probes go through it, plus what
  already travels over web push to any user (alerts and coverage notices), end-to-end
  encrypted with the keys in `data/push-state.json`. Mozilla sees when a push arrives,
  not the content.
- **ntfy.sh**: only if `MONITOR_NTFY_TOPIC` exists, and only for FAIL.
- **AWS**: `describe-instances` for the IP (it changes with every spot interruption) and SSH for the
  tunnel. It writes nothing on the EC2.

## Data (`data/`, outside git)

| file | what |
|---|---|
| `monitor-key` | the gateway's `MONITOR_KEY`, 0600. Read once over read-only SSH |
| `health.jsonl` | one record per minute |
| `evidence.jsonl` | copy of the gateway evidence |
| `probes-sent.jsonl`, `pushes.jsonl` | probes sent and everything that arrived over web push |
| `push-state.json` | keys of its own subscriptions, 0600 |
| `state.json` | cursors, catalog and notices already sent |
| `known_hosts` | EC2 host key. A new IP is accepted once; a changed key is rejected |

## Limits

- The Mac has to be on. If the monitor saw less than 90 % of the minutes of the
  day, the certificate says DEGRADED: what was not seen is not certified.
- An AWS receptor counts from the first minute the monitor saw it covered. Earlier
  quakes come out as N/A.
- The downtime of the control Mac is inferred from `lab.py`'s "Device caido"/"Device recuperado"
  notices and its `last_seen`. It is not exact to the minute.

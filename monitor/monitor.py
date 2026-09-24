#!/usr/bin/env python3
"""Certifier: watches the gateway from outside and writes a daily certificate.

    python3 monitor/monitor.py run            # loop: health 60 s, evidence 5 min, catalogs 30 min, probe 1 h
    python3 monitor/monitor.py once           # one pass of everything, for a check by hand
    python3 monitor/monitor.py cert [YYYY-MM-DD]   # write docs/qa/cert/<day>.md (UTC day)

Talks to the gateway only over HTTP, through an SSH tunnel to the EC2 (the gateway listens
on 127.0.0.1 only). Reads the Mac control fleet from lab.py's files, read-only. Everything
it learns goes to monitor/data/ (git-ignored). See monitor/README.md.
"""
import glob
import hashlib
import hmac
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import verify  # noqa: E402
from verify import lab  # noqa: E402

DATA = os.environ.get("MONITOR_DATA", os.path.join(HERE, "data"))
CERT_DIR = os.path.join(ROOT, "docs", "qa", "cert")
INSTANCE_ID = os.environ.get("MONITOR_INSTANCE", "i-0d1c0b6dd02e0ae61")
REGION = os.environ.get("MONITOR_REGION", "sa-east-1")
SSH_KEY = os.path.expanduser(os.environ.get("MONITOR_SSH_KEY", "~/.ssh/aea-lab.pem"))
LOCAL_PORT = int(os.environ.get("MONITOR_LOCAL_PORT", "18787"))
GATEWAY = f"http://127.0.0.1:{LOCAL_PORT}"
NTFY_TOPIC = os.environ.get("MONITOR_NTFY_TOPIC")
# The Mac control fleet: lab.py runs from here, live. Read-only.
# The user retired the Mac control fleet (launchd job removed, emulators off). After this the
# SGC and USGS catalogs are the only ground truth, and the Mac is "retired", never "down".
MAC_RETIRED_AT = datetime.fromisoformat(os.environ.get("MONITOR_MAC_RETIRED_AT", "2026-09-24T19:11:00+00:00")).timestamp()
LAB_DIR = os.environ.get("MONITOR_LAB_DIR", os.path.expanduser("~/Library/Application Support/aea-lab/evidence"))

HEALTH_EVERY_S = 60
EVIDENCE_EVERY_S = 300
CATALOG_EVERY_S = 1800
PROBE_EVERY_S = 3600
PROBE_TIMEOUT_S = 60
# A health record stands for the minute around it; a quake further than this from any
# record has no coverage data.
HEALTH_MATCH_S = 90
# Same box lab.py polls: Colombia plus margin.
BOX = {"minlatitude": -5, "maxlatitude": 16, "minlongitude": -84, "maxlongitude": -64}
BOGOTA = timezone(timedelta(hours=-5))


def path(name):
    return os.path.join(DATA, name)


def now():
    return time.time()


def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat(timespec="seconds")


def append(name, record):
    with open(path(name), "a") as handle:
        handle.write(json.dumps(record) + "\n")


def read_jsonl(file):
    try:
        with open(file) as handle:
            return [json.loads(line) for line in handle if line.strip()]
    except FileNotFoundError:
        return []


def load_state():
    return lab.load(path("state.json"), {"evidence_since": "2026-09-24T00:00:00.000Z", "catalog": {},
                                          "notified": [], "last": {}})


def notify(message):
    """Operator alert: FAIL, and live coverage runs of 15 min or more. Local first (a macOS
    notification and data/live-alerts.jsonl, nothing leaves the machine); ntfy only if configured."""
    print(f"NOTIFY: {message}")
    append("live-alerts.jsonl", {"at": now(), "message": message})
    try:
        subprocess.run(["osascript", "-e", f"display notification {json.dumps(message)} with title \"Earthquake certifier\""],
                       capture_output=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        pass  # the log line and live-alerts.jsonl above already hold it
    if not NTFY_TOPIC:
        return
    try:
        request = urllib.request.Request(f"https://ntfy.sh/{NTFY_TOPIC}", data=message.encode(),
                                         headers={"Title": "Certifier: FAIL", "Priority": "urgent"})
        urllib.request.urlopen(request, timeout=15).close()
    except Exception as error:
        print(f"ntfy failed: {error}", file=sys.stderr)


# --- the tunnel: the gateway is only on the EC2's loopback, and the IP changes with spot ---

tunnel = None


def instance():
    out = subprocess.run(["aws", "ec2", "describe-instances", "--region", REGION, "--instance-ids", INSTANCE_ID,
                          "--query", "Reservations[0].Instances[0].[State.Name,PublicIpAddress]", "--output", "json"],
                         capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        return None, None
    state, ip = json.loads(out.stdout)
    return state, ip


def port_open():
    with socket.socket() as probe:
        probe.settimeout(2)
        return probe.connect_ex(("127.0.0.1", LOCAL_PORT)) == 0


def ensure_tunnel():
    """(ok, reason). reason "spot" when AWS says the instance is not running."""
    global tunnel
    if tunnel and tunnel.poll() is None and port_open():
        return True, None
    # A tunnel from another monitor process (the loop, while `cert` runs by hand).
    if tunnel is None and port_open():
        return True, None
    if tunnel and tunnel.poll() is None:
        tunnel.kill()
    state, ip = instance()
    if state != "running" or not ip:
        return False, "spot" if state else "aws-cli"
    # Own known_hosts: a new IP is accepted once, a changed key for a known IP is refused loudly.
    tunnel = subprocess.Popen(["ssh", "-N", "-i", SSH_KEY, "-L", f"{LOCAL_PORT}:127.0.0.1:8787",
                               "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=30",
                               "-o", "StrictHostKeyChecking=accept-new",
                               "-o", f"UserKnownHostsFile={path('known_hosts')}",
                               "-o", "BatchMode=yes", f"ubuntu@{ip}"],
                              stdout=subprocess.DEVNULL, stderr=open(path("ssh.log"), "a"))
    for _ in range(20):
        if port_open():
            return True, None
        if tunnel.poll() is not None:
            break
        time.sleep(0.5)
    return False, "ssh"


# --- gateway API ---

def monitor_key():
    with open(path("monitor-key")) as handle:
        return handle.read().strip()


def call(method, path_with_query, payload=None, signed=False, timeout=15):
    body = b"" if payload is None else json.dumps(payload).encode()
    headers = {"content-type": "application/json"}
    if signed:
        timestamp = str(int(now()))
        message = f"{timestamp}\n{method} {path_with_query}\n{body.decode()}".encode()
        headers["x-monitor-timestamp"] = timestamp
        headers["x-monitor-signature"] = hmac.new(monitor_key().encode(), message, hashlib.sha256).hexdigest()
    request = urllib.request.Request(GATEWAY + path_with_query, data=body if payload is not None else None,
                                     method=method, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        text = response.read().decode()
        return json.loads(text) if text else None


def public_sensors():
    sensors = call("GET", "/sensors.json")["sensors"]
    return [s for s in sensors if s.get("public") is True]


def poll_health():
    ok, reason = ensure_tunnel()
    record = {"at": now()}
    if not ok:
        record["error"] = reason
    else:
        try:
            status = call("GET", "/status")
            record["sensors"] = {s["id"]: {k: s.get(k) for k in (
                "covered", "covered_apns", "covered_webpush", "stale", "aea_ok", "aea_stale",
                "last_canary_ok_at", "degraded")} for s in status["sensors"]}
            record["relay_enabled"] = status["relay_enabled"]
            # Changes on every gateway restart: how a deploy is told apart from a receiver down.
            if status.get("started_at"):
                record["started_at"] = datetime.fromisoformat(status["started_at"].replace("Z", "+00:00")).timestamp()
        except Exception as error:
            # Tunnel up, gateway not answering: that is the gateway down, not us.
            record["error"] = "gateway"
            record["detail"] = str(error)[:200]
    append("health.jsonl", record)
    return record


def poll_evidence(state):
    since = state["evidence_since"]
    for _ in range(20):
        page = call("GET", f"/evidence?since={urllib.parse.quote(since)}&limit=1000", signed=True, timeout=60)
        for record in page["records"]:
            append("evidence.jsonl", record)
        since = page["next_since"]
        if not page["records"]:
            break
    state["evidence_since"] = since


def fetch_json(url, timeout=60):
    request = urllib.request.Request(url, headers={"User-Agent": "aea-certifier/1"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def poll_catalogs(state, days=3):
    """USGS and SGC, merged later. SGC is mandatory: the Chaparral quakes of 23-sep are not in USGS."""
    start = datetime.now(timezone.utc) - timedelta(days=days)
    usgs = fetch_json("https://earthquake.usgs.gov/fdsnws/event/1/query?" + urllib.parse.urlencode(
        {"format": "geojson", "starttime": start.strftime("%Y-%m-%dT%H:%M:%S"),
         "minmagnitude": lab.CATALOG_MIN_MAG, **BOX}))
    # The SGC API takes Bogotá dates and at most 14 days.
    local_start = start.astimezone(BOGOTA).strftime("%Y-%m-%dT00:00:00")
    local_end = datetime.now(BOGOTA).strftime("%Y-%m-%dT23:59:59")
    sgc = fetch_json("https://api.sgc.gov.co/biweekly/biweekly_earthquakes?" + urllib.parse.urlencode(
        {"startdate": local_start, "enddate": local_end}))
    events = verify.usgs_events(usgs) + [e for e in verify.sgc_events(sgc) if (e["mag"] or 0) >= lab.CATALOG_MIN_MAG]
    for event in events:
        state["catalog"][event["id"]] = event


def probe(state):
    probe_id = f"probe-{uuid.uuid4()}"
    sent = now()
    queued = call("POST", "/probe", {"probe_id": probe_id, "sent_at": iso(sent)}, signed=True)["queued"]
    append("probes-sent.jsonl", {"probe_id": probe_id, "sent": sent, "queued": queued})


def node22():
    candidates = [os.environ.get("MONITOR_NODE")] + sorted(glob.glob(os.path.expanduser("~/.nvm/versions/node/v2[2-9]*/bin/node")))
    return next((c for c in candidates if c and os.path.exists(c)), "node")


receiver = None


def ensure_receiver_running(sensor_ids):
    """Checked every step: a dead receiver would lose every probe until someone noticed."""
    global receiver
    if receiver is None or receiver.poll() is not None:
        vapid = call("GET", "/status")["web_push_public_key"]
        receiver = subprocess.Popen([node22(), os.path.join(HERE, "push-receiver.mjs"), DATA, vapid, *sensor_ids],
                                    stdout=open(path("receiver.log"), "a"), stderr=subprocess.STDOUT)
        time.sleep(5)


def subscribe_receiver(sensor_ids):
    """Our own web push subscriptions, registered at the gateway as monitor subscriptions."""
    channels = lab.load(path("push-state.json"), {}).get("channels", {})
    for sensor_id, channel in channels.items():
        if channel.get("endpoint") and sensor_id in sensor_ids:
            call("POST", "/subscribe", {"sensor_id": sensor_id, "monitor": True, "subscription": {
                "endpoint": channel["endpoint"], "keys": {"p256dh": channel["publicKey"], "auth": channel["auth"]}}},
                signed=True)


# --- inputs for verify ---

def aws_captures():
    captures = []
    for record in read_jsonl(path("evidence.jsonl")):
        event = record.get("event")
        if not event or "accepted_at" not in record:
            continue
        origin = verify_origin(event)
        if origin is None:
            continue
        delivered = [r.get("delivered_at") for r in record.get("web_push", []) + record.get("apns", []) if r.get("delivered_at")]
        captures.append({"receiver": event["sensor_id"], "kind": "aws", "origin": origin,
                         "captured": datetime.fromisoformat(event["captured_at"].replace("Z", "+00:00")).timestamp(),
                         "accepted": datetime.fromisoformat(record["accepted_at"].replace("Z", "+00:00")).timestamp(),
                         "first_delivery": min((datetime.fromisoformat(d.replace("Z", "+00:00")).timestamp()
                                                for d in delivered), default=None),
                         "event_id": event["event_id"], "late": event.get("late")})
    return captures


def verify_origin(event):
    if event.get("time_occurred_s") is not None:
        return float(event["time_occurred_s"])
    if event.get("post_time_ms") is not None:
        return float(event["post_time_ms"]) / 1000
    return None


def mac_captures():
    """ALERTs, plus UPDATEs flagged as such: an update without its alert is UPDATE_ONLY."""
    captures = []
    for record in read_jsonl(os.path.join(LAB_DIR, "lab-log.jsonl")):
        kind = lab.classify(record["event"]) if record.get("type") == "GMS_NOTIFICATION" else None
        if kind not in ("ALERT", "UPDATE"):
            continue
        event = record["event"]
        occurred = (event.get("selected_extras") or {}).get("TIME_OCCURRED_EXTRA")
        origin = float(occurred) if occurred not in (None, "null") else event["post_time_ms"] / 1000
        captures.append({"receiver": record["device"], "kind": "mac", "origin": origin,
                         "captured": event["captured_at_ms"] / 1000, "update": kind == "UPDATE"})
    return captures


def mac_down_intervals():
    """lab.py notifies "Device caido" and "Device recuperado"; between them the control is blind."""
    intervals, open_since = [], {}
    for record in read_jsonl(os.path.join(LAB_DIR, "lab-log.jsonl")):
        if record.get("type") != "NOTIFY":
            continue
        at = datetime.fromisoformat(record["at"]).timestamp() if "at" in record else None
        name = (record.get("message") or "").split(" ")[0]
        if at and record.get("title") == "Device caido":
            open_since[name] = at
        elif at and record.get("title") == "Device recuperado" and name in open_since:
            intervals.append((name, open_since.pop(name), at))
    return intervals + [(name, since, float("inf")) for name, since in open_since.items()]


def receivers(sensors, health):
    first_seen = {}
    for record in health:
        for sensor_id, s in (record.get("sensors") or {}).items():
            if s.get("covered") and sensor_id not in first_seen:
                first_seen[sensor_id] = record["at"]
    result = [{"id": s["id"], "lat": s["lat"], "lon": s["lon"], "kind": "aws",
               # Before the monitor first saw it covered, there is nothing to certify.
               "since": first_seen.get(s["id"], float("inf"))} for s in sensors]
    by_id = {r["id"]: r for r in result}
    for a, b in CANARY_PAIRS:
        if a in by_id and b in by_id:
            by_id[a]["pair"], by_id[b]["pair"] = by_id[b], by_id[a]
    lab_state = lab.load(os.path.join(LAB_DIR, "lab-state.json"), {"devices": {}})
    for _, name, lat, lon in lab.FLEET:
        since = (lab_state["devices"].get(name) or {}).get("online_since")
        result.append({"id": name, "lat": lat, "lon": lon, "kind": "mac", "until": MAC_RETIRED_AT,
                       "since": datetime.fromisoformat(since).timestamp() if since else float("inf")})
    return result


def coverage_lookup(health):
    times = [record["at"] for record in health]
    readings = [r for r in read_jsonl(path("control.jsonl")) if "error" not in r]
    lab_state = lab.load(os.path.join(LAB_DIR, "lab-state.json"), {"devices": {}})
    down = mac_down_intervals()

    def covered(kind, receiver_id, t):
        if kind == "mac":
            device = lab_state["devices"].get(receiver_id) or {}
            if not device.get("online_since") or not device.get("last_seen"):
                return None
            start = datetime.fromisoformat(device["online_since"]).timestamp()
            end = datetime.fromisoformat(device["last_seen"]).timestamp() + lab.STALE_DEVICE_MIN * 60
            if not start <= t <= end or any(n == receiver_id and a <= t <= b for n, a, b in down):
                return None
            # A control whose location is too old sees nothing: it cannot excuse an AWS miss.
            return None if verify.control_fresh(readings, receiver_id, t) is False else True
        nearest = min(range(len(times)), key=lambda i: abs(times[i] - t), default=None)
        if nearest is None or abs(times[nearest] - t) > HEALTH_MATCH_S:
            return None
        record = health[nearest]
        if record.get("error") in ("gateway", "spot"):
            return False
        sensor = (record.get("sensors") or {}).get(receiver_id)
        return None if sensor is None else bool(sensor.get("covered"))
    return covered


def felt(event, receiver):
    if not str(event.get("ids", [event["id"]])[0]).startswith(("us", "ci", "nc", "pt", "at")):
        return None
    try:
        return (lab.felt_intensity(lab.usgs_detail(event["ids"][0]), receiver["lat"], receiver["lon"]) or {}).get("mmi")
    except Exception:
        return None


def classify_all(state, sensors):
    health = read_jsonl(path("health.jsonl"))
    events = verify.merge_catalogs(list(state["catalog"].values()))
    captures = aws_captures() + mac_captures()
    return verify.classify(events, captures, receivers(sensors, health), coverage_lookup(health), now(), felt)


# --- the daily certificate ---

def day_bounds(day):
    start = datetime.strptime(day, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()
    return start, start + 86400


INTERVENTIONS = os.path.join(HERE, "interventions.json")


def interventions():
    """Declared by the operator by hand; versioned so the certificate can be audited."""
    return lab.load(INTERVENTIONS, [])


def poll_control():
    """QA-85: how old the Mac control's GMS location is. adb read-only: uptime and dumpsys."""
    if now() >= MAC_RETIRED_AT:
        return
    for port, name, _, _ in lab.FLEET:
        serial = f"emulator-{port}"
        uptime = lab.adb(serial, "shell", "cat", "/proc/uptime", timeout=20)
        dump = lab.adb(serial, "shell", "dumpsys", "location", timeout=60)
        if uptime is None or dump is None:
            append("control.jsonl", {"at": now(), "device": name, "age_s": None, "error": "adb"})
            continue
        append("control.jsonl", {"at": now(), "device": name,
                                 "age_s": verify.location_age_s(dump, float(uptime.split()[0]))})


# Which emulator is which receptor on the EC2 (the map there is 0600 and holds keys).
AWS_SERIALS = dict(item.split(":") for item in os.environ.get(
    "MONITOR_AWS_SERIALS", "emulator-5554:chaparral,emulator-5556:quibdo").split(","))
# Receptors running GpsKeeperService: held to the 1 h / 2 h rule instead of the ~24 h one.
# Canary pairs that control each other, "a:b,c:d" (docs/siting-canaries.md). Empty until provisioned.
CANARY_PAIRS = [pair.split(":") for pair in os.environ.get("MONITOR_CANARY_PAIRS", "").split(",") if pair]
GPSKEEPER = set(filter(None, os.environ.get("MONITOR_GPSKEEPER", "quibdo").split(",")))
# Read-only: uptime, the GPS line of dumpsys location, and earthquake_alerting's total.
REMOTE_LOCATION_SCRIPT = """A="sudo -u aea -H /opt/android-sdk/platform-tools/adb"
for s in {serials}; do
  echo "== $s"; $A -s $s shell cat /proc/uptime
  $A -s $s shell dumpsys location | grep -m1 "last location=Location\\[gps"
  $A -s $s shell dumpsys activity service com.google.android.gms | grep -E "earthquake_alerting\\]: total|delivered locations.*\\[earthquake_alerting\\]"
  echo "guest_now $($A -s $s shell date +%Y-%m-%dT%H:%M:%S | tr -d '\\r')"
  echo "clock $(date +%s.%N) $($A -s $s shell date +%s.%N | tr -d '\\r') $(date +%s.%N)"
done"""


def poll_aws_location():
    """QA-84: the location Play Services holds on each AWS receptor, and whether
    earthquake_alerting keeps getting fed. Over ssh, read-only."""
    state, ip = instance()
    if state != "running" or not ip:
        return
    out = subprocess.run(["ssh", "-i", SSH_KEY, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
                          "-o", f"UserKnownHostsFile={path('known_hosts')}", f"ubuntu@{ip}",
                          REMOTE_LOCATION_SCRIPT.format(serials=" ".join(AWS_SERIALS))],
                         capture_output=True, text=True, timeout=180).stdout
    history = read_jsonl(path("aws-location.jsonl"))
    for chunk in out.split("== ")[1:]:
        serial, _, rest = chunk.partition("\n")
        lines = rest.splitlines()
        try:
            uptime = float(lines[0].split()[0])
        except (IndexError, ValueError):
            uptime = None
        sensor = AWS_SERIALS.get(serial.strip(), serial.strip())
        previous = next((r.get("alert_delivery_at") for r in reversed(history) if r["sensor"] == sensor
                         and r.get("alert_delivery_at") is not None), None)
        age = verify.remembered_alert_age_s(verify.last_alerting_delivery_age_s(rest, guest_now(rest)),
                                            previous, now(), uptime)
        append("aws-location.jsonl", {
            "at": now(), "sensor": AWS_SERIALS.get(serial.strip(), serial.strip()),
            "age_s": verify.location_age_s(rest, uptime) if uptime is not None else None,
            "deliveries": verify.alerting_deliveries(rest), "uptime_s": uptime,
            "skew_s": verify.emulator_skew_s(rest),
            "alert_age_s": age, "alert_delivery_at": None if age is None else now() - age})


def guest_now(text):
    match = re.search(r"guest_now (\S+)", text)
    return match.group(1) if match else None


def poll_mac_clock():
    """The Mac's NTP offset, so push arrivals can be put in true time. sntp only reads, it never sets."""
    out = subprocess.run(["sntp", "-t", "3", "time.apple.com"], capture_output=True, text=True, timeout=30).stdout
    append("mac-clock.jsonl", {"at": now(), "offset_s": verify.sntp_offset_s(out)})


def deploy_times():
    """DEPLOY records the bootstrap writes to the evidence right before it restarts the gateway."""
    return verify.planned_deploys(read_jsonl(path("evidence.jsonl")))


def certificate(day, state, sensors):
    start, end = day_bounds(day)
    horizon = min(end, now())
    health = read_jsonl(path("health.jsonl"))
    in_day = [r for r in health if start <= r["at"] < end]
    completeness = len([r for r in in_day if r.get("error") not in ("ssh", "aws-cli")]) / max(1, (horizon - start) / 60)
    sensor_ids = [s["id"] for s in sensors]
    windows = verify.restart_windows(health, deploy_times(), set(sensor_ids)) \
        + verify.intervention_windows(interventions(), health)
    coverage = verify.coverage_stats(health, sensor_ids, start, end, windows)
    restarts = [w[:3] for w in windows if start <= w[0] < end and len(w) == 3]
    manual = [w for w in windows if start <= w[0] < end and len(w) == 4]
    sent = [p for p in read_jsonl(path("probes-sent.jsonl")) if start <= p["sent"] < end]
    arrivals = {}
    for push in read_jsonl(path("pushes.jsonl")):
        payload = push.get("payload") or {}
        if payload.get("kind") == "probe":
            arrivals.setdefault(payload["probe_id"], []).append(
                datetime.fromisoformat(push["received_at"].replace("Z", "+00:00")).timestamp())
    latencies = [min(arrivals[p["probe_id"]]) - p["sent"] for p in sent if p["probe_id"] in arrivals]
    # A probe is expected once per monitor subscription; "received" counts probes that arrived at all.
    probes = {"sent": len(sent), "received": len(latencies), "latencies_s": latencies}
    findings, unexplained = classify_all(state, sensors)
    repeated = verify.repeated_explained_misses(findings, end)
    findings = [f for f in findings if start <= f["time"] < end]
    unexplained = [c for c in unexplained if start <= c["captured"] < end]
    alerts = [c for c in aws_captures() if start <= c["captured"] < end]
    delays = [c["first_delivery"] - c["captured"] for c in alerts if c["first_delivery"]]
    received, skews, mac_clock = monitor_arrivals(), read_jsonl(path("aws-location.jsonl")), read_jsonl(path("mac-clock.jsonl"))
    for c in alerts:
        c["received"] = received.get(f"quake:{round(c['origin'] * 1000 / 60_000)}")
        c["skew_s"] = verify.nearest([r for r in skews if r["sensor"] == c["receiver"]], c["captured"], "skew_s")
        c["our_part"] = verify.our_part_s(c["captured"], c["received"], c["skew_s"],
                                          verify.nearest(mac_clock, c["captured"], "offset_s"))
        c["usgs_origin"] = verify.usgs_origin(c["origin"], list(state["catalog"].values()))
    location = [r for r in read_jsonl(path("aws-location.jsonl")) if start <= r["at"] < end]
    decision, reasons = verify.verdict(findings, unexplained, coverage, probes, delays,
                                       min(1.0, completeness), verify.location_problems(location, GPSKEEPER) + repeated,
                                       [(c["event_id"], c["our_part"]) for c in alerts])
    return render(day, decision, reasons, coverage, probes, findings, unexplained, alerts, completeness, horizon < end,
                  restarts, manual)


def render(day, decision, reasons, coverage, probes, findings, unexplained, alerts, completeness, partial, restarts,
           manual=()):
    lines = [f"# Certificate {day} (UTC){', partial: the day is not over' if partial else ''}", "",
             f"**Verdict: {decision}**", ""]
    lines += [f"- {reason}" for reason in reasons] or ["- No FAIL or DEGRADED rule fired."]
    lines += ["", "Rules: FAIL = MISS with the receptor down, unexplained, or with the Mac capturing while AWS was covered; "
              "FALSE confirmed (24 h); a receptor uncovered > 60 min in a row. DEGRADED = > 15 min uncovered "
              "in the day; probes lost > 5 % or p95 > 10 s; real alert delivered > 10 s after capture; "
              "the monitor saw < 90 % of the minutes; GMS GPS location > 1 h on a receptor with GpsKeeper, "
              "> 20 h or null on one without it; AEA's own location (last delivery to earthquake_alerting) > 20 h "
              "on any receptor. With the Mac control retired, 3 explained misses on one receptor in 7 days with no hit in between. MISSes explained by Google do not lower the verdict.",
              "", f"Minutes observed by the monitor: {completeness:.0%}.", "", "## Coverage per receptor", "",
              "| receptor | min uncovered | longest gap | min in deploy or intervention (not counted) | gaps |",
              "|---|---|---|---|---|"]
    for sensor_id, stats in coverage.items():
        gaps = ", ".join(f"{iso(g['from'])[11:16]} ({g['reason']})" for g in stats["gaps"]) or "—"
        lines.append(f"| {sensor_id} | {stats['uncovered_min']} | {stats['longest_gap_min']} min | "
                     f"{stats['deploy_min']} | {gaps} |")
    lines += ["", "## Gateway restarts", ""]
    lines += [f"- {iso(a)[11:19]}: {reason}, covered again {iso(b)[11:19]}" for a, b, reason in restarts] \
        or ["None."]
    if manual:
        reasons_by_sensor = {i["sensor"]: i.get("reason", "") for i in interventions()}
        lines += ["", "## Manual interventions (monitor/interventions.json)", ""]
        lines += [f"- {sensor} {iso(a)[11:16]}–{iso(b)[11:16]}: {reasons_by_sensor.get(sensor, '')}"
                  for a, b, _, sensor in manual]
    lines += aws_location_section(day)
    summary = verify.summarize_latencies(probes["latencies_s"])
    lines += ["", "## Probe (monitor → gateway → push service → monitor)", "",
              f"Sent {probes['sent']}, arrived {probes['received']}."]
    if summary:
        lines.append(f"p50 {summary['p50']:.2f} s, p95 {summary['p95']:.2f} s, p99 {summary['p99']:.2f} s, "
                     f"max {summary['max']:.2f} s.")
    lines += ["", "## Real alerts", ""]
    if alerts:
        lines += ["| event | origin → capture | capture → gateway | capture → 1st delivery | origin → monitor "
                  "| listener → monitor, corrected | emulator skew | late |",
                  "|---|---|---|---|---|---|---|---|"]
        for c in alerts:
            origin = c["usgs_origin"] or c["origin"]
            first = f"{c['first_delivery'] - c['captured']:.1f} s" if c["first_delivery"] else "no delivery"
            to_monitor = f"{c['received'] - origin:.1f} s" if c["received"] else "did not arrive"
            ours = f"{c['our_part']:.2f} s" if c["our_part"] is not None else "did not arrive"
            skew = f"{c['skew_s']:+.2f} s" if c["skew_s"] is not None else "unknown (taken as 0)"
            lines.append(f"| {c['event_id']} | {c['captured'] - origin:.1f} s | {c['accepted'] - c['captured']:.1f} s | "
                         f"{first} | {to_monitor} | {ours} | {skew} | {'yes' if c['late'] else 'no'} |")
        lines += ["", "Raw columns use each machine's own clock. The emulator has no NTP (chaparral ran 1.70 s behind "
                  "on 24-sep), so \"origin → capture\" comes out short and \"capture → gateway\" long by its skew. "
                  "\"Listener → monitor, corrected\" puts the capture and the arrival in true time with the nearest "
                  "emulator skew and Mac NTP readings (within 6 h); over 2 s is DEGRADED. The origin is USGS's, in ms, "
                  "when USGS has the quake; otherwise Google's, in whole seconds."]
    else:
        lines.append("None.")
    lines += ["", "## Catalog quakes (USGS + SGC)", ""]
    if findings:
        lines += ["| quake | M | receptor | km / radius | result | why |", "|---|---|---|---|---|---|"]
        for f in sorted(findings, key=lambda f: (f["time"], f["receiver"], f["kind"])):
            lines.append(f"| {f['event']} {iso(f['time'])[11:16]} | {f['mag']} | {f['receiver']} ({f['kind']}) | "
                         f"{f['km']} / {f['radius_km']} | {f['verdict']} | {f['cause'] or ''} |")
    else:
        lines.append("None expected or near.")
    if unexplained:
        lines += ["", "## Captures with no quake in any catalog", ""]
        lines += [f"- {c['receiver']} ({c['kind']}) {iso(c['captured'])}: {c['verdict']}" for c in unexplained]
    return decision, "\n".join(lines) + "\n"


def monitor_arrivals():
    """First arrival of each real alert at the monitor's own subscriptions, by quake tag."""
    arrivals = {}
    for push in read_jsonl(path("pushes.jsonl")):
        payload = push.get("payload") or {}
        if payload.get("kind") == "alert" and payload.get("tag"):
            at = datetime.fromisoformat(push["received_at"].replace("Z", "+00:00")).timestamp()
            arrivals[payload["tag"]] = min(at, arrivals.get(payload["tag"], at))
    return arrivals


def aws_location_section(day):
    start, end = day_bounds(day)
    rows = [r for r in read_jsonl(path("aws-location.jsonl")) if start <= r["at"] < end]
    lines = ["", "## GMS location on the AWS receptors (QA-84)", ""]
    if not rows:
        return lines + ["No readings."]
    lines += ["| receptor | readings | GPS max age | GPS last age | AEA location max age "
              "| earthquake_alerting deliveries (first → last) |", "|---|---|---|---|---|---|"]
    for sensor in sorted({r["sensor"] for r in rows}):
        mine = [r for r in rows if r["sensor"] == sensor]
        ages = [r["age_s"] for r in mine if r["age_s"] is not None]
        worst = f"{max(ages) / 3600:.1f} h" if ages else "no location"
        last = "no location" if mine[-1]["age_s"] is None else f"{mine[-1]['age_s'] / 60:.1f} min"
        alert_ages = [r["alert_age_s"] for r in mine if r.get("alert_age_s") is not None]
        aea = f"{max(alert_ages) / 3600:.1f} h" if alert_ages else "not measured"
        lines.append(f"| {sensor} | {len(mine)} | {worst} | {last} | {aea} "
                     f"| {mine[0]['deliveries']} → {mine[-1]['deliveries']} |")
    return lines + ["", "AEA asks GMS for a location only on a move of 1 km or more (minUpdateDistance=1000), so "
                    "the deliveries do not grow on a stationary receptor and AEA's copy ages from its last one "
                    "(boot, a move, or a nudge), even with GpsKeeper keeping the GPS fresh (QA-90)."]


def write_certificate(day, state, sensors):
    decision, text = certificate(day, state, sensors)
    os.makedirs(CERT_DIR, exist_ok=True)
    with open(os.path.join(CERT_DIR, f"{day}.md"), "w") as handle:
        handle.write(text)
    return decision


# --- loop ---

def due(state, job, every_s):
    if now() - state["last"].get(job, 0) < every_s:
        return False
    state["last"][job] = now()
    return True


def step(state, force=False):
    record = poll_health()
    if "error" in record:
        print(f"{iso(record['at'])} health: {record['error']}")
        return
    sensors = public_sensors()
    sensor_ids = [s["id"] for s in sensors]
    # ponytail: rereads health.jsonl every minute (~1.4k lines/day); keep the tail if it grows slow.
    notices, state["uncovered"] = verify.live_coverage_notices(
        read_jsonl(path("health.jsonl"))[-24 * 60:], sensor_ids, state.get("uncovered", {}))
    for notice in notices:
        notify(notice)
    try:
        ensure_receiver_running(sensor_ids)
    except Exception as error:
        print(f"{iso(now())} receiver failed: {error}", file=sys.stderr)
    jobs = [("subscribe", 3600, lambda: subscribe_receiver(sensor_ids)),
            ("evidence", EVIDENCE_EVERY_S, lambda: poll_evidence(state)),
            ("catalogs", CATALOG_EVERY_S, lambda: poll_catalogs(state)),
            ("control", CATALOG_EVERY_S, poll_control),
            ("aws-location", CATALOG_EVERY_S, poll_aws_location),
            ("mac-clock", CATALOG_EVERY_S, poll_mac_clock),
            ("probe", PROBE_EVERY_S, lambda: probe(state))]
    for job, every_s, run in jobs:
        if force or due(state, job, every_s):
            try:
                run()
            except Exception as error:
                print(f"{iso(now())} {job} failed: {error}", file=sys.stderr)
    # A failure is told at once, not at the end of the day.
    findings, unexplained = classify_all(state, sensors)
    for item in [f for f in findings if verify.fails(f)] + [c for c in unexplained if c["kind"] == "aws" and c["verdict"] == "FALSE"]:
        key = f"{item.get('event', item.get('captured'))}:{item['receiver']}:{item['verdict']}"
        if key not in state["notified"]:
            state["notified"].append(key)
            notify(f"{item['verdict']} on {item['receiver']}: {item.get('cause') or 'capture with no quake in any catalog'}")
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    if state.get("certified_day") != today:
        yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d")
        if state.get("certified_day") and write_certificate(yesterday, state, sensors) == "FAIL":
            notify(f"certificate {yesterday}: FAIL, see docs/qa/cert/{yesterday}.md")
        state["certified_day"] = today
    lab.save(path("state.json"), state)


def main():
    os.makedirs(DATA, exist_ok=True)
    command = sys.argv[1] if len(sys.argv) > 1 else "run"
    state = load_state()
    if command == "cert":
        ensure_tunnel()
        day = sys.argv[2] if len(sys.argv) > 2 else datetime.now(timezone.utc).strftime("%Y-%m-%d")
        print(write_certificate(day, state, public_sensors()))
        return
    if command == "once":
        step(state, force=True)
        return
    while True:
        started = now()
        try:
            step(state)
        except Exception as error:
            print(f"{iso(now())} step failed: {error}", file=sys.stderr)
        time.sleep(max(1, HEALTH_EVERY_S - (now() - started)))


if __name__ == "__main__":
    import signal
    # kill <pid> must also stop the tunnel and the receiver, not leave them orphaned.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        main()
    finally:
        for child in (tunnel, receiver):
            if child and child.poll() is None:
                child.terminate()

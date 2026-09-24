#!/usr/bin/env python3
"""Reports to the gateway, per sensor, whether AEA can still receive an alert (aea_ok), and
reboots a guest whose location Play Services can no longer use.

The listener proves itself with its own heartbeat, but it cannot read dumpsys. This runs
on the host next to the emulators, every 5 minutes (systemd timer from aws-bootstrap.sh),
as the user that runs the emulators: adb and the emulator console only trust that user.

    sensor-health.py <sensor-map>

sensor-map has one "<adb serial> <sensor_id> <lat> <lon> <sensor key>" per line, written by
the bootstrap's listener step (0600, owned by that user). The key is the per-sensor one,
already derived: this never sees the master secret. A missing map means the listener step
has not run yet: nothing to do.

Trap, measured on the EC2: `cmd location set-location-enabled false/true` is NOT a way to
refresh the location. It wipes the last location (null) and asks for no new fix, which
left a sensor blind. The only proven remedy is a guest reboot while aea-geofix.py feeds
the assigned place.
"""
import fcntl
import hashlib
import hmac
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone

import lab

MAX_DRIFT_KM = 25
GATEWAY_URL = "http://127.0.0.1:8787/heartbeat"
STATE_FILE = os.path.expanduser("~/sensor-health-state.json")
LOCK_FILE = os.path.expanduser("~/sensor-health.lock")
PROBLEM_RUNS_BEFORE_REBOOT = 2
MIN_REBOOT_INTERVAL_S = 60 * 60
# Reboots are spread out: a booting emulator starves the others on the same host.
MIN_HOST_REBOOT_SPACING_S = 30 * 60
# Play Services takes the GPS once per boot, and past ~24 h it stopped alerting (24-sep: the
# Mac missed a real quake with a 25 h old location, AWS got it with 2.7 h). 20 h leaves a
# margin for the reboot, the staggering and the ~7 min until the new fix.
MAX_LOCATION_AGE_S = 20 * 60 * 60
# The first fix comes minutes into a boot, fed by aea-geofix.py: no location then is normal.
BOOT_WINDOW_S = 15 * 60
RECENT_ALERT_S = 10 * 60
LISTENER_EVIDENCE = "files/notification-evidence.jsonl"

GPS_LOCATION = re.compile(r"last location=Location\[gps (-?[\d.]+),(-?[\d.]+)[^\]]*?et=\+([0-9a-z]+)")


def duration_s(text):
    """Android's elapsed-time format, e.g. "1d2h3m4s567ms", in seconds."""
    units = {"d": 86400, "h": 3600, "m": 60, "s": 1, "ms": 0.001}
    return sum(int(value) * units[unit] for value, unit in re.findall(r"(\d+)(ms|d|h|m|s)", text))


def gms_location(serial):
    """{"lat", "lon", "age_s", "uptime_s"}, {"missing": True, "uptime_s"} when Play Services
    has none, or None when it cannot be read."""
    dump = lab.adb(serial, "shell", "dumpsys", "location", timeout=60)
    uptime = lab.adb(serial, "shell", "cat", "/proc/uptime", timeout=20)
    try:
        uptime_s = float(uptime.split()[0])
    except (AttributeError, IndexError, ValueError):
        return None
    if dump is None:
        return None
    match = GPS_LOCATION.search(dump)
    if match:
        return {"lat": float(match.group(1)), "lon": float(match.group(2)),
                "age_s": uptime_s - duration_s(match.group(3)), "uptime_s": uptime_s}
    if "last location=null" in dump:
        return {"missing": True, "uptime_s": uptime_s}
    return None


def clock_offset(serial):
    """(offset_s, round_trip_s): guest clock minus host clock, read against the midpoint of the
    adb call; the round trip bounds the error. None when unreadable. The emulators run
    without NTP (QA-86: 1.70 s behind on 24-sep), and every guest timestamp in the evidence
    needs this to be compared with the gateway's."""
    before = time.time()
    output = lab.adb(serial, "shell", "date", "+%s.%N", timeout=20)
    after = time.time()
    try:
        guest = float(output.strip())
    except (AttributeError, ValueError):
        return None
    return guest - (before + after) / 2, after - before


def log_clock_offset(serial, sensor_id):
    offset = clock_offset(serial)
    if offset is None:
        print(f"CLOCK_OFFSET {sensor_id} ({serial}): unreadable")
    else:
        print(f"CLOCK_OFFSET {sensor_id} ({serial}): offset_s={offset[0]:.3f} rtt_s={offset[1]:.3f}")


def check(serial, lat, lon):
    """(aea_ok, problem). problem is "drift", "stale" or "missing" when a guest reboot is the
    remedy, else None. Anything unknown counts as not ok, and never as a reason to reboot."""
    health = lab.aea_health(serial)
    location = gms_location(serial)
    if not health or location is None:
        return False, None
    if location.get("missing"):
        booting = location["uptime_s"] < BOOT_WINDOW_S
        return False, None if booting else "missing"
    # A guest that booted without the geo fix keeps a wrong place: after a spot
    # interruption the EC2 kept a default in California. Only this check sees it.
    if lab.km_between(location["lat"], location["lon"], lat, lon) > MAX_DRIFT_KM:
        return False, "drift"
    if location["age_s"] > MAX_LOCATION_AGE_S:
        return False, "stale"
    # The delivery history starts with the Play Services process, so after a cold boot it
    # stays at 0 until AEA has really been handed a location.
    return bool(health["registered"] and health["deliveries"] > 0), None


def recent_alert(serial, now):
    """True if the listener captured an eew_* notification in the last 10 min: rebooting then
    could cut an alert still being relayed. Unreadable counts as no alert: a certain blind
    sensor weighs more than an unlikely overlap."""
    tail = lab.adb(serial, "exec-out", "run-as", "com.earthquakes.relay",
                   "tail", "-n", "200", LISTENER_EVIDENCE, timeout=20)
    for line in (tail or "").splitlines():
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if (record.get("event_type") == "NOTIFICATION_POSTED"
                and str(record.get("channel_id") or "").startswith("eew_")
                and now - record.get("captured_at_ms", 0) / 1000 < RECENT_ALERT_S):
            return True
    return False


def load_state():
    try:
        with open(STATE_FILE) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def save_state(state):
    with open(STATE_FILE + ".tmp", "w") as handle:
        json.dump(state, handle)
    os.replace(STATE_FILE + ".tmp", STATE_FILE)


def reboot_if_stuck(serial, sensor_id, problem, state, now, alert_in_progress=lambda: False):
    """Reboots the guest while aea-geofix.py feeds the right place, the only proven remedy
    for a wrong, old or missing location. Two runs in a row first, so one bad read does not
    reboot; at most once an hour per sensor, so a cause a reboot cannot fix does not loop;
    and one guest per host every 30 min, so reboots never overlap."""
    entry = state.setdefault(sensor_id, {"problem_runs": 0, "rebooted_at": 0})
    entry["problem_runs"] = entry.get("problem_runs", 0) + 1 if problem else 0
    host = state.setdefault("_host", {"rebooted_at": 0})
    if (entry["problem_runs"] < PROBLEM_RUNS_BEFORE_REBOOT
            or now - entry["rebooted_at"] < MIN_REBOOT_INTERVAL_S
            or now - host["rebooted_at"] < MIN_HOST_REBOOT_SPACING_S):
        return
    if alert_in_progress():
        print(f"{sensor_id} ({serial}): {problem}, reboot put off, recent eew alert")
        return
    lab.adb(serial, "reboot", timeout=30)
    entry["rebooted_at"] = host["rebooted_at"] = now
    entry["problem_runs"] = 0
    print(f"REBOOT_PREVENTIVE {sensor_id} ({serial}): {problem}")


def restart_foreign_adb_server(serials):
    """The adb server is shared with the scrcpy tunnel and operators, so it is restarted only
    when it is visibly another user's (our devices unauthorized), once per run. Offline is
    normal while booting and a restart does not help."""
    listing = subprocess.run([lab.ADB, "devices"], capture_output=True, text=True, timeout=30).stdout
    states = dict(line.split()[:2] for line in listing.splitlines()[1:] if len(line.split()) >= 2)
    if any(states.get(serial) == "unauthorized" for serial in serials):
        subprocess.run([lab.ADB, "kill-server"], capture_output=True, timeout=30)
        subprocess.run([lab.ADB, "start-server"], capture_output=True, timeout=30)
        time.sleep(5)


def report(sensor_key, sensor_id, ok):
    body = json.dumps({
        "sensor_id": sensor_id,
        "sent_at": datetime.now(timezone.utc).isoformat(),
        "aea_ok": ok,
    }).encode()
    signature = hmac.new(sensor_key.encode(), body, hashlib.sha256).hexdigest()
    request = urllib.request.Request(GATEWAY_URL, data=body, method="POST", headers={
        "content-type": "application/json", "x-relay-signature": signature})
    urllib.request.urlopen(request, timeout=10).close()


def main(map_path):
    if not os.path.exists(map_path):
        print(f"{map_path} missing: listener step not run yet")
        return 0
    # One run at a time per host, even if started by hand while the timer fires.
    with open(LOCK_FILE, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("another sensor-health run holds the lock")
            return 0
        return check_all(map_path)


def check_all(map_path):
    with open(map_path) as handle:
        rows = [line.split() for line in handle if line.strip()]
    restart_foreign_adb_server([row[0] for row in rows])
    state = load_state()
    failures = 0
    for row in rows:
        # One old or broken row must not stop the other sensors from reporting.
        try:
            serial, sensor_id, lat, lon, sensor_key = row
            log_clock_offset(serial, sensor_id)
            # The listener's GpsKeeperService holds GPS open, so this fix reaches Play
            # Services within a minute. It is also how a sensor moved in the map takes its
            # new place, without a reboot.
            lab.adb(serial, "emu", "geo", "fix", lon, lat, timeout=20)
            ok, problem = check(serial, float(lat), float(lon))
            now = time.time()
            # Before reporting: the self-repair must not depend on the gateway being up.
            reboot_if_stuck(serial, sensor_id, problem, state, now,
                            lambda: recent_alert(serial, now))
            report(sensor_key, sensor_id, ok)
            print(f"{sensor_id} ({serial}): aea_ok={ok} problem={problem}")
        except Exception as error:
            failures += 1
            print(f"row {row[:2]}: report failed: {error!r}", file=sys.stderr)
    save_state(state)
    return 1 if failures else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))

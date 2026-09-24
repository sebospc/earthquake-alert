#!/usr/bin/env python3
"""Reports to the gateway, per sensor, whether AEA can still receive an alert (aea_ok), and
reboots a guest whose location Play Services can no longer use. After a relayed alert it also
saves the guest's log around it, to time what happens inside Play Services before the
notification.

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
# QA-90: a still receptor's AEA copy only renews on a >= 1 km move. Past 6 h, a receptor with
# GpsKeeper is moved 2 km and back, well before the 20 h reboot. 2 km, not just over 1: the
# fused location may mix in network fixes. It changes nothing against the 31 km M4.5 radius.
NUDGE_AFTER_S = 6 * 60 * 60
# No delivery seen this boot (state lost after the log rolled): past the boot's own delivery
# window, a nudge is the quickest way to a known-fresh AEA copy.
NUDGE_UNKNOWN_AFTER_UPTIME_S = 30 * 60
NUDGE_OFFSET_DEG = 2.0 / 111.195  # 2 km north
# AEA gets a move within ~5 min; three runs per leg before giving up.
NUDGE_LEG_S = 15 * 60
LISTENER_EVIDENCE = "files/notification-evidence.jsonl"
LOGCAT_DIR = os.path.expanduser("~/alert-logcat")
# Measured read-only on the EC2 guests: main and system are 2 MiB and hold the whole uptime
# (5.3 h), so a dump up to 30 min after the alert still finds its lines.
LOGCAT_BUFFERS = "main,system,events"
LOGCAT_BEFORE_S = 120
LOGCAT_AFTER_S = 60
# Dumped only once the alert is this old: the listener's POST and its retries (~50 s at
# most) must never share the guest's CPU with a logcat read.
LOGCAT_MIN_AGE_S = 60
LOGCAT_MAX_AGE_S = 30 * 60
MAX_LOGCAT_BYTES = 4 * 1024 * 1024
MAX_LOGCAT_DUMPS = 50

# GMS's event log line when it hands AEA a location (same pattern as monitor/verify.py).
# AEA asks with minUpdateDistance=1000 m, so a still receptor gets one at boot and after a
# move only: this, not the GPS provider, is the location AEA alerts with (QA-90).
AEA_DELIVERY = re.compile(r"(\d\d-\d\d \d\d:\d\d:\d\d)\.\d+: delivered locations\[\d+\] to [^\n]*\[earthquake_alerting\]")
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
    # A date without %N prints whole seconds or "1790268393.", off by up to a second.
    if not re.fullmatch(r"\d+\.\d+", (output or "").strip()):
        return None
    return float(output) - (before + after) / 2, after - before


def log_clock_offset(serial, sensor_id):
    offset = clock_offset(serial)
    if offset is None:
        print(f"CLOCK_OFFSET {sensor_id} ({serial}): unreadable")
    else:
        print(f"CLOCK_OFFSET {sensor_id} ({serial}): offset_s={offset[0]:.3f} rtt_s={offset[1]:.3f}")


def aea_location_age(serial, uptime_s):
    """(age_s, source): time since GMS last handed earthquake_alerting a location, both ends
    on the guest clock, so no clock offset applies. When the line has rolled out of the
    event log, or cannot be read, the uptime is the bound: pessimistic, so it errs loud."""
    output = lab.adb(serial, "shell",
                     "dumpsys activity service com.google.android.gms | grep 'delivered locations' "
                     "| grep earthquake_alerting | tail -n 1; date +%Y-%m-%dT%H:%M:%S", timeout=90)
    lines = (output or "").strip().splitlines()
    delivery = AEA_DELIVERY.search("\n".join(lines[:-1]))
    try:
        guest_now = datetime.fromisoformat(lines[-1].strip())
    except (IndexError, ValueError):
        guest_now = None
    if delivery is None or guest_now is None:
        return uptime_s, "uptime"
    last = datetime.strptime(f"{guest_now.year}-{delivery.group(1)}", "%Y-%m-%d %H:%M:%S")
    if last > guest_now:  # the log has no year: a December delivery read in January
        last = last.replace(year=guest_now.year - 1)
    return (guest_now - last).total_seconds(), "eventlog"


def check(serial, lat, lon, readings=None):
    """(aea_ok, problem). problem is "drift", "stale" or "missing" when a guest reboot is the
    remedy, else None. Anything unknown counts as not ok, and never as a reason to reboot,
    with one exception: an unreadable AEA age is bounded by the uptime, so past 20 h of
    uptime it is "stale" (the two-run rule still applies before a reboot).
    `readings`, if given, may carry aea_delivered_at (host epoch remembered from an earlier
    run) and gets aea_age_s, aea_age_source, when read from the log aea_delivered_at, and
    for a "not ok" with no problem, not_ok_reason: that one must not stay silent."""
    readings = {} if readings is None else readings
    health = lab.aea_health(serial)
    location = gms_location(serial)
    if not health or location is None:
        readings["not_ok_reason"] = "unreadable"
        return False, None
    readings["uptime_s"] = location["uptime_s"]
    if location.get("missing"):
        if location["uptime_s"] < BOOT_WINDOW_S:
            readings["not_ok_reason"] = "booting"
            return False, None
        return False, "missing"
    # A guest that booted without the geo fix keeps a wrong place: after a spot
    # interruption the EC2 kept a default in California. Only this check sees it.
    if lab.km_between(location["lat"], location["lon"], lat, lon) > MAX_DRIFT_KM:
        return False, "drift"
    if location["age_s"] > MAX_LOCATION_AGE_S:
        return False, "stale"
    # With GpsKeeper the GPS provider stays fresh while AEA's own copy ages (QA-90).
    aea_age_s, source = aea_location_age(serial, location["uptime_s"])
    now = time.time()
    # The event log rolls: a delivery seen by an earlier run (every 5 min, so none is
    # missed) still counts, if it is from this boot.
    remembered_at = readings.get("aea_delivered_at")
    if source == "eventlog":
        remembered_at = now - aea_age_s
    elif remembered_at is not None and now - remembered_at < min(aea_age_s, location["uptime_s"]):
        aea_age_s, source = now - remembered_at, "remembered"
    readings.update(aea_age_s=aea_age_s, aea_age_source=source)
    if source == "eventlog":
        readings["aea_delivered_at"] = remembered_at
    if aea_age_s > MAX_LOCATION_AGE_S:
        return False, "stale"
    if not health["registered"]:
        readings["not_ok_reason"] = "not_registered"
        return False, None
    # A delivery known for this boot, not health["deliveries"]: that counts event log lines,
    # which GpsKeeper's lines roll over, and it read 0 on a healthy quibdo for hours.
    if source == "uptime":
        # After a cold boot, until AEA is first handed a location. A nudge ends it too.
        readings["not_ok_reason"] = "no_delivery_this_boot"
        return False, None
    return True, None


def eew_posts(serial, now, max_age_s):
    """The listener's NOTIFICATION_POSTED records of eew_* channels captured in the last
    max_age_s. Unreadable reads as none."""
    tail = lab.adb(serial, "exec-out", "run-as", "com.earthquakes.relay",
                   "tail", "-n", "200", LISTENER_EVIDENCE, timeout=20)
    posts = []
    for line in (tail or "").splitlines():
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if (record.get("event_type") == "NOTIFICATION_POSTED"
                and str(record.get("channel_id") or "").startswith("eew_")
                and now - record.get("captured_at_ms", 0) / 1000 < max_age_s):
            posts.append(record)
    return posts


def has_gps_keeper(serial):
    services = lab.adb(serial, "shell", "dumpsys", "activity", "services", "com.earthquakes.relay", timeout=30)
    return "GpsKeeperService" in (services or "")


def geo_fix_target(entry, lat, lon):
    """Where this run's geo fix points: the site, except during the out leg of a nudge."""
    nudge = (entry or {}).get("nudge")
    if nudge and nudge["phase"] == "out":
        return lat + NUDGE_OFFSET_DEG, lon
    return lat, lon


def geo_fix(serial, lat, lon):
    lab.adb(serial, "emu", "geo", "fix", f"{lon:.6f}", f"{lat:.6f}", timeout=20)


def nudge_step(serial, sensor_id, lat, lon, aea_age_s, state, now, alert_in_progress, keeper,
               uptime_s=None, aea_age_source=None):
    """Renews AEA's location by moving the receptor 2 km and back (QA-90). A leg counts as
    confirmed when AEA got a location after it started (its age is shorter than the leg).
    The out leg ends after 15 min even unconfirmed; the way back is retried every run, and
    after 30 min it logs NUDGE_FAILED and leaves the 20 h reboot as the fallback.
    `keeper` says whether the guest runs GpsKeeper; without it no geo fix is taken now.
    A leg from before the current boot is dropped: the boot's own delivery at the site
    once confirmed a 2 km trip that never happened (24-sep 23:25)."""
    entry = state.setdefault(sensor_id, {"problem_runs": 0, "rebooted_at": 0})
    nudge = entry.get("nudge")
    if nudge is not None and uptime_s is not None and nudge["at"] < now - uptime_s:
        print(f"NUDGE_ABORTED {sensor_id} ({serial}): reboot")
        del entry["nudge"]
        nudge = None
    if nudge is None:
        unknown_this_boot = (aea_age_source == "uptime" and uptime_s is not None
                             and uptime_s > NUDGE_UNKNOWN_AFTER_UPTIME_S)
        if aea_age_s is None or (aea_age_s <= NUDGE_AFTER_S and not unknown_this_boot):
            return
        if alert_in_progress():
            print(f"NUDGE_SKIPPED {sensor_id} ({serial}): recent eew alert")
            return
        if not keeper():
            print(f"NUDGE_SKIPPED {sensor_id} ({serial}): no GpsKeeper, the 20 h reboot covers it")
            return
        # Recorded before the move, but the state file is only written at the end of the
        # run: a run that dies here leaves no nudge, and the next one fixes the site.
        entry["nudge"] = {"phase": "out", "at": now, "age_before_s": aea_age_s}
        geo_fix(serial, lat + NUDGE_OFFSET_DEG, lon)
        print(f"NUDGE_OUT {sensor_id} ({serial}): age_before_s={aea_age_s:.0f}")
        return
    # No geo fix changes while an alert may still be on its way out.
    if alert_in_progress():
        return
    elapsed = now - nudge["at"]
    delivered = aea_age_s is not None and aea_age_s < elapsed
    if nudge["phase"] == "out":
        if delivered or elapsed >= NUDGE_LEG_S:
            nudge.update(phase="back", at=now, out_ok=delivered)
            geo_fix(serial, lat, lon)
            print(f"NUDGE_BACK {sensor_id} ({serial}): out_ok={delivered}")
        return
    result = (f"out_ok={nudge['out_ok']} back_ok={delivered} age_before_s={nudge['age_before_s']:.0f} "
              f"age_after_s={aea_age_s if aea_age_s is None else round(aea_age_s)}")
    if delivered:
        print(f"NUDGE {sensor_id} ({serial}): {result}")
        del entry["nudge"]
    elif elapsed >= 2 * NUDGE_LEG_S:
        print(f"NUDGE_FAILED {sensor_id} ({serial}): {result}")
        del entry["nudge"]


def recent_alert(serial, now):
    """True if the listener captured an eew_* notification in the last 10 min: rebooting then
    could cut an alert still being relayed. Unreadable counts as no alert: a certain blind
    sensor weighs more than an unlikely overlap."""
    return bool(eew_posts(serial, now, RECENT_ALERT_S))


def within_window(line, until_s):
    """Lines past the window are dropped; lines without a timestamp ("--------- beginning
    of main") are kept."""
    try:
        return float(line.split(None, 1)[0]) <= until_s
    except (IndexError, ValueError):
        return True


def save_alert_logcat(serial, sensor_id, now):
    """Saves, once per alert, the guest log from 2 min before the notification was posted to
    1 min after, as ~/alert-logcat/<sensor>-<post_time_ms>.log. Times are the guest clock,
    same as post_time_ms; CLOCK_OFFSET converts them. A failed read is retried next run."""
    os.makedirs(LOGCAT_DIR, exist_ok=True)
    for record in eew_posts(serial, now, LOGCAT_MAX_AGE_S):
        post_time_ms = record.get("post_time_ms")
        if not isinstance(post_time_ms, int):
            continue
        if now - record.get("captured_at_ms", 0) / 1000 < LOGCAT_MIN_AGE_S:
            continue
        path = os.path.join(LOGCAT_DIR, f"{sensor_id}-{post_time_ms}.log")
        if os.path.exists(path):
            continue
        since_s = post_time_ms / 1000 - LOGCAT_BEFORE_S
        dump = lab.adb(serial, "logcat", "-d", "-v", "epoch", "-b", LOGCAT_BUFFERS,
                       "-t", f"{since_s:.3f}", timeout=60)
        if dump is None:
            print(f"LOGCAT_FAILED {sensor_id} ({serial}): post_time_ms={post_time_ms}")
            continue
        until_s = post_time_ms / 1000 + LOGCAT_AFTER_S
        text = "".join(line for line in dump.splitlines(keepends=True) if within_window(line, until_s))
        data = text.encode()
        truncated = len(data) > MAX_LOGCAT_BYTES
        # ponytail: a plain cut; ~3 min of log is far below 4 MB, this only stops a runaway.
        data = data[:MAX_LOGCAT_BYTES]
        header = (f"# sensor={sensor_id} serial={serial} post_time_ms={post_time_ms} "
                  f"notification_key={record.get('notification_key')} truncated={truncated}\n")
        with open(path + ".tmp", "wb") as handle:
            handle.write(header.encode() + data)
        os.replace(path + ".tmp", path)
        print(f"LOGCAT_SAVED {sensor_id} ({serial}): {path} bytes={len(data)}")
    dumps = sorted((os.path.join(LOGCAT_DIR, name) for name in os.listdir(LOGCAT_DIR)
                    if name.endswith(".log")), key=os.path.getmtime)
    for old in dumps[:-MAX_LOGCAT_DUMPS]:
        os.remove(old)


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
            lat, lon = float(lat), float(lon)
            # The listener's GpsKeeperService holds GPS open, so this fix reaches Play
            # Services within a minute. It is also how a sensor moved in the map takes its
            # new place, without a reboot, and how a nudge's way back is retried.
            geo_fix(serial, *geo_fix_target(state.get(sensor_id), lat, lon))
            entry = state.setdefault(sensor_id, {"problem_runs": 0, "rebooted_at": 0})
            readings = {"aea_delivered_at": entry.get("aea_delivered_at")}
            ok, problem = check(serial, lat, lon, readings=readings)
            if readings.get("aea_delivered_at") is not None:
                entry["aea_delivered_at"] = readings["aea_delivered_at"]
            if "aea_age_s" in readings:
                print(f"AEA_LOCATION_AGE {sensor_id} ({serial}): age_s={readings['aea_age_s']:.0f} "
                      f"source={readings['aea_age_source']}")
            now = time.time()
            # Before reporting: the self-repair must not depend on the gateway being up.
            reboot_if_stuck(serial, sensor_id, problem, state, now,
                            lambda: recent_alert(serial, now))
            report(sensor_key, sensor_id, ok)
            print(f"{sensor_id} ({serial}): aea_ok={ok} problem={problem}")
            if not ok and problem is None:
                print(f"AEA_NOT_OK {sensor_id} ({serial}): reason={readings.get('not_ok_reason', 'unknown')}")
            # Last: a hung guest's adb timeout must not delay the geo fix or the report.
            log_clock_offset(serial, sensor_id)
            nudge_step(serial, sensor_id, lat, lon, readings.get("aea_age_s"), state, now,
                       lambda: recent_alert(serial, now), lambda: has_gps_keeper(serial),
                       uptime_s=readings.get("uptime_s"), aea_age_source=readings.get("aea_age_source"))
            # Evidence only: a full disk here must not mark the run failed after the report.
            try:
                save_alert_logcat(serial, sensor_id, now)
            except Exception as error:
                print(f"LOGCAT_FAILED {sensor_id} ({serial}): {error!r}")
        except Exception as error:
            failures += 1
            print(f"row {row[:2]}: report failed: {error!r}", file=sys.stderr)
    save_state(state)
    return 1 if failures else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))

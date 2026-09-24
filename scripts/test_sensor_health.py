#!/usr/bin/env python3
"""Checks sensor-health.py's decisions without adb: when a sensor is ok, which location
problems call for a guest reboot, when the reboot happens, and that one bad map row does
not silence the others.

Run: python3 scripts/test_sensor_health.py
"""
import importlib.util, json, os, sys, tempfile, time

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPTS)  # sensor-health.py does `import lab`
spec = importlib.util.spec_from_file_location("sensor_health", os.path.join(SCRIPTS, "sensor-health.py"))
health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(health)
lab = health.lab
real_aea_location_age = health.aea_location_age

# Never the real adb: on the Mac these serials are the live fleet.
adb_calls = []
# Nor the real home: the dumps would pile up in ~/alert-logcat.
health.LOGCAT_DIR = os.path.join(tempfile.mkdtemp(), "alert-logcat")
lab.adb = lambda serial, *args, **kwargs: adb_calls.append((serial, args))

CHAPARRAL = (3.7236, -75.4836)
HOUR = 3600


# --- reading Play Services' location out of dumpsys --------------------------------------

assert health.duration_s("1d2h3m4s500ms") == 86400 + 7200 + 180 + 4.5
assert health.duration_s("7m14s") == 434


def gms_location_from(dump, uptime):
    lab.adb = lambda serial, *args, **kwargs: dump if "dumpsys" in args else uptime
    try:
        return health.gms_location("emulator-5554")
    finally:
        lab.adb = lambda serial, *args, **kwargs: adb_calls.append((serial, args))


GPS_LINE = "    last location=Location[gps 3.723600,-75.483600 hAcc=5.0 et=+2h0m0s alt=0.0]\n"
location = gms_location_from(GPS_LINE, "93600.00 90000.00\n")  # up 26 h, fix taken at 2 h
assert (location["lat"], location["lon"], location["age_s"]) == (3.7236, -75.4836, 24 * HOUR)
assert gms_location_from("    last location=null\n", "3000.0 1.0\n") == {"missing": True, "uptime_s": 3000.0}
assert gms_location_from("no location section\n", "3000.0 1.0\n") is None
assert gms_location_from(GPS_LINE, None) is None
print("PASS location reading and its age")


# --- check(): aea_ok and which problem calls for a reboot --------------------------------

def dumpsys(registered=True, deliveries=3):
    return {"registered": registered, "deliveries": deliveries, "last_delivery": None,
            "lat": None, "lon": None}


def check_with(location, reading=None, aea_age_h=1, aea_source="eventlog", readings=None):
    lab.aea_health = lambda serial: dumpsys() if reading is None else reading
    health.gms_location = lambda serial: location
    health.aea_location_age = lambda serial, uptime_s: (aea_age_h * HOUR, aea_source)
    return health.check("emulator-5554", *CHAPARRAL, readings=readings)


def at(lat, lon, age_h, uptime_h=30):
    return {"lat": lat, "lon": lon, "age_s": age_h * HOUR, "uptime_s": uptime_h * HOUR}


assert check_with(at(3.73, -75.49, 19)) == (True, None), "19 h is still fine"
assert check_with(at(3.73, -75.49, 21)) == (False, "stale"), "past 20 h Play Services stops alerting"
# The spot-interruption case: Play Services kept a place in California.
assert check_with(at(39.237, -123.150, 1)) == (False, "drift")
assert check_with({"missing": True, "uptime_s": 2 * HOUR}) == (False, "missing")
# While booting, aea-geofix.py is still feeding the first fix: not ok, but no reboot.
assert check_with({"missing": True, "uptime_s": 5 * 60}) == (False, None)
# Right place, but AEA has not been handed a location yet this boot: not ok, no reboot,
# and a reason, so it is not silent.
readings = {}
assert check_with(at(3.73, -75.49, 1), aea_age_h=2, aea_source="uptime", readings=readings) == (False, None)
assert readings["not_ok_reason"] == "no_delivery_this_boot"
# 24-sep 21:15-23:40, quibdo: GpsKeeper rolled GMS's event history, so the delivery lines were gone
# (0 in the log) while AEA had its location from a remembered delivery 2 h earlier. That is healthy.
rolled = {"registered": True, "deliveries": 0, "last_delivery": None}
readings = {"aea_delivered_at": time.time() - 2 * HOUR}
assert check_with(at(3.73, -75.49, 0.01, uptime_h=6), reading=rolled, aea_age_h=6, aea_source="uptime",
                  readings=readings) == (True, None), "a rolled event log made a healthy receptor uncovered"
assert readings["aea_age_source"] == "remembered"
readings = {}
assert check_with(at(3.73, -75.49, 1), dumpsys(registered=False), readings=readings) == (False, None)
assert readings["not_ok_reason"] == "not_registered"
# The 24-sep 21:15 incident: GpsKeeper's lines rolled the delivery lines out of the event
# log (deliveries=0) on a healthy quibdo. A delivery known for this boot is what counts.
assert check_with(at(3.73, -75.49, 1), dumpsys(deliveries=0)) == (True, None), "log roll read as not ok"
assert check_with(at(3.73, -75.49, 1), dumpsys(deliveries=0), aea_source="remembered") == (True, None)
readings = {}
assert check_with(None, readings=readings) == (False, None) and readings["not_ok_reason"] == "unreadable"
readings = {}
assert check_with({"missing": True, "uptime_s": 5 * 60}, readings=readings) == (False, None)
assert readings["not_ok_reason"] == "booting"
# Unknown is never ok, and never a reason to reboot.
assert check_with(None) == (False, None)
assert check_with(at(3.73, -75.49, 1), reading={}) == (False, None)
print("PASS aea_ok: 19 h ok, 21 h no, deriva, null, arranque")

# QA-90: GpsKeeper keeps the GPS provider fresh while AEA's own copy ages. That copy decides.
assert check_with(at(3.73, -75.49, 0.01), aea_age_h=19) == (True, None)
assert check_with(at(3.73, -75.49, 0.01), aea_age_h=21) == (False, "stale"), "AEA's 21 h copy passed"
assert check_with(at(3.73, -75.49, 0.01), aea_age_h=20.5) == (False, "stale")
readings = {}
lab.aea_health = lambda serial: dumpsys()
health.gms_location = lambda serial: at(3.73, -75.49, 0.01)
health.aea_location_age = lambda serial, uptime_s: (HOUR, "eventlog")
health.check("emulator-5554", *CHAPARRAL, readings=readings)
assert (readings["aea_age_s"], readings["aea_age_source"]) == (1 * HOUR, "eventlog")


def aea_age_from(output, uptime_s=30 * HOUR):
    lab.adb = lambda serial, *args, **kwargs: output
    try:
        return real_aea_location_age("emulator-5556", uptime_s)
    finally:
        lab.adb = lambda serial, *args, **kwargs: adb_calls.append((serial, args))


DELIVERY = ("09-24 18:11:03.214: delivered locations[1] to 10144/com.google.android.gms"
            "[earthquake_alerting]\n")
assert aea_age_from(DELIVERY + "2026-09-25T02:11:03\n") == (8 * HOUR, "eventlog")
# No year in the log: a 31-Dec delivery read on 1-Jan is 1 h old, not -1 year.
assert aea_age_from(DELIVERY.replace("09-24 18:11", "12-31 23:11") + "2027-01-01T00:11:03\n") == (HOUR, "eventlog")
# Rolled out of the event log, or unreadable: the uptime bounds it, pessimistic.
assert aea_age_from("2026-09-25T02:11:03\n") == (30 * HOUR, "uptime")
assert aea_age_from(None) == (30 * HOUR, "uptime")
assert aea_age_from(DELIVERY + "not a date\n") == (30 * HOUR, "uptime")
assert aea_age_from(DELIVERY.replace("earthquake_alerting", "fused_location") + "2026-09-25T02:11:03\n") == (30 * HOUR, "uptime")
print("PASS QA-90 AEA location age drives aea_ok: event log, year wrap, uptime fallback")


# The delivery line rolls out of the event log (~160 lines/h with GpsKeeper): a delivery an
# earlier run saw still counts, but only from this boot.
def check_remembering(aea_age, remembered_age_h, uptime_h=30):
    lab.aea_health = lambda serial: dumpsys()
    health.gms_location = lambda serial: at(3.73, -75.49, 0.01, uptime_h=uptime_h)
    health.aea_location_age = lambda serial, uptime_s: aea_age
    readings = {"aea_delivered_at": None if remembered_age_h is None else time.time() - remembered_age_h * HOUR}
    return health.check("emulator-5554", *CHAPARRAL, readings=readings), readings


(result, readings) = check_remembering((30 * HOUR, "uptime"), 2)
assert result == (True, None) and readings["aea_age_source"] == "remembered", readings
assert abs(readings["aea_age_s"] - 2 * HOUR) < 5
(result, readings) = check_remembering((30 * HOUR, "uptime"), 31)
assert result == (False, "stale"), "a delivery from before the reboot was trusted"
(result, readings) = check_remembering((30 * HOUR, "uptime"), None)
assert result == (False, "stale") and readings["aea_age_source"] == "uptime"
# Read from the log: that is what gets remembered, and a newer log line wins.
(result, readings) = check_remembering((HOUR, "eventlog"), 3)
assert readings["aea_age_s"] == HOUR and abs(readings["aea_delivered_at"] - (time.time() - HOUR)) < 5
# A guest reboot: the uptime bound is younger than the remembered delivery, which is dropped.
(result, readings) = check_remembering((HOUR / 2, "uptime"), 2, uptime_h=0.5)
assert readings["aea_age_source"] == "uptime" and readings["aea_age_s"] == HOUR / 2
print("PASS QA-90 last delivery remembered across runs when the event log rolls, reset by a reboot")


# --- reboot_if_stuck(): when the guest is rebooted ---------------------------------------

T0 = 1_790_194_179  # wall clock, as time.time() gives it; "never rebooted" is stored as 0


def reboots():
    return [call for call in adb_calls if call[1] == ("reboot",)]


state = {}


def run(problem, offset_s, sensor="chaparral", serial="emulator-5554", alert=False):
    health.reboot_if_stuck(serial, sensor, problem, state, T0 + offset_s, lambda: alert)
    return len(reboots())


assert run("drift", 0) == 0, "one bad read rebooted the guest"
assert run(None, 300) == 0
assert run("drift", 600) == 0, "a clean run in between must reset the count"
assert run("drift", 900) == 1
assert reboots()[-1] == ("emulator-5554", ("reboot",))
assert run("drift", 1200) == 1 and run("drift", 1500) == 1, "rebooted twice within the hour"
assert run("drift", 900 + HOUR - 1) == 1
assert run("drift", 900 + HOUR) == 2
print("PASS reboot only after 2 failing runs, at most 1 per hour")

adb_calls.clear()
state = {}
assert run("stale", 0) == 0 and run("stale", 300) == 1, "a 21 h old location is not rebooted"
adb_calls.clear()
state = {}
assert run("missing", 0) == 0 and run("missing", 300) == 1, "a null location is not rebooted"
print("PASS 21 h and null trigger the reboot")

# Two receptors on one host, both stale: only one reboots; the other waits 30 min.
adb_calls.clear()
state = {}
for offset in (0, 300):
    run("stale", offset, "chaparral", "emulator-5554")
    run("stale", offset, "quibdo", "emulator-5556")
assert [serial for serial, _ in reboots()] == ["emulator-5554"], "two guests rebooted together"
run("stale", 300 + health.MIN_HOST_REBOOT_SPACING_S - 1, "quibdo", "emulator-5556")
assert len(reboots()) == 1
run("stale", 300 + health.MIN_HOST_REBOOT_SPACING_S, "quibdo", "emulator-5556")
assert [serial for serial, _ in reboots()] == ["emulator-5554", "emulator-5556"]
print("PASS one reboot at a time per host, 30 min between receptors")

# An eew notification in the last 10 min: the reboot waits.
adb_calls.clear()
state = {}
run("stale", 0, alert=True)
assert run("stale", 300, alert=True) == 0, "rebooted in the middle of an alert"
assert run("stale", 600, alert=False) == 1
print("PASS no reboot after a recent eew alert")


def recent_alert_with(lines, now):
    lab.adb = lambda serial, *args, **kwargs: "\n".join(json.dumps(line) for line in lines)
    try:
        return health.recent_alert("emulator-5554", now)
    finally:
        lab.adb = lambda serial, *args, **kwargs: adb_calls.append((serial, args))


now = time.time()
posted = lambda channel, age_s: {"event_type": "NOTIFICATION_POSTED", "channel_id": channel,
                                 "captured_at_ms": (now - age_s) * 1000}
assert recent_alert_with([posted("eew_alert_v2", 120)], now)
assert recent_alert_with([posted("eew_update", 540)], now)
assert not recent_alert_with([posted("eew_alert_v2", 660)], now)
assert not recent_alert_with([posted("finder-configuration", 60)], now)
assert not recent_alert_with([], now)
print("PASS recent eew alert from the listener evidence")


# --- clock_offset(): guest clock vs host, logged every run (QA-86) ------------------------

def clock_offset_with(answer):
    lab.adb = lambda serial, *args, **kwargs: answer() if "date" in args else None
    try:
        return health.clock_offset("emulator-5554")
    finally:
        lab.adb = lambda serial, *args, **kwargs: adb_calls.append((serial, args))


offset_s, round_trip_s = clock_offset_with(lambda: f"{time.time() - 1.70:.6f}\n")
assert abs(offset_s + 1.70) < 0.05, offset_s
assert 0 <= round_trip_s < 0.05
assert clock_offset_with(lambda: None) is None
assert clock_offset_with(lambda: "1790268393.%N\n") is None, "a date without %N is not a reading"
assert clock_offset_with(lambda: "1790268393.\n") is None, "an empty %N is whole seconds"
assert clock_offset_with(lambda: "1790268393\n") is None

import contextlib, io
printed = io.StringIO()
lab.adb = lambda serial, *args, **kwargs: f"{time.time() + 0.31:.6f}"
with contextlib.redirect_stdout(printed):
    health.log_clock_offset("emulator-5556", "quibdo")
lab.adb = lambda serial, *args, **kwargs: adb_calls.append((serial, args))
assert printed.getvalue().startswith("CLOCK_OFFSET quibdo (emulator-5556): offset_s=0.3"), printed.getvalue()
print("PASS emulator clock offset")


# --- save_alert_logcat(): the guest log around each relayed alert ------------------------

POST_S = 1_790_268_411.373  # guest clock, like post_time_ms


def logcat_line(offset_s, text):
    return f"{POST_S + offset_s:.3f}  1234  1300 I EarthquakeAlert: {text}\n"


def save_logcat_with(posts, dump, now):
    """posts: [(post offset from POST_S, captured age in s)]. Returns the logcat reads."""
    evidence = "\n".join(json.dumps({
        "event_type": "NOTIFICATION_POSTED", "channel_id": "eew_alert_v2",
        "post_time_ms": int((POST_S + offset) * 1000), "captured_at_ms": (now - age) * 1000,
        "notification_key": "0|com.google.android.gms|1|eew"}) for offset, age in posts)
    reads = []

    def fake_adb(serial, *args, **kwargs):
        if "run-as" in args:
            return evidence
        if "-t" in args:
            reads.append(args)
            return dump
        return ""
    lab.adb = fake_adb
    try:
        health.save_alert_logcat("emulator-5554", "chaparral", now)
    finally:
        lab.adb = lambda serial, *args, **kwargs: adb_calls.append((serial, args))
    return reads


def saved(offset=0):
    path = os.path.join(health.LOGCAT_DIR, f"chaparral-{int((POST_S + offset) * 1000)}.log")
    return open(path).read() if os.path.exists(path) else None


dump = ("--------- beginning of main\n" + logcat_line(-119, "fetching alert")
        + logcat_line(-2.5, "alert received") + logcat_line(0, "notification posted")
        + logcat_line(59, "still showing") + logcat_line(61, "past the window"))
now = time.time()
assert save_logcat_with([(0, 30)], dump, now) == [], "logcat read while the POST may be in flight"
assert saved() is None
reads = save_logcat_with([(0, 90)], dump, now)
assert len(reads) == 1 and reads[0][reads[0].index("-t") + 1] == f"{POST_S - 120:.3f}"
assert "-v" in reads[0] and "epoch" in reads[0] and "main,system,events" in reads[0]
text = saved()
assert text.startswith("# sensor=chaparral serial=emulator-5554 post_time_ms=")
assert "alert received" in text and "still showing" in text and "beginning of main" in text
assert "past the window" not in text
assert save_logcat_with([(0, 120)], dump, now) == [], "the same alert dumped twice"
assert save_logcat_with([(0, 31 * 60)], dump, now) == [], "older than the buffer reaches"
# Without an integer post_time_ms there is no window and no file name: skipped, not crashed.
logcat_reads = []
for bad_post_time in (None, "1790268411999", 1790268411.999):
    def fake_adb(serial, *args, **kwargs):
        if "run-as" in args:
            return json.dumps({"event_type": "NOTIFICATION_POSTED", "channel_id": "eew_alert_v2",
                               "post_time_ms": bad_post_time, "captured_at_ms": (now - 90) * 1000})
        logcat_reads.append(args)
        return dump
    lab.adb = fake_adb
    health.save_alert_logcat("emulator-5554", "chaparral", now)
lab.adb = lambda serial, *args, **kwargs: adb_calls.append((serial, args))
assert logcat_reads == [], logcat_reads
print("PASS alert logcat: -2 to +1 min window, once, never with the POST in flight")

# A failed read leaves no file, so the next run tries again.
assert save_logcat_with([(5, 90)], None, now) and saved(5) is None
assert save_logcat_with([(5, 90)], dump, now) and saved(5) is not None

# Bounded: one dump by size, the folder by count.
health.MAX_LOGCAT_BYTES = 1000
save_logcat_with([(7, 90)], logcat_line(0, "x" * 5000), now)
assert "truncated=True" in saved(7) and len(saved(7)) < 1200
health.MAX_LOGCAT_BYTES = 4 * 1024 * 1024
for name in range(60):
    path = os.path.join(health.LOGCAT_DIR, f"old-{name}.log")
    open(path, "w").close()
    os.utime(path, (1_000_000 + name, 1_000_000 + name))
save_logcat_with([], dump, now)
kept = os.listdir(health.LOGCAT_DIR)
assert len(kept) == health.MAX_LOGCAT_DUMPS and "old-0.log" not in kept and saved() is not None
print("PASS alert logcat bounded: 4 MB per dump, 50 dumps")


# --- nudge_step(): QA-90, renew AEA's copy by a 2 km move and back ------------------------

QUIBDO = (5.6947, -76.6611)
MINUTE = 60


def geo_fixes():
    return [(float(args[4]), float(args[3])) for _, args in adb_calls if args[:3] == ("emu", "geo", "fix")]


def nudge(state, at_s, aea_age_s, alert=False, keeper=True, uptime_s=None, source="eventlog"):
    health.nudge_step("emulator-5556", "quibdo", *QUIBDO, aea_age_s, state, T0 + at_s,
                      lambda: alert, lambda: keeper, uptime_s=uptime_s, aea_age_source=source)
    return state.get("quibdo", {}).get("nudge")


def is_site(fix):
    return abs(fix[0] - QUIBDO[0]) < 1e-6 and abs(fix[1] - QUIBDO[1]) < 1e-6


def km_from_site(fix):
    return lab.km_between(fix[0], fix[1], *QUIBDO)


adb_calls.clear()
state = {}
assert nudge(state, 0, 5 * HOUR) is None and geo_fixes() == [], "nudged a 5 h copy"
assert nudge(state, 0, 7 * HOUR, alert=True) is None and geo_fixes() == [], "nudged during an alert"
assert nudge(state, 0, 7 * HOUR, keeper=False) is None and geo_fixes() == [], "nudged without GpsKeeper"
assert nudge(state, 0, None) is None, "nudged with no AEA reading"

# The whole trip: out, AEA gets it, back, AEA gets it. The age may be the uptime bound
# (source=uptime, as on quibdo 24-sep): the nudge is what fixes that, so it must fire.
import contextlib, io
printed = io.StringIO()
with contextlib.redirect_stdout(printed):
    assert nudge(state, 0, 7 * HOUR)["phase"] == "out"
assert printed.getvalue().startswith("NUDGE_OUT quibdo (emulator-5556): age_before_s=25200"), printed.getvalue()
assert len(geo_fixes()) == 1 and 1.9 < km_from_site(geo_fixes()[0]) < 2.1
target = health.geo_fix_target(state["quibdo"], *QUIBDO)
assert 1.9 < km_from_site(target) < 2.1, "the next run's geo fix would undo the out leg"
assert nudge(state, 5 * MINUTE, 7 * HOUR + 5 * MINUTE)["phase"] == "out", "no delivery yet"
assert nudge(state, 10 * MINUTE, 2 * MINUTE)["out_ok"] is True
assert is_site(geo_fixes()[-1]) and is_site(health.geo_fix_target(state["quibdo"], *QUIBDO))
import contextlib, io
printed = io.StringIO()
with contextlib.redirect_stdout(printed):
    assert nudge(state, 15 * MINUTE, 1 * MINUTE) is None
assert printed.getvalue().startswith("NUDGE quibdo (emulator-5556): out_ok=True back_ok=True age_before_s=25200"), printed.getvalue()
assert is_site(health.geo_fix_target(state["quibdo"], *QUIBDO))

# AEA never answers: the out leg ends at 15 min anyway, the way back fails loud at 30.
adb_calls.clear()
state = {}
nudge(state, 0, 7 * HOUR)
assert nudge(state, 14 * MINUTE, 7 * HOUR + 14 * MINUTE)["phase"] == "out"
assert nudge(state, 15 * MINUTE, 7 * HOUR + 15 * MINUTE)["phase"] == "back", "left off-site past 15 min"
assert is_site(geo_fixes()[-1])
assert nudge(state, 44 * MINUTE, 7 * HOUR + 44 * MINUTE)["phase"] == "back"
printed = io.StringIO()
with contextlib.redirect_stdout(printed):
    assert nudge(state, 45 * MINUTE, 7 * HOUR + 45 * MINUTE) is None
assert printed.getvalue().startswith("NUDGE_FAILED quibdo (emulator-5556): out_ok=False back_ok=False"), printed.getvalue()
assert is_site(health.geo_fix_target(state.get("quibdo"), *QUIBDO))

# 24-sep 23:25: a reboot mid-nudge. The boot's own delivery, at the site, must not confirm
# a leg that started before it: the leg is dropped, loud, and nothing counts as ok.
adb_calls.clear()
state = {}
nudge(state, 0, 7 * HOUR, uptime_s=8 * HOUR)
assert nudge(state, 5 * MINUTE, 7 * HOUR + 5 * MINUTE, uptime_s=8 * HOUR + 5 * MINUTE)["phase"] == "out"
printed = io.StringIO()
with contextlib.redirect_stdout(printed):
    assert nudge(state, 10 * MINUTE, 16, uptime_s=2.4 * MINUTE) is None
assert printed.getvalue() == "NUDGE_ABORTED quibdo (emulator-5556): reboot\n", printed.getvalue()
assert is_site(health.geo_fix_target(state.get("quibdo"), *QUIBDO))
# Same for a back leg: the boot delivery does not make it back_ok.
state = {}
nudge(state, 0, 7 * HOUR, uptime_s=8 * HOUR)
nudge(state, 10 * MINUTE, 2 * MINUTE, uptime_s=8 * HOUR + 10 * MINUTE)
assert state["quibdo"]["nudge"]["phase"] == "back"
printed = io.StringIO()
with contextlib.redirect_stdout(printed):
    nudge(state, 20 * MINUTE, 16, uptime_s=3 * MINUTE)
assert "NUDGE_ABORTED" in printed.getvalue() and "back_ok=True" not in printed.getvalue()

# No delivery known this boot (state lost after the log rolled): nudge from 30 min of
# uptime instead of waiting for 6 h, but only on the uptime bound, and only with GpsKeeper.
state = {}
assert nudge(state, 0, 20 * MINUTE, uptime_s=20 * MINUTE, source="uptime") is None, "inside the boot window"
assert nudge(state, 0, 40 * MINUTE, uptime_s=40 * MINUTE, source="eventlog") is None
assert nudge(state, 0, 40 * MINUTE, uptime_s=40 * MINUTE, source="uptime", keeper=False) is None
assert nudge(state, 0, 40 * MINUTE, uptime_s=40 * MINUTE, source="uptime")["phase"] == "out"

# An alert mid-nudge: the legs hold, no geo fix change until it is 10 min old.
adb_calls.clear()
state = {}
nudge(state, 0, 7 * HOUR)
assert nudge(state, 20 * MINUTE, 7 * HOUR + 20 * MINUTE, alert=True)["phase"] == "out"
assert len(geo_fixes()) == 1, "moved during an alert"
assert nudge(state, 25 * MINUTE, 7 * HOUR + 25 * MINUTE)["phase"] == "back"
print("PASS QA-90 nudge: 2 km out and back, never during an alert or without GpsKeeper, never left off-site")


# --- main(): rows, the lock, and reporting ------------------------------------------------

reported = []
health.restart_foreign_adb_server = lambda serials: None
health.recent_alert = lambda serial, now: False
health.check = lambda serial, lat, lon, readings=None: (True, None)
health.report = lambda key, sensor_id, ok: reported.append((key, sensor_id, ok))
# The logcat capture must stay wired into every good row, after the report.
logcat_saved, real_save_alert_logcat = [], health.save_alert_logcat
health.save_alert_logcat = lambda serial, sensor_id, now: logcat_saved.append((sensor_id, list(reported)))
with tempfile.TemporaryDirectory() as directory:
    health.STATE_FILE = os.path.join(directory, "state.json")
    health.LOCK_FILE = os.path.join(directory, "sensor-health.lock")
    sensor_map = os.path.join(directory, "sensors.map")
    with open(sensor_map, "w") as handle:
        handle.write("emulator-5554 chaparral\n"
                     "emulator-5556 quibdo 5.6947 -76.6611 quibdo-key\n")
    assert health.main(sensor_map) == 1, "a broken row must still show as a failed run"
    assert reported == [("quibdo-key", "quibdo", True)]
    assert logcat_saved == [("quibdo", [("quibdo-key", "quibdo", True)])], logcat_saved
    assert health.main(os.path.join(directory, "missing.map")) == 0
health.save_alert_logcat = real_save_alert_logcat
print("PASS one broken row does not silence the others")

# QA-90 wiring: the nudge runs for every good row with that run's AEA age, and during an out leg
# the geo fix at the top of the row keeps the receptor out instead of silently pulling it back.
nudged, real_nudge_step, real_check = [], health.nudge_step, health.check
health.nudge_step = lambda serial, sensor_id, lat, lon, aea_age_s, state, now, alert, keeper, **boot: \
    nudged.append((sensor_id, aea_age_s, boot))
def check_with_age(serial, lat, lon, readings=None):
    readings.update(aea_age_s=7 * 3600.0, aea_age_source="eventlog", uptime_s=9 * 3600.0)
    return True, None
health.check = check_with_age
with tempfile.TemporaryDirectory() as directory:
    health.STATE_FILE = os.path.join(directory, "state.json")
    health.LOCK_FILE = os.path.join(directory, "sensor-health.lock")
    with open(health.STATE_FILE, "w") as handle:
        json.dump({"quibdo": {"problem_runs": 0, "rebooted_at": 0,
                              "nudge": {"phase": "out", "at": time.time(), "age_before_s": 7 * 3600}}}, handle)
    sensor_map = os.path.join(directory, "sensors.map")
    with open(sensor_map, "w") as handle:
        handle.write("emulator-5556 quibdo 5.6947 -76.6611 quibdo-key\n")
    adb_calls.clear()
    health.main(sensor_map)
    geo = [args for serial, args in adb_calls if args[:3] == ("emu", "geo", "fix")]
    assert geo and abs(float(geo[0][4]) - (5.6947 + health.NUDGE_OFFSET_DEG)) < 1e-5, geo
    # The uptime has to reach it: without it a pre-reboot leg would be confirmed.
    assert nudged == [("quibdo", 7 * 3600.0, {"uptime_s": 9 * 3600.0, "aea_age_source": "eventlog"})], nudged

# "not ok" with no problem is never silent: the reason reaches the journal.
def check_not_ok(serial, lat, lon, readings=None):
    readings.update(not_ok_reason="no_delivery_this_boot")
    return False, None
health.check = check_not_ok
with tempfile.TemporaryDirectory() as directory:
    health.STATE_FILE = os.path.join(directory, "state.json")
    health.LOCK_FILE = os.path.join(directory, "sensor-health.lock")
    sensor_map = os.path.join(directory, "sensors.map")
    with open(sensor_map, "w") as handle:
        handle.write("emulator-5556 quibdo 5.6947 -76.6611 quibdo-key\n")
    printed = io.StringIO()
    with contextlib.redirect_stdout(printed):
        health.main(sensor_map)
    assert "AEA_NOT_OK quibdo (emulator-5556): reason=no_delivery_this_boot" in printed.getvalue(), printed.getvalue()

# The delivery a run read from the log is saved, and handed to the next run's check().
handed = []
def check_remembering_run(serial, lat, lon, readings=None):
    handed.append(readings.get("aea_delivered_at"))
    if len(handed) == 1:
        readings.update(aea_age_s=3600.0, aea_age_source="eventlog", aea_delivered_at=1_790_000_000.0)
    return True, None
health.check = check_remembering_run
with tempfile.TemporaryDirectory() as directory:
    health.STATE_FILE = os.path.join(directory, "state.json")
    health.LOCK_FILE = os.path.join(directory, "sensor-health.lock")
    sensor_map = os.path.join(directory, "sensors.map")
    with open(sensor_map, "w") as handle:
        handle.write("emulator-5556 quibdo 5.6947 -76.6611 quibdo-key\n")
    health.main(sensor_map)
    health.main(sensor_map)
    assert handed == [None, 1_790_000_000.0], handed
health.nudge_step, health.check = real_nudge_step, real_check
print("PASS nudge wired into every row, out leg kept by the per-run geo fix")

# QA-54: the gateway is down, so every report fails, and the guest still gets rebooted.
adb_calls.clear()
health.check = lambda serial, lat, lon, readings=None: (False, "stale")


def gateway_down(key, sensor_id, ok):
    raise OSError("connection refused")


health.report = gateway_down
with tempfile.TemporaryDirectory() as directory:
    health.STATE_FILE = os.path.join(directory, "state.json")
    health.LOCK_FILE = os.path.join(directory, "sensor-health.lock")
    sensor_map = os.path.join(directory, "sensors.map")
    with open(sensor_map, "w") as handle:
        handle.write("emulator-5554 chaparral 3.7236 -75.4836 chaparral-key\n")
    health.main(sensor_map)
    health.main(sensor_map)
    assert reboots() == [("emulator-5554", ("reboot",))], "self-repair waited for the gateway"

    # A second run while one holds the lock does nothing.
    import fcntl
    with open(health.LOCK_FILE, "w") as held:
        fcntl.flock(held, fcntl.LOCK_EX)
        adb_calls.clear()
        assert health.main(sensor_map) == 0 and adb_calls == []
print("PASS the reboot does not depend on the gateway, and the lock stops overlapping runs")

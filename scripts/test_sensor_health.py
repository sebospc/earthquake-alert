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

# Never the real adb: on the Mac these serials are the live fleet.
adb_calls = []
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


def check_with(location, reading=None):
    lab.aea_health = lambda serial: dumpsys() if reading is None else reading
    health.gms_location = lambda serial: location
    return health.check("emulator-5554", *CHAPARRAL)


def at(lat, lon, age_h, uptime_h=30):
    return {"lat": lat, "lon": lon, "age_s": age_h * HOUR, "uptime_s": uptime_h * HOUR}


assert check_with(at(3.73, -75.49, 19)) == (True, None), "19 h is still fine"
assert check_with(at(3.73, -75.49, 21)) == (False, "stale"), "past 20 h Play Services stops alerting"
# The spot-interruption case: Play Services kept a place in California.
assert check_with(at(39.237, -123.150, 1)) == (False, "drift")
assert check_with({"missing": True, "uptime_s": 2 * HOUR}) == (False, "missing")
# While booting, aea-geofix.py is still feeding the first fix: not ok, but no reboot.
assert check_with({"missing": True, "uptime_s": 5 * 60}) == (False, None)
# Right place, but AEA has not been handed a location yet (cold boot): not ok, no reboot.
assert check_with(at(3.73, -75.49, 1), dumpsys(deliveries=0)) == (False, None)
assert check_with(at(3.73, -75.49, 1), dumpsys(registered=False)) == (False, None)
# Unknown is never ok, and never a reason to reboot.
assert check_with(None) == (False, None)
assert check_with(at(3.73, -75.49, 1), reading={}) == (False, None)
print("PASS aea_ok: 19 h ok, 21 h no, deriva, null, arranque")


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
print("PASS 21 h y null disparan el reboot")

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
print("PASS alerta eew reciente segun la evidencia del listener")


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

import contextlib, io
printed = io.StringIO()
lab.adb = lambda serial, *args, **kwargs: f"{time.time() + 0.31:.6f}"
with contextlib.redirect_stdout(printed):
    health.log_clock_offset("emulator-5556", "quibdo")
lab.adb = lambda serial, *args, **kwargs: adb_calls.append((serial, args))
assert printed.getvalue().startswith("CLOCK_OFFSET quibdo (emulator-5556): offset_s=0.3"), printed.getvalue()
print("PASS desfase del reloj del emulador")


# --- main(): rows, the lock, and reporting ------------------------------------------------

reported = []
health.restart_foreign_adb_server = lambda serials: None
health.recent_alert = lambda serial, now: False
health.check = lambda serial, lat, lon: (True, None)
health.report = lambda key, sensor_id, ok: reported.append((key, sensor_id, ok))
with tempfile.TemporaryDirectory() as directory:
    health.STATE_FILE = os.path.join(directory, "state.json")
    health.LOCK_FILE = os.path.join(directory, "sensor-health.lock")
    sensor_map = os.path.join(directory, "sensors.map")
    with open(sensor_map, "w") as handle:
        handle.write("emulator-5554 chaparral\n"
                     "emulator-5556 quibdo 5.6947 -76.6611 quibdo-key\n")
    assert health.main(sensor_map) == 1, "a broken row must still show as a failed run"
    assert reported == [("quibdo-key", "quibdo", True)]
    assert health.main(os.path.join(directory, "missing.map")) == 0
print("PASS one broken row does not silence the others")

# QA-54: the gateway is down, so every report fails, and the guest still gets rebooted.
adb_calls.clear()
health.check = lambda serial, lat, lon: (False, "stale")


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
print("PASS el reboot no depende del gateway, y el lock evita corridas simultaneas")

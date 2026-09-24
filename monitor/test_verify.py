#!/usr/bin/env python3
"""Fails if the certifier would misclassify a real quake. Fixtures are real events.

Run: python3 monitor/test_verify.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verify  # noqa: E402

DAY = 86400
SINCE = 1790035200  # 2026-09-22 00:00 UTC, when the Mac fleet and AWS sensors came up
NOW = 1790300000
CHAPARRAL = {"id": "chaparral", "lat": 3.7236, "lon": -75.4836, "since": SINCE}
AWS = {**CHAPARRAL, "kind": "aws"}
MAC = {**CHAPARRAL, "kind": "mac"}


def covered_everywhere(kind, receiver, t):
    return True


def sgc(feature_id, utc, mag, lon, lat):
    return {"type": "Feature", "id": feature_id, "geometry": {"coordinates": [lon, lat, 10.0]},
            "properties": {"agency": "SGC", "type": "earthquake", "utcTime": utc, "mag": mag,
                           "place": "Chaparral - Tolima, Colombia"}}


# Real SGC records of 23/24-sep. Neither is in USGS.
SGC_FEED = {"features": [
    sgc("SGC2026stzmyx", "2026-09-23 20:09:40", 4.5, -75.65883333333333, 3.8375),
    sgc("SGC2026sujuuj", "2026-09-24 01:19:40", 3.6, -75.63182720908954, 3.858325270227576),
    {**sgc("OTHER", "2026-09-24 01:19:40", 5.0, -75.6, 3.8), "properties": {
        **sgc("OTHER", "2026-09-24 01:19:40", 5.0, -75.6, 3.8)["properties"], "agency": "GFZ"}},
]}
events = verify.merge_catalogs(verify.sgc_events(SGC_FEED))
assert [e["id"] for e in events] == ["SGC2026stzmyx", "SGC2026sujuuj"], "non-SGC agency kept"
try:
    verify.sgc_events({"error": {"statusCode": 503}})
    raise AssertionError("an SGC error read as 'no quakes'")
except ValueError:
    pass

# The two real Chaparral captures: TIME_OCCURRED_EXTRA 1790194179 and 1790212783.
captures = [{"receiver": "chaparral", "kind": "aws", "origin": 1790194179, "captured": 1790194196},
            {"receiver": "chaparral", "kind": "aws", "origin": 1790212783, "captured": 1790212800}]
findings, unexplained = verify.classify(events, captures, [AWS], covered_everywhere, NOW)
by_event = {f["event"]: f for f in findings}
assert by_event["SGC2026stzmyx"]["verdict"] == "HIT", by_event
assert by_event["SGC2026sujuuj"]["verdict"] == "HIT", "M3.6 capture matched by time, not by magnitude"
assert "below the threshold" in by_event["SGC2026sujuuj"]["cause"]
assert unexplained == []
print("PASS Chaparral 23/24-sep: HIT, including the SGC M3.6")

# us6000tjl2, M7.4 San José del Palmar, 10-ago: 596 km radius, zero captures. The fleet did
# not exist yet, so it is not a MISS (lab.py once called it FALSO NEGATIVO).
m74 = verify.usgs_events({"features": [{"id": "us6000tjl2", "properties": {
    "time": 1786365268009, "mag": 7.4, "place": "2 km SE of San José del Palmar, Colombia"},
    "geometry": {"coordinates": [-76.2182, 4.8836, 108.174]}}]})
findings, _ = verify.classify(verify.merge_catalogs(m74), [], [AWS], covered_everywhere, NOW)
assert [f["verdict"] for f in findings] == ["N/A"], findings
assert not any(verify.fails(f) for f in findings)
print("PASS M7.4 10-aug: N/A (PREDATES_DEVICE), no MISS")

# A synthetic M5.0 on top of Chaparral with no capture, under each explanation.
quake = verify.merge_catalogs([{"id": "synthetic", "source": "sgc", "time": 1790250000,
                                "lat": 3.75, "lon": -75.5, "mag": 5.0, "place": "x"}])


def miss(receivers, captures=(), covered=covered_everywhere, felt=lambda e, r: None):
    findings, _ = verify.classify(quake, list(captures), receivers, covered, NOW, felt)
    return next(f for f in findings if f["kind"] == "aws")


down = miss([AWS], covered=lambda kind, r, t: kind != "aws")
assert (down["verdict"], down["cause"]) == ("MISS", verify.DOWN) and verify.fails(down)
mac_got_it = miss([AWS, MAC], [{"receiver": "chaparral", "kind": "mac", "origin": 1790250002, "captured": 1790250020}])
assert mac_got_it["cause"] == verify.CONTROL_CAPTURED and verify.fails(mac_got_it)
google_silent = miss([AWS, MAC])
assert google_silent["cause"] == verify.GOOGLE_SILENT and not verify.fails(google_silent)
# Control down: its silence proves nothing, so the cause falls through and says so.
mac_down = miss([AWS, MAC], covered=lambda kind, r, t: kind == "aws")
assert mac_down["cause"] == verify.UNEXPLAINED and verify.fails(mac_down), mac_down
no_mac = miss([AWS])
assert no_mac["cause"] == f"{verify.UNEXPLAINED}; {verify.NO_CONTROL}"
not_felt = miss([AWS], felt=lambda e, r: 2.1)
assert not_felt["cause"].startswith(verify.NOT_FELT) and not verify.fails(not_felt)
print("PASS MISS causes in the agreed order")

near_threshold = verify.merge_catalogs([{**quake[0], "mag": 4.6, "ids": None}])
findings, _ = verify.classify(near_threshold, [], [AWS], covered_everywhere, NOW)
assert findings[0]["cause"].startswith(verify.NEAR_THRESHOLD) and not verify.fails(findings[0])

stray = {"receiver": "chaparral", "kind": "aws", "origin": 1790000000 + 5 * DAY, "captured": 1790000000 + 5 * DAY}
_, unexplained = verify.classify([], [stray], [AWS], covered_everywhere, stray["captured"] + 3600)
assert unexplained[0]["verdict"] == "PENDING", "a catalog gets 24 h before a capture is FALSE"
_, unexplained = verify.classify([], [stray], [AWS], covered_everywhere, stray["captured"] + DAY)
assert unexplained[0]["verdict"] == "FALSE"
print("PASS FALSE only after 24 h")

clean = dict(findings=[], unexplained=[], coverage={"chaparral": {"uncovered_min": 3, "longest_gap_min": 3}},
             probes={"sent": 24, "received": 24, "latencies_s": [0.8] * 24}, alert_delays_s=[1.2],
             monitor_completeness=0.99)
assert verify.verdict(**clean) == ("CERTIFIED", [])
assert verify.verdict(**{**clean, "findings": [down]})[0] == "FAIL"
assert verify.verdict(**{**clean, "findings": [google_silent]})[0] == "CERTIFIED", "Google's silence is not ours"
assert verify.verdict(**{**clean, "coverage": {"chaparral": {"uncovered_min": 61, "longest_gap_min": 61}}})[0] == "FAIL"
assert verify.verdict(**{**clean, "coverage": {"chaparral": {"uncovered_min": 20, "longest_gap_min": 10}}})[0] == "DEGRADED"
assert verify.verdict(**{**clean, "probes": {"sent": 24, "received": 22, "latencies_s": [0.8] * 22}})[0] == "DEGRADED"
assert verify.verdict(**{**clean, "alert_delays_s": [12.0]})[0] == "DEGRADED"
assert verify.verdict(**{**clean, "monitor_completeness": 0.8})[0] == "DEGRADED"
print("PASS verdict rules")

# 24-sep, 16:0x UTC: the gateway was redeployed. After a restart it has no heartbeats until
# the sensors report again, so /status says "not covered" for a few minutes.
def minute(at, covered, started_at):
    return {"at": at, "started_at": started_at, "sensors": {"chaparral": {"covered": covered}}}


T = 1790265600
health = ([minute(T + 60 * i, True, 1000) for i in range(5)]
          + [minute(T + 60 * i, False, T + 330) for i in range(5, 10)]
          + [minute(T + 60 * i, True, T + 330) for i in range(10, 12)])
planned = verify.restart_windows(health, deploys=[T + 300])
stats = verify.coverage_stats(health, ["chaparral"], T, T + 3600, planned)["chaparral"]
assert (stats["uncovered_min"], stats["deploy_min"]) == (0, 5), stats
assert [g["reason"] for g in stats["gaps"]] == ["deploy"]
unplanned = verify.restart_windows(health, deploys=[])
stats = verify.coverage_stats(health, ["chaparral"], T, T + 3600, unplanned)["chaparral"]
assert (stats["uncovered_min"], stats["deploy_min"]) == (5, 0), "an unplanned restart hidden as a deploy"
assert stats["gaps"][0]["reason"] == "gateway restart"
# A receiver still down 15 min after the deploy is the receiver's fault again.
long_down = health[:5] + [minute(T + 60 * i, False, T + 330) for i in range(5, 40)]
stats = verify.coverage_stats(long_down, ["chaparral"], T, T + 3600, verify.restart_windows(long_down, [T + 300]))["chaparral"]
assert stats["deploy_min"] <= 16 and stats["uncovered_min"] >= 19, stats
print("PASS planned deploy excused, unplanned restart counts")

# The real sequence of 24-sep: the first deploy of started_at (16:17, older records have
# none) with its DEPLOY, then a manual restart at 16:22 without one. Only public sensors
# here, as monitor.py records them.
def real(at, covered, started_at=None):
    record = {"at": at, "sensors": {"chaparral": {"covered": covered}, "quibdo": {"covered": covered}}}
    return {**record, "started_at": started_at} if started_at else record


D = 1790266644  # 16:17:24
day = ([real(D - 135, True), real(D - 75, True), real(D - 15, True)]
       + [real(D + 45 + 60 * i, False, D) for i in range(4)] + [real(D + 285, True, D)]
       + [real(D + 345, True, D + 308)])
# bucaramanga-a is in /status but not public, and never covered: it must not hold the window open.
day = [{**r, "sensors": {**r["sensors"], "bucaramanga-a": {"covered": False}}} for r in day]
windows = verify.restart_windows(day, deploys=[D - 0.4], sensor_ids={"chaparral", "quibdo"})
assert windows[0][1] == D + 285, "the deploy window did not close when the public sensors came back"
assert [w[2] for w in windows] == ["deploy", "gateway restart"], windows
stats = verify.coverage_stats(day, ["chaparral"], D - 3600, D + 3600, windows)["chaparral"]
assert (stats["uncovered_min"], stats["deploy_min"]) == (0, 4), stats
print("PASS 24-sep: 16:17 deploy excused, 16:22 manual restart unplanned")

# The real quake of 24-sep 16:46:33 UTC (TIME_OCCURRED 1790268393, Google M4.48): AWS
# chaparral got eew_alert_v2 at +16.6 s; the Mac control got only eew_update at +40 s.
quake_1646 = verify.merge_catalogs([{"id": "chaparral-1646", "source": "sgc", "time": 1790268393,
                                     "lat": 3.83, "lon": -75.62, "mag": 4.5, "place": "Chaparral"}])
aws_now = {**AWS, "since": 1790265600}
mac_now = {**MAC, "since": 1790035200}
real_captures = [{"receiver": "chaparral", "kind": "aws", "origin": 1790268393, "captured": 1790268409.614},
                 {"receiver": "chaparral", "kind": "mac", "origin": 1790268393, "captured": 1790268433.272, "update": True}]
findings, unexplained = verify.classify(quake_1646, real_captures, [aws_now, mac_now], covered_everywhere, NOW)
by_kind = {f["kind"]: f for f in findings}
assert by_kind["aws"]["verdict"] == "HIT", by_kind
assert by_kind["mac"]["verdict"] == "UPDATE_ONLY", by_kind
assert unexplained == [], "an eew_update was taken for a capture without a quake"
assert not any(verify.fails(f) for f in findings), "AWS captured: the control's miss is not our failure"
assert verify.verdict(**{**clean, "findings": findings})[0] == "CERTIFIED"
aws_update_only = verify.classify(quake_1646, [{**real_captures[1], "kind": "aws"}], [aws_now], covered_everywhere, NOW)[0]
assert aws_update_only[0]["verdict"] == "UPDATE_ONLY" and verify.fails(aws_update_only[0]), "AWS users got nothing"
print("PASS real quake 24-sep 16:46: AWS HIT, Mac UPDATE_ONLY, no FAIL")

# QA-85: the control's location age, read from the real dumpsys of emulator-5558 on 24-sep.
DUMPSYS = "  last location=Location[gps 3.723598,-75.483598 hAcc=5.0 et=+5m46s850ms alt=0.0 vAcc=0.5]"
assert verify.elapsed_s("+1d1h23m33s395ms") == 91413.395
assert round(verify.location_age_s(DUMPSYS, 91492.96)) == 91146, "about 25.3 h"
assert verify.location_age_s("  last location=null", 100.0) is None
readings = [{"device": "chaparral", "at": 1790268792, "age_s": 91146},
            {"device": "quibdo", "at": 1790268792, "age_s": None},
            {"device": "bucaramanga-a", "at": 1790268792, "age_s": 3600}]
assert verify.control_fresh(readings, "chaparral", 1790268393) is False, "a 25 h old control counted as seeing"
assert verify.control_fresh(readings, "quibdo", 1790268393) is False, "a control with no location counted"
assert verify.control_fresh(readings, "bucaramanga-a", 1790268393) is True
assert verify.control_fresh(readings, "chaparral", 1790268393 - 3 * 3600) is None, "a reading 3 h away used"


# With a blind control, an AWS miss is not excused as "Google did not alert".
def blind_control(kind, receiver, t):
    return True if kind == "aws" else None


assert miss([AWS, MAC], covered=blind_control)["cause"] == verify.UNEXPLAINED
print("PASS Mac control: > 20 h or no location = no control")

# Manual intervention on quibdo: excused until it is covered again, capped.
Q = 1790268600  # 16:50 UTC
quibdo_health = [{"at": Q + 60 * i, "sensors": {"quibdo": {"covered": i >= 12}}} for i in range(20)]
windows = verify.intervention_windows([{"sensor": "quibdo", "from": "2026-09-24T16:50:00Z", "max_min": 60}], quibdo_health)
stats = verify.coverage_stats(quibdo_health, ["quibdo", "chaparral"], Q - 60, Q + 3600, windows)
assert (stats["quibdo"]["uncovered_min"], stats["quibdo"]["deploy_min"]) == (0, 12), stats["quibdo"]
assert stats["quibdo"]["gaps"][0]["reason"] == "manual intervention"
capped = verify.intervention_windows([{"sensor": "quibdo", "from": "2026-09-24T16:50:00Z", "max_min": 5}], quibdo_health)
assert verify.coverage_stats(quibdo_health, ["quibdo"], Q - 60, Q + 3600, capped)["quibdo"]["uncovered_min"] == 6
print("PASS manual intervention excused until the sensor is back, with a cap")

# As it really went: quibdo still covered when the work started, down later, then back.
real_quibdo = [{"at": Q + 60 * i, "sensors": {"quibdo": {"covered": not 10 <= i < 19}}} for i in range(30)]
windows = verify.intervention_windows([{"sensor": "quibdo", "from": "2026-09-24T16:50:00Z", "max_min": 60}], real_quibdo)
stats = verify.coverage_stats(real_quibdo, ["quibdo"], Q - 60, Q + 3600, windows)["quibdo"]
assert (stats["uncovered_min"], stats["deploy_min"]) == (0, 9), "the window closed before the sensor went down"
print("PASS intervention that starts with the sensor healthy")

# GpsKeeper check (QA-84): real line from AWS chaparral, 24-sep.
GMS = "      10144/com.google.android.gms[earthquake_alerting]: total = 2h56m46s, min/max = 0s/30m, deliveries = 2"
assert verify.alerting_deliveries(GMS) == 2
assert verify.alerting_deliveries("nothing about it") is None
print("PASS earthquake_alerting deliveries")

# Location rule in the verdict (QA-84). Readings every 30 min; quibdo has GpsKeeper, chaparral not.
def reading(sensor, minute, age_s, deliveries, uptime_s=None):
    return {"at": Q + 60 * minute, "sensor": sensor, "age_s": age_s, "deliveries": deliveries,
            "uptime_s": 10_000 + 60 * minute if uptime_s is None else uptime_s}

healthy = [reading("quibdo", m, 40, 4 + m // 60) for m in range(0, 361, 30)] + \
          [reading("chaparral", m, 16_000 + 60 * m, 2) for m in range(0, 361, 30)]
assert verify.location_problems(healthy, {"quibdo"}) == [], "chaparral's 4-10 h fix is not a problem without GpsKeeper"
assert verify.verdict([], [], {}, {"sent": 0}, [], 1.0, verify.location_problems(healthy, {"quibdo"}))[0] == "CERTIFIED"

old_fix = healthy + [reading("quibdo", 390, 3601, 10)]
assert verify.location_problems(old_fix, {"quibdo"}) == ["quibdo: GMS location 1.0 h (> 1 h)"]
assert verify.verdict([], [], {}, {"sent": 0}, [], 1.0, verify.location_problems(old_fix, {"quibdo"}))[0] == "DEGRADED"
assert verify.location_problems([reading("quibdo", 0, 3600, 4)], {"quibdo"}) == []
assert verify.location_problems([reading("quibdo", 0, 3600.5, 4)], {"quibdo"}) != [], "ages are fractional seconds"
assert verify.location_problems([reading("quibdo", 0, None, 4)], {"quibdo"}) == ["quibdo: GMS has no location"]
assert verify.location_problems(healthy, {"quibdo", "chaparral"})[0].startswith("chaparral: GMS location 10.4 h (> 1 h)")
blind = [reading("chaparral", 0, 20 * 3600 + 1, 2)]
assert verify.location_problems(blind, set()) == ["chaparral: GMS location 20.0 h (> 20 h)"]
assert verify.location_problems([], {"quibdo"}) == ["quibdo: no GMS location readings"]
print("PASS location age in the verdict")

stalled = [reading("quibdo", m, 40, 4) for m in range(0, 121, 30)]
assert verify.location_problems(stalled, {"quibdo"}) == []
stalled.append(reading("quibdo", 121, 40, 4))
assert verify.location_problems(stalled, {"quibdo"}) == ["quibdo: earthquake_alerting deliveries flat for 2.0 h (> 2 h)"]
assert verify.location_problems(stalled, set()) == [], "without GpsKeeper deliveries are not expected to grow"
# One growth in the middle restarts the clock; so does a reboot that resets the count to 0.
grows = [reading("quibdo", m, 40, 4 + (m >= 90)) for m in range(0, 181, 30)]
assert verify.location_problems(grows, {"quibdo"}) == []
rebooted = [reading("quibdo", m, 40, 4) for m in (0, 30, 60, 90)] + \
           [reading("quibdo", m, 40, 0, uptime_s=60 * (m - 90)) for m in (120, 150, 180, 210)]
assert verify.deliveries_stall_s(rebooted) == 90 * 60
print("PASS flat deliveries in the verdict")

# Our part of a real alert (QA-86): the 24-sep 16:46 chaparral alert, with the real clock readings.
CAPTURED, RECEIVED = 1790268409.614, 1790268411.664  # emulator clock, Mac clock
assert abs(verify.emulator_skew_s("clock 1790276000.100 1790275998.360 1790276000.140") - -1.76) < 1e-6
assert verify.emulator_skew_s("error: device offline") is None
assert verify.sntp_offset_s("+0.184773 +/- 0.109443 time.apple.com 2620:149:a33:3000::31\n") == 0.184773
assert verify.sntp_offset_s("-0.020000 +/- 0.01 time.apple.com 17.253.4.125") == -0.02
assert verify.sntp_offset_s("sntp: Exchange failed: Timeout") is None
ours = verify.our_part_s(CAPTURED, RECEIVED, -1.70, 0.184773)
assert abs(ours - 0.535) < 0.001, ours  # 0.78 s counted from the post, 0.24 s earlier
assert verify.our_part_s(CAPTURED, RECEIVED, None, None) > 2, "uncorrected, the same alert looks like 2.05 s"
assert verify.our_part_s(CAPTURED, None, -1.70, 0.18) is None

skews = [{"at": CAPTURED - 7 * 3600, "skew_s": -1.0}, {"at": CAPTURED + 2.1 * 3600, "skew_s": -1.76},
         {"at": CAPTURED + 1800, "skew_s": None}]
assert verify.nearest(skews, CAPTURED, "skew_s") == -1.76, "a reading 7 h away is too old, a null one is not a reading"
assert verify.nearest(skews[:1], CAPTURED, "skew_s") is None

def verdict_with(parts):
    return verify.verdict([], [], {}, {"sent": 0}, [], 1.0, (), parts)
assert verdict_with([("chaparral:t1790268393:alert", ours)]) == ("CERTIFIED", [])
assert verdict_with([("e", 2.0)])[0] == "CERTIFIED"
assert verdict_with([("e", 2.01)]) == ("DEGRADED", ["real alert e: listener → monitor 2.01 s (> 2 s)"])
assert verdict_with([("e", None)]) == ("DEGRADED", ["real alert e never reached the monitor"])
print("PASS our part of a real alert, clocks corrected")

catalog = [{"source": "sgc", "time": 1790268392.0}, {"source": "usgs", "time": 1790268392.437},
           {"source": "usgs", "time": 1790268393 + 91}]
assert verify.usgs_origin(1790268393, catalog) == 1790268392.437
assert verify.usgs_origin(1790268393, catalog[:1]) is None, "SGC has whole seconds only"
assert verify.usgs_origin(1790268393, catalog[2:]) is None, "91 s away is another quake"
print("PASS origin in ms from USGS when it has the quake")

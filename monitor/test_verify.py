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
# 20 h 15 min is a planned sensor-health reboot still finishing: not a problem. Past 21 h it did not help.
assert verify.location_problems([reading("chaparral", 0, 20.25 * 3600, 2)], set()) == []
blind = [reading("chaparral", 0, 21 * 3600 + 1, 2)]
assert verify.location_problems(blind, set()) == ["chaparral: GMS location 21.0 h (> 21 h)"]
assert verify.location_problems([], {"quibdo"}) == ["quibdo: no GMS location readings"]
print("PASS location age in the verdict")

# QA-90: AEA's own location is the last one GMS delivered to earthquake_alerting (minUpdateDistance=1000 m).
# Real quibdo lines, 24-sep: boot delivery 17:06, the Tadó move 18:06 and 18:11.
QUIBDO_GMS = """      09-24 17:06:15.044: delivered locations[1] to 10144/com.google.android.gms[earthquake_alerting]/85e9f318
      09-24 18:06:19.406: delivered locations[1] to 10144/com.google.android.gms[earthquake_alerting]/bd31da74
      09-24 18:06:19.408: delivered locations[1] to 10144/com.google.android.gms[earthquake_detection]/861b2f5a
      09-24 18:11:19.436: delivered locations[1] to 10144/com.google.android.gms[earthquake_alerting]/bd31da74
      10144/com.google.android.gms[earthquake_alerting]: total = 2h28m51s, min/max = 0s/30m, deliveries = 4
"""
assert verify.alerting_location_age_s(QUIBDO_GMS, "2026-09-24T19:26:15", 8900.0) == 3600 + 14 * 60 + 56
assert verify.alerting_location_age_s(QUIBDO_GMS, None, 8900.0) == 8900.0, "no guest clock: the uptime bounds it"
assert verify.alerting_location_age_s("only earthquake_detection here", "2026-09-24T19:26:15", 8900.0) == 8900.0
assert verify.alerting_location_age_s("      12-31 23:00:00.000: delivered locations[1] to x[earthquake_alerting]/1",
                                      "2027-01-01T01:00:00", 1e6) == 7200, "the log has no year"
assert verify.alerting_deliveries(QUIBDO_GMS) == 4
assert verify.alerting_location_age_s(QUIBDO_GMS + "      09-24 19:00:00.000: delivered locations[1] to 10144/com.google.android.gms[earthquake_detection]/1\n",
                                      "2026-09-24T19:26:15", 8900.0) == 3600 + 14 * 60 + 56, "a later earthquake_detection delivery is not AEA's"

# The rule: > 20 h on any receptor, GpsKeeper or not. A flat counter alone is healthy (stationary).
fresh_gps_old_aea = [{**reading("quibdo", 0, 40, 4), "alert_age_s": 21 * 3600 + 1}]
assert verify.location_problems(fresh_gps_old_aea, {"quibdo"}) == ["quibdo: AEA's location 21.0 h old (> 21 h)"]
assert verify.location_problems([{**reading("chaparral", 0, 3600, 2), "alert_age_s": 21 * 3600}], set()) == []
assert verify.location_problems([{**reading("chaparral", 0, 3600, 2), "alert_age_s": 21 * 3600 + 0.5}], set()) != []
flat_for_a_day = [{**reading("quibdo", m, 40, 4), "alert_age_s": 600 + 60 * m} for m in range(0, 19 * 60, 30)]
assert verify.location_problems(flat_for_a_day, {"quibdo"}) == [], "a stationary receptor never grows the counter"
assert verify.location_problems([reading("quibdo", 0, 40, 4)], {"quibdo"}) == [], "old rows without alert_age_s"
# The event log can drop AEA's line (GpsKeeper floods it): the last delivery seen in this boot still counts.
T = 1_790_300_000
assert verify.remembered_alert_age_s(600.0, T - 9000, T, 20_000) == 600.0, "a line in the log wins"
assert verify.remembered_alert_age_s(None, T - 9000, T, 20_000) == 9000, "rolled out: remembered delivery"
assert verify.remembered_alert_age_s(None, T - 9000, T, 5_000) == 5_000, "remembered from before this boot: uptime"
assert verify.remembered_alert_age_s(None, None, T, 5_000) == 5_000
assert verify.last_alerting_delivery_age_s("no lines", "2026-09-24T19:26:15") is None
print("PASS AEA location age in the verdict (QA-90)")

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

# The Mac control was retired on 24-sep 19:11 UTC (QA-85 follow-up): the catalog alone is ground truth.
RETIRED = 1790277060  # 2026-09-24T19:11:00Z
chaparral_aws = {"id": "chaparral", "lat": 3.72, "lon": -75.48, "kind": "aws", "since": 0}
chaparral_mac = {**chaparral_aws, "kind": "mac", "until": RETIRED}
after = {"id": "SGC-after", "source": "sgc", "time": RETIRED + 3600, "lat": 3.8, "lon": -75.5, "mag": 5.0, "place": "x"}
before = {**after, "id": "SGC-before", "time": RETIRED - 3600}
mac_up = lambda kind, receiver_id, t: True
findings, _ = verify.classify([after], [], [chaparral_aws, chaparral_mac], mac_up, RETIRED + 7200)
assert [(f["kind"], f["verdict"]) for f in findings] == [("aws", "MISS")], "a retired Mac makes no rows of its own"
assert findings[0]["cause"] == f"{verify.UNEXPLAINED}; {verify.CONTROL_RETIRED}", findings[0]["cause"]
assert verify.fails(findings[0]), "an unexplained miss with no control is still a FAIL"
assert verify.verdict(findings, [], {}, {"sent": 0}, [], 1.0)[0] == "FAIL"
# Explained by the catalog (M4.6, within 0.3 of the M4.5 threshold): still listed, does not fail, by the same rules as before.
findings, _ = verify.classify([{**after, "mag": 4.6}], [], [chaparral_aws, chaparral_mac], mac_up, RETIRED + 7200)
assert findings[0]["cause"] == f"{verify.NEAR_THRESHOLD}; {verify.CONTROL_RETIRED}" and not verify.fails(findings[0])
# Before retirement the Mac still controls: its silence means Google did not alert.
findings, _ = verify.classify([before], [], [chaparral_aws, chaparral_mac], mac_up, RETIRED)
assert {(f["kind"], f["cause"]) for f in findings} == {("aws", verify.GOOGLE_SILENT), ("mac", verify.UNEXPLAINED)}
print("PASS Mac control retired: catalog alone, labelled retired, never down")

# Explained misses with no control can hide a real failure if they keep coming.
def miss(day, cause=f"{verify.NEAR_THRESHOLD}; {verify.CONTROL_RETIRED}", receiver="chaparral"):
    return {"kind": "aws", "receiver": receiver, "time": RETIRED + day * 86400, "verdict": "MISS", "cause": cause}
def hit(day):
    return {"kind": "aws", "receiver": "chaparral", "time": RETIRED + day * 86400, "verdict": "HIT", "cause": None}
END = RETIRED + 8 * 86400
assert verify.repeated_explained_misses([miss(2), miss(4)], END) == []
assert verify.repeated_explained_misses([miss(2), miss(4), miss(6)], END) == \
    ["chaparral: no control, repeated explained misses (3 in 7 days, no hit in between)"]
assert verify.repeated_explained_misses([miss(2), miss(4), hit(5), miss(6)], END) == [], "a hit resets the count"
assert verify.repeated_explained_misses([miss(2), {**hit(3), "kind": "mac"}, miss(4), miss(6)], END) != [], \
    "a Mac hit is not an AWS hit"
assert verify.repeated_explained_misses([miss(0.5), miss(4), miss(6)], END) == [], "older than 7 days"
assert verify.repeated_explained_misses([miss(2), miss(4), miss(6, receiver="quibdo")], END) == [], "per receptor"
assert verify.repeated_explained_misses([miss(2), miss(4), miss(6, cause=verify.NEAR_THRESHOLD)], END) == [], \
    "with a control, an explained miss is not suspicious"
assert verify.repeated_explained_misses([miss(2), miss(4), miss(6, cause=f"{verify.UNEXPLAINED}; {verify.CONTROL_RETIRED}")], END) == [], \
    "an unexplained miss is already a FAIL, not part of this streak"
assert verify.repeated_explained_misses([miss(2), miss(4), miss(9)], END) == [], "after `end` does not count"
assert verify.verdict([], [], {}, {"sent": 0}, [], 1.0,
                      verify.repeated_explained_misses([miss(2), miss(4), miss(6)], END))[0] == "DEGRADED"
print("PASS repeated explained misses with no control")

# Canary pair (General Santos + Glan, 32 km apart): each is the other's control.
gsantos = {"id": "general-santos", "lat": 6.11, "lon": 125.17, "kind": "aws", "since": 0}
glan = {"id": "glan", "lat": 5.82, "lon": 125.20, "kind": "aws", "since": 0}
gsantos["pair"], glan["pair"] = glan, gsantos
offshore = {"id": "us-mindanao", "source": "usgs", "time": RETIRED + 3600, "lat": 5.95, "lon": 125.40, "mag": 5.5, "place": "x"}
both_up = lambda kind, receiver_id, t: True
def capture(receiver):
    return {"receiver": receiver, "kind": "aws", "origin": offshore["time"] + 1, "captured": offshore["time"] + 20}
def causes(captures, covered=both_up, event=offshore):
    findings, _ = verify.classify([event], captures, [gsantos, glan], covered, event["time"] + 7200)
    return {f["receiver"]: (f["verdict"], f["cause"]) for f in findings}

assert causes([capture("glan")])["general-santos"] == ("MISS", verify.PAIR_CAPTURED)
assert verify.fails({"kind": "aws", "verdict": "MISS", "cause": verify.PAIR_CAPTURED}), "one misses = FAIL"
assert causes([]) == {"general-santos": ("MISS", verify.PAIR_SILENT), "glan": ("MISS", verify.PAIR_SILENT)}
assert not verify.fails({"kind": "aws", "verdict": "MISS", "cause": verify.PAIR_SILENT}), "both miss = Google silent"
# A partner that was down is no control: the miss falls back to the catalog rules.
glan_down = lambda kind, receiver_id, t: receiver_id != "glan"
assert causes([], glan_down)["general-santos"] == ("MISS", f"{verify.UNEXPLAINED}; {verify.NO_CONTROL}")
assert causes([], glan_down)["glan"][1] == verify.DOWN
# Nor is a partner the quake did not reach: an M5.0 north of General Santos, outside Glan's radius.
north = {**offshore, "id": "us-north", "lat": 6.70, "lon": 125.10, "mag": 5.0}
assert verify.lab.km_between(glan["lat"], glan["lon"], north["lat"], north["lon"]) > verify.lab.beaware_radius_km(5.0) \
    >= verify.lab.km_between(gsantos["lat"], gsantos["lon"], north["lat"], north["lon"]), "fixture no longer splits the pair"
assert causes([], event=north)["general-santos"][1].startswith(verify.UNEXPLAINED)
print("PASS canary pair: one misses = FAIL, both miss = Google silent, only when the partner counts")

# A deploy that rolled back is an outage, not a planned restart (infra/deploy/remote.sh).
evidence = [{"type": "DEPLOY", "at": "2026-09-24T16:17:00.000Z", "by": "bootstrap"},
            {"type": "DEPLOY", "at": "2026-09-25T10:00:00.000Z", "by": "ci"},
            {"type": "DEPLOY", "at": "2026-09-25T10:07:10.000Z", "by": "ci-rollback"},
            {"type": "DEPLOY", "at": "2026-09-25T10:12:00.000Z", "by": "ci"},  # the fix, after the rollback
            {"type": "DEPLOY", "at": "2026-09-25T12:00:00.000Z", "by": "ci"},
            {"type": "WEB_PUSH_DISPATCH", "at": "2026-09-25T12:01:00.000Z"}]
planned = verify.planned_deploys(evidence)
assert [verify.datetime.fromtimestamp(t, verify.timezone.utc).strftime("%d %H:%M") for t in planned] == ["24 16:17", "25 10:12", "25 12:00"], planned
print("PASS a rolled-back deploy and its rollback are not excused")

# Live coverage notices: quibdo on 24-sep, covered until 21:15, then uncovered for 2 h 25 min.
Q0 = 1790284500  # 2026-09-24T21:15:00Z
def poll(minute, covered, error=None):
    record = {"at": Q0 + 60 * minute, "sensors": {"quibdo": {"covered": covered}}}
    return {**record, "error": error, "sensors": {}} if error else record
health = [poll(-5, True)] + [poll(m, False) for m in range(0, 146)]
told, runs = [], {}
for i in range(1, len(health) + 1):
    notices, runs = verify.live_coverage_notices(health[:i], ["quibdo"], runs)
    told += [(round((health[i - 1]["at"] - Q0) / 60), notice) for notice in notices]
assert [(m, n.split()[0]) for m, n in told] == [(15, "DEGRADED"), (60, "FAIL")], told
assert "since 21:15 UTC" in told[0][1]
notices, runs = verify.live_coverage_notices(health + [poll(146, True)], ["quibdo"], runs)
assert notices == ["RESTORED quibdo: covered again after 146 min"] and runs == {}
# The monitor's own blind spots (ssh down) neither end the run nor start one.
gap = [poll(0, False)] + [poll(m, None, error="ssh") for m in range(1, 20)] + [poll(20, False)]
assert verify.uncovered_since(gap, "quibdo") == Q0
assert verify.uncovered_since([poll(0, True)] + [poll(m, None, error="ssh") for m in range(1, 30)], "quibdo") is None
# The gateway itself down counts as uncovered.
assert verify.uncovered_since([poll(0, True), poll(1, None, error="gateway")], "quibdo") == Q0 + 60
# A short blip (a deploy restart) never pages.
blip = [poll(0, True)] + [poll(m, False) for m in range(1, 10)] + [poll(10, True)]
runs = {}
for i in range(1, len(blip) + 1):
    notices, runs = verify.live_coverage_notices(blip[:i], ["quibdo"], runs)
    assert notices == [], f"a 9 min blip was told: {notices}"
print("PASS live coverage notices: 15 min DEGRADED, 60 min FAIL, once each, then RESTORED")

# poll_health: a dead tunnel (the host's IP changed) is rebuilt once before blaming the gateway.
import monitor  # noqa: E402
written, dropped = [], []
monitor.append = lambda name, record: written.append(record)
monitor.drop_tunnel = lambda: dropped.append(1)
monitor.ensure_tunnel = lambda: (True, None)
STATUS = {"relay_enabled": True, "started_at": "2026-09-24T23:33:00Z", "sensors": [{"id": "quibdo", "covered": True}]}
answers = [OSError("connection reset"), STATUS]
def scripted(method, path):
    answer = answers.pop(0)
    if isinstance(answer, Exception):
        raise answer
    return answer
monitor.call = scripted
record = monitor.poll_health()
assert "error" not in record and record["sensors"]["quibdo"]["covered"] is True, record
assert dropped == [1], "the stale tunnel was not dropped"
answers[:] = [OSError("refused"), OSError("refused")]
dropped.clear()
assert monitor.poll_health()["error"] == "gateway", "a gateway really down must still read as down"
monitor.ensure_tunnel = lambda: (False, "ssh")
assert monitor.poll_health()["error"] == "ssh"
assert len(written) == 3, "one health line per poll"
print("PASS a dead tunnel is rebuilt once before the gateway is called down")

# The $0 plan: general-santos and glan share the Colombia host. A host outage takes both canaries down.
pair_down = lambda kind, receiver_id, t: False
findings, _ = verify.classify([offshore], [], [gsantos, glan], pair_down, offshore["time"] + 7200)
assert {(f["receiver"], f["cause"]) for f in findings} == {("general-santos", verify.DOWN), ("glan", verify.DOWN)}
CANARIES = {"general-santos", "glan"}
decision, reasons = verify.verdict(findings, [], {}, {"sent": 0}, [], 1.0, (), (), CANARIES)
assert decision == "DEGRADED" and all(r.startswith("MISS on canary") for r in reasons), (decision, reasons)
assert verify.verdict(findings, [], {}, {"sent": 0}, [], 1.0)[0] == "FAIL", "a user-facing receptor down stays FAIL"
long_gap = {"glan": {"uncovered_min": 90, "longest_gap_min": 90}}
assert verify.verdict([], [], long_gap, {"sent": 0}, [], 1.0, (), (), CANARIES)[0] == "DEGRADED"
assert verify.verdict([], [], long_gap, {"sent": 0}, [], 1.0)[0] == "FAIL"
print("PASS canaries never FAIL: a lost signal, not a lost warning (both down at once included)")

# One canary alone (general-santos, emulator 3; glan waits for its own host): certified, no pair.
monitor.CANARIES = {"general-santos"}
monitor.call = lambda method, path: {"sensors": [
    {"id": "chaparral", "public": True, "lat": 3.72, "lon": -75.48},
    {"id": "general-santos", "public": False, "lat": 6.11, "lon": 125.17},
    {"id": "glan", "public": False, "lat": 5.82, "lon": 125.20},
    {"id": "hinatuan", "public": False, "lat": 8.37, "lon": 126.34}]}
assert [s["id"] for s in monitor.certified_sensors()] == ["chaparral", "general-santos"]
alone = {k: v for k, v in gsantos.items() if k != "pair"}
findings, _ = verify.classify([offshore], [], [alone], both_up, offshore["time"] + 7200)
assert findings[0]["cause"] == f"{verify.UNEXPLAINED}; {verify.NO_CONTROL}", findings[0]["cause"]
assert verify.verdict(findings, [], {}, {"sent": 0}, [], 1.0, (), (), monitor.CANARIES)[0] == "DEGRADED"
print("PASS a lone canary is certified from MONITOR_CANARIES, catalog rules, capped at DEGRADED")

# The AWS receptor list comes from the host's sensor map, not from code: a receptor added there is
# polled with no change here, its key never leaves the host, and an unreadable map is loud.
import subprocess  # noqa: E402
import tempfile  # noqa: E402
with tempfile.TemporaryDirectory() as host:
    bin_dir = os.path.join(host, "bin")
    os.mkdir(bin_dir)
    with open(os.path.join(bin_dir, "sudo"), "w") as fake_sudo:  # `sudo -u aea -H <adb> ...` runs the fake adb
        fake_sudo.write('#!/bin/sh\nif [ "$1" = -u ]; then shift 4; exec adb "$@"; fi\nexec "$@"\n')
    with open(os.path.join(bin_dir, "adb"), "w") as fake_adb:
        fake_adb.write('#!/bin/sh\ncat >/dev/null\ncase "$4" in cat) echo "3600.0 1.0";; esac\n')
    for name in ("sudo", "adb"):
        os.chmod(os.path.join(bin_dir, name), 0o755)
    monitor.AWS_SENSOR_MAP = os.path.join(host, "earthquake-sensors.map")
    with open(monitor.AWS_SENSOR_MAP, "w") as sensor_map:
        sensor_map.write("emulator-5554 chaparral 3.72 -75.48 KEY-ONE\n"
                         "emulator-5560 brand-new-site 6.11 125.17 KEY-TWO\n")

    def run_on_host():
        return subprocess.run(["bash", "-c", monitor.remote_location_script()], capture_output=True, text=True,
                              stdin=subprocess.DEVNULL, env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"},
                              timeout=30).stdout

    out = run_on_host()
    assert [(serial, sensor) for serial, sensor, _ in monitor.location_chunks(out)] == [
        ("emulator-5554", "chaparral"), ("emulator-5560", "brand-new-site")], out
    assert "KEY-" not in out, "a sensor key left the host"
    monitor.AWS_SERIALS_OVERRIDE = "emulator-5556:quibdo"
    assert [sensor for _, sensor, _ in monitor.location_chunks(run_on_host())] == ["quibdo"]
    monitor.AWS_SERIALS_OVERRIDE = ""
    os.remove(monitor.AWS_SENSOR_MAP)
    try:
        list(monitor.location_chunks(run_on_host()))
        raise AssertionError("an unreadable sensor map polled nothing, silently")
    except RuntimeError:
        pass
print("PASS AWS receptors come from the host's sensor map: a new id is polled, keys stay, no map is loud")

# An instance id that no longer resolves (account moved, credentials gone) fails the poll, not skips it.
monitor.instance = lambda: (None, None)
try:
    monitor.poll_aws_location()
    raise AssertionError("an unresolvable instance skipped the location poll silently")
except RuntimeError:
    pass
print("PASS an instance the AWS CLI cannot describe fails the location poll instead of skipping it")

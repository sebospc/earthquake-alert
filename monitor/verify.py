"""Ground truth: which receivers should have alerted for each catalog quake, and why not.

Pure functions, no I/O: monitor.py feeds them catalogs, captures and the coverage history,
the tests feed them real events. Radii and thresholds come from scripts/lab.py so the lab
and the certifier can never disagree on what "expected" means.
"""
import os
import re
import statistics
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
import lab  # noqa: E402  (only its pure helpers and constants are used)

# A capture belongs to a catalog quake when its origin is this close in time. Distance is
# only a sanity bound: Google's own magnitude (and so its radius) can be far from the
# catalog's, e.g. the M3.6 SGC quake of 24-sep that Google did alert on.
MATCH_WINDOW_S = 90
MATCH_MAX_KM = 500
# Two catalogs reporting one quake.
SAME_QUAKE_S = 60
SAME_QUAKE_KM = 100
NEAR_THRESHOLD_MAG = 0.3
EDGE_OF_RADIUS = 0.85
NEAR_RADIUS_FACTOR = 1.15
FELT_MMI = 3.0
# A catalog can publish a quake hours late; a capture is only FALSE after this.
FALSE_AFTER_S = 24 * 3600

DOWN = "receptor down"
CONTROL_CAPTURED = "the Mac captured and AWS did not"
GOOGLE_SILENT = "Google did not alert (the Mac control did not either)"
NO_CONTROL = "no control"
NEAR_THRESHOLD = "catalog magnitude near the threshold (Google estimates differently)"
AT_EDGE = "at the edge of the radius"
NOT_FELT = "not felt (DYFI < MMI 3)"
UNEXPLAINED = "unexplained"
FAILING_CAUSES = {DOWN, CONTROL_CAPTURED, UNEXPLAINED}


def usgs_events(feed):
    """GeoJSON from the USGS FDSN query, as scripts/lab.py requests it."""
    return [{"id": feature["id"], "source": "usgs", "time": feature["properties"]["time"] / 1000,
             "lat": feature["geometry"]["coordinates"][1], "lon": feature["geometry"]["coordinates"][0],
             "mag": feature["properties"].get("mag"), "place": feature["properties"].get("place")}
            for feature in feed.get("features", [])]


def sgc_events(feed):
    """api.sgc.gov.co biweekly GeoJSON. Failures arrive as HTTP 200 with an "error" object,
    so an empty list must never be read as "no quakes": callers check for that key."""
    if "error" in feed:
        raise ValueError(f"SGC error: {feed['error']}")
    events = []
    for feature in feed.get("features", []):
        props = feature["properties"]
        if props.get("agency") != "SGC" or props.get("type", "earthquake") != "earthquake":
            continue
        when = datetime.strptime(props["utcTime"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        lon, lat = feature["geometry"]["coordinates"][:2]
        events.append({"id": feature["id"], "source": "sgc", "time": when.timestamp(),
                       "lat": lat, "lon": lon, "mag": props.get("mag"), "place": props.get("place")})
    return events


def merge_catalogs(*catalogs):
    """One entry per quake. The larger magnitude wins: the stricter expectation."""
    merged = []
    for event in sorted((e for catalog in catalogs for e in catalog), key=lambda e: e["time"]):
        twin = next((m for m in merged if abs(m["time"] - event["time"]) <= SAME_QUAKE_S
                     and lab.km_between(m["lat"], m["lon"], event["lat"], event["lon"]) <= SAME_QUAKE_KM), None)
        if twin is None:
            merged.append({**event, "ids": [event["id"]]})
            continue
        twin["ids"].append(event["id"])
        if (event["mag"] or 0) > (twin["mag"] or 0):
            twin["mag"] = event["mag"]
    return merged


def matches(capture, event, receiver):
    return (abs(capture["origin"] - event["time"]) <= MATCH_WINDOW_S
            and lab.km_between(receiver["lat"], receiver["lon"], event["lat"], event["lon"]) <= MATCH_MAX_KM)


def miss_cause(event, receiver, km, radius, captured_by, covered, felt_mmi):
    """First cause that explains a MISS, in the order the operator asked for."""
    if receiver["kind"] == "aws":
        if covered("aws", receiver["id"], event["time"]) is False:
            return DOWN
        control = captured_by.get(("mac", receiver["id"]))
        if control is True:
            return CONTROL_CAPTURED
        if control is False:
            return GOOGLE_SILENT
    if abs((event["mag"] or 0) - lab.MIN_ALERT_MAG) <= NEAR_THRESHOLD_MAG:
        return NEAR_THRESHOLD
    if km >= EDGE_OF_RADIUS * radius:
        return AT_EDGE
    if felt_mmi is not None and felt_mmi < FELT_MMI:
        return NOT_FELT
    return UNEXPLAINED


def classify(events, captures, receivers, covered, now, felt=lambda event, receiver: None):
    """Per (quake, receiver): HIT, MISS (with cause), NEAR or N/A; plus FALSE/PENDING
    per capture that no catalog explains.

    covered(kind, receiver_id, t) -> True | False | None (no data). For the Mac control,
    None means it was down or unknown: its silence proves nothing.
    """
    findings = []
    for event in events:
        radius = lab.beaware_radius_km(event["mag"])
        captured_by = {}
        for receiver in receivers:
            key = (receiver["kind"], receiver["id"])
            hit = any(c["receiver"] == receiver["id"] and c["kind"] == receiver["kind"] and not c.get("update")
                      and matches(c, event, receiver) for c in captures)
            available = receiver["kind"] == "aws" or covered("mac", receiver["id"], event["time"]) is True
            captured_by[key] = hit if (hit or available) else None
        for receiver in receivers:
            km = lab.km_between(receiver["lat"], receiver["lon"], event["lat"], event["lon"])
            expected = km <= radius
            hit = captured_by[(receiver["kind"], receiver["id"])] is True
            base = {"event": event["ids"][0] if "ids" in event else event["id"], "time": event["time"],
                    "mag": event["mag"], "place": event.get("place"), "receiver": receiver["id"],
                    "kind": receiver["kind"], "km": round(km, 1), "radius_km": round(radius, 1)}
            if expected and receiver["since"] > event["time"]:
                findings.append({**base, "verdict": "N/A", "cause": "the receptor did not exist yet (PREDATES_DEVICE)"})
            elif hit:
                note = None if expected else "below the threshold in the catalog: Google estimated it higher"
                findings.append({**base, "verdict": "HIT", "cause": note})
            elif any(c["receiver"] == receiver["id"] and c["kind"] == receiver["kind"] and c.get("update")
                     and matches(c, event, receiver) for c in captures):
                # Google knew the device was there (the late "you may have felt it" came),
                # yet the early warning never did. For the user that is a missed alert.
                findings.append({**base, "verdict": "UPDATE_ONLY",
                                 "cause": "the late notice (eew_update) arrived but not the early alert"})
            elif expected:
                cause = miss_cause(event, receiver, km, radius, captured_by, covered, felt(event, receiver))
                if receiver["kind"] == "aws" and cause not in (DOWN, CONTROL_CAPTURED, GOOGLE_SILENT) \
                        and ("mac", receiver["id"]) not in captured_by:
                    cause = f"{cause}; {NO_CONTROL}"
                findings.append({**base, "verdict": "MISS", "cause": cause})
            elif km <= lab.NEAR_MISS_KM or (radius and km <= NEAR_RADIUS_FACTOR * radius):
                findings.append({**base, "verdict": "NEAR", "cause": None})
    unexplained = []
    by_id = {(r["kind"], r["id"]): r for r in receivers}
    for capture in (c for c in captures if not c.get("update")):
        receiver = by_id.get((capture["kind"], capture["receiver"]))
        if receiver is None or any(matches(capture, event, receiver) for event in events):
            continue
        verdict = "FALSE" if now - capture["captured"] >= FALSE_AFTER_S else "PENDING"
        unexplained.append({**capture, "verdict": verdict})
    return findings, unexplained


def fails(finding):
    if finding["kind"] != "aws":
        return False
    # AWS only relays eew_alert, so an update-only on AWS means the user got nothing.
    return finding["verdict"] == "UPDATE_ONLY" or (
        finding["verdict"] == "MISS" and finding["cause"].split(";")[0] in FAILING_CAUSES)


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * fraction))]


def verdict(findings, unexplained, coverage, probes, alert_delays_s, monitor_completeness, location=(), our_parts=()):
    """The day's verdict and every rule that fired.

    coverage: {receiver: {"uncovered_min": n, "longest_gap_min": n}} for public receivers.
    probes: {"sent": n, "received": n, "latencies_s": [...]}.
    our_parts: [(event_id, seconds or None)] for the real alerts of the day.
    """
    failures, degradations = [], []
    failures += [f"MISS on {f['receiver']} ({f['event']}, M{f['mag']}): {f['cause']}" for f in findings if fails(f)]
    failures += [f"FALSE on {c['receiver']}: capture with no quake in any catalog" for c in unexplained
                 if c["kind"] == "aws" and c["verdict"] == "FALSE"]
    for receiver, stats in coverage.items():
        if stats["longest_gap_min"] > 60:
            failures.append(f"{receiver} uncovered {stats['longest_gap_min']} min in a row (> 60)")
        elif stats["uncovered_min"] > 15:
            degradations.append(f"{receiver} uncovered {stats['uncovered_min']} min in the day (> 15)")
    if probes["sent"]:
        lost = 1 - probes["received"] / probes["sent"]
        if lost > 0.05:
            degradations.append(f"probes lost {lost:.0%} (> 5 %)")
        p95 = percentile(probes["latencies_s"], 0.95)
        if p95 is not None and p95 > 10:
            degradations.append(f"probe p95 {p95:.1f} s (> 10 s)")
    degradations += [f"real alert delivered {d:.1f} s after capture (> 10 s)" for d in alert_delays_s if d > 10]
    degradations += list(location)
    for event_id, seconds in our_parts:
        if seconds is None:
            degradations.append(f"real alert {event_id} never reached the monitor")
        elif seconds > OUR_PART_MAX_S:
            degradations.append(f"real alert {event_id}: listener → monitor {seconds:.2f} s (> {OUR_PART_MAX_S:.0f} s)")
    if monitor_completeness < 0.9:
        degradations.append(f"the monitor saw {monitor_completeness:.0%} of the minutes (< 90 %): what was not seen cannot be certified")
    if failures:
        return "FAIL", failures + degradations
    if degradations:
        return "DEGRADED", degradations
    return "CERTIFIED", []


# After a restart the gateway knows nothing until the next heartbeat and watcher report
# (5 min each): at most this long is blamed on the restart, not on the receiver.
RESTART_BLIND_S = 15 * 60
# The bootstrap writes DEPLOY seconds before it restarts the gateway. Anything looser lets a
# deploy excuse a later, unplanned restart (seen on 24-sep: DEPLOY 16:17, manual restart 16:22).
DEPLOY_BEFORE_START_S = 120


def restart_windows(health, deploys, sensor_ids=None):
    """[(start, end, "deploy" | "gateway restart")] from the gateway's started_at in
    /status. A window ends when every sensor is covered again, or after RESTART_BLIND_S.
    deploys: times of DEPLOY records in the evidence; each one excuses one restart only.
    sensor_ids: the public ones. A non-public sensor that is never covered would otherwise
    hold every window open for the full RESTART_BLIND_S."""
    windows, unused = [], sorted(deploys)
    previous_record = None
    for index, record in enumerate(health):
        if not record.get("sensors"):
            continue
        started = record.get("started_at")
        # A gateway that did not report started_at before (older version) and does now
        # restarted too: that first deploy of the feature must not look like a receiver down.
        restarted = previous_record is not None and started is not None \
            and started != previous_record.get("started_at")
        if restarted:
            deploy = next((d for d in unused if -5 <= started - d <= DEPLOY_BEFORE_START_S), None)
            if deploy is not None:
                unused.remove(deploy)
            begin, end = previous_record["at"], started + RESTART_BLIND_S
            for later in health[index:]:
                if later["at"] > end:
                    break
                watched = [s for sensor_id, s in (later.get("sensors") or {}).items()
                           if sensor_ids is None or sensor_id in sensor_ids]
                if watched and all(s.get("covered") for s in watched):
                    end = later["at"]
                    break
            windows.append((begin, end, "deploy" if deploy is not None else "gateway restart"))
        previous_record = record
    return windows


EXCUSED = ("deploy", "manual intervention")


def intervention_windows(interventions, health):
    """Operator-declared work on one sensor (monitor/interventions.json). Excused from its
    start until the sensor is covered again, never longer than its max_min."""
    windows = []
    for item in interventions:
        begin = datetime.fromisoformat(item["from"].replace("Z", "+00:00")).timestamp()
        end = begin + item.get("max_min", 60) * 60
        went_down = False
        for record in health:
            sensor = (record.get("sensors") or {}).get(item["sensor"])
            if not begin <= record["at"] <= end or not sensor:
                continue
            # The work usually starts while the sensor is still fine: only its return after
            # going down closes the window (24-sep: quibdo fine at 16:50, down 17:00).
            if not sensor.get("covered"):
                went_down = True
            elif went_down:
                end = record["at"]
                break
        windows.append((begin, end, "manual intervention", item["sensor"]))
    return windows


def coverage_stats(health, sensor_ids, start, end, windows=()):
    """Minutes without coverage per receiver in [start, end). Minutes inside a planned
    deploy or a declared manual intervention are counted apart and never reach the verdict;
    an unplanned restart counts. A window of 4 elements applies to that sensor only."""
    def window_of(t, sensor_id):
        return next((w[2] for w in windows if w[0] <= t <= w[1] and (len(w) == 3 or w[3] == sensor_id)), None)

    stats = {}
    for sensor_id in sensor_ids:
        uncovered = deploy = gap = longest = 0
        gaps = []
        for record in (r for r in health if start <= r["at"] < end):
            sensor = (record.get("sensors") or {}).get(sensor_id)
            down = record.get("error") in ("gateway", "spot") or (sensor is not None and not sensor.get("covered"))
            if not down:
                gap = 0
                continue
            reason = window_of(record["at"], sensor_id) or record.get("error") or "receptor"
            if reason in EXCUSED:
                deploy += 1
                if not gaps or gaps[-1]["reason"] != reason or gap:
                    gaps.append({"from": record["at"], "reason": reason})
                gap = 0
                continue
            uncovered += 1
            gap += 1
            if gap == 1:
                gaps.append({"from": record["at"], "reason": reason})
            longest = max(longest, gap)
        stats[sensor_id] = {"uncovered_min": uncovered, "longest_gap_min": longest, "deploy_min": deploy, "gaps": gaps}
    return stats


# QA-84: Play Services seems not to alert on a location older than ~24 h, and receivers only
# get one at boot. A control past this sees nothing and must not excuse an AWS miss.
CONTROL_MAX_LOCATION_AGE_S = 20 * 3600
CONTROL_READING_VALID_S = 90 * 60


def elapsed_s(text):
    """dumpsys duration like "+1d1h23m33s395ms" or "+5m46s850ms", in seconds."""
    units = {"d": 86400, "h": 3600, "m": 60, "s": 1, "ms": 0.001}
    return sum(float(n) * units[u] for n, u in re.findall(r"(\d+)(ms|d|h|m|s)", text))


def location_age_s(dumpsys_location, uptime_s):
    """Age of the last GPS fix Play Services has, from `dumpsys location`. None if it has none."""
    match = re.search(r"last location=Location\[gps [^\]]*?et=(\+[0-9dhms]+)", dumpsys_location)
    return None if match is None else uptime_s - elapsed_s(match.group(1))


def alerting_deliveries(dumpsys_gms):
    """How many locations earthquake_alerting has been handed since Play Services started.
    With the GPS kept open (GpsKeeperService) it must keep growing, about every 30 min."""
    match = re.search(r"\[earthquake_alerting\]: total = .*?deliveries = (\d+)", dumpsys_gms)
    return None if match is None else int(match.group(1))


def control_fresh(readings, device, t):
    """True/False from the control reading nearest to t; None if there is none close enough."""
    near = [r for r in readings if r["device"] == device and abs(r["at"] - t) <= CONTROL_READING_VALID_S]
    if not near:
        return None
    reading = min(near, key=lambda r: abs(r["at"] - t))
    if reading["age_s"] is None:
        return False
    return reading["age_s"] - (reading["at"] - t) <= CONTROL_MAX_LOCATION_AGE_S


# With GpsKeeper the fix is refreshed every minute and GMS takes it about every 30 min.
KEEPER_MAX_LOCATION_AGE_S = 3600
KEEPER_MAX_STALL_S = 2 * 3600


def location_problems(readings, keeper_sensors):
    """DEGRADED reasons from the AWS location readings of one day (QA-84).

    A receptor with GpsKeeper must keep its fix under an hour old and keep feeding it to
    earthquake_alerting. One without it only has to stay under the ~24 h blind limit.
    """
    problems = []
    by_sensor = {}
    for reading in sorted(readings, key=lambda r: r["at"]):
        by_sensor.setdefault(reading["sensor"], []).append(reading)
    for sensor in sorted(set(by_sensor) | set(keeper_sensors)):
        mine = by_sensor.get(sensor, [])
        if not mine:
            problems.append(f"{sensor}: no GMS location readings")
            continue
        limit = KEEPER_MAX_LOCATION_AGE_S if sensor in keeper_sensors else CONTROL_MAX_LOCATION_AGE_S
        if any(r["age_s"] is None for r in mine):
            problems.append(f"{sensor}: GMS has no location")
        elif max(r["age_s"] for r in mine) > limit:
            problems.append(f"{sensor}: GMS location {max(r['age_s'] for r in mine) / 3600:.1f} h "
                            f"(> {limit / 3600:.0f} h)")
        if sensor in keeper_sensors and deliveries_stall_s(mine) > KEEPER_MAX_STALL_S:
            problems.append(f"{sensor}: earthquake_alerting deliveries flat for "
                            f"{deliveries_stall_s(mine) / 3600:.1f} h (> 2 h)")
    return problems


def deliveries_stall_s(readings):
    """Longest time the delivery count stood still. A reboot resets the count, and the clock.

    ponytail: a stall that crosses midnight is counted from the day's first reading.
    """
    longest, since, previous = 0, None, None
    for reading in readings:
        rebooted = previous is not None and reading["uptime_s"] is not None and previous["uptime_s"] is not None \
            and reading["uptime_s"] < previous["uptime_s"]
        grew = previous is not None and (reading["deliveries"] or 0) > (previous["deliveries"] or 0)
        if since is None or rebooted or grew:
            since = reading["at"]
        longest = max(longest, reading["at"] - since)
        previous = reading
    return longest


# Our part of a real alert: listener capture to push received by the monitor (QA-86).
# Measured 0.54 s on the 24-sep quake once both clocks were corrected (0.78 s from the post).
OUR_PART_MAX_S = 2.0
# The emulator clock drifts about 30 ms/h, so an older skew reading is off by more than we measure.
CLOCK_READING_VALID_S = 6 * 3600


def emulator_skew_s(text):
    """Emulator clock minus host clock from a "clock <host> <emulator> <host>" line. Negative = behind."""
    match = re.search(r"clock (\d+\.\d+) (\d+\.\d+) (\d+\.\d+)", text)
    if not match:
        return None
    before, emulator, after = map(float, match.groups())
    return emulator - (before + after) / 2


def sntp_offset_s(text):
    """Seconds to add to the Mac clock to get true time, from `sntp` ("+0.184773 +/- 0.109443 host ...")."""
    match = re.search(r"^([+-]\d+\.\d+) \+/- ", text, re.MULTILINE)
    return float(match.group(1)) if match else None


def nearest(readings, t, key):
    """The key of the reading closest to t, if one is within CLOCK_READING_VALID_S."""
    near = [r for r in readings if r.get(key) is not None and abs(r["at"] - t) <= CLOCK_READING_VALID_S]
    return min(near, key=lambda r: abs(r["at"] - t))[key] if near else None


def our_part_s(captured, received, emulator_skew, mac_offset):
    """Listener capture (emulator clock) to push received (Mac clock), in true time. None if it never arrived.

    ponytail: an unknown skew is taken as 0, which overstates our part by the emulator's lag: loud, not silent.
    """
    if received is None:
        return None
    return (received + (mac_offset or 0)) - (captured - (emulator_skew or 0))


def usgs_origin(origin, catalog):
    """USGS's millisecond origin for the quake Google timed at `origin` (whole seconds), if USGS has it.
    SGC only gives whole seconds, and USGS misses most quakes under M4.5."""
    near = [e for e in catalog if e["source"] == "usgs" and abs(e["time"] - origin) <= MATCH_WINDOW_S]
    return min(near, key=lambda e: abs(e["time"] - origin))["time"] if near else None


def summarize_latencies(values):
    if not values:
        return None
    return {"n": len(values), "p50": percentile(values, 0.5), "p95": percentile(values, 0.95),
            "p99": percentile(values, 0.99), "max": max(values), "mean": statistics.fmean(values)}

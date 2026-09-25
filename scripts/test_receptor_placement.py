#!/usr/bin/env python3
"""Checks receptor-placement.py: which demand counts, how it is grouped and scored, the
spacing, and that nothing is marked for creation without a budget.

Run: python3 scripts/test_receptor_placement.py
"""
import contextlib, importlib.util, io, json, os, tempfile

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("placement", os.path.join(SCRIPTS, "receptor-placement.py"))
placement = importlib.util.module_from_spec(spec)
spec.loader.exec_module(placement)

VERIFIED = "2026-09-25T00:00:00Z"


def phones(cell, count, verified=True, sensor_ids=()):
    return {f"{cell}-{n}-{verified}-{len(sensor_ids)}": {
        "platform": "ios", "sensor_ids": list(sensor_ids), "demand_cell": cell,
        "verified_at": VERIFIED if verified else None} for n in range(count)}


NO_SENSORS = {"sensors": []}
NO_ALERTS = {"period": {"years": 2.85}, "alerts": []}
# One alert a year whose BeAware circle covers Bucaramanga (7.1, -73.1).
BUCARAMANGA_ALERTS = {"period": {"years": 1.0},
                      "alerts": [{"lat": 6.8, "lon": -73.0, "be_aware_km": 60, "mag": 4.8, "at": "x"}]}

# --- which demand counts --------------------------------------------------------------

devices = {**phones("71,-732", 3), **phones("71,-732", 5, verified=False),
           **phones("50,-760", 2), **phones("40,-750", 2, sensor_ids=["chaparral"]),
           **phones("40,-750", 1)}
assert placement.demand_by_cell(devices) == {"71,-732": 3, "40,-750": 3}, placement.demand_by_cell(devices)
# A phone that moved into coverage registers without a cell (the gateway stores null).
covered = {"x": {"sensor_ids": ["chaparral"], "demand_cell": None, "verified_at": VERIFIED}} | phones("40,-750", 2)
assert placement.demand_by_cell(covered) == {}, placement.demand_by_cell(covered)
# Reviewers and testers abroad: Cupertino and Madrid never count. San Andrés and Leticia do.
abroad = {**phones("373,-1221", 5), **phones("404,-37", 5), **phones("125,-818", 3), **phones("-42,-700", 3)}
assert placement.demand_by_cell(abroad) == {"125,-818": 3, "-42,-700": 3}, placement.demand_by_cell(abroad)
print("PASS demand: verified phones only, 3 or more per cell, limited phones (sensors + cell) count, Colombia only")

# --- grouping and score ---------------------------------------------------------------

# Two cells 11 km apart go together; the centroid leans to the busier one.
devices = {**phones("71,-732", 9), **phones("70,-732", 3)}
[proposal] = placement.propose(devices, NO_SENSORS, BUCARAMANGA_ALERTS, 0, 25)
assert proposal["expected_users"] == 12
assert 7.02 < proposal["lat"] < 7.15 and abs(proposal["lat"] - 7.125) < abs(proposal["lat"] - 7.05)
assert proposal["alerts_per_year"] == 1.0 and proposal["score"] == 12.0

# No alert in the period: the floor still lets a crowd get a receptor (Caribbean coast).
[proposal] = placement.propose(phones("109,-749", 40), NO_SENSORS, NO_ALERTS, 0, 25)
assert proposal["alerts_per_year"] == 0 and proposal["score"] == 4.0
# ...but a few phones with no hazard do not.
assert placement.propose(phones("109,-749", 20), NO_SENSORS, NO_ALERTS, 0, 25) == []
# An alert counts only inside its own BeAware distance: 40 km away with a 39 km radius does not.
edge = {"period": {"years": 1}, "alerts": [{"lat": 0.0, "lon": 0.0, "be_aware_km": 39.0}]}
north_40km = 40 / 111.195
assert placement.alerts_per_year(north_40km, 0.0, edge) == 0
assert placement.alerts_per_year(north_40km, 0.0, {**edge, "alerts": [{**edge["alerts"][0], "be_aware_km": 41.0}]}) == 1
print("PASS score: phones × alerts per year, grouped within 31 km, hazard floor")

# --- spacing --------------------------------------------------------------------------

near_existing = {"sensors": [{"id": "bucaramanga-a", "lat": 7.12, "lon": -73.12}]}
assert placement.propose(phones("71,-732", 10), near_existing, BUCARAMANGA_ALERTS, 0, 25) == []
# Two groups 35 km apart: both score, only the better one is proposed.
devices = {**phones("71,-732", 10), **phones("68,-731", 4)}
proposals = placement.propose(devices, NO_SENSORS, BUCARAMANGA_ALERTS, 0, 25)
assert [p["expected_users"] for p in proposals] == [10], proposals
print("PASS spacing: 40 km from existing receptors and from each other")

# --- budget ---------------------------------------------------------------------------

devices = {**phones("71,-732", 10), **phones("45,-760", 60), **phones("109,-749", 50)}
proposals = placement.propose(devices, NO_SENSORS, BUCARAMANGA_ALERTS, 0, 25)
assert len(proposals) == 3 and not any(p["auto_create"] for p in proposals), "created without a budget"
proposals = placement.propose(devices, NO_SENSORS, BUCARAMANGA_ALERTS, 50, 25)
assert [p["auto_create"] for p in proposals] == [True, True, False], proposals
assert [p["score"] for p in proposals] == sorted((p["score"] for p in proposals), reverse=True)
print("PASS budget: 0 only proposes, otherwise best scores first until it runs out")

# --- the real alert list and main() ---------------------------------------------------

with open(os.path.join(SCRIPTS, "aea-alerts-colombia.json")) as handle:
    real_alerts = json.load(handle)
assert placement.alerts_per_year(3.7236, -75.4836, real_alerts) > 0, "Chaparral had alerts in the period"

with tempfile.TemporaryDirectory() as directory:
    paths = {name: os.path.join(directory, f"{name}.json") for name in ("devices", "sensors", "out")}
    with open(paths["devices"], "w") as handle:
        json.dump({**phones("71,-732", 10), **phones("373,-1221", 4), **phones("404,-37", 1, verified=False)}, handle)
    with open(paths["sensors"], "w") as handle:
        json.dump(NO_SENSORS, handle)
    os.environ.pop("AUTO_RECEPTOR_BUDGET_USD", None)
    printed = io.StringIO()
    with contextlib.redirect_stdout(printed):
        assert placement.main(paths["devices"], paths["sensors"],
                              os.path.join(SCRIPTS, "aea-alerts-colombia.json"), paths["out"]) == 0
    with open(paths["out"]) as handle:
        report = json.load(handle)
    assert report["budget_usd"] == 0 and len(report["proposals"]) == 1
    assert report["ignored_outside_colombia"] == 4, report
    assert "ignored_outside_colombia=4" in printed.getvalue()
    assert report["proposals"][0]["auto_create"] is False
    assert "RECEPTOR_PROPOSED lat=" in printed.getvalue() and "auto_create=False" in printed.getvalue()
    # Before any phone registered, there is no devices.json yet.
    with contextlib.redirect_stdout(io.StringIO()):
        placement.main(os.path.join(directory, "missing.json"), paths["sensors"],
                       os.path.join(SCRIPTS, "aea-alerts-colombia.json"), paths["out"])
    with open(paths["out"]) as handle:
        assert json.load(handle)["proposals"] == []
print("PASS main: writes the proposals and one RECEPTOR_PROPOSED line each, no devices file is fine")

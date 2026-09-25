#!/usr/bin/env python3
"""Proposes new receptors where phones without coverage are, weighted by quake hazard.

    receptor-placement.py <devices.json> <sensors.json> <alerts.json> <proposals.json>

Demand is the 0.1° cell a phone registers when no receptor covers it, or covers it only for
strong quakes (docs/ios-contract.md, "Outside coverage"), counted only once APNs accepted a push to that phone (verified_at).
Cells within 31 km (the M4.5 radius) are grouped; each group scores
    phones × max(AEA alerts per year at its centroid, HAZARD_FLOOR_PER_YEAR)
with alerts from Allen et al. 2025 (scripts/aea-alerts-colombia.json), counted as in
docs/siting-pilot.md: an alert counts where the point is within its BeAware distance.

It only proposes. Every proposal is `auto_create: false` unless AUTO_RECEPTOR_BUDGET_USD
(default 0) covers it at RECEPTOR_MONTHLY_USD each; creating the receptor is a separate
step (devops), and nothing here spends money. Run daily on the gateway host.
"""
import json
import math
import os
import sys
from collections import Counter
from datetime import datetime, timezone

GROUP_RADIUS_KM = 31
MIN_SPACING_KM = 40
# A cell with fewer phones is neither used nor shown: 11 km in the countryside can be one house.
MIN_CELL_PHONES = 3
# Without it, a region with no alert in 2021-2024 (the Caribbean coast) never gets a
# receptor however many people ask.
HAZARD_FLOOR_PER_YEAR = 0.1
# 30 phones at the floor, or ~9 at one alert a year.
MIN_SCORE = 3.0
# Colombia with San Andrés, as (lat, lon) min and max. App reviewers and testers abroad register
# cells too; they must not pull a receptor to Cupertino.
# ponytail: a box, not the border; it also takes in bits of the neighbours, fine for now.
COLOMBIA_BOX = ((-4.3, -82.0), (13.6, -66.8))


def km_between(lat1, lon1, lat2, lon2):
    to_rad = math.radians
    d_lat, d_lon = to_rad(lat2 - lat1), to_rad(lon2 - lon1)
    h = math.sin(d_lat / 2) ** 2 + math.cos(to_rad(lat1)) * math.cos(to_rad(lat2)) * math.sin(d_lon / 2) ** 2
    return 2 * 6371 * math.asin(math.sqrt(h))


def cell_center(cell):
    lat10, lon10 = (int(part) for part in cell.split(","))
    return (lat10 + 0.5) / 10, (lon10 + 0.5) / 10


def demand_cells(devices):
    """One cell per verified phone. With sensor_ids too it is a "limited" phone: far receptors,
    strong quakes only, and it still asks for a closer one."""
    return [device["demand_cell"] for device in devices.values()
            if device.get("demand_cell") and device.get("verified_at")]


def in_colombia(cell):
    (lat_min, lon_min), (lat_max, lon_max) = COLOMBIA_BOX
    lat, lon = cell_center(cell)
    return lat_min <= lat <= lat_max and lon_min <= lon <= lon_max


def demand_by_cell(devices):
    counts = Counter(cell for cell in demand_cells(devices) if in_colombia(cell))
    return {cell: phones for cell, phones in counts.items() if phones >= MIN_CELL_PHONES}


def alerts_per_year(lat, lon, alerts):
    hits = sum(1 for alert in alerts["alerts"]
               if km_between(lat, lon, alert["lat"], alert["lon"]) <= alert["be_aware_km"])
    return hits / alerts["period"]["years"]


def groups(demand):
    """Greedy: the busiest cell left takes every free cell within GROUP_RADIUS_KM of it.
    ponytail: O(cells²); fine for a country's worth of 11 km cells (~10k)."""
    free = sorted(demand, key=lambda cell: (-demand[cell], cell))
    while free:
        seed_lat, seed_lon = cell_center(free[0])
        members = [cell for cell in free
                   if km_between(seed_lat, seed_lon, *cell_center(cell)) <= GROUP_RADIUS_KM]
        free = [cell for cell in free if cell not in members]
        phones = sum(demand[cell] for cell in members)
        lat = sum(cell_center(cell)[0] * demand[cell] for cell in members) / phones
        lon = sum(cell_center(cell)[1] * demand[cell] for cell in members) / phones
        yield lat, lon, phones


def propose(devices, sensors, alerts, budget_usd, receptor_monthly_usd):
    existing = [(sensor["lat"], sensor["lon"]) for sensor in sensors["sensors"]]
    candidates = []
    for lat, lon, phones in groups(demand_by_cell(devices)):
        rate = alerts_per_year(lat, lon, alerts)
        candidates.append({"lat": round(lat, 4), "lon": round(lon, 4), "expected_users": phones,
                           "alerts_per_year": round(rate, 2),
                           "score": round(phones * max(rate, HAZARD_FLOOR_PER_YEAR), 2)})
    proposals, spent = [], 0.0
    for candidate in sorted(candidates, key=lambda c: -c["score"]):
        if candidate["score"] < MIN_SCORE:
            continue
        taken = existing + [(p["lat"], p["lon"]) for p in proposals]
        nearest = min((km_between(candidate["lat"], candidate["lon"], *place) for place in taken), default=None)
        if nearest is not None and nearest < MIN_SPACING_KM:
            continue
        candidate["nearest_receptor_km"] = None if nearest is None else round(nearest, 1)
        # Never spends by default: a budget of 0 makes every proposal a proposal only.
        candidate["auto_create"] = budget_usd > 0 and spent + receptor_monthly_usd <= budget_usd
        if candidate["auto_create"]:
            spent += receptor_monthly_usd
        proposals.append(candidate)
    return proposals


def main(devices_path, sensors_path, alerts_path, out_path):
    budget_usd = float(os.environ.get("AUTO_RECEPTOR_BUDGET_USD", "0"))
    # Estimate, per emulator: ~1/2 of a spot r8i.large plus disk and traffic.
    receptor_monthly_usd = float(os.environ.get("RECEPTOR_MONTHLY_USD", "25"))
    if budget_usd < 0 or receptor_monthly_usd <= 0:
        sys.exit("AUTO_RECEPTOR_BUDGET_USD must be >= 0 and RECEPTOR_MONTHLY_USD > 0")
    try:
        with open(devices_path) as handle:
            devices = json.load(handle)
    except FileNotFoundError:
        devices = {}
    with open(sensors_path) as handle:
        sensors = json.load(handle)
    with open(alerts_path) as handle:
        alerts = json.load(handle)
    proposals = propose(devices, sensors, alerts, budget_usd, receptor_monthly_usd)
    ignored = sum(1 for cell in demand_cells(devices) if not in_colombia(cell))
    report = {"generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
              "budget_usd": budget_usd, "receptor_monthly_usd": receptor_monthly_usd,
              "ignored_outside_colombia": ignored, "proposals": proposals}
    with open(out_path + ".tmp", "w") as handle:
        json.dump(report, handle, indent=1)
    os.replace(out_path + ".tmp", out_path)
    for proposal in proposals:
        print("RECEPTOR_PROPOSED " + " ".join(f"{key}={value}" for key, value in proposal.items()))
    print(f"placement: {len(proposals)} proposal(s), budget_usd={budget_usd}, "
          f"ignored_outside_colombia={ignored}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))

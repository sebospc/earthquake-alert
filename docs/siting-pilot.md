# Pilot receptors for Colombia

Proposal of 18 receptors, chosen by population × real alerts per year.
2026-09-24. None of this is deployed; `gateway/public/sensors.json` was not touched.

## Result

The 18 receptors cover municipalities with about **18.6 million** inhabitants (plus their
metropolitan area, like Soacha and Bello). Together they would have received **28 distinct alerts**
in the 2.85 years of the dataset: **9.8 per year**, one every ~37 days.

| # | city | lat | lon | population | alerts/year | why |
|---|---|---|---|---|---|---|
| 1 | Bogotá | 4.7110 | -74.0721 | 7,930,000 | 2.5 | a third of the target population; also covers Soacha (22 km) |
| 2 | Medellín | 6.2442 | -75.5812 | 2,640,000 | 1.1 | second city; covers Bello and Itagüí |
| 3 | Bucaramanga | 7.1193 | -73.1227 | 620,000 | 3.5 | the highest rate in the country, because of the Bucaramanga nest |
| 4 | Villavicencio | 4.1420 | -73.6266 | 560,000 | 2.8 | Llanos foothills, second highest rate |
| 5 | Cali | 3.4516 | -76.5320 | 2,290,000 | 0.4 | low rate, but it is the third city |
| 6 | Cúcuta | 7.8939 | -72.5078 | 820,000 | 0.7 | border, no other receptor within 110 km |
| 7 | Ibagué | 4.4389 | -75.2322 | 540,000 | 1.1 | Tolima, capital of the department of the Chaparral swarm |
| 8 | Montería | 8.7479 | -75.8814 | 510,000 | 1.1 | the only Caribbean point with a relevant rate |
| 9 | Pereira | 4.8133 | -75.6961 | 480,000 | 1.1 | Coffee Axis; covers Dosquebradas |
| 10 | Neiva | 2.9273 | -75.2819 | 370,000 | 1.1 | Huila, fault at the edge of the Eastern Cordillera |
| 11 | Santa Marta | 11.2408 | -74.1990 | 550,000 | 0.7 | Caribbean coast; Barranquilla and Cartagena had 0 |
| 12 | Tunja | 5.5353 | -73.3678 | 210,000 | 1.4 | central Boyacá |
| 13 | Barrancabermeja | 7.0653 | -73.8547 | 210,000 | 1.4 | Magdalena Medio, 81 km from Bucaramanga |
| 14 | Pitalito | 1.8537 | -76.0511 | 140,000 | 1.8 | south of Huila, high rate for its size |
| 15 | Popayán | 2.4448 | -76.6147 | 330,000 | 0.7 | Cauca, no other receptor nearby |
| 16 | Sogamoso | 5.7145 | -72.9339 | 120,000 | 1.4 | eastern Boyacá; covers Duitama (17 km) |
| 17 | Girardot | 4.3032 | -74.8037 | 110,000 | 1.4 | upper Magdalena, between Bogotá and Ibagué |
| 18 | Quibdó | 5.6947 | -76.6611 | 130,000 | 1.1 | Pacific; already on AWS |

Chaparral (already on AWS) does not make it by score: 47,000 inhabitants and 0.7 alerts/year. It is
there for the Tolima swarm and it is worth keeping while it lasts. When it dies down, Ibagué
(84 km) covers Tolima.

## How it was computed

- **Alerts:** Allen et al. 2025, *Science*, data on Zenodo
  ([10.5281/zenodo.15498729](https://doi.org/10.5281/zenodo.15498729)), file
  `DataS1-AndroidAlertList-240331-v2.csv`: the 1279 AEA alerts worldwide between
  2021-05-23 and 2024-03-31 (2.85 years). An alert counts for a city if the distance
  from the city center to the estimated epicenter is less than or equal to
  `BeAwareAlertDistancekm`. It is the same method as `docs/fleet-siting.md`, and it gives the same
  figures for the cities that were already there.
- **Population:** DANE, municipal population projections 2018-2035 (post-COVID-19
  update), municipal total 2024, rounded to thousands. **They are approximate**: they must be
  checked against the DANE table before using them outside this document.
- **Selection:** 40 cities were sorted by population × alerts/year and taken in
  order, skipping any within 40 km of one already chosen (the same
  alert covers it, and almost always the same full 31 km radius).

## Limits

- Few events: 1 to 10 alerts per city. A rate of 0.4 against 1.1 can be chance.
  The order of the first 5 is solid; from 10 down, not so much.
- The dataset ends in March 2024. AEA thresholds may have changed.
- The score rewards big cities even with little activity (Cali). If the
  goal is to validate delivery and not to cover people, it is better to sort by rate only.
- The northern Caribbean coast (Barranquilla, Cartagena, Valledupar, Riohacha) had no
  alert in the period. A receptor there brings no alerts, but it does bring coverage if something
  ever happens.
- Each receptor is an emulator of ~3.5 GB of RAM. 18 are ~6 r8i.large machines with
  sequential boot, or 1 server with 128 GB.

## Draft for sensors.json

Not applied. The ids that already exist are kept (`bucaramanga-a`, `quibdo`).

```json
{ "id": "bogota", "name": "Bogotá", "lat": 4.7110, "lon": -74.0721, "public": true },
{ "id": "medellin", "name": "Medellín", "lat": 6.2442, "lon": -75.5812, "public": true },
{ "id": "bucaramanga-a", "name": "Bucaramanga", "lat": 7.1193, "lon": -73.1227, "public": true },
{ "id": "villavicencio", "name": "Villavicencio", "lat": 4.1420, "lon": -73.6266, "public": true },
{ "id": "cali", "name": "Cali", "lat": 3.4516, "lon": -76.5320, "public": true },
{ "id": "cucuta", "name": "Cúcuta", "lat": 7.8939, "lon": -72.5078, "public": true },
{ "id": "ibague", "name": "Ibagué", "lat": 4.4389, "lon": -75.2322, "public": true },
{ "id": "monteria", "name": "Montería", "lat": 8.7479, "lon": -75.8814, "public": true },
{ "id": "pereira", "name": "Pereira", "lat": 4.8133, "lon": -75.6961, "public": true },
{ "id": "neiva", "name": "Neiva", "lat": 2.9273, "lon": -75.2819, "public": true },
{ "id": "santa-marta", "name": "Santa Marta", "lat": 11.2408, "lon": -74.1990, "public": true },
{ "id": "tunja", "name": "Tunja", "lat": 5.5353, "lon": -73.3678, "public": true },
{ "id": "barrancabermeja", "name": "Barrancabermeja", "lat": 7.0653, "lon": -73.8547, "public": true },
{ "id": "pitalito", "name": "Pitalito", "lat": 1.8537, "lon": -76.0511, "public": true },
{ "id": "popayan", "name": "Popayán", "lat": 2.4448, "lon": -76.6147, "public": true },
{ "id": "sogamoso", "name": "Sogamoso", "lat": 5.7145, "lon": -72.9339, "public": true },
{ "id": "girardot", "name": "Girardot", "lat": 4.3032, "lon": -74.8037, "public": true },
{ "id": "quibdo", "name": "Quibdó", "lat": 5.6947, "lon": -76.6611, "public": true }
```

## Demand-driven growth

Built: the demand record in the gateway (`POST /devices` with `demand_cell`) and the daily
proposal job (`scripts/receptor-placement.py`, writes `receptor-proposals.json` and one
`RECEPTOR_PROPOSED` line each). Not built: creating a receptor (devops), the
`new_receptor` push, and reloading `sensors.json` without a restart.
`AUTO_RECEPTOR_BUDGET_USD` defaults to 0, and at 0 nothing is marked for creation.

Goal: a user outside coverage leaves a signal, and enough signal in one area with real
quake risk becomes a receptor there. Today the phone never sends its location, and the app
says so. This design keeps that: the phone sends only a coarse cell, which it computes itself.

1. Demand record. When no receptor is eligible, the app registers with `demand_cell`
   instead of `sensor_ids`. When only far receptors serve it (level "limited", strong quakes
   only), it sends `demand_cell` together with `sensor_ids`, and the cell counts the same
   (`docs/ios-contract.md`). The cell is a 0.1° grid (about 11 km):
   `floor(lat*10),floor(lon*10)`, for example `"37,-755"`. It lives on the device record,
   so there is one cell per device, no extra id, and it goes away with the token (410 or
   DELETE). The app shows the same "Tu zona todavía no tiene cobertura." as today.
2. Placement. A daily job on the host groups demand cells within 31 km of each other. The
   score is devices × alerts per year at the demand-weighted centroid (Allen et al. data,
   same method as above). The hazard has a floor, otherwise the Caribbean coast can never
   get a receptor however many users it has. It places one (id: nearest town) when the
   score passes the threshold, it is 40 km or more from any receptor, and the monthly
   budget cap is not reached. Above the cap, a person approves.
3. More receptors at one site. Users per receptor is not a limit: 50k APNs went out in under
   2 s. A second receptor at the same place is for redundancy only, on another host or AZ,
   once the site has real users. No new API: own id, same coordinates; the app already
   registers the 2-3 closest and the gateway already sends one push per quake per phone.
4. Provisioning time. Boot, the GMS update and the `earthquake_alerting` registration take
   about 15-20 min, but the daily job and a possible new host dominate: hours to days.
   Meanwhile the app keeps saying "no coverage". A receptor becomes `public` only after
   its first `aea_ok=true`; then devices with a cell within 78 km get a coverage push.
5. Abuse and cost. Demand counts only after one push to that token got a 200 from APNs,
   so invented tokens never count (APNs rejects them). There is one cell per device, the
   /devices IP limit applies, App Attest later. The budget cap bounds the worst case in
   money. Web push subscriptions are free to create in bulk: no PWA demand in v1. A cell
   is only used or shown with 3 or more devices.

Changes needed:
- `POST /devices`: accept `demand_cell` with no `sensor_ids` (since 2026-09-25 also both,
  for "limited"), returning `201 {"sensor_ids": [], "demand_cell": ...}`. Leaving coverage re-registers
  with a cell instead of DELETE. ios-contract: new field, new step in the location flow.
- Coverage push: `kind: "coverage"` with `reason: "new_receptor"`. The app then downloads
  `sensors.json` again and registers.
- Gateway: reload `sensors.json` without a restart (SIGHUP or file watch), and count a
  device's demand only after its first successful push.
- Host: the placement job, and an "add receptor" step in `aws-bootstrap.sh` that adds
  one emulator without touching the running ones.
- App privacy text: "only the sensor name reaches the server" gains "or an 11 km zone
  when you have no coverage".

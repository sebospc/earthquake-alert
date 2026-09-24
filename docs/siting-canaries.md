# Canary receptor sites

Canaries are production receptors that only the monitor subscribes to. Their job is to give the
certifier frequent real quakes to certify against. The budget is 2 r8i.large hosts with 2 emulators
each. Decided 2026-09-24.

## Final 4

| site | lat, lon | alerts/month | setting | UTC |
|---|---|---|---|---|
| General Santos, Philippines | 6.11, 125.17 | 2.75 | Cotabato trench / Philippine Sea plate, Mindanao | +8 |
| Glan, Philippines (pair) | 5.82, 125.20 | 3.94 | same, 32 km south, on the coast | +8 |
| La Serena, Chile | -29.90, -71.25 | 0.78 | Nazca subduction, flat slab | -3/-4 |
| San Salvador, El Salvador | 13.69, -89.19 | 0.72 | Middle America trench | -6 |

Expected: about 5.7 distinct quakes a month across all four. The Mindanao pair gives 4.2 a month
(quakes that reach either of the two). Of those, 2.5 reach both, and those are the ones the pair
can certify as a control. For comparison, chaparral gets about 0.1 a month.

Put each half of the pair on a different host, for example General Santos + La Serena on one and
Glan + San Salvador on the other. A host outage then takes down one canary of the pair, never both.

Backup: Kokopo, Papua New Guinea (-4.34, 152.26), 1.36/month, New Britain trench, UTC +10.
Dropped: Port Vila, Vanuatu (2.50/month). There are few Android phones there, so Google may not
detect those quakes, and every month that would read as a FAIL.

## The pair

The partner was chosen to share as many of General Santos's alerts as possible. Share of the 99
General Santos alerts in 36 months that also reach the candidate:

| partner | km from General Santos | shared | own alerts/month |
|---|---|---|---|
| Glan | 32 | 92% | 3.94 |
| Malita | 59 | 71% | 2.36 |
| Koronadal | 56 | 64% | 1.81 |
| Kidapawan | 100 | 54% | 1.89 |
| Davao | 117 | 51% | 2.08 |

At the ~100 km first proposed, only about half the quakes reach both, so half the time there is no
control. Being closer loses nothing: the pair checks whether Google alerted the area, not whether
two places feel the same shaking.

Certifier rule (`verify.miss_cause`, pairs set with `MONITOR_CANARY_PAIRS=a:b`). The partner
counts as a control only if it was covered and the quake was inside its own radius as well.
- **Both miss:** Google was silent. It is listed and does not lower the verdict.
- **One misses and the partner captured:** FAIL for the one that missed.
- **Partner down, or the quake outside its radius:** no control, and the normal catalog rules apply.

## How "alerts/month" was counted

Source: USGS FDSN, M ≥ 4.5, 2023-09-24 to 2026-09-24 (36 months). A quake counts when the site is
inside Google's alert radius for that magnitude (`lab.beaware_radius_km`, the same rule the
certifier uses). Query for one site, for example:

    https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=2023-09-24&endtime=2026-09-24&minmagnitude=4.5&latitude=6.11&longitude=125.17&maxradiuskm=800

This is a proxy. Google alerts on its own magnitude estimate, which can be a few tenths away from
the catalog's.

Candidates measured and dropped (alerts/month): Santiago 0.14, Lima 0.25, Ica 0.39,
Guayaquil 0.19, Wellington 0.11, Gisborne 0.19, Izmir 0.17, Malatya 0.19, Heraklion 0.19,
Dushanbe 0.22, Kathmandu 0.11, Bandar Abbas 0.19, Honiara 0.33, Dili 0.28, Managua 0.39,
Manila 0.14, Anchorage 0.06.

## AEA status

The Philippines, Chile and El Salvador are all in the country list of the Android Earthquake Alerts
help page, https://support.google.com/android/answer/9319337 (read 2026-09-24). Indonesia, Japan and
Mexico are not.

## Before counting a site's misses

Colombia works from a Brazil IP with a geo fix and no Google account. Confirm the first real alert
on each new site before its misses count.

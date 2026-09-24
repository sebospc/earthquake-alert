# Where to place the devices, and why

## Summary

Four emulators: Bucaramanga (x2), Villavicencio and Quibdó. Combined expected
rate of one alert every ~55 days.

## How it was chosen

The first version of this analysis used a standard attenuation equation
(Allen, Wald & Worden 2012) over the USGS catalog to estimate in which
cities MMI 3 would be exceeded, which is the BeAware threshold Google documents.
That model put Bucaramanga as the worst site in the country: 0.5 events/year
above MMI 3, and zero above MMI 4.5, because the Bucaramanga nest is about
150 km deep and attenuation penalizes hypocentral distance a lot.

The model was wrong, and we know it because the real data exists.

The Allen et al. 2025 paper in Science published on Zenodo (DOI
10.5281/zenodo.15498729) the full list of the 1279 alerts the AEA system
issued between May 2021 and March 2024, with estimated epicenter and alert
radius in kilometers. Counting how many of those real alerts cover each
city, Bucaramanga goes from the worst site to the best: 10 alerts in 2.85
years, 3.5 per year.

The reason is that Google's alert radius depends on the estimated magnitude and
almost not on depth. The nest events fall practically under
Bucaramanga, so the epicentral distance is a few kilometers and the city
falls inside the radius even if little is felt at the surface. Physics says it is
barely felt; Google's system alerts anyway. For this experiment
what matters is the second.

## Rates measured on real alerts, 2021-2024

| City           | BeAware alerts  | Per year |
|----------------|-----------------|---------|
| Bucaramanga    | 10              | 3.5     |
| Villavicencio  | 8               | 2.8     |
| Bogotá         | 7               | 2.5     |
| Rionegro       | 4               | 1.4     |
| Quibdó         | 3               | 1.1     |
| Nuquí          | 3               | 1.1     |
| Pereira        | 3               | 1.1     |

TakeAction was zero in all Colombian cities in the three years. Only
BeAware alerts are expected, that is, a normal notification. The listener must not
depend on `fullScreenIntent`.

## Fleet size

Cities catch overlapping events, so adding devices does not add rates.
Real union of distinct alerts:

- 3 devices (Bucaramanga, Villavicencio, Quibdó): 6.7/year, one every 55 days
- 4 devices (+ Montería): 7.4/year, one every 50 days
- 5 devices (+ Rionegro): 7.7/year, one every 47 days

Clear diminishing returns. 4 devices are used but the fourth is not a
new city: it is a second emulator in Bucaramanga. A fourth site would add
0.7 alerts/year, while duplicating Bucaramanga answers a question that
no new city answers: whether delivery is reliable device to device
or whether one device can miss an alert another one does receive.

## Prediction of expected alerts

`scripts/lab.py` interpolates the BeAware radius from the empirical table of the dataset
instead of estimating intensities. Validated against the 69 real alerts in
Colombia in the dataset: median error of 0.4 km, p90 of 26.8 km.

That is what turns silence into information. When a quake happens in
the USGS catalog, the watcher computes whether Google's radius reached
any of the devices. If it did and we captured nothing, that is a real
negative result and not an empty wait.

## Known limitations

- The USGS catalog is incomplete in Colombia below M4.5, but
  since AEA does not alert below M4.5 either, the bias does not matter much.
- The alert list goes up to March 2024. AEA coverage and thresholds
  may have changed since then.
- The four emulators were cloned from the same AVD, so they share the Android
  ID. If Google dedups by device, it could deliver to only one. The two
  Bucaramanga emulators serve to detect that: if one captures and the other
  does not while at the same location, the cloning is the problem.

## Tactical change: Tolima swarm, 23-sep-2026

On 21 September a shallow swarm started in Tolima, around
Roncesvalles, San Antonio and Chaparral: six M4.3-4.5 events at 10-20 km
depth in two days, with nothing in the previous 28 days.

The Villavicencio device was moved to Chaparral (3.7236, -75.4836), 24 km
from the swarm centroid. Villavicencio was the weakest Colombian device
of the fleet, and the August M7.4 also showed that it is right at the edge where
Google's radius overestimates: people there reported MMI 2.9, below the
threshold, even though the radius did cover it.

Chaparral was chosen over Roncesvalles, which is 5 km closer to the centroid,
because of population: about 47,000 inhabitants against 6,000. DYFI corroboration
needs someone to report, and in a town of 6,000 a failure of ours would stay
as "sin reportes", which concludes nothing.

It is reversible and temporary. Swarms decay; if the Tolima one dies down without
producing anything, the device should go back to Villavicencio. Only one of the
six events crossed the M4.5 threshold, so the bet is that the sequence
continues or escalates, not on what already happened.

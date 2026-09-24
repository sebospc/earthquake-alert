# Findings

Everything the lab tested or ruled out, with the evidence behind it.
Conclusions are ordered from most to least established.

---

## 1. A real AEA alert reaches an emulator with a fake location

**Confirmed on 23-sep-2026.** Full detail in
[`result-first-capture.md`](result-first-capture.md).

```
15:09:39 COL   quake
15:09:56 COL   com.google.android.gms → channel eew_alert_v2
               "Expect shaking. Initial estimate M4.5 about 12.1 miles away."
```

Package signature `5f2391277b1dbd489000467e4c2fa6af802430080457dce2f618992e9dfb5402`,
which is the Play Services certificate.

What makes it conclusive is not the capture but the control: the other three
emulators, 478 km away or more, received nothing. The BeAware radius of an M4.5 is
31 km and Chaparral was at 19.5 km. If delivery were a broadcast, all four
would have received it. Only the one inside the radius received it, and that device is
inside only because of a coordinate injected with `adb emu geo fix`.

**Google delivers based on the location the device reports, and a fake
location on an emulator is enough.**

Along the way three open risks were ruled out: Google does not exclude
emulators from *delivery*, the simulated SIM that says United States (T-Mobile,
MCC 310260) blocks nothing, and the `network` location provider being null is
irrelevant because AEA reads the fused one.

---

## 2. The emulator does NOT contribute to Google's detection network

**Confirmed.** It is the other direction of the system and the answer is different.

If AEA took part in detection it would have to subscribe to the accelerometer.
It does not. In 500 sensor records covering 18 hours:

```
"earthquake|eew|seismic" in the whole sensorservice dump:   0 matches
```

The two permanent accelerometer connections belong to the Android system, not to
Google:

```
com.android.server.wm.WindowOrientationListener   uid 1000   screen rotation
com.android.server.power.FaceDownDetector         uid 1000   face-down detection
```

The only Google package that touches it, 158 times, is
`com.google.android.location.collectionlib.SensorScanner`, which is the
positioning library, not the earthquake one.

The `earthquake_alerting` component (the same one that requests location every 30 minutes
and that delivered the alert) never registered a sensor.

The alternative explanation was ruled out: the emulator reports `AC powered: true`,
level 100, which is exactly the charging condition Google requires for a
phone to take part in detection.

### What probably explains it

In the same dump this one shows up sampling linear acceleration and rotation vector
at 50 Hz in short bursts:

```
com.google.ccc.abuse.droidguard.events.b
```

DroidGuard is Google's attestation and anti-abuse system. It reads the
motion sensors precisely to decide whether the device is real.
An emulator with a synthetic accelerometer is what that component exists to
detect.

Reasonable reading: Google accepts the emulator as a recipient but excludes it
from the detection network. Consistent from their side: a fake receiver harms
nobody, a fake sensor does.

---

## 3. Injecting sensors is technically possible, but useless today

The emulator console exposes sensor injection and it works:

```
acceleration = 0:9.77631:0.812349      before
acceleration = 1.5:2.5:9               after 'sensor set'
```

Over a persistent socket to the console port we reach **150 Hz effective**,
6.7 ms per sample, plenty to sample a P wave. The emulator
accelerometer declares `maxRate=100.00Hz`, so the real ceiling is 100 Hz.

So the idea of taking the iPhone accelerometer and injecting it into the Android
works mechanically. What blocks it is finding 2: **nobody is reading
that sensor for seismic purposes**, so the data would go nowhere.

### The obstacles that would remain, if it is ever unblocked

**Timestamp.** Android stamps the `SensorEvent` at the moment of
injection. There is no way to say "this sample is from 3 seconds ago". Since
Google locates the epicenter by comparing P-wave arrival times between
phones, and P waves travel at ~6 km/s, network latency turns
directly into location error:

| network delay | epicenter error introduced |
|----------------|-------------------------------|
| 0.5 s | 3 km |
| 2 s | 12 km |
| 5 s | 30 km |

With few contributions it gets diluted. With many, it biases the computation systematically.

**Only still devices count.** Google's paper is explicit: it filters for
stationary devices, typically charging at night. A phone in a
pocket is noise.

**The blast radius is outside the product.** Injecting synthetic data into a
system that fires alerts for millions of people means that a bug of ours
(clock offset, stuck value, retry burst) does not break the app: it
wakes up someone else's city or shifts the epicenter of a real alert. Google
reports 3 false alarms in 3 years, two from thunderstorms.

**Next experiment if resumed:** check with a physical Android whether *it*
registers the accelerometer for AEA. Ten minutes with a borrowed phone and the
same `dumpsys sensorservice`. If a real phone does not do it either, phase 2 does not
exist by any path.

---

## 4. How often AEA updates the location

From the `dumpsys activity service com.google.android.gms` dump:

```
earthquake_alerting  Request[@30m BALANCED_POWER_ACCURACY,
                             minUpdateInterval=5m,
                             minUpdateDistance=1000.0,
                             THROTTLE_NEVER]
```

**AEA only learns that the device moved if it traveled more than 1 km, and
at most every 5 minutes.**

It is a hard limit for any design that follows a user's location in
real time: chasing accuracy below 1 km or below 5 minutes makes
no difference in what Google delivers. Better to use it than to
fight it: it cuts a lot of the traffic the iPhone needs to send.

---

## 5. Where sensors are worth having, measured on real alerts

Base: the 1279 real AEA alerts from Allen et al. 2025
([Zenodo 15498729](https://doi.org/10.5281/zenodo.15498729)), 65 of them with
epicenter in Colombia.

### Google's alert radius is a table, not a model

The magnitude → BeAware radius relation is almost deterministic, median equal to the
maximum with 1 km of spread:

```
M4.5 → 31km    M5.0 → 78km     M5.5 → 197km    M6.0 → 346km
M6.5 → 443km   M7.0 → ~560km   M7.8 → 669km
```

Interpolating that table predicts the real radius with a **median error of 0.4 km** over
the 69 Colombian alerts in the dataset. It is implemented in
`scripts/lab.py:beaware_radius_km`.

### Google's radius barely corrects for depth

A standard attenuation model (Allen, Wald & Worden 2012) put Bucaramanga
as the worst site in Colombia, 0.5 events/year above MMI 3, because the nest is
~150 km deep. The real alerts say the opposite: **3.5 per year, the
best in the country.**

The reason is that the radius depends on the estimated magnitude and almost not on
depth. The nest events fall practically under the city, so
the epicentral distance is a few kilometers and it falls inside the radius even if
little is felt at the surface.

When physics and empirical data disagree about how a
system behaves, the data wins: what matters is not how much is felt, it is when Google decides
to alert.

### TakeAction does not happen in Colombia

Zero TakeAction alerts in the 65 Colombian ones in three years. Only BeAware, that is,
a normal notification. The real capture confirms it: `has_full_screen_intent: false`.
A listener that depends on `fullScreenIntent` captures nothing in Colombia.

---

## 6. External corroboration: what exists and what does not

**There is no authoritative source of issued AEA alerts.** Google does not publish it.
USGS asked for it in public. The only list that exists is the paper's and it ends
in March 2024.

What does help, from strongest to weakest:

**USGS DYFI.** Public reports aggregated in 10 km cells. Intensity
observed by people, not modeled, at the exact location of each device. Since
the BeAware threshold is MMI 3, comparing against it tells whether the alert was
justified there. It is the piece that turns a silence into data.

Tested on the M7.4 of 10-aug with zero simulated captures:

| city | MMI felt | reports | verdict |
|--------|-------------|----------|----------|
| Quibdó | 7.8 | 4 | false negative |
| Bucaramanga | 4.7 | 10 | false negative |
| Villavicencio | 2.9 | 2 | below threshold |

Villavicencio is the case that justifies the whole mechanism: Google's radius
(596 km) covered it, but people reported below the threshold. Without data from
people, that absence would have counted as our own failure.

**Press by region,** via Google News RSS without a key. Only covers big
events; an M4.8 does not make a story.

**Reddit:** ruled out, it blocks unauthenticated requests with HTTP 403.

**A person on site** is still the only direct source for most
M4.5-5.5 events. It cannot be built from here.

---

## 7. USGS is not enough as a catalog for Colombia

The quake that triggered our capture **never appeared in USGS**. Colombia falls
below its detection threshold for M<4.5.

Also, the catalog is demonstrably incomplete below M4.5: there are
more M4.5 events than M4.0, which is impossible and gives away the cutoff.

And Google alerts with **its own** magnitude estimate, which differs from USGS
by tenths in either direction. That is why the poller queries from M4.0 and not
from M4.5, and records as `NEAR_MISS` what falls in between. Even so there are Google alerts
for quakes USGS never lists. **The SGC catalog is the one
we would need.**

---

## 8. Latency: what this is really good for

We captured at +17.6 s from origin. The S wave travels at ~3.5 km/s:

| distance | S wave arrives | net warning |
|-----------|--------------|------------|
| 20 km | 6 s | −12 s |
| 50 km | 14 s | −3 s |
| 100 km | 29 s | +11 s |
| 200 km | 57 s | +40 s |
| 300 km | 86 s | +68 s |

Our own event proves it: at 19.5 km the alert said "Expect shaking"
but the shaking had passed 12 seconds before, and that is why the second message
said "You may have felt shaking".

**This only gives useful warning beyond about 80 km.** For the quake right
underneath there is nothing to do, with this app or any other. Google itself
reports that only 36% of its users get the alert before feeling the
shaking.

It is not a defect to hide. It is what the product has to say upfront.

---

## 9. What the emulator simulates badly, and did not matter

| signal | value | did it matter? |
|-------|-------|----------|
| fused location | the injected one | it is the one that counts |
| time zone | America/Bogota | — |
| SIM / carrier | T-Mobile, MCC 310260, country `us` | blocked nothing |
| network location | null | irrelevant, AEA reads the fused one |
| public IP | NAT through the Mac, Colombia | matches the location |

The argument that the SIM cannot be decisive: AEA works on WiFi-only tablets,
with no SIM at all. The real capture confirmed it.

---

## 10. Google alerts with its own magnitude, even below M4.5

The 24-sep 01:19 UTC capture in Chaparral (Google: M4.46, 18.9 km) matches a quake the SGC measures as **M3.6**. The 23-sep 20:09:40 UTC one is the SGC's M4.5.

Consequence: captures and catalog are matched by time and place, never by magnitude. The catalog that works for Colombia is the SGC's (`api.sgc.gov.co/biweekly/biweekly_earthquakes`, 14-day window or less, Bogotá time). USGS has neither of the two quakes.

---

## 11. AWS without a Google account receives the real early alert (24-sep-2026)

Quake of 24-sep at 16:46:33 UTC in Chaparral, M4.48 according to Google.

| receptor | account | image / IP | early alert | later notice |
|---|---|---|---|---|
| AWS chaparral | none | x86_64 / Brazil | **+18.1 s** (emulator clock corrected by 1.70 s) | +4.3 min |
| Mac chaparral | personal | arm64 / Colombia | did not arrive | +40 s |

- Validated: no Google account, no Colombian IP and no ARM image needed.
- Measured end-to-end latency (clocks corrected, QA hop breakdown in `docs/qa/load.md`): origin → push received ≈ 18.8 s. Google takes ~18.1 s, our system ~0.78 s (listener 0.24, to gateway 0.24, to push service 0.37 s). The earlier "~16.6 s + ~2 s" came from the emulator clock running 1.70 s behind.
- Still not explained why the Mac did not get the early alert.
- The "a ~16 km" text was the distance to the receptor, not to the user. It is removed.

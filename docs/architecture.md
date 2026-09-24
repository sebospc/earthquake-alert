# Architecture: bringing AEA alerts to the iPhone

Scope: **reception only**. Contributing to Google's detection network was
ruled out by evidence, not by a product decision; see finding 2 in
[`findings.md`](findings.md). The emulator receives alerts but Google does not read its
sensors, so there is nothing to contribute that way.

That simplifies the risk a lot: this system **only reads**. A bug of ours degrades
the service for our own users; it does not fire a false alarm at a
city.

## General shape

```
iPhone  --location-->  backend  --geo fix-->  Android emulator
                                                     |
                                    captures eew_alert_v2 / eew_update
                                                     v
                                              gateway (dedup, HMAC)
                                                     |
                                                   APNs
                                                     v
                                                  iPhone
```

## The decision that sets the cost

There are two models and they differ by two orders of magnitude.

### Measured on 4,800 simulated users and the 65 real alerts in Colombia

| sensor spacing | sensors | hits | missed alerts | extra alerts |
|---|---|---|---|---|
| 5 km | 1748 | 99.9% | 0.03% | 0.04% |
| 10 km | 764 | 99.9% | 0.07% | 0.06% |
| 20 km | 296 | 99.7% | 0.13% | 0.15% |
| 30 km | 172 | 99.6% | 0.26% | 0.14% |
| 50 km | 78 | 99.3% | 0.46% | 0.25% |

"Hits" compares *the user should have received it* against *the closest sensor
received it*.

### Cost

> Corrected on 2026-09-23: in steady state an emulator uses ~10% of a core
> and ~5.7 GB of RAM. The cost is set by RAM and it is about 4 times lower than the one
> below. New numbers in [`decision.md`](decision.md).

Measured reference: our Mac runs 4 emulators with load 16 on 12 cores,
so ~3 cores and ~5 GB per emulator. A server with 64 cores and 256 GB
holds about 20.

```
grid of 78 sensors       →   4 servers      →  ~USD 2,000/month  for ALL users
one emulator per user    →   1,000 users    →  ~USD 25,000/month and grows linearly
```

At 10,000 users the grid costs USD 0.20 per user per month. The per-user
model costs USD 25 per user per month forever, and no subscription
price covers it.

**Recommendation: shared grid.** It costs 0.7 percentage points of
accuracy and saves two orders of magnitude. A user misses one in 200
alerts that were theirs, and those are almost always the ones right at the
edge of the radius, where shaking is minimal by definition.

The per-user model is still valid if accuracy turns out to be a
hard requirement, for example because of regulation. It is better to decide before
building, because it changes the whole backend.

## The limit neither model can cross

```
earthquake_alerting  Request[@30m BALANCED_POWER_ACCURACY,
                             minUpdateInterval=5m, minUpdateDistance=1000.0]
```

**AEA only notices that the device moved if it traveled more than 1 km, and at
most every 5 minutes.**

Direct consequences:

- The iPhone does not have to send its location continuously. Sending it when it moved
  more than 1 km is enough, and it also saves battery.
- Chasing accuracy below 1 km makes no difference in what
  Google delivers. It is wasted work.
- A user moving fast has up to 5 minutes of lag between where they
  are and where Google thinks they are. At 80 km/h that is 6 km of error. There is no way
  to fix it from the outside.

That last point weakens the per-user argument a lot: when
moving, accuracy is lost anyway, and at rest the grid already gets
99.3% right.

## Deduplication

Two sensors inside the radius of the same quake both capture. Without dedup, the
user gets it twice.

The key has to come from the structured extras, not from the text:

```
TIME_OCCURRED_EXTRA   java.lang.Long     quake origin
MAGNITUDE_EXTRA       java.lang.Float
DISTANCE_EXTRA        java.lang.Double   varies per sensor, do NOT use in the key
```

`CaptureService` already stores them. The natural key is `TIME_OCCURRED_EXTRA` plus
rounded magnitude; the distance changes with the sensor and would break the dedup.

Watch out for `eew_update`: Google sends a second notification minutes later
about the same quake, with the same `tag`. They are different messages with a different
purpose (one warns before, the other confirms after) and we need to decide if the
user gets both. Forwarding the update late, when everything is over, annoys
more than it helps.

## Subscription by region

The user does not get the whole country. If someone in Bogotá gets alerts from Nariño,
they uninstall within a week.

## Provider

The fact that matters: **AWS only allows nested virtualization on
`.metal` instances**, ~USD 1,600/month. GCP allows it on normal N1/N2 VMs with a special
license, Azure on the Dv3/Ev3 series. For running emulators, AWS is the worst of
the three.

```
6 emulators on AWS .metal        ~USD 1,600/month
6 emulators on GCP with nested   ~USD   300/month
6 emulators on a Mac mini         USD   700 once
```

Since the fake location works, the sensors do not need to be geographically
distributed: they can all be in the same room. For a small fleet,
own hardware beats the cloud. For a grid of 78, dedicated servers
with nested virtualization.

The gateway does go to the cloud and it is cheap: a USD 5 Lightsail nano is enough, and
the current account credentials already allow it.

## What must be solved before building

This is not technical and it can kill the product. It goes first, not last.

**Apple.** Safety and emergency apps get stricter review. An app
that promises earthquake warnings and can fail silently is a candidate for rejection and,
worse, for removal after it is published.

**Colombia.** Public emergency alerting is a State function. UNGRD and SGC
are the authorities. Issuing emergency alerts to the public without authorization is
regulated ground.

**Google.** Extracting their alerts with a `NotificationListenerService` on
emulators with a spoofed location and retransmitting them is against their terms,
almost surely. The method does not survive scrutiny.

**Civil liability.** If someone relies on it and it fails.

Possible paths: position it as informational and not as a life-safety early warning
system, or seek an agreement with the SGC. It is a product decision and
it should be made before writing the backend.

## What the product has to say upfront

From finding 8: this **only gives useful warning beyond about 80 km** from the epicenter.
Closer, the shaking arrives before the alert. The extra hop to the iPhone pushes
that threshold even farther.

Google itself reports that only 36% of its users get the alert before
feeling the shaking. Promising more than that is lying, and in a safety app
lying has consequences that are not only about reputation.

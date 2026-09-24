# Result: a real AEA alert reached an emulator with a fake location

23 September 2026. The central hypothesis of the lab was confirmed
24 hours after starting, not after two months.

## What happened

```
23-Sep 15:09:39 COL   quake
23-Sep 15:09:56 COL   com.google.android.gms posts on channel eew_alert_v2
                      "Earthquake nearby"
                      "Expect shaking. Initial estimate M4.5 about 12.1 miles away."
23-Sep 15:13:56 COL   second notification, channel eew_update
                      "Earthquake at 3:09 PM"
                      "You may have felt shaking. Initial estimate M4.5 about 12.1 miles away."
```

The alert went out **17.6 seconds** after the quake origin. The device that
received it is an Android emulator running on a Mac in Medellín, with its
location mocked in Chaparral, Tolima, 19.5 km from the epicenter according to
Google's own estimate.

## Why it is conclusive

**The package signature.** `com.google.android.gms`, signer SHA-256
`5f2391277b1dbd489000467e4c2fa6af802430080457dce2f618992e9dfb5402`. It is the
Play Services certificate, not something we could have made up.

**The control.** The other three emulators received nothing. Bucaramanga is
478 km away, Quibdó and Hinatuan even farther, and the BeAware radius for an M4.5
is 31 km. If delivery were a broadcast to everyone with the app, all
four would have received it. Only the one inside the radius received it, and that
device is "inside" only because of a fake coordinate injected with
`adb emu geo fix`.

That is what answers the question: **Google delivers alerts based on the
location the device reports, and a mocked location on an emulator
is enough.**

## What was ruled out along the way

Three risks that were open and that this single event closes:

- Google does not exclude emulators from alert delivery.
- The simulated SIM that says United States (T-Mobile, MCC 310260) blocks
  nothing. The reported location counts, not the carrier.
- The `network` location provider being null does not matter either. AEA reads the
  fused one, and the injected coordinate is there.

## Useful technical detail

The notification is BeAware, `has_full_screen_intent: false`, as the
Allen et al. dataset predicted: TakeAction was zero in Colombia in three years.

Play Services sends the real numbers in structured extras that the listener
was dropping:

```
MAGNITUDE_EXTRA      java.lang.Float
DISTANCE_EXTRA       java.lang.Double
TIME_OCCURRED_EXTRA  java.lang.Long
```

`CaptureService` was extended to store them. From the next alert on
we will have exact magnitude and distance instead of having to parse the text.

The event does not appear in USGS. Colombia is below its detection
threshold for M<4.5; the SGC catalog is the one that has it. That confirms something
already adjusted: querying USGS from M4.0 instead of M4.5 is not enough
for every case, because there are Google alerts for quakes USGS never
lists.

## State of the experiment

The mechanism question is answered. What follows is different and
simpler: accumulate captures to measure delivery reliability, latency and
coverage. The Hinatuan device, which existed to answer this same question
quickly, is no longer needed for that and can go back to Colombia.

Raw evidence in `evidence/FIRST-REAL-AEA-CAPTURE/`.

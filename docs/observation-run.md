# Observation run

Four Android emulators with a mocked location waiting for a real alert from the
Android Earthquake Alerts system. It runs on this Mac, no cloud.

Three are in Colombia, which is the underlying question. The fourth is in
Hinatuan, Philippines, and exists to answer a different question quickly:
whether the mocked location works to receive alerts. Hinatuan received 81
real alerts in 2.85 years, one every 13 days, against one every 104 days for
Bucaramanga. If in three weeks the Philippines device has captured nothing, the
mechanism does not work and there is no need to wait months for Colombia to know it.

## Why it is not on AWS

The Android emulator needs hardware virtualization. On AWS that means
`.metal` instances, the only ones with nested virtualization. Lightsail does not
have them and does not expose `/dev/kvm`, and this account's credentials only allow
Lightsail. Without KVM the emulator falls back to software emulation and Play Services
on top is unusable. There is no path to the cloud for the Android part with the
current permissions.

What would work well on Lightsail is the relay gateway to iPhone, when that
stage exists. It costs about US$5/month and is not needed yet.

## What runs

- `scripts/fleet.sh`: AVD lifecycle: create, start, provision, status, stop.
- `scripts/lab.py`: watchdog. Reads the log of each emulator, fires the canary, queries USGS and sends notices.
- `scripts/supervise.sh`: brings up whatever went down and runs a cycle every 5 minutes.
- `scripts/test_lab.py`: checks of the classification logic and the radii.

The runtime lives in `~/Library/Application Support/aea-lab/`, not in this repo.
macOS blocks a launchd agent from reading `~/Documents`, and moving the runtime
avoids giving Full Disk Access to `/bin/bash`. This repo is still
the source; after editing a script you have to copy it:

```bash
cp scripts/{fleet.sh,lab.py,supervise.sh,lab.config.json} \
   ~/Library/Application\ Support/aea-lab/scripts/
```

## What it takes for silence to mean something

A passive experiment of months fails in a silent way: nothing arrives and
you do not know if it was because there was no quake, because AEA did not fire, because the
listener died or because the emulator shut down. Three pieces cover that.

**Canary.** Every 24 hours the watcher makes the fixture app post a
notification and checks that the listener captured it. If the canary stops
showing up for 48 hours, it warns that the chain is broken. From that moment
silence does not count as a negative result.

**Heartbeat.** Every cycle checks that each emulator answers. If one has been
down for more than 45 minutes, it sends a notice.

**Prediction.** Every 30 minutes it queries the USGS catalog and, with the table of
BeAware radii taken from Google's real alerts, computes whether the radius
reached any of the devices. If it did, it sends a notice to check whether there was a
capture. That turns a negative into data instead of waiting.

## Operation

```bash
./scripts/fleet.sh status                  # status of the four emulators

# Ask the deployed copy for the report: each copy keeps its own
# state, and the repo one is empty.
python3 ~/Library/Application\ Support/aea-lab/scripts/lab.py report
tail -f ~/Library/Application\ Support/aea-lab/evidence/supervise.log
launchctl unload ~/Library/LaunchAgents/com.earthquakes.aea-lab.plist   # stop everything
./scripts/fleet.sh stop
```

Notices arrive over ntfy to the topic in `scripts/lab.config.json`.
Install the ntfy app and subscribe to that topic.

## Still to configure by hand

The laptop still sleeps when the lid is closed, and asleep we capture nothing.
It needs sudo, so it has to be run:

```bash
sudo pmset disablesleep 1
```

To revert, `sudo pmset disablesleep 0`.

## Cost on the machine

The four emulators keep the load average around 16 on 12 cores, with
about 40% idle CPU and no swap. The Mac stays usable but the fans
will work. If it bothers, going down to three emulators by removing `bucaramanga-b`
from the `FLEET` list in `fleet.sh` and in `lab.py` costs only redundancy,
not coverage.

## Open risks

- **Mocked location.** It is the central hypothesis and it is not proven. What
  is verified is half the path: the fused provider, which is the one
  AEA queries, returns the assigned city, and the GMS
  `earthquake_alerting` subsystem keeps an active subscription and receives those
  deliveries. What we still need to know is whether Google's server accepts that position
  to decide whom to alert.

- **The SIM says another country.** The emulator modem simulates T-Mobile, MCC/MNC
  310260, `gsm.sim.operator.iso-country=us`. So the country signals do not
  match: the location and the time zone say Colombia, the SIM says United
  States. The MCC/MNC is built into the goldfish modem and the
  Play images do not allow root, so it cannot be changed. In our favor, AEA
  works on WiFi-only tablets with no SIM at all, so the system cannot
  be filtering only by carrier country.

  Note: the `network` location provider is null, but that is
  triangulation by towers and BSSIDs, not connectivity. Both network interfaces
  are VALIDATED against Google's servers.
- **Shared Android ID.** All four were cloned from the same AVD. If Google
  dedups by device, it could deliver to only one. The two
  Bucaramanga emulators detect that case.
- **Detectable emulator.** Google could exclude emulators from delivery. There is
  no way to rule it out without a physical control phone.

The three risks point to the same thing: if several expected alerts pass without
a capture, the problem is not seismicity, it is the emulator. Then we need a physical
phone.

## How a real positive is corroborated

The problem: if the fleet captures nothing, it can be that Google did not alert, or that
it alerted but not to emulators. Without external evidence both look the same.
There are three levels, from strongest to weakest.

### 1. Telemetry from the AEA subsystem itself

Play Services registers a location client called `earthquake_alerting`
with a 30-minute interval, and records each delivery:

```bash
adb -s emulator-5554 shell dumpsys activity service com.google.android.gms \
  | grep earthquake_alerting
```

All four emulators have it registered and receiving the mocked location
of their city. That proves the alerts component is alive and consuming
the fake location, which is half of the hypothesis. It does not prove that Google's server
registered that location for delivery.

The watcher checks it every cycle and sends a notice if the subsystem shuts down or if the
position GMS sees drifts more than 25 km from the assigned one. A device that stays
on but whose AEA died looks healthy to any other check, and it is
exactly the case that would ruin the run without us noticing.

### 2. What real people reported (DYFI)

This is the strong piece, and it is structured and free.

USGS collects public reports after each quake and aggregates them in cells
of 10 km: the "Did You Feel It?" product. It gives intensity observed by people,
not modeled, at the exact location of each device. Since Google's BeAware threshold
is MMI 3, comparing what people felt against that threshold tells whether
the alert was justified there.

The watcher queries it 24 hours after each expected alert and gives a verdict per
device (labels as `lab.py` prints them):

- **FALSO NEGATIVO** (false negative): people reported MMI 3 or more and the fleet captured nothing.
  The alert was justified and we missed it. The emulator is the problem.
- **bajo umbral** (below threshold): people reported less than MMI 3. There was no alert to
  capture, and not counting this as a failure is half the value of the system.
- **capturado** (captured): reports above the threshold and a capture of ours. Confirmed positive.
- **sin reportes** (no reports): nobody reported. Nothing can be concluded.

Tested against the M7.4 of 10 August, with zero simulated captures:

| device | MMI felt | reports | verdict |
|--------|-------------|----------|----------|
| bucaramanga-a | 4.7 | 10 | FALSO NEGATIVO |
| quibdo | 7.8 | 4 | FALSO NEGATIVO |
| villavicencio | 2.9 | 2 | bajo umbral |
| hinatuan | no data | - | sin reportes |

Villavicencio is the interesting case. Google's radius (596 km for an M7.4)
covered it, but people there reported 2.9, below the threshold. The radius
overestimates, and without data from people we would have counted that absence as a
failure of ours.

The limitation is that DYFI depends on someone reporting. In small towns or
quakes in the early morning there may be nobody, and then the verdict stays at "sin
reportes".

### 3. Press, by region

Google does not publish a feed of issued alerts; USGS has asked for it in public
and the only list that exists is the paper's, which ends in March 2024.

What does exist is coverage, and Google News RSS does not need a key. The
watcher queries in Spanish for the Colombian devices and in English with
region Philippines for Hinatuan. It only works for big events: an M4.8 does not
produce a single story. It stays as a secondary signal, behind DYFI.

Reddit was ruled out: it blocks unauthenticated queries with HTTP 403.

### 4. A person in Bucaramanga

For most events, between M4.5 and M5.5, there is no source that can be automated.
What works is asking someone who lives there whether they got the alert.
Bucaramanga gets about 3.5 alerts a year, so a single contact willing
to answer "yes" or "no" over WhatsApp turns each expected event into clean
data, and costs nothing.

It is the missing piece and it cannot be built from here.

## Two corrections from 23-sep

**Catalog threshold lowered to M4.0.** Google alerts from M4.5 but with its
own magnitude estimate, which differs from USGS by a few tenths in
either direction. Querying only from M4.5, an event USGS calls M4.3
and Google called M4.6 would have been invisible. Now everything from M4.0 is recorded;
only from M4.5 is it marked as an expected alert, and what falls in between and near
a device is noted as `NEAR_MISS` for context.

The Tolima swarm uncovered it: seven M4.1-4.4 events less than 45 km from
Chaparral that were not being recorded anywhere.

**A device cannot miss an alert older than itself.** Each
device stores `online_since` and the predictor drops earlier events. Without
this the San Antonio M4.5 of 21 September was marked as an expected
alert for Chaparral, which was created on the 23rd, and the corroboration would have
reported it as a false negative 24 hours later. It would have sent us looking for an emulator
bug that does not exist.

The drops stay in the log as `PREDATES_DEVICE`.

# Decision: grid, provider, Android image, compliance and security

Date: 2026-09-23. Everything marked "measured" came from this Mac today. What says
"source" has the link at the end.

## Short conclusion

1. **As designed, the product is not compliant.** It breaks the Android SDK
   license, Google's terms and two Apple App Review rules. As a
   private lab the risk is low. As a public product there is no way
   to defend it.
2. If there is permission one day, the technical answer is already clear: **shared
   grid**, Linux x86_64 with KVM on dedicated servers and the
   **API 35 Google Play** image, which is the only one tested.
3. Slimming down the emulator is not worth it. It saves 11% of RAM.
4. The cost model we had was wrong and exaggerated about 4 times. CPU
   barely matters, what matters is RAM.
5. The best business option is not technical. We have to use the data from this
   lab to ask for formal access, from Google or from the SGC.

## 1. What was measured today

### Real consumption of an emulator

The architecture document assumed 3 cores per emulator, but that number
was taken during boot. In steady state it is something else:

| | CPU (of one core) | RAM on the host |
|---|---|---|
| fleet emulator, 60 s sample | 7-10% | 5.6-5.7 GB |
| slimmed emulator, 1 core, 19 apps disabled | 13% | 5.0 GB |

With a single virtual core, AEA stayed alive anyway: `earthquake_alerting`
registered 72 s after boot.

What was tried to slim it and what happened:

- `-cores 1`: works and AEA stays registered.
- `-memory 1536` and `hw.ramSize=1536M`: the emulator ignores them. The guest
  still sees 2.5 GB, which seems to be the minimum for this image.
- `pm disable-user` of YouTube, Chrome, Maps, Gmail, Photos, the Google app and
  13 more: it applies, but it does not survive a restart of the clone.
- Animations at 0: applies, no measurable effect.

**Conclusion:** the limit is the fixed RAM of the emulator, not the guest
apps. Fighting for that 11% does not change any decision.

### A new capture, and what it shows

```
2026-09-24 01:19:43 UTC  quake, M4.46 according to Google, 18.9 km from Chaparral
2026-09-24 01:25:04 UTC  only eew_update: "You may have felt shaking"
```

It is a different quake from the 15:09 one, and USGS does not have it. It leaves three facts that
change the design:

- **There was no early alert.** Only the after-the-fact notice arrived, 5 min 21 s late.
  If the product forwarded an `eew_update` as an alert, it would tell someone to
  take cover five minutes after the quake.
- **Google warns with M4.46.** The lab's M4.5 threshold is the
  rounded magnitude of the text, not the real one.
- **The `tag` is the same in both quakes** (`BmGrzDxTRr6j7/D96FBC/Q`). If
  dedup is by tag, the second quake is dropped. The key has to be
  `TIME_OCCURRED_EXTRA` plus the notification type.

## 2. Grid or one emulator per user

**Grid.** With the numbers corrected for RAM the difference is even bigger
than before.

Assumption: 6 GB per emulator, 20 emulators per 128 GB server, Hetzner
AX102 at €122/month.

| spacing | sensors | servers | cost/month | missed alerts |
|---|---|---|---|---|
| 50 km | 78 | 4 | ~€490 | 0.46% |
| 30 km | 172 | 9 | ~€1,100 | 0.26% |
| 20 km | 296 | 15 | ~€1,830 | 0.13% |
| per user, 1,000 users | 1,000 | 50 | ~€6,100 | ~0% at rest |

There is also a reason that is not about cost. With a grid, the iPhone can choose
its cell **on the phone itself** and subscribe only to it. That way the
user's location never leaves the phone. That solves half of the
personal data problem and makes Apple's rule 5.1.5 moot, because
the server does not use the location. The per-user model requires sending the
continuous location of every person to an emulator.

Recommendation: 50 km for a pilot and 30 km when there are real users. The
difference between 30 and 20 km is 0.13 points and almost all of it falls at the edge of the
radius, where the shaking is minimal.

## 3. Provider

The emulator needs hardware virtualization. Options that have it today:

| option | virtualization | note |
|---|---|---|
| **Hetzner AX102** (dedicated) | native KVM | €122/month + €269 setup, 128 GB. The cheapest per GB. Only Germany and Finland. |
| AWS C8i/M8i/R8i | nested since feb-2026 | Before it was only `.metal`. Graviton does not work. AWS still recommends metal for sensitive workloads. |
| GCP N2 | nested | Price per GB several times higher than a dedicated server. |
| Own Mac mini | Hypervisor.framework | The only thing tested end to end. Works for a small fleet, not for 78. |

**Recommendation: dedicated Hetzner**, with one condition. Everything tested so far
ran on ARM64 on a Mac, with a Colombian IP. Two things still need measuring
before committing:

1. That the **x86_64** API 35 Google Play image passes the regional gate and
   registers `earthquake_alerting` the same as the ARM64 one.
2. That a **German IP** with a location in Colombia keeps receiving. Today the IP
   and the location match, and we do not know if Google cross-checks them.

They are tested by renting a single AX102 for a month and waiting for a quake with the
same control as today. If the IP turns out to matter, we have to move to AWS in São
Paulo with nested virtualization. It costs more but the IP stays in the region.

## 4. Which Android and which AVD

**API 35, `google_apis_playstore`, Pixel 8, arm64 on Mac and x86_64 on Linux.**
It is the combination that received two real quakes. Moving to API 36
without a reason is not a good idea: repeating the validation costs waiting for another quake.

What cannot be pinned is the Play Services version, because it updates
itself. An update can rename channels or change the format. That is what
the `REVIEW` classification in section 6 is for.

Images ruled out:

- `google_apis` without Play Store: without Play Store there is no GMS update, and
  with the factory GMS (24.23) Colombia came out "not supported in this region".
- ATD (Automated Test Device): no Play Store, same problem.
- Genymotion and others: no certified Play Services.

## 5. Compliance

I am not a lawyer. This is a risk map to take to one, not a legal
opinion.

| rule | what it says | the current design | risk |
|---|---|---|---|
| Android SDK License, 3.1 and 3.4 | license "solely to develop applications"; any other use is prohibited | the emulators are production infrastructure | **breaks it** |
| SDK License, 8.1 | data obtained from Google APIs cannot be distributed without permission | we forward AEA content | **breaks it** |
| Google Terms | do not use others' content without permission; do not hide who you are to violate the terms | Google content + fake location on dozens of devices | **breaks it** |
| Apple 5.2.2 | showing content from a third-party service requires permission under its terms | no permission from Google | almost certain rejection |
| Apple 5.1.5 | location APIs must not be used for emergency services | the per-user model does it | rejection; with grid and cell on the phone it is more defensible |
| Apple Critical Alerts | entitlement with approval | not requested | blocked |
| Ley 1581 de 2012 (habeas data) | prior consent, purpose, processing policy, rules for transfer abroad | location is personal data | can comply; with grid and cell on the phone there is almost no data |
| Ley 1480 de 2011 (consumer) | misleading advertising | promising "early warning" when 64% get it late | can comply if communicated upfront |
| Ley 1523 de 2012 and SNAST bill | risk management; the bill makes the SGC the authority for the official alert | a private app called "alert" | grey today; if the bill passes, it gets worse |

Two things in the lab to fix now, even if it is private:

- **The four emulators use your personal Google account.** If Google bans
  the fleet, you lose the account. They have to move to a dedicated account.
- The evidence logs store that account's email. It happens in the
  Find My Device notifications. The gateway does not forward it, but any
  evidence export has to clean it.

**Verdict:** it is not compliant and no technical adjustment fixes it. What
is missing is a permission, not code.

## 6. Safety: where someone can die and what catches it

There are three ways to do harm. By severity:

1. **Silent failure.** The user thinks they are covered and they are not.
2. **Late alert presented as a warning.** It tells them to take cover when it has already
   passed.
3. **False alarm.** It causes panic and trust is lost.

The rule that comes out of this: **the system has to fail visibly, never
silently.** State of each check:

| risk | check | state |
|---|---|---|
| emulator down | heartbeat, notice at 45 min | existed |
| AEA off inside the emulator | `earthquake_alerting` registered, location within <25 km | existed |
| dead listener | daily canary, notice at 48 h | existed |
| silence that is really a failure | prediction with USGS + DYFI 24 h later | existed |
| alert lost if APNs fails once | the gateway marked "seen" before sending; the retry was dropped as a duplicate | **fixed today**, with test |
| false alarm from text | any GMS notification with "earthquake" counted as an alert | **fixed today**: requires Play Services signature + `eew_*` channel |
| Google renames the channel | before, it was lost silently; now it comes out as `REVIEW` with an urgent notice | **new today**, with test |
| package with a different signature | never counts as real, comes out as `REVIEW` | **new today**, with test |
| `eew_update` presented as an alert | `ALERT` is told apart from `UPDATE` | **new today**; the product must not forward `UPDATE` as a warning |
| emulator clock offset | the gateway rejects >5 min silently; now it warns at 30 s | **new today** |
| evidence file reset | the old index skipped all new captures | **fixed today** |
| Google excludes emulators overnight | only an expected quake that does not arrive detects it | pending; it is the risk no local check covers |
| the user does not know they have no coverage | the app has to show "last checked X ago" and turn red when the threshold passes | pending, goes before any user |

Calibration. Two numbers have to be tuned with real data, and it has started:

- **Radius.** Each capture carries `DISTANCE_EXTRA` and `MAGNITUDE_EXTRA`. With those
  figures we compare against the Allen et al. table. So far there are 2 points, both
  consistent.
- **Threshold.** Google warned with M4.46. When there are 5 or more cases near the edge
  we decide whether the predictor has to go below 4.5.

How to run the checks:

```bash
python3 scripts/test_lab.py
cd gateway && npm test
```

## 7. Best options

In order:

1. **Ask for permission with evidence.** This lab already has what Google and
   the SGC have not published: real latency (17.6 s), the geographic control and
   the late notice case. It is a good pilot to offer "an iOS channel for
   Colombia". The question to Google is already drafted in `viability.md`.
2. **Position for SNAST.** If the bill passes, the SGC will
   need broadcast channels. An iOS app that already has dedup, expiry and
   coverage state is a good complement, and legal too.
3. **Meanwhile, keep this as a private lab.** Switch
   the Google account to a dedicated one and do not open it to third parties.

What I do not recommend: launching with the grid without permission. Google can cut
delivery to emulators without notice, and no local check would detect it before
the next quake. In a safety app, that is the silent failure of
point 1.

## Sources

- [Android SDK License Agreement](https://developer.android.com/studio/terms)
- [Google Terms of Service](https://policies.google.com/terms)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [AWS: nested virtualization on virtual instances, feb-2026](https://aws.amazon.com/about-aws/whats-new/2026/02/amazon-ec2-nested-virtualization-on-virtual)
- [Hetzner AX102](https://www.hetzner.com/dedicated-rootserver/ax102/)
- [SNAST bill, El Colombiano](https://www.elcolombiano.com/colombia/nueva-ley-alerta-sismica-colombia-terremotos-FA40046704)
- [Ley 1523 de 2012](https://www.alcaldiabogota.gov.co/sisjur/normas/Norma1.jsp?i=47141)
- [iPhone without native earthquake alerts in Colombia, El Colombiano](https://www.elcolombiano.com/tecnologia/alerta-sismo-android-como-activar-HL39766364)

## 8. Notification channel on the iPhone (noted on 2026-09-24)

The goal is the **loudest** possible warning: it has to sound with the iPhone on silent and in Focus.
For now only the backend is built. The native app comes later.

| channel | sounds on silent/Focus | requirement | state |
|---|---|---|---|
| AlarmKit (iOS 26+) | yes, like the clock alarm | native app + user permission | **main goal**. Still to test that a push fires it within seconds |
| Critical Alerts | yes, even with volume at 0 | native app + Apple approval | request it later; they will probably deny it without an official source |
| Time-sensitive push | Focus only | native app | fallback inside the app |
| SMS/call + Emergency Bypass | yes | the user turns on the bypass | expensive and slow at scale; only for few users |
| Web Push (PWA) | no | nothing | **what exists today**, the base while there is no app |

For the AlarmKit test we need:
- full Xcode;
- an Apple Developer account (USD 99/year);
- a real iPhone with iOS 26.

Minimal test: an app that asks for the alarm permission, plus a gateway push that tries to fire the alarm. It passes if it sounds with the iPhone on silent a few seconds after the push.

Impact on the backend when the app arrives: per-sensor delivery must also be able to send native APNs, with one token per device subscribed to a sensor. Today APNs only exists as an inherited global route.

**Decision 2026-09-24:** the app will be native iOS. Web Push stays only as a fallback.
- Loudness: AlarmKit as the goal, time-sensitive as the minimum and Critical Alerts later.
- User movement: the app listens to iOS "significant location change", recomputes the receptor on the phone and re-subscribes by itself. The location never leaves the phone: only the sensor_id reaches the server.
- Latency is similar to Web Push, because both travel over APNs. The advantage of the app is loudness and following the user, not speed.
- Risk that remains: App Store review (5.2.2).

## 9. Next step, after stabilizing: distill and optimize to the extreme

**Not done now.** It starts when the backend and the receptors are stable and proven in production.
Hard rule: **nothing may add latency to the alert.** Every optimization is measured before and after, with the time from capture to push.

Candidates, ordered by expected gain (none measured):
1. Sequential boot: several emulators per machine, no simultaneous boots. ~4 per r8i.large instead of 1.
2. KSM on the host: merges identical memory between emulators (~30-50% expected). Check that the emulator allows it.
3. Disable unused apps (~11% measured on the Mac) and lower the guest RAM to 2 GB, if Android tolerates it without killing Play Services.
4. Gateway on its own cheap machine, with worker threads, reused VAPID/JWT signing, persistent HTTP/2 with APNs and SQLite for subscriptions.
5. Compare AWS spot against a dedicated server without nested virtualization.

Ruled out: swap/zswap on the host (paging in from swap adds seconds right when the alert arrives), low-RAM/Go mode (requires modifying the image) and changing the Android version without revalidating AEA with a real quake.
Note 2026-09-25: a 4 GB swapfile with vm.swappiness=1 is allowed as an emergency buffer only, because under memory pressure the alternative is the OOM killer taking a whole emulator. Swap in real use (> 100 MB for 10 min) pages and means over budget: the last canary emulator comes off.

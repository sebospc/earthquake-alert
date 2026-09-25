# iOS techniques for the alert app

Researched 2026-09-25 by the investigator session. Sources are at the end.

Tags used below: **[V]** read in Apple's own documentation. **[R]** reported by developers or
third parties, not confirmed by Apple. **[U]** unverified, needs a test on a real device.
Nothing here was run on a phone. Where this doc says "test", `developer-ios` does it.

## Recommendation

1. **Sound tiers.** Ship with a time-sensitive alert push (already in the contract). Request
   Critical Alerts now, because approval takes weeks and the app cannot ship it without it. Text
   is in section 1. Treat AlarmKit as an experiment, not the plan: Apple documents no way to
   start an AlarmKit alarm from a push. The only candidate path is the notification service
   extension (NSE) scheduling the alarm when the push arrives, and nobody has shown it works [U].
   This changes the note in `decision.md` §8 ("AlarmKit main goal").
2. **Push.** The current headers are right (`alert`, priority 10, absolute expiration,
   collapse-id). Nothing is faster than a standard alert push. Do not use PushKit/VoIP.
   Add one custom field, `sent_at_ms`, and have the NSE log the arrival time, so we can
   measure the APNs leg for the first time.
3. **Location.** Ask for "Always", use significant-location-change only, and never rely on it
   to wake a force-quit app (Apple's docs and the forums disagree on that). The subscription lives on the
   server, so a missed wake-up only means the receptor set is stale, not that alerts stop.
4. **Receptor choice.** Choose the 3 receptors that surround the user, not the 3 nearest.
   Numbers below: two receptors on the same side leave 3 to 4 times more alerts uncovered than
   two on opposite sides. Also, the current "full coverage at 31 km" label overstates what the
   physics gives (details in section 4, for the coordinator to decide).
5. **Keeping the subscription alive.** Re-POST `/devices` on every launch and wake (it is
   idempotent, so the 201 is the health check, no new endpoint). Add a local "dead-man"
   notification that fires after 8 days without a successful POST.
6. **UI.** One screen, one status, one button only when something is wrong. Full-screen alert
   view only after the user opens the app. Details in section 6.
7. **Review.** Highest risks in order: 5.2.2 (Google's terms), 4.2 (a one-screen app),
   5.1.5 (location and "emergency services"), 2.5.1 (using AlarmKit or Critical Alerts for
   their intended purpose). Give the reviewer a way to trigger a test alert.

Device tests to run before trusting anything marked [U], in this order:

| # | test | decides |
|---|---|---|
| T1 | NSE calls `AlarmManager.shared.schedule` on an alert push, app force-quit, phone locked and silent | whether AlarmKit is a push path at all |
| T2 | Alert push with mutable-content to a force-quit app: does the NSE run? | T1 and `sent_at_ms` telemetry |
| T3 | Sig-loc relaunch: after force-quit, after reboot and unlock, in Low Power Mode | how much to trust location wake-ups |
| T4 | Time-sensitive push in Focus with the silent switch on | what the fallback tier really does |
| T5 | `sent_at_ms` vs NSE arrival time over 50 pushes, on Wi-Fi and cellular | APNs leg latency |

---

## 1. Loudest possible alert

### Options compared

| | bypasses silent switch | bypasses Focus/DND | sound length | needs from Apple | from a push, app killed |
|---|---|---|---|---|---|
| Time-sensitive | no [V] | yes, if the user has not turned it off [V] | custom file under 30 s [V] | capability only, no approval [U] | yes |
| Critical Alert | yes [V] | yes [V] | custom sound and volume 0 to 1 [V], under 30 s per file [V] | entitlement, manual approval [V] | yes |
| AlarmKit | yes [V] | yes [V] | rings like the Clock alarm, duration not documented [U] | none, user permission only [V] | no documented path [V], NSE path [U] |
| Notification Service Extension | not a channel; it edits a push before display [V] | | | | runs for visible pushes only [V] |
| Emergency Bypass / government alerts | | | | not available to third-party apps [V] | |

Facts behind the table:

- Time-sensitive "breaks through system controls such as Notification Summary and Focus. The
  user can turn off the ability" [V, UNNotificationInterruptionLevel.timeSensitive]. It does
  not mention the mute switch, and the critical page says only critical "bypasses the mute
  switch" [V]. So a time-sensitive alert on a phone with the ringer off is silent. It still
  lights the screen and vibrates [U].
- Critical Alerts: "play a sound even when the app is locked, muted, or a person uses Do Not
  Disturb". The app asks for `criticalAlert` authorization, and the user must accept it
  separately and can revoke it [V]. Payload: `interruption-level: critical` plus
  `sound: {critical: 1, name: "...", volume: 0..1}` [V].
- Sound files: linear PCM, IMA4, µLaw or aLaw in aiff/wav/caf, **under 30 seconds** or the
  system plays the default sound instead [V]. So no long alarm from a single notification.
  A 29 s designed siren is the maximum. The file must already be in the app bundle or
  `Library/Sounds` [V].
- AlarmKit: "It overrides both a device's focus and silent mode, if necessary" [V]. Alarms are
  scheduled locally with `AlarmManager.shared.schedule(id:configuration:)` [V]. The
  documentation and WWDC25 session 230 mention no push or remote scheduling [V, absence].
  Needs `NSAlarmKitUsageDescription`, and authorization is a separate user prompt [V].
  Reports of custom sounds not working in 26.0 and alarms sometimes firing late on locked
  devices exist [R, Apple forums and GitHub issue, not reproduced].
- NSE: called for pushes that display an alert and carry `"mutable-content": 1`, about 30 s to
  finish. It does not run for silent or sound-only pushes [V]. Our payload already has
  `mutable-content`. It is reported to run when the app was force-quit [R]. Whether it can
  use AlarmKit is unknown [U, T1].
- Silent (`content-available`) pushes cannot replace the NSE: "The system treats background
  notifications as low priority", "don't try to send more than two or three per hour", and if
  the user force-quits the app, the held notification is discarded [V].

### How the tiers combine

Send one alert push, as today. On the phone:

1. Base: time-sensitive alert, custom sound under 30 s. Works on every device, no approval.
2. When Apple approves the entitlement and the user grants it: the gateway sends
   `interruption-level: critical` and the `sound` dictionary with `critical: 1`, volume 1.0.
   The app tells the server it can do this (a `critical_ok` boolean on `POST /devices`), so we never send
   critical to a user who did not grant it. What iOS does with a critical payload for a user who
   has not granted it is unknown [U].
3. If T1 passes: the NSE also schedules an AlarmKit alarm a second ahead, with a fixed id
   derived from `event_id` (idempotent). The banner still shows. If the NSE fails or times out,
   the push shows anyway, so AlarmKit can only add, never remove.

Late alerts (`late: true`) stay `active` and never critical or AlarmKit, as the contract says.

### App Review view on these tiers

- Critical Alerts are meant for health, safety and security. The docs say Apple will not
  grant it "purely for demo purposes" [R, forum]. Earthquake warning fits the category on paper.
  Precedent: Earthquake Network (Futura Innovation) lists a critical-alerts option in its
  version history [V, App Store page]. Approval odds are my judgment, not data: fair, with
  a real chance of a first rejection asking for a stronger case. The weak point is that our
  alerts do not come from an official agency.
- AlarmKit is for alarms and timers. Guideline 2.5.1 says apps "should use APIs and frameworks
  for their intended purposes and indicate that integration in their app description" [V].
  A reviewer can read an earthquake siren on AlarmKit as misuse. Weigh that before building T1
  into the product. If Critical Alerts are approved, AlarmKit is not needed.

### Text for the Critical Alerts request

The form is at `https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/`.
The Account Holder of the developer account must submit it [R]. Have the App ID created first.
The user sends it; nothing here was sent.

> **App:** [app name], bundle ID [com.example.app], Team ID [XXXXXXXXXX].
>
> **What the app does.** It warns people in [Colombia, and later other countries] that an
> earthquake has started near them, seconds before the shaking arrives. The warning comes from
> the Android Earthquake Alerts system that Google runs. We receive those alerts on
> receiver devices placed at fixed sites, and our server sends a push to the iPhones of people
> who live near each site. The app does not measure earthquakes by itself. Our part adds
> under one second. The alert usually reaches the phone about 18 seconds after the earthquake begins.
>
> **Why the alert is critical.** The value of the warning is the seconds between the alert and
> the strong shaking. In that time a person can drop, cover and hold on, move away from a window
> or stop a car. Many earthquakes happen at night. A person asleep with the phone on silent or
> in a Sleep Focus will not hear a normal or time-sensitive notification, and the seconds are
> lost. Time-sensitive notifications do not play a sound when the ringer switch is off. That is
> the gap we are asking Apple to close.
>
> **How often and for whom.** Alerts are sent only for earthquakes at magnitude 4.5 or more
> that Google's system has decided are close to the receiver. This is a few events per year
> in most places (in Colombia, 65 in three years in the public dataset of Allen et al., Science
> 2025). A user only gets alerts from the 1 to 3 receivers nearest to them.
>
> **What we will not do.** Critical alerts are never used for marketing, news, aftershock
> summaries, service messages or anything else. If an alert arrives more than 2 minutes after the
> earthquake began, our server sends it as a normal notification, not critical. The user turns critical alerts on
> explicitly, with a clear explanation, and can turn them off in Settings.
>
> **Privacy.** The phone chooses its receivers on the device. Its location is not sent to our
> server. Outside coverage only a coarse 11 km cell is sent, to decide where to place new receivers.
>
> **Limits, stated honestly.** The system can miss earthquakes or be late, and the app says
> so in its description and on screen. It is a warning aid, not an official alert system.

Naming Google is a choice. Leaving it out is misleading, and App Review can ask for the source
anyway under 5.2.2. The text names it.

---

## 2. Push delivery speed and reliability

Current headers in the contract: `apns-push-type: alert`, `apns-priority: 10`, absolute
`apns-expiration`, `apns-collapse-id`. All correct. What Apple says for each:

| header | rule | our status |
|---|---|---|
| `apns-priority` | 10 sends immediately, 5 "based on power considerations", 1 prevents waking the device. Omitted means 10. Alert pushes with immediate action should use 10 [V] | ok |
| `apns-push-type` | `alert` for pushes that show something. `background` needs priority 5, and priority 10 with `background` is an error [V] | ok, no background sends |
| `apns-expiration` | Nonzero: APNs stores and retries until that date, "best efforts", may deliver a bit after it. Zero: one attempt, not stored [V] | ok, capture + 3 min |
| `apns-collapse-id` | Merges repeats into one notification, max 64 bytes [V] | check the id stays under 64 bytes; today's `chaparral:t1790194179:alert` is 27 |
| payload size | 4 KB [V] | ok |

What happens in the bad cases:

- **Phone offline or asleep in a tunnel.** APNs stores **one** notification per bundle ID. If
  several arrive, one is kept, usually the latest, not guaranteed [V]. Practical effect: a
  "Cobertura restablecida" push sent after an alert can replace the stored alert. It only
  matters for a phone that stays offline through both events; the alert's 3 min expiry makes that
  window short. No change proposed.
- **App force-quit.** Alert pushes are still delivered and displayed by the system, and the
  NSE runs for them [R]. Silent pushes are discarded [V]. This is why the alert must never be a
  silent push.
- **Low Power Mode.** Apple's pages I read do not describe an effect on alert pushes. Reports
  say alerts still arrive and background work is restricted [R]. Test in T3/T5 [U].
- **No network on the phone.** Covered above (stored, delivered when back online if not expired).
- **Throttling.** Alert priority 10 is not throttled the way priority 5 and 1 are, which "might
  get grouped and delivered in bursts" [V]. Never send earthquake alerts at 5.

Is anything faster than a standard alert push? No.

- PushKit / VoIP: forbidden for this. Since iOS 13 PushKit requires CallKit, and Apple says "if you
  are unable to support CallKit in your app, you cannot use PushKit" [V]. Using it for alerts is the abuse the
  rule is written against. Do not do it.
- Live Activity pushes and push-to-start use the same APNs path. They change what is shown,
  not when it arrives [U for exact latency].
- A persistent socket from the app only works while the app runs.
- The gateway side can shave time (persistent HTTP/2, pre-signed JWT), which is already in
  `decision.md` §9. It is our 0.8 s, not APNs.

**Measure the APNs leg.** Today nobody knows it. Add `sent_at_ms` (gateway clock, at the moment
the request is written) as a custom key. The NSE writes `received_at_ms` to an app-group file
and the app uploads the pair on next launch, if the user opted into diagnostics. Phone clocks
drift by up to about a second, so use the median over many pushes, not single values.
APNs's delivery metrics in the Push Notifications Console give a second view [V, existence only].

---

## 3. Location with minimal battery

| API | wakes a terminated app | granularity | battery | notes |
|---|---|---|---|---|
| Significant location change | yes, "the system automatically relaunches the app into the background" [V] | about 500 m, not more often than every 5 min [V] | lowest of the continuous ones (cell-based) [U] | Always authorization. Works best with network [V] |
| Region monitoring / CLMonitor | yes: "if an iOS app isn't running when a condition is satisfied, the system tries to launch it" [V] | max 20 conditions per app [V]; delay 3 to 5 min on average [V, old text] | low | must recreate the monitor at launch. **Only after the user unlocks the device following a reboot** [V] |
| Visits | yes [V] | on arrival or departure at a place, delayed | low | good for "moved to another city", late for a road trip |
| `CLLocationUpdate.liveUpdates` (iOS 17+) | yes when updates are available, must recreate the call and any `CLBackgroundActivitySession` on launch [R, WWDC23 10180] | continuous, pauses when stationary | high while moving; needs the blue location indicator for background [R] | wrong tool: we need "moved 30 km", not a track |
| Location push service extension | yes, from a server push | on demand | low | **Not eligible.** Only for apps that share location with people the user approves, or alert first responders [V]. It would also send location to our server |

Force-quit and reboot, honestly:

- Apple's text says a user-terminated app is relaunched only by region monitoring or the
  significant-change service [V, quoted in a forum thread]. A developer in that thread reports it
  does not relaunch after force-quit, and nobody from Apple answered [R]. Other reports show
  relaunches on some iOS versions [R]. **Treat force-quit as "no wake-ups" [U, T3].**
- Reboot: monitoring resumes only after the first unlock [V]. Until then the phone has the old
  subscription, which is fine.
- Background App Refresh off: old docs say significant-change stops relaunching the app.
  A developer reports iOS 16 no longer behaves that way [R]. [U, T3].
- Low Power Mode: reported to pause background location for most apps [R, low quality source]. [U, T3].

**Recommendation: one mechanism.** Significant-location-change, started at every launch. On each
event run the selection from section 4; call `POST /devices` only if the set changed. A second
mechanism (a region around the current spot, sized to the distance to the nearest decision
boundary) would cut wake-ups but adds a second failure mode. Add it only if T3 shows sig-loc
wakes are too frequent to matter for battery, which I do not expect: each wake is a few
milliseconds of arithmetic and usually no network call.

Wake-ups without the user opening the app, all together:

1. sig-loc relaunch (Always).
2. `BGAppRefreshTask`: opportunistic, the system decides when, not after force-quit [U, not read in detail].
3. Silent push `content-available`: max 2 or 3 an hour, not after force-quit [V]. Could carry a
   "resync" nudge from the server, e.g. after a new receptor is added near a phone's demand
   cell. Low value, since sig-loc plus app open cover it.
4. Nothing else. If all three fail the phone keeps its old set, which is why section 4 picks 3
   receptors that surround the user: a stale set still covers a person who moved some tens of km.

### Permissions and how to ask

- "When in use" alone does not wake a terminated app [R, matches the WWDC24 model where background
  use needs `.always`]. The app needs "Always" for the wake-ups. The alerts themselves need
  no location permission at all: a user who says "no" to location still gets alerts from receptors
  they choose by hand or by cell. Build that fallback: it is the "denied" path and also
  the path that avoids the 5.1.5 discussion.
- iOS 18+: `.always` is only effective when held through `CLServiceSession(authorization:
  .always)`, created while the app is in the foreground [V, WWDC24 10212 transcript]. Recreate it on
  every launch.
- iOS shows "When in use" first and offers "Always" later, as a follow-up prompt [U, from memory
  of iOS 13+ behaviour; verify on device]. So ask twice, in context:
  1. First run, after the user sees the screen and taps the one button: ask for When-in-use with
     the reason on screen just before.
  2. After the first armed state, a plain card: "Para seguir avisándole si viaja, permita
     'Siempre'." One button that opens Settings, one that dismisses forever.
- Apple's advice: ask in context, not at first launch [V, "Asking permission to use notifications"],
  and try provisional notifications so users see one before deciding. **Do not use provisional
  for this app**: provisional notifications are delivered quietly [V], which is the opposite
  of the product. Ask for the full permission, with a screen that says what will happen.
- Accept reduced accuracy. Approximate location is enough for 78 km decisions, but its updates
  come "every 15 to 20 minutes" [R, WWDC24 summary] and its error can be several km. Section 4
  handles that with a margin.
- Purpose strings (Spanish), keep them plain and specific: `NSLocationWhenInUseUsageDescription`:
  "Su ubicación se usa solo en el teléfono para elegir los sensores de sismo más cercanos. No
  se envía." `NSLocationAlwaysAndWhenInUseUsageDescription`: "Para cambiar de sensores cuando
  usted viaja, aunque la app esté cerrada. La ubicación no sale del teléfono."
  Both are true only if the app never sends the location (the demand cell is a coarse
  exception: state it in the privacy policy, section 7).

---

## 4. Receptor choice on the phone

### What the numbers say

Model: AEA alerts a device when the epicenter is within R(M) of it, with R = 31, 78, 197, 346 km
for M4.5, 5.0, 5.5, 6.0 (`findings.md` §5, median error 0.4 km). A user is "missed" when their
own phone would alert (epicenter within R of the user) but no chosen receptor would (all
farther than R from the epicenter). With epicenters uniform inside the disc, this fraction is
(`receptor-edge-sim.py`, 400k samples):

Share of alerts the user would get on their own phone that a single receptor at distance d misses:

| d | M4.5 (R 31) | M5.0 (R 78) | M5.5 (R 197) | M6.0 (R 346) |
|---|---|---|---|---|
| 5 km | 10% | 4% | 2% | 1% |
| 10 km | 21% | 8% | 3% | 2% |
| 20 km | 40% | 16% | 6% | 4% |
| 31 km | 61% | 25% | 10% | 6% |
| 50 km | 90% | 40% | 16% | 9% |
| 78 km | 100% | 61% | 25% | 14% |

Two and three receptors at the same distance d, by arrangement:

| receptors (each at d) | d | M4.5 | M5.0 | M5.5 |
|---|---|---|---|---|
| 2, opposite sides | 31 | 22% | 1% | 0% |
| 2, at 90° | 31 | 36% | 10% | 3% |
| 2, same side | 31 | 58% | 23% | 9% |
| 3, 120° apart (user inside the triangle) | 31 | 0% | 0% | 0% |
| 3, 120° apart | 50 | 70% | 0% | 0% |
| 3, 120° apart | 78 | 100% | 0% | 0% |

How to read it:

- The missed alerts are epicenters in the outer band of Google's radius, where the user's own
  shaking is near the alert threshold (BeAware fires at about MMI 3, `findings.md` §6). So the
  loss is real but concentrated in the weakest-felt events. This is a model, not a measurement
  [U]. It assumes uniform epicenters and a hard radius.
- Bigger earthquakes are much safer than small ones because R grows and d/R shrinks. At
  M5.5 and up a single receptor 31 km away misses 10% or less.
- **Surrounding beats nearest.** Three receptors around the user cut misses to zero for
  M4.5 at d = 31 km, and two on opposite sides cut M5.0 to 1%. Two receptors on the same side
  give almost nothing over one.
- **Contract impact (coordinator to decide).** The text "Cobertura completa (sismos desde
  M4.5)" for ≤ 31 km promises more than this gives for a single receptor at the edge: 61% of
  M4.5 alerts can be missed there. It is nearly right only with 3 surrounding receptors or a
  receptor within about 5 to 10 km. Proposed replacement, computed on the phone from the chosen set's
  miss share at M5.0 (the smallest magnitude that most people would call a real earthquake):
  full ≤ 10%, partial ≤ 40%, else "limited". Keeps three levels on screen, changes what
  decides them. If the coordinator prefers to leave the contract alone, the distance rule still
  works, but the copy should say "desde M5.0" for full coverage between 10 and 31 km.

### Algorithm

Constants, all [U] until tested: `enterKm = 78` (the contract's `partial_km`), leave band =
`max(10, 2 × accuracyKm)`, `maxK = 3`, switch margin 3 points of weighted miss.

```
struct Fix { lat, lon, accuracyKm, timestamp }

// fixed once: 128 points of a sunflower spiral on the unit disc
let discPoints: [(x, y)] = sunflower(128)
let magnitudes = [(4.5, 31.0, weight 0.2), (5.0, 78.0, 0.5), (5.5, 197.0, 0.3)]   // R from the table

func missShare(subset, fix) -> Double {
    total = 0
    for (M, R, w) in magnitudes {
        missed = discPoints.count { p in
            epicenter = fix + R * p                      // flat local projection, km
            return !subset.contains { dist($0, epicenter) <= R }
        }
        total += w * missed / discPoints.count
    }
    return total
}

func choose(fix, current: [ID], sensors, covered: Set<ID>) -> Decision {
    // 1. Never act on a bad fix. Missing data means keep, never drop.
    if now - fix.timestamp > 30 min || fix.accuracyKm > 25 { return .keep }

    // 2. Candidates: public, and inside the enter radius, or already ours and inside the leave radius.
    leaveKm = enterKm + max(10, 2 * fix.accuracyKm)
    candidates = sensors.filter { s in
        s.public && (dist(fix, s) <= enterKm || (current.contains(s.id) && dist(fix, s) <= leaveKm))
    }
    if candidates.isEmpty { return .noCoverage(demandCell: floor(lat*10), floor(lon*10)) }

    // 3. Score all subsets of size 1...3 (at most ~100 for 8 candidates, well under a millisecond
    //    of arithmetic). Receptors reported not covered by /status count as absent for the score,
    //    so a dead one is backfilled instead of kept.
    live = candidates.filter { covered.contains($0.id) }
    best = subsets(live, upTo: maxK).min { (missShare($0, fix), sumDist($0, fix)) }   // ties: closer wins

    // 4. Hysteresis. Stay on the current set unless the new one is clearly better, or the
    //    current one lost a member (out of the leave band, or not covered).
    currentLive = current.filter { live.contains($0) }
    if currentLive.count == current.count
       && missShare(currentLive, fix) - missShare(best, fix) < 0.03 { return .keep }

    return .subscribe(best)     // POST /devices { sensor_ids }
}
```

Behavior by case:

- **Stale location.** Older than 30 minutes or accuracy worse than 25 km: keep the current set. If
  the user opens the app, ask for one fresh fix (`requestLocation`, 10 s timeout) and then decide.
  Never unsubscribe because location is missing. The location age is shown to the user only if
  it is over 7 days (section 6).
- **Flip-flop between two receptors.** At the midpoint the two sets score almost the same, so the
  3-point margin holds the current one. The leave band keeps a member until the user is clearly
  beyond it. The server also dedups a quake for a token that follows both, so overlap is harmless.
- **Edge of coverage.** The `enterKm` boundary uses `accuracyKm` only for staying (leave band).
  Entering is on the raw distance, so a bad fix cannot make a receptor look near.
- **Not covered yet.** No candidate: `POST /devices` with `demand_cell`, screen says "Tu zona
  todavía no tiene cobertura". The next sig-loc event, or a new `sensors.json` on app open,
  reevaluates.
- **A receptor goes down.** `covered_apns == false` in `/status` removes it from `live`, and
  the algorithm backfills with the next best. The contract already sends "Sin cobertura" per
  receptor, so the app should not show a red state unless `live` is empty.
- **Cheap fallback if this feels like too much:** nearest 3 within `enterKm` with the leave
  band and no scoring. The tables show its cost: when the 3 nearest are on one side, it is
  the "same side" row, 3 to 4 times worse than surrounding. I would still ship the scoring
  version. It is about 40 lines and testable with a table of fixes.

Test that must exist (life-safety rule in `CLAUDE.md`): a fixture of receptors and fixes with
expected sets, including the midpoint case walked in 1 km steps (must switch at most once), a
receptor not covered, an empty candidate list, and a fix of 30 km accuracy (must keep).

---

## 5. Keeping the subscription alive

What can break, and what fixes it:

| break | cause | fix |
|---|---|---|
| New token | restore from backup, new phone, OS reinstall [V]. Updates normally keep it [U] | call `registerForRemoteNotifications()` on every launch and every wake. Never cache the token as the truth [V] |
| Server dropped the row | 410 / BadDeviceToken cleanup, database restore, the 10,000 device limit | re-POST (idempotent, replaces the set) |
| App never launched after a restore | iCloud restore installs the app but does not run it, so no new token is sent | unavoidable: the old token is dead until first launch. The onboarding screen must be reachable in one tap |
| Notifications turned off by the user | Settings | read `UNNotificationSettings` on every foreground: `authorizationStatus`, `timeSensitiveSetting`, `criticalAlertSetting`. Show the red state |
| Receptor set stale | no location wake-ups | section 4, 3 surrounding receptors |
| Gateway or receptor down | operations | `/status` `covered_apns`, already in the contract |

**The silent health check, no backend change.** On every launch, foreground, and sig-loc wake
(debounced to once per 12 h): register for remote notifications, then `POST /devices` with the
current token and set. A `201` whose `sensor_ids` matches means the backend has us and holds the
right set. Anything else (network error, 4xx, 5xx, mismatch) is "not registered", retried with
backoff as the contract says. No new endpoint, no per-phone state to build.

**Dead-man local notification.** After each successful POST, schedule a local notification
8 days ahead (`UNCalendarNotificationTrigger`, same identifier, so it replaces itself): "Abra la
app para verificar sus alertas de sismo." If the phone stops verifying itself for any reason
(app force-quit and no wake-ups, backend loss the app could not see, broken token), this fires and the user is
sent back into the app, which then re-registers. It works with the app killed, because it is
local. Cost: a user who force-quits often sees it now and then. Acceptable for a life-safety
app, and it makes the silent failures loud, which `CLAUDE.md` asks for.

**What the check cannot see.** A 201 does not prove APNs can reach the phone. Only a real push does.
Optional, server side: a daily `background` push (priority 5) per token and an ack call from the
app. It is silent-push traffic (limits above), never arrives for force-quit apps, and would
cost a new endpoint. Skip for now: no evidence yet that the dead-man plus the
POST check leaves a gap. Revisit if T5 telemetry shows tokens going dead without a 410.

`App Attest` for `/devices` (the contract's "later") should land before the first public build:
the endpoint lets anyone who knows a token change its receptors.

---

## 6. Minimal-UI craft

The screen answers one question: "will it warn me?" Everything else is one tap away or not there.

**Structure.**

- One primary screen. A large SF Symbol, one line of state, one line of detail, and a button only
  when the user must act.
- A second, quiet screen ("Cobertura") lists the chosen receptors, and their state, in a plain
  `List`. It also gives review something beyond a single label (4.2, section 7). Reached by tapping
  the state line. No tab bar.
- Settings are the iOS Settings app. The app deep-links there for anything that needs
  permission: `UIApplication.openSettingsURLString`.

**States** (symbol names are SF Symbols, to be checked in the SF Symbols app [U]):

| state | symbol | line | detail | button |
|---|---|---|---|---|
| armed, full | `checkmark.shield.fill` | Alertas activas | Cobertura completa | none |
| armed, partial | `shield.lefthalf.filled` | Alertas activas | Cobertura parcial, sismos desde M5.0 | none |
| no coverage | `shield.slash` | Sin cobertura en su zona | Todavía no hay sensores cerca | none |
| notifications off | `bell.slash.fill` | Alertas desactivadas | Sin permiso no podemos avisarle | Activar |
| time-sensitive off | `exclamationmark.triangle.fill` | Las alertas pueden no sonar con Concentración | | Abrir Ajustes |
| not registered | `wifi.exclamationmark` | Sin conexión con el servidor | Reintentando | none |
| server red | `exclamationmark.triangle.fill` | Sin cobertura ahora | Su sensor no responde | none |

Rules: never green when `/status` did not answer (the contract already says so); never rely on
color alone, the symbol and text carry the state; use system colors so dark mode, Increase
Contrast and color-blind settings work.

**"Armed" animation.** One `.symbolEffect(.pulse)` (iOS 17+) or a slow opacity change on the
symbol, about 4 s a cycle, and nothing else moving. Off when `accessibilityReduceMotion` is on
or when the state is not armed. It says "alive" without asking for attention. Do not animate the
background.

**Haptics.** Short and few, in line with Apple's guidance ("avoid overusing haptics", "prefer
short haptics that complement discrete events", make them optional) [V, HIG Playing haptics]:
`UINotificationFeedbackGenerator` `.success` once when the state becomes armed; `.warning`
when it turns to a problem. During an alert, only while the app is in the foreground, a
`CoreHaptics` pattern of a strong tap every 1 s for the first 10 s. Killed or locked, the
notification's own vibration is what exists, and the app cannot add more.

**The alert experience.** iOS has no full-screen-intent for third-party pushes (that is an
Android feature). What the user sees when it fires:

1. Locked or unlocked: the notification banner plus sound (time-sensitive or critical), or the AlarmKit
   screen if T1 passes.
2. If the user taps it, or the app is already open: an in-app full-screen cover (`fullScreenCover`)
   with, from top to bottom: "Sismo M4.8" (the magnitude the payload carries, rounded to 1
   decimal), the action line, the time since the alert in seconds, and one button to close.
   Black or system-background, white text, largest Dynamic Type, no map, no distance (the contract
   forbids showing `distance_km` as the user's distance).
3. `late: true` uses the same cover with the "Aviso atrasado" title and no protective-action
   line, as the contract says.

Keep the cover on screen until the user closes it or the alert expires. Use
`UIApplication.shared.isIdleTimerDisabled = true` while it shows.

**Accessibility.**

- VoiceOver: the whole status is one accessibility element with a combined label ("Alertas
  activas. Cobertura completa."). On a state change, post an announcement
  (`AccessibilityNotification.Announcement`). The alert cover takes focus first thing and the
  alert text is the label.
- Dynamic Type: only text styles (`.largeTitle`, `.title2`, `.body`), never fixed sizes, and a
  `ScrollView` so 200% still fits. Apple's target is 200% [V, HIG Accessibility].
- Contrast: meet the minimum, and a higher-contrast variant with Increase Contrast on [V, HIG
  Accessibility]. Do not use gray text for the state line.
- Alerts must not depend on the screen: the sound and vibration are the primary channel, the
  screen is secondary. Also deaf and hard-of-hearing users get the vibration and the flash
  (`LED flash for alerts` is a user setting, nothing to build).

**Spanish copy and tone.**

- The contract mixes registers: the alert body says "Protéjase ahora" (usted) and the coverage
  texts say "Tu zona" (tú). Pick one. For Colombia I would use usted throughout the alert and
  neutral noun phrases ("Alertas activas", "Cobertura completa") in the UI, which avoids the
  choice on most screens [U: my read of Colombian usage, ask a native reviewer].
- Alert action line: short imperatives, no adjectives, no exclamation marks. Something like
  "Agáchese, cúbrase y sujétese." The gateway composes the text today, so the words are the
  coordinator's decision. The app must not add advice the gateway did not send.
- Problem states say what is wrong and what happens next, in one sentence each. No apologies,
  no "Oops", no emojis.
- Avoid "Seguro". A safe/unsafe word is a promise. "Alertas activas" is a fact.

**References.**

- Apple HIG, Notifications: `https://developer.apple.com/design/human-interface-guidelines/notifications`
  (do not rely on a short look for critical information, keep sound distinctive, support
  people who turned badges off).
- Apple HIG, Playing haptics: `https://developer.apple.com/design/human-interface-guidelines/playing-haptics`
- Apple HIG, Accessibility: `https://developer.apple.com/design/human-interface-guidelines/accessibility`
- Apple sample "Scheduling an alarm with AlarmKit" and WWDC25 session 230, for how an
  alarm screen looks and how its buttons behave, if T1 passes.

---

## 7. App Review risk

The user accepted the compliance risk (`decision.md` §10). This section states it, it does not
argue against it. Quotes from the App Review Guidelines [V, fetched 2026-09-25].

| guideline | text (short) | why it applies | mitigation |
|---|---|---|---|
| **5.2.2** Third-party services | Apps that use or display content from a third-party service must be "specifically permitted to do so under the service's terms of use. Authorization must be provided upon request." | The alerts are Google's. There is no permission on file (`docs/outreach/` was dropped). This is the largest risk and the one with no technical fix | Describe the source truthfully. Accept that Apple can ask for authorization and we cannot show it. Fallback and early warning are in `decision.md` §10 |
| **4.2** Minimum functionality | The app should go "beyond a repackaged website" and be "useful, unique, or app-like" | A one-screen app looks thin | The receptor list screen, notification settings, the alert view, location-based re-subscription. Say in the review notes that the value is the push |
| **5.1.5** Location | Location APIs "shouldn't be used to provide emergency services". Also: notify and get consent, explain the purpose | We use location to choose sensors. A reviewer can read the product as an emergency service | The app is a notification service. Location is on-device and used only to pick a sensor. The alerts work without location permission. Purpose strings are honest |
| **2.5.1** Intended API use | Use "APIs and frameworks for their intended purposes and indicate that integration in their app description" | AlarmKit for a siren, Critical Alerts for an unofficial source | Prefer Critical Alerts, which are for this. Mention the use in the description |
| **1.4** Physical harm | Rejected if it "risks physical harm". Text is about medical, drugs and risky activities | False reassurance or a missed alert could hurt someone | Plain limits on screen and in the description: may be late, may miss, not official. No "safe" wording |
| **4.5.4** Push | "Push Notifications must not be required for the app to function" | The app's function is a push | Low risk in practice (messaging apps live on push). The app still shows state and receptors without a push |
| **5.1.1** Privacy | Privacy policy link, consent, data minimization | The device token and, outside coverage, an 11 km cell go to our server | Declare both in the App Privacy label and the policy. Nothing else leaves the phone. State it |

Other review risks:

- **The reviewer cannot trigger an earthquake.** Add a review-only way to fire a real alert:
  a "Enviar alerta de prueba" in Settings behind a review-notes code, hitting an authenticated
  gateway route that sends one test push (marked `test`, never critical) to that token. Also
  put a screen recording of a real alert in the review notes.
- **Critical entitlement not approved at review time.** Submit with time-sensitive and enable
  critical in an update. Do not ship code that assumes it: the app must work with both.
- **Google can change or block the path.** It is a business risk, not a review one. The certifier
  is the early warning (`decision.md` §10).
- The App Store description must not say "official", must not promise a warning time, and must
  name the source. This is also what protects the honesty of the Critical Alerts request.

---

## Unverified list, in one place

- AlarmKit scheduled from an NSE, and its ring duration and volume (T1).
- NSE running for force-quit apps, from Apple's own words (T2; only reports found).
- Sig-loc relaunch after force-quit, after reboot, with Low Power Mode, with Background App
  Refresh off (T3). Sources disagree.
- What iOS does with a critical payload when the user did not grant critical.
- Time-sensitive does not play sound when the ringer switch is off (implied by Apple's critical
  text, not stated for time-sensitive).
- Whether "Always" is offered as a follow-up prompt in iOS 26 the way older versions did.
- The receptor model in section 4 against a real quake: it assumes uniform epicenters and a
  hard radius. The certifier's catalog data could check the miss share by receptor over time.
- Approval odds for Critical Alerts: my judgment.
- Spanish register for Colombia.

## Sources

Apple documentation (read through Apple's public JSON docs endpoint, `developer.apple.com/tutorials/data/...`):

- Sending notification requests to APNs, `https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns`
- Generating a remote notification, `https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification`
- Pushing background updates to your app, `https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app`
- Registering your app with APNs, `https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns`
- Handling notification responses from APNs, `https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns`
- UNNotificationInterruptionLevel (critical, timeSensitive), UNNotificationSound, UNAuthorizationOptions.criticalAlert, Critical Alerts entitlement, under `https://developer.apple.com/documentation/usernotifications/` and `.../bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts`
- Modifying content in newly delivered notifications, UNNotificationServiceExtension, same base path
- Asking permission to use notifications, same base path
- AlarmKit, Scheduling an alarm with AlarmKit, AlarmManager, NSAlarmKitUsageDescription, `https://developer.apple.com/documentation/alarmkit`
- Responding to VoIP notifications from PushKit, `https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit`
- startMonitoringSignificantLocationChanges(), startMonitoringVisits(), startMonitoring(for:), Monitoring the user's proximity to geographic regions, Creating a Location Push Service Extension, under `https://developer.apple.com/documentation/corelocation/`
- App Review Guidelines, `https://developer.apple.com/app-store/review/guidelines/`
- Human Interface Guidelines: Notifications, Playing haptics, Accessibility, `https://developer.apple.com/design/human-interface-guidelines/`
- WWDC25 230 Wake up to the AlarmKit API, `https://developer.apple.com/videos/play/wwdc2025/230/`
- WWDC24 10212 What's new in location authorization, `https://developer.apple.com/videos/play/wwdc2024/10212/`
- WWDC23 10147 CLMonitor, `https://developer.apple.com/videos/play/wwdc2023/10147/`; WWDC23 10180 CLLocationUpdate, `https://developer.apple.com/videos/play/wwdc2023/10180/` (read as transcript summaries, so [R] for details not in the reference docs)
- Government, Emergency, and Enhanced Safety Alerts on iPhone, `https://support.apple.com/en-us/102516`

Third party and forums:

- Critical Alerts entitlement thread, `https://developer.apple.com/forums/thread/106042` (request URL, demo policy, timelines from 2 weeks to 2 months)
- Do user-terminated apps relaunch automatically for location changes?, `https://developer.apple.com/forums/thread/701377`
- Background App Refresh and Significant Location Changes Tracking, `https://developer.apple.com/forums/thread/652985`
- How to get the Apple Critical Alerts entitlement (Newly), `https://newly.app/how-to/critical-alerts-entitlement`
- Earthquake Network on the App Store (critical alerts in version notes), `https://apps.apple.com/us/app/earthquake-network/id1449893235`
- AlarmKit late-firing and sound reports: GitHub `IgorJonski/Snoozeloo` issues #2 and #12 (a research request, not a result), Apple forums AlarmKit threads found by search only, not opened

Model: `docs/research/receptor-edge-sim.py`; radius table from `docs/findings.md` §5.

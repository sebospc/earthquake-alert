# Device tests

These need a real iPhone and the Apple Developer account. The simulator can't answer any of them.
Source: `docs/research/ios-techniques.md`, "Device tests". Write each result into the table at
the end, with date, iPhone model and iOS version.

## Before starting

- [ ] Developer account active and `TESTFLIGHT.md` done up to the first device build: real
      `APP_BUNDLE_ID` and `DEVELOPMENT_TEAM` in `project.yml`, app group `group.<APP_BUNDLE_ID>`.
- [ ] APNs key (.p8) for the gateway sandbox. The coordinator decides which gateway the phone
      uses. A debug build talks to `http://localhost:8787` unless it is started with
      `-gateway <url>`.
- [ ] A way to send one push by hand to the phone's token: the gateway's probe, or
      `curl --http2` with the key. It must be the contract's alert payload, `mutable-content: 1`
      and `sent_at_ms` included.
- [ ] Phone clock set to automatic.

## T1. AlarmKit from the notification service extension

Decides if AlarmKit can be a push path at all. Not in the app yet: a throwaway branch adds
`AlarmManager.shared.schedule` (alarm 1 s ahead, id derived from `event_id`) to
`AlertService/NotificationService.swift`.

- [ ] App force-quit, phone locked, silent switch on. Send one alert push.
- [ ] Does the alarm screen show? Does it sound with the silent switch on?
- [ ] Same with the app in the background, not force-quit.
- [ ] Send the same `event_id` twice: only one alarm.
- [ ] Result decides: if it fails, AlarmKit stays out and nothing changes in the app.

## T2. Does the extension run for a force-quit app

On the simulator (Xcode 27), `xcrun simctl push` shows the notification but the extension never
runs, even with the app open. So this is device-only.

- [ ] Force-quit the app. Send one alert push.
- [ ] Open the app. Is there a new line in the app group's `push-arrivals.jsonl` with this
      `event_id`? Copy it with the command in "Reading the arrival log" below.
- [ ] Repeat with a coverage push (`kind: coverage`).

## T3. Location wake-ups

The app must keep working if the answer is "never". A missed wake-up only leaves the receptor
set old; the server keeps sending alerts to the old set.

- [ ] "Always" granted, app in the background: travel more than 5 km (car or bus). Does the app
      re-register? Check the gateway log for a POST /devices from this token.
- [ ] Same after force-quit.
- [ ] Same after a reboot, before and after the first unlock.
- [ ] Same with Low Power Mode on.
- [ ] Same with Background App Refresh off.

## T4. Time-sensitive alert with Focus and the silent switch

- [ ] Focus on (Do Not Disturb), app allowed nothing special. Send one alert push. Does it show
      and sound?
- [ ] Silent switch on, no Focus. Sound or only vibration?
- [ ] In Settings, turn off "Time Sensitive Notifications" for the app. Does the main screen show
      "Las alertas pueden no sonar"? Send a push: what happens?
- [ ] Late alert (`late: true`, `interruption-level: active`) with Focus on: expected silent.

## T5. APNs leg latency

- [ ] Send 50 alert pushes on Wi-Fi, 50 on cellular, a few seconds apart.
- [ ] Opt the phone in first. From `GET /telemetry` (or `push-arrivals.jsonl`), take
      received minus sent for each. Report the median and
      the 90th percentile per network. Single values mean little, phone clocks drift about 1 s.

## T6. Push text in the phone's language

The simulator's `simctl push` skips the extension, so this is device-only.

- [ ] Phone in Spanish (Colombia). Send an alert push with magnitude 4.8: title "Alerta de sismo",
      body "Sismo M4,8 cerca de su zona..." (comma: the extension formats it).
- [ ] Phone in English: title "Earthquake Alert"; the body stays Spanish until the official
      English wording exists (docs/research/languages.md).
- [ ] Build without one key in the catalog (delete `ALERT_TITLE` from
      `Localizable.xcstrings`, do not ship it): the push shows the payload's Spanish title, never
      "ALERT_TITLE".

## Reading the arrival log

The extension (`source: nse`) and the app when open (`source: app`) write one JSON line per push
to `push-arrivals.jsonl` in the app group (last 500 kept). A phone the operator opted in
(`POST /devices/telemetry`, monitor key) uploads it on its own at each launch, wake and
registration; read it with `GET /telemetry`. Fallback, for a development build installed from
Xcode (not TestFlight):

```sh
xcrun devicectl list devices    # the phone's identifier
xcrun devicectl device copy from --device <identifier> \
  --domain-type appGroupDataContainer --domain-identifier group.<APP_BUNDLE_ID> \
  --source push-arrivals.jsonl --destination ./push-arrivals.jsonl
```

## Also check while you have the phone

- [ ] First run: consent screen ("Acepto") → notification prompt → location prompt → main screen.
      After the first "Alertas activas", iOS asks for "Always" once.
- [ ] The dead-man notification: set the phone's date 9 days ahead with the app closed. It
      should show "Verifique sus alertas de sismo". Open the app, it re-registers, reset the date.
- [ ] VoiceOver reads the state as one sentence. Largest Dynamic Type fits without cutting text.
- [ ] Alert screen: the phone doesn't lock while it shows, 10 haptic taps, "Cerrar" returns.

## Results

| test | date | iPhone / iOS | result | notes |
|---|---|---|---|---|
| T1 | | | | |
| T2 | | | | |
| T3 | | | | |
| T4 | | | | |
| T5 | | | | |
| T6 | | | | |

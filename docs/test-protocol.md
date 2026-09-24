# Validation protocol

## Evidence labels

- `SYNTHETIC_FIXTURE`: created by `android-fixture`; never counts as AEA.
- `AEA_DEMO_START` / `AEA_DEMO_END`: window marked by hand around the demo.
- `GMS_CANDIDATE`: notification from `com.google.android.gms`; it may still not be AEA.
- `AEA_REAL_CONFIRMED`: only assigned outside the app after correlating UI, an independent event and artifacts.

The app never labels anything as a real alert automatically.

## 1. Physical phone

Minimum requirements:

- Android with updatable Google Play Services.
- Play Protect certified.
- Earthquake Alerts visible and on.
- Location on and no mock provider.
- Wi‑Fi or data; ideally both.
- Automatic time.

Run:

```bash
./scripts/audit-android.sh physical
```

Record by hand the model, Play Protect state and screenshots of the toggle/demo. If the phone does not offer AEA after updating and rebooting, it is no good as a control.

## 2. AVD

First use a single Pixel profile with the stable `google_apis_playstore` image for `arm64-v8a`. Do not use AOSP, root or Xposed for the reception test.

Set Rionegro:

```bash
adb emu geo fix -75.3737 6.1532
./scripts/audit-android.sh avd
```

A working toggle or demo only produces `GO-UX`.

## 3. Listener and fixture

```bash
./gradlew :android-listener:installDebug :android-fixture:installDebug
```

1. Open AEA Capture Lab and grant Notification Listener access.
2. Post the fixture's normal notification.
3. Check a `SYNTHETIC_FIXTURE` entry with channel `synthetic_normal`.
4. Grant or deny Full Screen Intent and test with the screen unlocked, locked and off.
5. Check `has_full_screen_intent: true` even if Android degrades the presentation.

## 4. AEA demo

1. Start the capture:

   ```bash
   ./scripts/capture-window.sh demo
   ```

2. In AEA Capture Lab, mark the start.
3. Run `Settings → Safety & emergency → Earthquake alerts → See a demo`.
4. Mark the end.
5. Finish the script with Enter and export the JSONL from the app.

A GMS callback during the window describes the demo, not production.

## 5. Real event

Keep the physical Android and the AVD on, connected and with synced time. Do not run demos or fixtures during observation.

When the physical phone shows AEA:

1. Record the screen right away with another device.
2. Run `./scripts/capture-window.sh real-physical`.
3. Export the JSONL.
4. Save the identifier/time of the event from the SGC or another independent source.
5. Repeat on the AVD.

### Criteria

- `GO listener`: real AEA UI + independent event + correlated GMS callback.
- `GO Take Action`: in addition there is a `NotificationRecord`/callback compatible with the takeover.
- `NO-GO Take Action` for that build: the control phone shows the takeover, but there was no callback or enqueue and there was a GMS Activity.
- `GO AVD`: the same real event shows up natively on the control and the AVD.
- Absent on both devices: invalid trial to judge the AVD.

## 6. APNs

Do not use production until source rights and the entitlement are solved.

Tests:

- active, time-sensitive and critical;
- silent, volume zero, each Focus, screen off;
- Wi‑Fi and mobile data;
- app terminated and phone rebooted;
- offline until before and after `expires_at`;
- duplicate with the same `event_id`.

Record p50, p95, p99 and losses. Do not report only the best time.

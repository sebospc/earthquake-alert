# Functional test results

Date: 2026-08-29. Device: AVD Pixel 8, Android 15 Google Play ARM64.

## Result

| Test | Result | Evidence |
|---|---|---|
| Build listener and fixture | PASS | `./gradlew test assembleDebug` |
| Show normal notification | PASS | `evidence/functional-notifications/normal-visible.png` |
| Capture normal notification | PASS | `listener.jsonl`, ID 2001 |
| Full-screen with permission | PASS | Activity visible, screen on and ID 2002 captured |
| Full-screen without permission | PASS | Screen stayed off; `AlertActivity` did not open |
| Reconnection after reboot | PASS | `LISTENER_CONNECTED` with boot 3 and later ID 2001 |
| Signature and metadata | PASS | JSONL contains package, signer SHA-256, channel, extras and timestamps |
| Authenticated HTTP gateway | PASS in dry-run | 202 response and simulated APNs dispatch |
| Invalid HMAC, expiry and duplicates | PASS | 3 Node tests |
| iOS project generated | PASS | XcodeGen correct and Swift parsed |
| Real APNs push to iPhone | BLOCKED | No membership, key, token, connected iPhone or full Xcode |
| Real Critical Alert | BLOCKED | Requires an entitlement approved by Apple |
| AEA demo | PASS visually; not capturable by NLS | After updating GMS, it opened `EAlertSafetyInfoActivity` without posting a notification |
| Real Google AEA alert | NOT TESTED | Requires a real event received by an eligible device |

## Observed behavior

### Normal notification

Android visibly showed:

- app: `AEA Synthetic Fixture`;
- title: `SYNTHETIC — Android Earthquake Alerts System`;
- body: `SYNTHETIC normal fixture`.

The listener received the same event with channel `synthetic_normal` and
`has_full_screen_intent=false`.

### Full-screen

With `USE_FULL_SCREEN_INTENT=allow`, posting while the screen was off:

- turned the screen on;
- opened `com.earthquakes.fixture/.AlertActivity`;
- showed the red full-screen warning;
- produced a listener callback;
- recorded `has_full_screen_intent=true`.

With the permission denied:

- it did not open the Activity;
- it did not turn the screen on.

This proves the generic Android mechanism. It does not prove that Google's `Take Action` uses that mechanism.

### Reboot

After rebooting the AVD, the listener reconnected automatically and captured
a new notification without granting access again.

## Functional conclusion

The synthetic Android chain really works, including full-screen
presentation, observation, persistence and recovery after reboot. The gateway
works up to the APNs boundary.

We cannot yet claim that the two proprietary ends work:

1. input: delivery/capture of a real Google AEA;
2. output: real APNs/Critical delivery on an iPhone.

Those two results need accounts, devices and external events; they
cannot be replaced by simulations without faking the experiment.

## AEA eligibility update

Signing in to the Play Store and updating Google Play Services from `24.23.35` to
`26.32.34` removed the unsupported region message. With a
GNSS/fused fix at `6.1532, -75.3737`, the AVD showed:

- Earthquake Alerts on;
- normal operating information;
- `See a demo`;
- full-screen demo `Test Earthquake`.

During the demo no AEA `NotificationRecord` appeared and the listener did not create
any event. `dumpsys activity` confirmed that GMS directly opened
`com.google.android.location.ealert.ux.EAlertSafetyInfoActivity`.

This shows that the `Take Action` demo cannot be intercepted through
`NotificationListenerService`. It does not yet show that a `Take Action`
received from production uses exactly the same path.

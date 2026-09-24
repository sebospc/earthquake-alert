# Pilot verdict

Last update: 2026-08-29.

## Current decision

**No-go for public launch. Limited go for the lab.**

It is not an aesthetic or conservative decision: there is still no evidence of the three prerequisites the product rests on.

1. Google does not publish an API or a redistribution license for AEA for this use.
2. No real AEA alert has been captured with `NotificationListenerService`.
3. Apple has not approved Critical Alerts for an App ID of this product.

## Results obtained

- The M3 Pro Mac with 36 GB is fit for an ARM64 AVD.
- `AEA_Pixel8_API35_Play` was created and started: Android 15, Google Play ARM64 image and build `AE3A.240806.036`.
- The AVD contains `EALERT` components, shows the toggle on and has a valid GNSS/fused location in Rionegro.
- Before signing in, GMS `24.23.35` showed `not supported in this region`.
- After signing in and updating to GMS `26.32.34`, the regional block disappeared and `See a demo` showed up. This gate passes as **GO-UX**, not as production reception.
- The `Take Action` demo runs as `EAlertSafetyInfoActivity`. It did not post a notification or produce a callback in our `NotificationListenerService`.
- The internal debug Activity exists but is not exported; normal ADB cannot use it.
- Android instrumentation was built that separates fixtures, demo windows and GMS candidates.
- A normal and a full-screen fixture were built to verify the listener without attributing the result to Google.
- On the AVD, the listener captured both variants correctly; the full-screen one recorded `has_full_screen_intent: true`.
- A gateway was built with HMAC, five-minute expiry, deduplication and APNs; its local tests pass.
- A minimal iOS client was built, without geolocation and without unauthorized Critical Alerts.
- The Swift code passes syntax validation and XcodeGen generates the project.
- There is no full Xcode, signing identity, Apple Developer membership or APNs credentials. The automatic Xcode install was blocked by the admin password; its App Store page was opened for manual install.
- A reproducible capture with `dumpsys` and logcat was documented.

## Evidence still missing

| Test | State | What unblocks it |
|---|---|---|
| Eligible physical Android | Pending | Connect, authorize ADB and run the audit. |
| AVD with toggle/demo | GO-UX | After updating GMS, region accepted, toggle on and demo working. |
| Normal/full-screen listener | Passed on AVD | JSONL keeps both callbacks and the full-screen intent. |
| Observable AEA demo | Activity yes; listener no | `EAlertSafetyInfoActivity` visible, no `NotificationRecord` or callback. |
| Real AEA captured | Blocked externally | A real event that the control phone receives. |
| Real AEA on AVD | Blocked externally | Same event received first by the control. |
| APNs on iPhones | Blocked by credentials/devices | Full Xcode, membership, App ID, key and iPhones. |
| Critical Alerts | Blocked by Apple | Request from the Account Holder and approval. |
| Redistribution rights | Blocked by Google/legal | Written answer and legal review. |

## Criteria to change the decision

The result only changes to `GO for public pilot` when:

- Google or an applicable agreement authorizes the source and redistribution;
- a real alert, not a demo, produces capturable evidence;
- Apple approves the required notification behavior;
- tests report acceptable delivery rate and p95/p99;
- the product is presented as complementary, without promising guaranteed lead time.

Until then, any claim of commercial viability would be speculation.

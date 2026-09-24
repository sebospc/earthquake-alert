# Viability: Google AEA → Android relay → iPhone

Cutoff date: 2026-08-29.

## Verdict

| Part | State | Reason |
|---|---|---|
| AEA in Colombia | Proven | Colombia is on the official list. |
| AEA on an eligible physical Android | Supported, not guaranteed per event | Google requires location, data/Wi‑Fi and the feature on; it warns about misses and late alerts. |
| AEA on a Google Play AVD | Not proven | GMS and the local demo do not prove backend registration or delivery. |
| `NotificationListenerService` with `Be Aware` | Plausible, pending a real event | It shows as a standard notification, but we have no sample of our own. |
| Listener with `Take Action` | Not proven | It may be a notification with a full-screen intent or a direct privileged Activity. |
| AEA demo | Useful only for UI/local path | Does not prove detection, geotargeting or remote delivery. |
| Own gateway | Viable | Conventional engineering once a reliable signal exists. |
| Normal/Time Sensitive APNs | Viable, best effort | Does not guarantee delivery or sound with the phone silenced. |
| Critical APNs | Blocked by approval | Requires Apple's managed entitlement and separate consent. |
| Public product | Provisional no-go | There is no public AEA API/license and no proven redistribution permission. |

## Primary sources

- [Official Android help](https://support.google.com/android/answer/9319337): countries, requirements, approximate magnitude 4.5+, limitations and non-guaranteed timing.
- [Google Research](https://research.google/blog/android-earthquake-alerts-a-global-system-for-early-warning/): aggregate architecture and alert types.
- [Google Crisis Resilience](https://crisisresilience.google/android-early-earthquake-warnings): alert levels and presentation.
- [Android Emulator](https://developer.android.com/studio/run/managing-avds): what a Google Play image guarantees; it does not promise AEA.
- [NotificationListenerService](https://developer.android.com/reference/android/service/notification/NotificationListenerService): observes notifications, not Activities or overlays.
- [Full-screen intent limits](https://source.android.com/docs/core/permissions/fsi-limits): restrictions since Android 14.
- [Critical Alerts](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts): sound with lock, silent mode and Focus.
- [Capability Requests](https://developer.apple.com/help/account/capabilities/capability-requests/): approval of managed entitlements.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): restrictions on location-based emergency services and minimum usefulness.
- [SGC](https://sgc.gov.co/sismos): official catalog for later correlation; it is not evidence of an EEW feed with an SLA.

## What cannot be claimed

- That an AVD receives AEA because it shows the toggle or the demo.
- That Google blocks emulators: no public exclusion was found.
- That simulating the accelerometer generates an alert: the backend needs correlation of many devices.
- That a synthetic alert, ETWS, WEA or Cell Broadcast proves AEA.
- That `APNs 200` means the user saw or heard the alert.
- That the system will warn before the shaking.
- That capturing and republishing a proprietary notification is commercially authorized.

## Commercial gate

Before publishing:

1. Get a written answer from Google on commercial use and redistribution.
2. Review with a Colombian lawyer the terms, liability, consumer protection, privacy and safety messages.
3. Get Critical Alerts if the requirement includes sounding in silent mode.
4. Describe the product as complementary and publish real metrics of delays and losses.

### Proposed question to Google

> We are evaluating a public Colombian iOS safety-information product that would observe Android Earthquake Alerts on a stock Android device and relay the alert content to authenticated iOS users. Does Google authorize capture, transformation, and commercial/public redistribution of AEA notifications? Is an official partner API or licensing route available? Are Android Studio AVDs with Google Play images eligible for production AEA delivery? We will not represent the product as an official Google service without permission.

Recipient to be confirmed with Google. Do not use a ShakeAlert contact as if it granted rights over Google's global system.

### Summary for the request to Apple

Explain:

- exact source and the right to use it;
- geographic area and thresholds;
- why a delay or silence causes harm;
- authentication, expiry, deduplication and false alarm prevention;
- that Critical will not be used for marketing, unexpected tests or minor events;
- fallback and an explicit notice that the system is complementary.

## Obsolescence risks

Apple may extend its native earthquake alerts and Colombia is studying a national system. This does not invalidate the lab, but it makes weak a business whose only value is copying AEA to iOS.

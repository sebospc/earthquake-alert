# Earthquake Relay Validation Lab

A lab to answer with evidence whether a real Google Android Earthquake Alerts alert can be observed on Android and forwarded to iPhone. It is not a safety product yet.

## Result

**23-sep-2026: a real AEA alert reached an emulator with a spoofed location.**
Google delivers based on the location the device reports, and a coordinate
injected with `adb emu geo fix` is enough. The other three emulators of the
fleet, outside the radius, received nothing. That control is what makes it
conclusive.

The opposite direction does not work: the emulator **does not contribute** to Google's
detection network. The `earthquake_alerting` component never subscribes to the
accelerometer.

- [`docs/decision.md`](docs/decision.md): grid, provider, image, compliance and security (23-sep)
- [`docs/findings.md`](docs/findings.md): everything tested and ruled out, with evidence
- [`docs/result-first-capture.md`](docs/result-first-capture.md): the capture in detail
- [`docs/architecture.md`](docs/architecture.md): what it would take to make it a product
- [`docs/observation-run.md`](docs/observation-run.md): the running experiment and how to operate it
- [`docs/fleet-siting.md`](docs/fleet-siting.md): where to place sensors and why
- `evidence/FIRST-REAL-AEA-CAPTURE/`: raw evidence, including the screenshot

## Components

- `android-listener`: records Google Play Services candidates and fixtures in JSONL.
- `android-fixture`: normal and full-screen notifications that are unmistakably synthetic.
- `gateway`: HMAC receiver, deduplication, expiry and APNs delivery.
- `ios-client`: minimal SwiftUI client with token and local history.
- `scripts`: Android audit and coordinated evidence capture.
- `docs`: verdict, sources and go/no-go protocol.

Executed results: [`docs/functional-results.md`](docs/functional-results.md).

## State verified on this Mac

- Apple M3 Pro, 36 GB: enough hardware for an ARM64 AVD.
- Java 17, Node 18, Android SDK, Gradle and XcodeGen available.
- A Pixel 8 Android 15 Google Play ARM64 was created.
- After signing in and updating GMS, the AVD accepts Rionegro, shows AEA enabled and runs the demo.
- Full Xcode is still missing; no signing identities or APNs credentials are configured.
- The workspace was empty; all content is a new lab.

## Android

Install SDK Platform 35 and accept the licenses, then:

```bash
./gradlew test assembleDebug
./gradlew :android-listener:installDebug :android-fixture:installDebug
./scripts/test-notifications.sh
```

Follow [`docs/test-protocol.md`](docs/test-protocol.md). A demo or fixture is never labeled as a real AEA.

## Gateway

```bash
cd gateway
npm test
set -a
source .env
set +a
npm start
```

`APNS_DRY_RUN=1` avoids contacting APNs. Production needs an APNs key, real tokens, the correct bundle ID and Apple's authorization. The HMAC secret must not be versioned.

The endpoint is `POST /events`. It requires `X-Relay-Signature`, a hex HMAC-SHA256 of the exact body, and rejects events that are expired or valid for more than five minutes.

## iOS

Requires full Xcode and XcodeGen:

```bash
cd ios-client
xcodegen generate
open EarthquakeRelay.xcodeproj
```

Change the bundle ID and select the signing team. The project only requests normal notifications. Do not add `com.apple.developer.usernotifications.critical-alerts` or send `critical` level until Apple approves the capability for that App ID.

## Conditions to continue

1. Permission or a clear legal basis to redistribute AEA.
2. An eligible physical Android.
3. A correlated capture of a real alert.
4. Critical Alerts approved if sounding in silent mode is mandatory.
5. Acceptable real measurements of loss and latency.

Without those five conditions, the result is a research prototype, not a viable public product.

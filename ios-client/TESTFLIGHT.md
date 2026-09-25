# TestFlight

What the user has to create or decide before the first TestFlight build. The code side is ready:
Release builds use the production APNs environment, the release gateway URL, and version numbers
from `project.yml`. Nothing is uploaded without the user's approval.

## Apple Developer account

1. Enroll in the Apple Developer Program (individual or organization). The seller name shows on
   the App Store, so pick it with the "not an official service" rule in mind: no SGC, UNGRD or
   government wording.
2. Choose the bundle id, for example `co.<yourdomain>.sismo`. Set it once as `APP_BUNDLE_ID` in
   `project.yml`. Targets, extension, UI tests and app group all follow it. Set the gateway's
   `APNS_BUNDLE_ID` to the same value.
3. Put the team id (Membership page) in `DEVELOPMENT_TEAM` in `project.yml`, then run
   `xcodegen generate`.
4. Certificates, Identifiers & Profiles:
   - App ID `<APP_BUNDLE_ID>` with Push Notifications, Time Sensitive Notifications and App
     Groups.
   - App ID `<APP_BUNDLE_ID>.alertservice` with App Groups.
   - App group `group.<APP_BUNDLE_ID>`, assigned to both App IDs.
   - With automatic signing, Xcode can create all three on the first build.
5. APNs auth key (.p8), Keys page, "Apple Push Notifications service". Note the key id. It goes
   to the gateway's secrets, never into the repo. One key serves sandbox and production.
6. Critical Alerts: optional, a separate request to Apple
   (developer.apple.com/contact/request/notifications-critical-alerts-entitlement). Until it is
   granted, the flag in `project.yml` stays off.

## App Store Connect

1. New app: platform iOS, name (for example "Sismo"), primary language Spanish (Mexico or
   Spain; es-CO is not offered there, the app's own text is es-CO), the bundle id from above,
   a SKU.
2. App Privacy: answer from `EarthquakeRelay/PrivacyInfo.xcprivacy`. Identifiers (Device ID),
   Location (Coarse Location) and Diagnostics (Performance Data, test phones only), all linked
   to the user, App Functionality only, no tracking.
3. Privacy policy URL: the hosted "política de tratamiento"
   (`docs/research/legal-colombia.md` §4.2). Put the same URL, and the terms URL, in
   `ConsentView.swift` (`privacyNoticeURL`, `termsURL`). Today they point to example.com.
4. Age rating questionnaire, category (Utilities or Weather), support URL.
5. TestFlight: an internal testing group with the testers' Apple IDs. External testing needs a
   short beta review first.
6. App Review notes: how to hear an alert without a quake, "Cobertura" → "Probar alerta", and
   the staged alert recording the coordinator approved.

## Each upload

1. Raise `CURRENT_PROJECT_VERSION` in `project.yml` (App Store Connect refuses a build number it
   has seen). `MARKETING_VERSION` only for a new public version.
2. `xcodegen generate`, then in Xcode: Product → Archive (Release), Distribute App → App Store
   Connect → Upload.
3. Before the upload: the release gateway is the one the coordinator names, and the gateway has
   the production APNs key for the bundle id.

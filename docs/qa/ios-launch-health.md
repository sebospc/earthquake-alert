# iOS pre-launch health check

Owner: developer-qa. Status: plan/checklist, nothing to run yet — no Apple Developer account
exists (`docs/STATUS.md` "Open", blocked on the user). This doc says what "healthy enough to
launch" means and how we'd check it, once there is something to check. Coordinate with
devops-earthquake's Apple-infra monitoring design (requested, not written yet as of this doc —
see "Cross-check" below) so their monitoring and this checklist agree on who owns what.

## 1. Certs, provisioning, APNs: what healthy looks like, how a silent failure gets loud

Same rule as the rest of the project (`CLAUDE.md`): a silent failure is worse than a loud one.
Three things can go bad here, each with a different detection story.

**APNs auth key (.p8) revoked or wrong.** Already has a detection path, not a new one to
build: `gateway/README.md` "Real APNs" — a bad Team ID, Key ID or bundle id only shows at the
first real push, the gateway logs `APNs rejects our configuration (InvalidProviderToken)`
(`gateway/src/server.js:920`), and the receptor's `covered_apns` goes `false`
(`APNS_CONFIG_REASONS`, `server.js:29-30`, `DeviceTokenNotForTopic` and friends never delete
phones, they degrade the sensor instead). That flows straight into the certifier's existing
uncovered-receptor rule (15 min DEGRADED / 60 min FAIL, `monitor/README.md`) and the CloudWatch
`UncoveredReceptors` alarm. **So a dead APNs key is not actually a silent-failure risk today —
it already pages someone, through the same path as a receptor going down for any other
reason.** What's missing: a way to tell "APNs config is broken" apart from "AEA stopped
alerting" apart from "the emulator died" from the alert text alone, since right now they all
surface as the same "uncovered" signal. QA-115 candidate once there's a real APNs key to test
against: confirm `apns_dry_run: false` and a `DeviceTokenNotForTopic`/`InvalidProviderToken`
event actually produces a distinguishable log line an on-call human can grep for, not just a
generic "uncovered" alarm.

**APNs auth keys don't expire on a calendar** (unlike a cert), but Apple can revoke one, and the
Apple Developer Program membership itself is annual — a lapsed membership silently breaks
provisioning-profile renewal for any build made after it lapses, and can revoke push
capability. Neither is exercised anywhere in code; this is a process/calendar risk, not
something a test catches. **Recommendation:** put the membership renewal date and the APNs key
creation date in `docs/STATUS.md` or `TESTFLIGHT.md` once they exist, and let the existing
uncovered-receptor alarm be the tripwire for "push stopped working," rather than trying to
predict expiry.

**Provisioning profile / signing.** This is a build-time failure (Xcode refuses to archive with
a bad profile), not a runtime one — it cannot silently ship a broken build to users, since the
build never leaves Xcode. Nothing to add here beyond what `TESTFLIGHT.md` already documents
(automatic signing, `xcodegen generate` regenerates from `project.yml`).

## 2. Quality bar before calling the app "sellable"

- **Crash-free session rate.** No third-party crash SDK is in the app (checked: no
  Crashlytics/Sentry import, and `PrivacyInfo.xcprivacy` only declares Performance Data for
  opted-in telemetry phones — adding a crash SDK would add its own privacy-label surface and
  App Review question, so don't, unless a real need shows up). Source of truth is Apple's own
  crash reports in App Store Connect / Xcode Organizer, which need zero extra code. Bar
  proposed: **≥ 99.5% crash-free sessions** over the TestFlight testing window before treating
  the app as launch-ready — this is the industry-standard TestFlight/production bar, not
  something specific to this app, and it's a floor, not a target. Below it, block launch and
  file the crash as QA-NN like any other finding.
- **Screenshots / metadata review.** Not my call on the marketing content itself, but a
  QA pass before submission should confirm: every screenshot shows real app state (no
  placeholder data, no `example.com` links visible — `TESTFLIGHT.md` §"App Store Connect" step 3
  flags `privacyNoticeURL`/`termsURL` still point to `example.com`, that must be fixed before
  screenshots are taken, not after), the "not an official service" framing appears somewhere in
  the metadata the way it does in-app (`ConsentView.swift:28`, `CoverageView.swift:77`), and no
  screenshot implies guaranteed or official coverage.
- **App Review rejection risk.** `docs/research/ios-techniques.md` §7 already has the
  guideline-by-guideline table (5.2.2 third-party data source, 4.2 minimum functionality, 5.1.5
  location/emergency services, 2.5.1 API intended use, 1.4 physical harm, 4.5.4 push
  requirement, 5.1.1 privacy) with mitigations for each — not duplicating it here. QA's job
  before submission is to verify each claimed mitigation is actually true in the shipped build,
  not just planned:
  - 1.4 / 5.1.5: grep the shipped app and its App Store description draft for "seguro",
    "garantizado", "oficial", "en tiempo real" or similar over-promising language — the design
    intent is explicit non-official framing (`ConsentView.swift:28`), confirm nothing added
    since contradicts it.
  - The review-only "Enviar alerta de prueba" path the research doc recommends (§7, "the
    reviewer cannot trigger an earthquake") — confirm it exists and is documented in the App
    Review notes before submission; as of this doc's writing, `POST /devices/test` exists
    (gateway-approved, QA-reviewed) but whether it's surfaced in the review notes and whether a
    screen recording of a real alert is attached is a submission-checklist item, not a code
    check.
  - Critical Alerts: confirm the app still works with the entitlement off (`TESTFLIGHT.md` §5:
    "Until it is granted, the flag in `project.yml` stays off") — this is testable today,
    without an Apple account: build with the flag off, confirm no code path assumes critical
    delivery.

## 3. Per-locale QA (once cultural/localization changes land)

`LocalizationCatalogTests` already proves every contract key has a translation and every arg
count matches (developer-ios, `f407540`) — that's "the key exists and doesn't crash." It does
not prove the translation reads right. That gap is this section, and it's manual/human-review
by nature, not something to automate away:

- **Native or near-native read-through per shipped locale** (es source, en and pt-BR once out
  of `needs_review`): does the alert text read as urgent and clear, not machine-translated?
  Does the "not an official service" disclaimer keep its legal weight in translation, not just
  its literal meaning? This needs a human fluent in that locale — flag to the coordinator which
  languages QA can actually judge vs. which need investigator or an external reviewer.
- **Screenshot pass per locale**, reusing developer-ios's existing per-language UI test runner
  (`TEST_RUNNER_UI_TEST_LANGUAGE=en|pt-BR|double`, per `docs/STATUS.md` developer-ios line) —
  QA's addition on top of their accessibility audit is reading the *rendered* screenshots for
  tone and register, not just layout (their audit already covers clipped text, contrast,
  VoiceOver order).
- **Double-length pseudo-locale run** (already wired, per the same STATUS.md line) stays a
  developer-ios/QA joint check: confirms no truncation, but someone still has to eyeball that
  the real en/pt-BR strings (not pseudo) don't read stilted at their actual length.
- Consent/legal text is Spanish-only on purpose until `docs/research/languages.md` lands
  (investigator, in progress per the coordinator) — nothing to check here until that's decided;
  don't invent a QA gate ahead of a legal decision that isn't made yet.

## 4. Cross-check with devops-earthquake's Apple-infra design

Not written yet (coordinator asked devops for it after asking me for this doc). Once it
exists, reconcile:
- Who owns the "APNs config broken" alert path end to end — devops if it's a CloudWatch/SNS
  addition, QA if it's a certifier rule, or both if it's both (likely: devops wires the alarm,
  QA proves the gateway actually emits a distinguishable signal for it, per §1's QA-115
  candidate above).
- Whether devops's design assumes the same "uncovered = APNs config OR AEA OR emulator, can't
  tell apart yet" gap noted in §1, so the two docs don't quietly disagree on whether that gap is
  already closed.
- Membership/key renewal calendar ownership (§1) — likely devops, since it's account-level, but
  say so explicitly once their doc exists rather than leaving it unclaimed by either doc.

## Open questions

- Physical iOS 26 device and Apple Developer account: blocked on the user, same blocker as
  `docs/qa/iphone-latency.md`.
- Which locales QA can personally judge for tone/register vs. which need an outside reviewer —
  ask the coordinator once en/pt-BR come out of `needs_review`.
- Whether a distinguishable "APNs config broken" signal (§1, QA-115 candidate) gets built at
  all, or whether "uncovered, go look at the log" stays good enough at this scale — worth a
  coordinator call, not a QA decision alone, since it's a build-vs-good-enough tradeoff.

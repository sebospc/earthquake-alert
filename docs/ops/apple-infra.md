# Apple-side infrastructure

How signing, pushes and uploads work once the Apple Developer account exists. Nothing here is
built yet. The account and App Store Connect steps are in `ios-client/TESTFLIGHT.md`, the gateway
switch is in `gateway/README.md` "Real APNs". This page holds the decisions and the day-one
checklist.

## Decisions

### APNs: one token key (.p8), no push certificates

Use the APNs auth key (.p8, token-based). Do not use the older .p12 push certificates.

- The .p8 key has no expiry. A .p12 certificate expires after a year. Every renewal is a push
  outage if someone forgets it, and a forgotten renewal is a silent failure for our users.
- One key serves sandbox and production, and every app in the team. The gateway already signs
  its JWT with it and renews the token when APNs answers `ExpiredProviderToken`.
- Apple lets you download the key once. It lives in two places: the gateway host
  (`/etc/earthquake-gateway/AuthKey_<KEY_ID>.p8`, mode 600, gateway user) and the user's password
  manager. Never in the repo, never in GitHub secrets: CI never sends pushes.
- Rotation (a leak, or a person with access leaves): Apple allows two APNs keys per team at the
  same time. Create the new key, switch the gateway env and restart, check with the test button,
  then revoke the old key. Revoking first means an outage.

Both backups (`infra/backup/` hourly and `backup.sh`) copy `etc/earthquake-gateway/*.p8`. If the
gateway env names a key file (`APNS_PRIVATE_KEY_FILE`) and the backup does not hold it, the backup
fails loudly, so keep the key in `/etc/earthquake-gateway/`. Without that, a rebuilt host would
come back with the right Key ID and no key, and no iPhone would get anything.

### CI does not sign anything

The `ios-core` job runs `swift test` on the RelayCore package, on the macOS runner itself. It
builds no app and runs nothing on a device, so it needs no team, no certificate and no
provisioning profile. Keep it that way. If CI later builds the full app, build it for the
simulator with `CODE_SIGNING_ALLOWED=NO`: still no signing material. `DEVELOPMENT_TEAM` in
`project.yml` only matters on the machine that archives, and it is not a secret (the team id
shows in every signed build).

Provisioning profiles and the distribution certificate come only with archiving. With automatic
signing, Xcode creates and renews them on the user's Mac. There is nothing for us to store.

### TestFlight upload: by hand from Xcode, for now

The user uploads from Xcode (Archive, then Distribute App), as `TESTFLIGHT.md` says. No CI upload.

- An upload puts a build on testers' phones. That is a publish, and every publish needs the
  user's approval. A manual upload is that approval.
- Automating it needs an App Store Connect API key in GitHub. That key can ship a build to every
  tester, which is worse than anything our AWS deploy role can do. This repo is public, and the
  release volume (a few builds before launch) does not pay for that risk.
- Revisit it when uploads are more than about one a week, or when someone other than the user
  releases.

If it is automated later, it gets the same rules as `ANDROID_DEBUG_KEYSTORE_B64` plus the
production deploy:

- An App Store Connect **team** API key with the lowest role that can upload (Developer). It is
  stored as a secret of a `testflight` GitHub environment, with the user as required reviewer,
  and runs only from `main`.
- Cloud-managed signing: `xcodebuild archive` and `-exportArchive` with
  `-allowProvisioningUpdates` and `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`,
  export method `app-store-connect`, destination `upload`. Apple then holds the distribution
  certificate, so no .p12 goes into GitHub.
- The key file is written to `$RUNNER_TEMP` and deleted in an `always()` step. The key id and
  issuer id go in secrets too, even if they are not strictly secret, so the workflow shows no
  account data.
- `CURRENT_PROJECT_VERSION` is set from the run number, so the build number never repeats.

### Expiry monitoring: CloudWatch for what breaks pushes at runtime, calendar for the rest

Split by who can see the failure.

**In CloudWatch (our infra, already there):** a rejected APNs configuration. A revoked key, a
wrong Key ID or a wrong bundle id shows at the first push: the gateway logs
`APNs rejects our configuration (...)` and marks the channel degraded. A receptor whose last
alert reached nobody on a channel with recipients reports `covered: false` in `/status`. The probe
counts that, so `receptor-uncovered` pages after 10 minutes. No new alarm is needed.

The gap is the time between pushes. The gateway only learns that APNs rejects it when it sends
something. A key revoked on a quiet week shows at the next real alert, and that alert reaches no
iPhone. Close it with a scheduled push: the certifier's iPhone leg (`docs/qa/iphone-latency.md`)
sends a test push to an opted-in test phone. Once that runs every few hours, a broken key turns
the receptors uncovered within hours and not at the next quake. That is developer-qa's piece, and
it must be running before `APNS_DRY_RUN=0` stays on for real users.

**Not in CloudWatch:** membership, certificates, profiles, TestFlight builds. The host cannot see
them without an App Store Connect key on it, and that key is too powerful to put there. They also
fail at build or install time, where a person notices them, not during a quake. They go into the
user's calendar the day each one starts:

| What | Lifetime | What happens when it runs out |
|---|---|---|
| Apple Developer Program membership | 1 year | Apps leave the store, no new builds or TestFlight. Renew a month early. |
| TestFlight build | 90 days | Testers can no longer open that build: no alerts for them. Upload a new build before day 80. |
| Distribution certificate, provisioning profiles | 1 year | The next archive fails. Automatic signing renews them; installed apps keep working. |
| APNs .p8 key | none | Only revocation stops it: `receptor-uncovered` after the next push. |

The TestFlight line is the one that hurts during the beta: a tester whose build expired is a
user without alerts who thinks they are covered. Put a "new build by day 80" reminder with every
upload.

## Checklist for the day the account exists

Before the first push to a real phone:

1. Account, bundle id, team id, App IDs, app group: `ios-client/TESTFLIGHT.md` steps 1-4.
2. Create the APNs key. Put the `.p8` in the password manager first, then on the host
   (`gateway/README.md` "Real APNs"). Do not set `APNS_DRY_RUN=0` yet.
3. Check that the next hourly backup lists `etc/earthquake-gateway/AuthKey_<KEY_ID>.p8`. It fails
   if the env names a key it cannot find.
4. developer-qa: the certifier's scheduled test push to an opted-in phone is running (above).
5. Gateway env switch and restart. `/status` shows `"apns_dry_run": false`.
6. Test button from a real phone (sandbox build from Xcode). `receptor-uncovered` stays OK. The
   `apns_env` of the phone is `development`.
7. First TestFlight build by hand. Test button again from the TestFlight install: `apns_env` is
   now `production`, the same key serves both.
8. Calendar: membership renewal date minus 30 days, and "new TestFlight build" 80 days after the
   upload.
9. Update `docs/STATUS.md`: APNs live, key id (not the key), the date of the first TestFlight
   build.

# Relay gateway

Receives signed alerts from the Android listeners and sends them as web push to the
phones subscribed to that sensor. It also serves the web app in `public/`.

```bash
npm install
npm test
cp .env.example .env   # fill in, then:
node --env-file=.env src/server.js   # Node 20+; on 18 export the variables first
```

## Endpoints

| | |
|---|---|
| `POST /events` | alert from a listener. Signed with the sensor key, `HMAC(master, sensor_id)`. `"canary": true` checks the path without pushing |
| `POST /heartbeat` | `{sensor_id, sent_at}` from the listener, or `{..., aea_ok}` from the host health check |
| `POST /subscribe` | `{sensor_id, subscription}` from the web app. No location is received |
| `POST /devices` | `{device_token, sensor_ids: [1..3], platform: "ios"}` from the iOS app. Replaces the token's sensors on every call. No location is received |
| `POST /devices/test` | one test alert to a registered phone, at most one per 10 min |
| `POST /telemetry/arrivals` | push arrival times from opted-in test phones, see `docs/ios-contract.md` |
| `GET /status` | per sensor: `covered`, `stale`, `aea_ok`, `aea_stale`, and the last check times. `apns_dry_run` says if APNs is faked |

Monitor key only: `POST /probe`, `GET /evidence`, `POST /devices/telemetry` (opt a test phone in),
`POST /probe/apns-burst` (up to 50 pushes to one test phone) and `GET /telemetry`.

## Real APNs

Until now every deploy ran with `APNS_DRY_RUN=1`: pushes are faked and no iPhone gets
anything. Once the Apple Developer account exists:

1. In Certificates, Identifiers & Profiles, create a key with "Apple Push Notifications
   service (APNs)". Download `AuthKey_<KEY_ID>.p8`. Apple lets you download it only once.
2. Copy it to the gateway host, readable only by the gateway user, for example
   `/etc/earthquake-gateway/AuthKey_<KEY_ID>.p8` with mode 600.
3. In `/etc/earthquake-gateway.env`, set:

```bash
APNS_DRY_RUN=0
APNS_TEAM_ID=<Team ID, 10 characters, Membership details>
APNS_KEY_ID=<Key ID, 10 characters, shown with the key>
APNS_BUNDLE_ID=<the app's bundle id, same as in the Xcode project>
APNS_PRIVATE_KEY_FILE=/etc/earthquake-gateway/AuthKey_<KEY_ID>.p8
```

4. Restart the gateway. `GET /status` must show `"apns_dry_run": false`.

The gateway refuses to start if the key file is missing, is not an EC P-256 key, or a
Team ID, Key ID or bundle id has the wrong shape. That is all it can check alone: a wrong
but well-formed Key ID or Team ID only shows at the first push. Then the log says
`APNs rejects our configuration (InvalidProviderToken)` and the receptors turn
`covered_apns: false`. So check with the test button from a real phone right after the
switch. The same key works for sandbox and production; each phone says which one it
uses (`apns_env`).

How APNs answers are handled:

- The provider token (JWT) is made once and renewed every 40 min. Apple refuses tokens
  older than 60 min and throttles renewals under 20 min. On `ExpiredProviderToken` it is
  renewed at once and the push is retried once.
- `410 Unregistered`, `410 ExpiredToken` and `400 BadDeviceToken` delete the phone. It is
  back once the app registers again.
- `400 DeviceTokenNotForTopic` does not delete anyone. It usually means `APNS_BUNDLE_ID` is
  wrong, and then every phone would get it. It is logged, and the receptor goes red.

`RELAY_KILL_SWITCH=1` stops all forwarding. Subscribers get a no-coverage push (Spanish, "Servicio interrumpido").

## Open risk: a dead gateway warns nobody

Users hear about lost coverage through a push that the gateway itself sends. When the
gateway is down, that push is not sent either. What is in place:

- systemd restarts it (`Restart=always`).
- The web app shows red when `/status` does not answer, but only while it is open.
- On the host, `gateway-watchdog` checks `/status` every minute and tells the operator
  through ntfy (`NTFY_TOPIC`). The users are not told.

Closing it needs something outside this host that can push to the subscribers, for
example a second gateway in another region holding the same subscriptions.

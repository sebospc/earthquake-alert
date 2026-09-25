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
| `GET /status` | per sensor: `covered`, `stale`, `aea_ok`, `aea_stale`, and the last check times |

`RELAY_KILL_SWITCH=1` stops all forwarding. Subscribers get a no-coverage push (Spanish, "Sin cobertura en su zona").

## Open risk: a dead gateway warns nobody

Users hear about lost coverage through a push that the gateway itself sends. When the
gateway is down, that push is not sent either. What is in place:

- systemd restarts it (`Restart=always`).
- The web app shows red when `/status` does not answer, but only while it is open.
- On the host, `gateway-watchdog` checks `/status` every minute and tells the operator
  through ntfy (`NTFY_TOPIC`). The users are not told.

Closing it needs something outside this host that can push to the subscribers, for
example a second gateway in another region holding the same subscriptions.

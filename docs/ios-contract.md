# Gateway ↔ iOS app contract

Taken from `gateway/src/server.js` on 2026-09-24. If the code changes, the code wins.

The app never sends the location. It chooses its receptors on the phone and only the
`sensor_id`s reach the server.

## App requirements

- **Time Sensitive Notifications** capability on the target. Without it iOS lowers the alerts
  to `active` and Focus silences them.
- Check `UNNotificationSettings.timeSensitiveSetting` on open. If it is off, warn
  on screen that alerts may not sound with Focus.

## POST /devices

Registers the APNs token and the receptors it follows. Each call **replaces** the
full set of receptors for that token.

```json
{ "device_token": "a1b2...", "sensor_ids": ["chaparral", "quibdo"], "platform": "ios", "apns_env": "production" }
```

| field | rule |
|---|---|
| `device_token` | hex, 64 to 200 characters (32 to 100 bytes). Stored in lowercase |
| `sensor_ids` | 1 to 3, no duplicates, all with `"public": true` in `sensors.json` |
| `demand_cell` | instead of `sensor_ids`, when no public receptor is within `partial_km`. See "Outside coverage" |
| `platform` | exactly `"ios"` |
| `apns_env` | `"production"` (default) or `"sandbox"`. Development builds use `"sandbox"` |

Any other field is ignored and not stored. Each token goes to its own APNs environment,
so a sandbox token is never sent to production or deleted because of `BadDeviceToken`.

| response | when |
|---|---|
| `201 {"sensor_ids": [...], "apns_env": "..."}` | registered |
| `400 {"error": "invalid platform"}` | `platform` other than `"ios"` |
| `400 {"error": "invalid apns_env"}` | neither `"production"` nor `"sandbox"` |
| `400 {"error": "invalid device_token"}` | malformed token |
| `400 {"error": "invalid sensor_ids"}` | empty, more than 3, duplicates, unknown or not public |
| `201 {"sensor_ids": [], "demand_cell": "37,-755", "apns_env": "..."}` | registered outside coverage |
| `400 {"error": "invalid demand_cell"}` | not `"<int>,<int>"`, or out of range |
| `400 {"error": "send sensor_ids or demand_cell, not both"}` | both fields present |
| `400 {"error": "device limit reached"}` | the server already has 10,000 tokens and this one is new |
| `400 {"error": "..."}` | invalid JSON |
| `413` | body over 16 KB (closes the connection) |
| `429 {"error": "too many subscriptions"}` | more than 120 calls to `/devices` per IP in 10 min |

On 429 or 5xx, the app retries with backoff and shows "not registered" until it gets a
201.

If any of the receptors is **new** for that token and is not covered at that moment,
the server immediately sends it the "Sin cobertura" push for that receptor. It is one per
new receptor: registering the same set again does not repeat it. That way, when
"Cobertura restablecida" arrives later, the phone already knew it was down.

### Outside coverage

```json
{ "device_token": "a1b2...", "demand_cell": "37,-755", "platform": "ios", "apns_env": "production" }
```

The phone computes the cell itself: `floor(lat*10),floor(lon*10)`, a cell of about 11 km.
Its location never leaves the phone; the cell is all the server gets. It is the demand
signal for placing new receptors (`docs/siting-pilot.md`, "Demand-driven growth"). One cell
per token: registering again replaces it, and registering with `sensor_ids` clears it.

The first time a token registers this way, the server sends the "no coverage yet" push
below. The demand only counts once APNs has accepted a push to that token, so an invented
token never counts. The app shows "Tu zona todavía no tiene cobertura." as before.

## DELETE /devices

```json
{ "device_token": "a1b2..." }
```

`204` whether the token exists or not, so the app can retry safely. `400` if the token
is malformed. It counts against the same limit of 120 per IP as `POST /devices`. The app
calls it when the user turns alerts off. Leaving all coverage is a `POST /devices` with
`demand_cell`, not a DELETE.

### No authentication, on purpose for now

Today `/devices` has no auth. **App Attest once the app exists.** Meanwhile the
risk is low: a made-up token only produces `BadDeviceToken` on the first push and the
server deletes it, and the per-IP rate limit stops mass abuse. What someone who knows a
real token can do is change its receptors. The token is not public.

## APNs push

Headers: `apns-push-type: alert`, `apns-priority: 10`, `apns-topic` = bundle id,
`apns-expiration` = absolute expiry (APNs drops it after that), `apns-collapse-id`.

All payloads carry `"mutable-content": 1` for the Notification Service Extension.
They are told apart by `kind` and, within alerts, by `late`.

`event_id` and `collapse-id` are **opaque**: the app does not extract information from them.

### Alert

```json
{
  "aps": {
    "alert": { "title": "Alerta de sismo", "body": "Sismo M4.8 cerca de tu zona. Protéjase ahora." },
    "sound": "default",
    "interruption-level": "time-sensitive",
    "thread-id": "earthquake-alerts",
    "mutable-content": 1
  },
  "kind": "alert",
  "event_id": "chaparral:t1790194179:alert",
  "sensor_id": "chaparral",
  "magnitude": 4.8,
  "distance_km": 40.2,
  "time_occurred_s": 1790194179,
  "late": false,
  "expires_at": "2026-09-24T10:05:00.000Z"
}
```

- `title` and `body` are **always composed by the gateway** from `magnitude` and `late`. The
  text the receptor sends is ignored: an old or compromised one cannot put words
  on the phone.
- `magnitude`, `distance_km` and `time_occurred_s` can be `null`.
- `magnitude` and `distance_km` arrive raw (for example `4.45852`). The app rounds to 1
  decimal.
- **`distance_km` is the distance from the RECEPTOR to the epicenter. The app NEVER shows it as
  the distance to the user.** The phone does not know where the quake was. The app shows the
  magnitude and "sismo cerca de tu zona", which is what the `body` already carries. Without magnitude, the
  `body` is "Posible sismo cerca de tu zona. Protéjase ahora."
- `expires_at` is the capture + 3 min, and never later than the quake origin + 5 min.
  After that time the notice is no longer useful to take cover.
- `collapse-id` is the same for all receptors that saw the quake.

### Late alert

Same format, with `"late": true`. The **server** decides it with its clock: more than
120 s have passed since the quake origin (`time_occurred_s`, or the time Play Services
posted the notice if missing). The text changes and the level goes down:

- `title`: `"Aviso de sismo atrasado"`
- `body`: `"El sismo ocurrió hace N min. Ya no es un aviso anticipado."`
- `interruption-level`: `"active"`

With `late: true` the app does not say "protéjase" nor fire AlarmKit. It also does not recompute the
delay with the phone clock.

### No coverage / coverage restored

```json
{
  "aps": {
    "alert": { "title": "Sin cobertura en tu zona", "body": "No confíes en esta app por ahora." },
    "sound": "default",
    "interruption-level": "active",
    "mutable-content": 1
  },
  "kind": "coverage",
  "sensor_id": "chaparral",
  "covered": false
}
```

With `covered: true` the text is `"Cobertura restablecida"` / `"Las alertas de tu zona
vuelven a funcionar."`. It expires after 12 h.

It is sent **per receptor** and each phone gets it only when it changes **for that phone**:
"Sin cobertura" if it had not been told yet (for example on registration, above), and
"Cobertura restablecida" only if it got "Sin cobertura" before. The server remembers the
last notice per phone and receptor.
A phone that follows 3 receptors can get one for each receptor that changes. With
`sensor_id` and `covered` the app decides whether its whole zone lost coverage or whether another
receptor still covers it.

It goes out when the receptor stops reporting for 15 min, when AEA stops being
confirmed, when all APNs deliveries of an alert fail because of us, or
when the operator turns on the kill switch.

### No coverage yet

Once per token, on the first `POST /devices` with `demand_cell`:

```json
{
  "aps": {
    "alert": { "title": "Sin cobertura en tu zona", "body": "Tu zona todavía no tiene cobertura." },
    "sound": "default",
    "interruption-level": "active"
  },
  "kind": "coverage",
  "sensor_id": null,
  "covered": false,
  "reason": "no_receptor"
}
```

`sensor_id: null` means no receptor is involved: the app must not look it up. No
"restored" push follows this one; when a receptor appears near the cell, the app finds it
in `sensors.json` on its next location change.

## Dedup per quake

- A token that follows 2 receptors that see the same quake gets **one** notice. The server
  remembers, per token, the origins already notified and drops those within ±30 s.
- If that send fails, the next receptor can still get through.
- The `collapse-id` makes iOS replace instead of stacking.

Accepted limits:
- Two real quakes less than 30 s apart arrive as one.
- Dedup lives in the gateway RAM. A restart in the middle of a quake can repeat the
  notice (the `collapse-id` still replaces the notification).

## GET /status

```json
{
  "now": "2026-09-24T10:05:00.000Z",
  "started_at": "2026-09-24T09:00:00.000Z",
  "relay_enabled": true,
  "web_push_public_key": "...",
  "sensors": [{
    "id": "chaparral",
    "covered": true,
    "covered_apns": true,
    "covered_webpush": true,
    "stale": false,
    "last_heartbeat_at": "2026-09-24T10:01:00.000Z",
    "aea_ok": true,
    "aea_stale": false,
    "aea_checked_at": "2026-09-24T10:02:00.000Z",
    "last_canary_ok_at": "...",
    "degraded_since": null,
    "degraded": { "apns": null, "webpush": null }
  }]
}
```

- The app reads `covered_apns` of its receptors on registration and every time it opens.
- All the "stale" logic (15 min) is computed by the server. The age to display
  ("last checked X ago") comes from the server's `now`, not the phone clock.
- If `/status` does not answer, show red, never the last green.
- The gateway keeps the last report of each receptor, so a deploy or short restart
  does not turn anyone red. During the restart itself `/status` does not answer for a few seconds: the
  app does not present it as an alarm if it lasts less than 5 min. The server also does not send "sin
  cobertura" in the first 15 min after starting.
- `started_at` in the response says when the gateway started.

## sensors.json and coverage levels

`GET /sensors.json`:

```json
{
  "version": 2,
  "coverage": { "full_km": 31, "partial_km": 78 },
  "sensors": [{ "id": "chaparral", "name": "Chaparral", "lat": 3.7236, "lon": -75.4836, "public": true }]
}
```

Only sensors with `"public": true` count; `/devices` rejects the rest. The levels
come from the magnitude → radius table of Allen et al. 2025: M4.5 reaches 31 km and M5.0 78 km.

| distance to the closest public receptor | level | text (UI, Spanish) |
|---|---|---|
| ≤ `full_km` (31) | full | Cobertura completa (sismos desde M4.5) |
| ≤ `partial_km` (78) | partial | Cobertura parcial: solo sismos desde M5.0 |
| farther | none | Tu zona todavía no tiene cobertura. Not registered |

The reference is `gateway/public/coverage.js`: haversine, Earth radius 6371 km.

## Significant location change

1. iOS wakes the app with the significant location change.
2. The app downloads `sensors.json` (or uses its copy) and computes on the phone the distance to
   each public receptor.
3. It keeps the 2-3 closest within `partial_km`.
4. If the set changed, it calls `POST /devices` with those `sensor_ids`. If none is
   left, it calls `POST /devices` with its `demand_cell` and shows "sin cobertura".
5. The location stays on the phone; only the cell leaves it, and only outside coverage.

## Missing in the backend

- **Per-phone state.** `/status` is per receptor. The app builds its own state from
  its 2-3 receptors; there is no "you are covered" per token.
- **Auth on /devices.** App Attest, once the app exists (see above).

# Gateway ↔ iOS app contract

Taken from `gateway/src/server.js` on 2026-09-25. If the code changes, the code wins.

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
| `demand_cell` | alone when no receptor is eligible, or together with `sensor_ids` when the level is "limited". See "Outside coverage" |
| `min_magnitude` | optional, only with `sensor_ids`: `{"<sensor_id>": 5.5}`. Keys are a subset of `sensor_ids`, values numbers from 4.0 to 7.0. See "Strong quakes only" |
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
| `201 {"sensor_ids": [...], "demand_cell": "...", "min_magnitude": {...}, "apns_env": "..."}` | registered as "limited". Each of the two fields is only there when it was sent |
| `201 {..., "telemetry": true}` | a test phone the operator opted in to arrival telemetry. Absent means off. The app cannot turn it on; see "Arrival telemetry" |
| `400 {"error": "invalid demand_cell"}` | not `"<int>,<int>"`, or out of range |
| `400 {"error": "invalid min_magnitude"}` | not an object, a key not in `sensor_ids`, a value that is not a number from 4.0 to 7.0, or sent without `sensor_ids` |
| `400 {"error": "device limit reached"}` | the server already has 10,000 tokens and this one is new |
| `400 {"error": "..."}` | invalid JSON |
| `413` | body over 16 KB (closes the connection) |
| `429 {"error": "too many subscriptions"}` | more than 120 calls to `/devices` per IP in 10 min |

On 429 or 5xx, the app retries with backoff and shows "not registered" until it gets a
201.

If any of the receptors is **new** for that token and is not covered at that moment,
the server immediately sends it the "Servicio interrumpido" push for that receptor. It is one per
new receptor: registering the same set again does not repeat it. That way, when
"Cobertura restablecida" arrives later, the phone already knew it was down.

### Outside coverage

```json
{ "device_token": "a1b2...", "demand_cell": "37,-755", "platform": "ios", "apns_env": "production" }
```

The phone computes the cell itself: `floor(lat*10),floor(lon*10)`, a cell of about 11 km.
Its location never leaves the phone; the cell is all the server gets. It is the demand
signal for placing new receptors (`docs/siting-pilot.md`, "Demand-driven growth"). One cell
per token: registering again replaces it, and registering without `demand_cell` clears it.

The first time a token registers this way, the server sends the "no coverage yet" push
below. The demand only counts once APNs has accepted a push to that token, so an invented
token never counts. The app shows "Su zona todavía no tiene cobertura." as before.

When the level is "limited", the phone sends its receptors and its cell together:

```json
{ "device_token": "a1b2...", "sensor_ids": ["cali"], "min_magnitude": {"cali": 5.5}, "demand_cell": "62,-758", "platform": "ios" }
```

Alerts follow `sensor_ids` as usual. The cell counts as demand exactly like a cell sent
alone. Such a phone does not get "no coverage yet", since it has receptors. The server
verifies its token with one background push instead, which the user never sees:

```json
{ "aps": { "content-available": 1 }, "kind": "verify" }
```

Headers `apns-push-type: background`, `apns-priority: 5`. The app ignores it. It is sent
again on each registration until APNs accepts one.

### Strong quakes only

A receptor followed only for strong quakes goes in `min_magnitude`. The server skips that
phone for alerts from that receptor whose magnitude is below the value. An alert with no
magnitude is always sent: when unsure, the phone is alerted. A skipped alert does not count
as delivered for the per-quake dedup, so the same quake from another receptor of the phone
still arrives. Registering again without `min_magnitude` clears it.

The app sends 5.5 for every receptor it follows only because of the far rule (see "sensors.json
and coverage levels"). Without it the phone would also get the weak quakes it will not feel:
about 75% of that receptor's alerts would be false for the user.

## DELETE /devices

```json
{ "device_token": "a1b2..." }
```

`204` whether the token exists or not, so the app can retry safely. `400` if the token
is malformed. It counts against the same limit of 120 per IP as `POST /devices`. The app
calls it when the user turns alerts off. Leaving all coverage is a `POST /devices` with
`demand_cell`, not a DELETE.

## POST /devices/test

"Enviar alerta de prueba": sends one test push to a registered phone, so the user (and App
Review, who cannot wait for a quake) hears how an alert sounds.

```json
{ "device_token": "a1b2..." }
```

| response | when |
|---|---|
| `202 {"sent_at_ms": 1790194180512, "event_id": "test:6f1c...-..."}` | queued; the push goes out right after |
| `400 {"error": "invalid device_token"}` | malformed token, or invalid JSON |
| `404 {"error": "unknown device_token"}` | the token is not registered |
| `429 {"error": "one test alert per 10 min"}` | this token already got one in the last 10 min |
| `429 {"error": "too many subscriptions"}` | over the per-IP limit it shares with `/devices` (120 in 10 min) |
| `503 {"error": "relay paused"}` | the operator's kill switch is on: real alerts are off, so nothing is sent. The app shows "Servicio interrumpido" |

The push:

```json
{
  "aps": {
    "alert": { "title": "Alerta de prueba", "body": "Así sonará una alerta de sismo. Esto es solo una prueba.",
               "title-loc-key": "TEST_ALERT_TITLE", "loc-key": "TEST_ALERT_BODY", "loc-args": [] },
    "sound": "default",
    "interruption-level": "time-sensitive",
    "mutable-content": 1
  },
  "kind": "test",
  "event_id": "test:6f1c...-...",
  "sent_at_ms": 1790194180512
}
```

Headers `apns-priority: 10`, `apns-expiration` 60 s after `sent_at_ms`, `apns-collapse-id`
`test:<first 8 characters of the token>`. It is never `critical`. `sent_at_ms` and `event_id`
are the same values as in the 202. `event_id` is new for every test push, so arrival
telemetry dedups on it.

It is not a quake: it does not count for the per-quake dedup, it is not in the evidence the
certifier reads, and a failed test push does not mark the receptor as degraded. With
`kind: "test"` the NSE must not fire AlarmKit or anything a real alert does beyond the
sound. The per-token limit is kept in the gateway's memory, so a restart resets it.

### No authentication, on purpose for now

Today `/devices` and `/devices/test` have no auth. **App Attest once the app exists.** Meanwhile the
risk is low: a made-up token only produces `BadDeviceToken` on the first push and the
server deletes it, and the per-IP rate limit stops mass abuse. What someone who knows a
real token can do is change its receptors, or make it play one test alert every 10 min. The
token is not public.

## Arrival telemetry (test phones only)

This is how we measure the real chain: quake, receptor, gateway, APNs, iPhone. Each push that
carries `sent_at_ms` (alert, test, probe) is logged by the NSE and the app, and a test phone
uploads those arrivals. Normal users never upload anything.

Opt-in is set by the operator with the monitor key, not by the app. The 201 of
`POST /devices` then carries `"telemetry": true`, and re-registering keeps it. Without that
flag the app does not upload.

### POST /telemetry/arrivals

```json
{
  "device_token": "a1b2...",
  "arrivals": [
    { "kind": "alert", "event_id": "chaparral:...", "sent_at_ms": 1790194180512,
      "received_at_ms": 1790194180931, "source": "nse", "app_state": "background" }
  ]
}
```

| field | rule |
|---|---|
| `arrivals` | 1 to 500 items. One bad item refuses the whole batch |
| `kind` | `"alert"`, `"test"` or `"probe"`, from the push |
| `event_id` | from the push, 1 to 200 characters |
| `sent_at_ms` | from the push (gateway clock), integer epoch ms |
| `received_at_ms` | when the phone got it (phone clock), integer epoch ms |
| `source` | `"nse"` (Notification Service Extension) or `"app"` (the app saw it) |
| `app_state` | `"foreground"`, `"background"` or `"unknown"` at arrival. QA splits the numbers on it |

| response | when |
|---|---|
| `202 {"stored": 2, "duplicates": 1}` | stored. The same `(device_token, event_id, source)` is stored once; a resend counts as a duplicate |
| `400 {"error": "invalid arrivals"}` | any item breaks a rule above. Drop the batch, do not retry it |
| `400 {"error": "invalid device_token"}` | malformed token, or invalid JSON |
| `404 {"error": "unknown device_token or telemetry off"}` | not registered, or not opted in. Stop uploading |
| `413` | body over 128 KB |
| `429 {"error": "too many uploads"}` | more than 120 uploads from this token in 10 min |
| `503 {"error": "telemetry not stored"}` | the server could not write it. Retry, it is not marked as seen |

On 429 or 5xx, retry later with backoff. The upload never touches the alert path: it has its
own file and shares nothing with the fanout.

`received_at_ms - sent_at_ms` mixes two clocks. iPhone clocks are usually within a second
of real time, so read the median over many pushes, not one value.

### Probe push (device test T5)

The operator can send a burst of up to 50 pushes, at least 1 s apart, to one opted-in test
phone. It skips the 10 min limit of the test button. Each push:

```json
{
  "aps": {
    "alert": { "title": "Prueba de entrega", "body": "Prueba 3 de 50. No es un sismo." },
    "sound": "default",
    "interruption-level": "active",
    "mutable-content": 1
  },
  "kind": "probe",
  "event_id": "probe:<probe_id>:3",
  "probe_id": "<uuid>",
  "seq": 3,
  "sent_at_ms": 1790194180512
}
```

Headers `apns-priority: 10`, `apns-expiration` 60 s after sending, `apns-collapse-id` equal
to `event_id`. With `kind: "probe"` the NSE logs the arrival and shows the text as it is.
It is not a quake: no AlarmKit, no dedup, nothing else.

Operator routes, all signed with the monitor key (not for the app):
`POST /devices/telemetry {"device_token", "enabled"}`,
`POST /probe/apns-burst {"device_token", "n", "interval_ms"}` (202 with `probe_id`, 409 while
one runs for that phone, 404 unless opted in) and `GET /telemetry?since=` (same paging as
`/evidence`). The burst writes one `APNS_BURST` evidence record with the APNs answer per push.

## APNs push

Headers: `apns-push-type: alert`, `apns-priority: 10`, `apns-topic` = bundle id,
`apns-expiration` = absolute expiry (APNs drops it after that), `apns-collapse-id`.

All payloads carry `"mutable-content": 1` for the Notification Service Extension.
They are told apart by `kind` and, within alerts, by `late`.

`event_id` and `collapse-id` are **opaque**: the app does not extract information from them.

### Localized text

Every visible push the gateway writes carries `title-loc-key`, `loc-key` and `loc-args` in
`aps.alert`. iOS looks the keys up in the app's String Catalog and shows the text in the
phone's language. `title` and `body` are still sent, in Spanish, as the reference text.

This table is the single list of keys. The String Catalog and every translation use exactly
these keys and argument order:

| push | `title-loc-key` | `loc-key` | `loc-args` | Spanish reference |
|---|---|---|---|---|
| alert with magnitude | `ALERT_TITLE` | `ALERT_BODY_MAGNITUDE` | `[magnitude]` | "Alerta de sismo" / "Sismo M%@ cerca de su zona. Protéjase ahora." |
| alert without magnitude | `ALERT_TITLE` | `ALERT_BODY_NO_MAGNITUDE` | `[]` | "Alerta de sismo" / "Posible sismo cerca de su zona. Protéjase ahora." |
| late alert | `LATE_ALERT_TITLE` | `LATE_ALERT_BODY` | `[minutes]` | "Aviso de sismo atrasado" / "El sismo ocurrió hace %@ min. Ya no es un aviso anticipado." |
| test alert | `TEST_ALERT_TITLE` | `TEST_ALERT_BODY` | `[]` | "Alerta de prueba" / "Así sonará una alerta de sismo. Esto es solo una prueba." |
| receptor down | `SERVICE_DOWN_TITLE` | `SERVICE_DOWN_BODY` | `[]` | "Servicio interrumpido" / "Ahora mismo no podemos avisarle." |
| receptor back | `COVERAGE_RESTORED_TITLE` | `COVERAGE_RESTORED_BODY` | `[]` | "Cobertura restablecida" / "Las alertas de su zona vuelven a funcionar." |
| no receptor yet | `NO_COVERAGE_TITLE` | `NO_COVERAGE_BODY` | `[]` | "Sin cobertura en su zona" / "Su zona todavía no tiene cobertura." |

- `loc-args` are always strings, never localized by the server. `magnitude` has one decimal
  and a dot (`"4.8"`, `"5.0"`); `minutes` is a whole number (`"3"`). In the catalog use `%@`
  (or `%1$@`). To show "4,8" in a comma locale, the NSE formats `magnitude` from the payload.
- A new language only needs catalog entries. No server change.
- Trap: if the app's catalog lacks a key, iOS shows the key itself (`ALERT_TITLE`), not the
  Spanish `title`. So every build must ship all keys in its base language. The NSE can also
  fall back to `title`/`body` when the text it receives equals the key.
- The probe push (test phones only) and Web Push stay Spanish, without keys.

### Alert

```json
{
  "aps": {
    "alert": { "title": "Alerta de sismo", "body": "Sismo M4.8 cerca de su zona. Protéjase ahora.",
               "title-loc-key": "ALERT_TITLE", "loc-key": "ALERT_BODY_MAGNITUDE", "loc-args": ["4.8"] },
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
  "expires_at": "2026-09-24T10:05:00.000Z",
  "sent_at_ms": 1790194180512
}
```

- `sent_at_ms` is the gateway clock, in epoch ms, at the moment the request to APNs for this
  phone went out. A retry to APNs carries its own new value. The NSE logs its own arrival time
  against it to measure the APNs leg. Phone and server clocks differ by up to about a second,
  so use the median over many pushes, never one value. Only alert pushes carry it.

- `title` and `body` are **always composed by the gateway** from `magnitude` and `late`. The
  text the receptor sends is ignored: an old or compromised one cannot put words
  on the phone.
- `magnitude`, `distance_km` and `time_occurred_s` can be `null`.
- `magnitude` and `distance_km` arrive raw (for example `4.45852`). The app rounds to 1
  decimal.
- **`distance_km` is the distance from the RECEPTOR to the epicenter. The app NEVER shows it as
  the distance to the user.** The phone does not know where the quake was. The app shows the
  magnitude and "sismo cerca de su zona", which is what the `body` already carries. Without magnitude, the
  `body` is "Posible sismo cerca de su zona. Protéjase ahora."
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
- keys: `LATE_ALERT_TITLE` / `LATE_ALERT_BODY`, `loc-args: ["N"]`

With `late: true` the app does not say "protéjase" nor fire AlarmKit. It also does not recompute the
delay with the phone clock.

### No coverage / coverage restored

```json
{
  "aps": {
    "alert": { "title": "Servicio interrumpido", "body": "Ahora mismo no podemos avisarle.",
               "title-loc-key": "SERVICE_DOWN_TITLE", "loc-key": "SERVICE_DOWN_BODY", "loc-args": [] },
    "sound": "default",
    "interruption-level": "active",
    "mutable-content": 1
  },
  "kind": "coverage",
  "sensor_id": "chaparral",
  "covered": false
}
```

With `covered: true` the text is `"Cobertura restablecida"` / `"Las alertas de su zona
vuelven a funcionar."`, keys `COVERAGE_RESTORED_TITLE` / `COVERAGE_RESTORED_BODY`. It expires after 12 h.

It is sent **per receptor** and each phone gets it only when it changes **for that phone**:
"Servicio interrumpido" if it had not been told yet (for example on registration, above), and
"Cobertura restablecida" only if it got "Servicio interrumpido" before. The server remembers the
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
    "alert": { "title": "Sin cobertura en su zona", "body": "Su zona todavía no tiene cobertura.",
               "title-loc-key": "NO_COVERAGE_TITLE", "loc-key": "NO_COVERAGE_BODY", "loc-args": [] },
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
  "apns_dry_run": false,
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
- `apns_dry_run: true` means the gateway fakes every APNs push, as in the lab today. No
  iPhone gets anything.

## sensors.json and coverage levels

`GET /sensors.json`:

```json
{
  "version": 2,
  "coverage": { "full_km": 31, "partial_km": 78 },
  "sensors": [{ "id": "chaparral", "name": "Chaparral", "lat": 3.7236, "lon": -75.4836, "public": true }]
}
```

Only sensors with `"public": true` count; `/devices` rejects the rest. The radii come from
the magnitude → radius table of Allen et al. 2025: M4.5 reaches 31 km and M5.0 78 km.

The level on screen is computed by the app, on the phone. The gateway does not compute it.
It depends on the chosen set of receptors, not on the distance to the closest one: a single
receptor 31 km away can miss 61% of the M4.5 alerts the user's own phone would get
(`docs/research/ios-techniques.md`, section 4). The reference is `ReceptorChooser` in
`ios-client/RelayCore`; if this text and that code disagree, fix one of them.

A receptor is eligible when it is public and one of these holds:

- near: within `partial_km` (78 km). One the phone already follows stays near up to
  78 km + max(10, 2 × fix accuracy in km);
- far: alone it misses at most 40% of the M5.5 alerts the user's own phone would get (in
  practice up to about 125 km). One the phone already follows stays eligible up to 45%.

Far receptors are followed for strong quakes only, with `min_magnitude` 5.5. The phone picks
up to 3 eligible receptors; see the research for how it scores the sets.

Miss share at a magnitude: the fraction of epicenters in the disc of radius R around the user
that no receptor of the set reaches (receptor farther than R from the epicenter). R is 31,
78 and 197 km for M4.5, 5.0 and 5.5. A far receptor does not count below M5.5, and neither
does a receptor with `covered_apns: false` in `/status`. The epicenters are a fixed set of
256 points (a sunflower spiral over the disc, the same points every time), never random ones,
so a user near 10% or 40% does not flip level between recomputes. They are placed in a flat
local projection around the user; the distance to decide "near" is haversine, Earth radius
6371 km.

The rows are checked in this order; the first that matches wins:

| condition | level | text (UI, Spanish) |
|---|---|---|
| 1. no eligible receptor | none | Su zona todavía no tiene cobertura. Registered with `demand_cell` only |
| 2a. every chosen receptor has `covered_apns: false` | down | Servicio interrumpido. Ahora mismo no podemos avisarle. Lo estamos arreglando. |
| 2b. `/status` does not answer | down | Servicio interrumpido. Ahora mismo no podemos avisarle. Revise su conexión a internet. |
| 3. miss share at M5.0 ≤ 10% | full | Cobertura completa |
| 4. miss share at M5.0 ≤ 40% | partial | Cobertura parcial: algunos sismos pequeños podrían no avisarse. |
| 5. higher | limited | Cobertura limitada: solo le avisaremos de sismos fuertes. Registered with `demand_cell` too |

"down" has the same title as the lost-coverage push, and it is red. It is not "none": the
receptors exist, they are just not working now, so the app keeps its `sensor_ids` and does
not change its registration. The 5 min grace for a `/status` that does not answer (see
`GET /status`) applies here too.

A set of only far receptors misses every M5.0 alert by definition, so it is always
"limited". As a guide, one near receptor is full up to about 12 km and partial up to about
50 km.

`full_km` in `sensors.json` is only used by the web page (`gateway/public/coverage.js`),
which stays on the old distance rule: it is for testing only and is removed once the iOS app
ships. The app ignores `full_km`.

## Significant location change

1. iOS wakes the app with the significant location change.
2. The app downloads `sensors.json` (or uses its copy) and computes on the phone the distance to
   each public receptor.
3. It chooses up to 3 eligible receptors (`ReceptorChooser`) and computes the level above.
4. If the set, its `min_magnitude` or the cell to send changed, it calls `POST /devices` with
   those `sensor_ids`, `min_magnitude` 5.5 for the far ones, and its `demand_cell` when the
   level is "limited". If no receptor is eligible, it calls `POST /devices` with only its `demand_cell` and shows "sin cobertura".
5. The location stays on the phone; only the cell leaves it, and only when the level is
   "limited" or "none".

## Missing in the backend

- **Per-phone state.** `/status` is per receptor. The app builds its own state from
  its 2-3 receptors; there is no "you are covered" per token.
- **Auth on /devices.** App Attest, once the app exists (see above).

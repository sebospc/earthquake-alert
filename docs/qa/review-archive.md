# QA review: archive

The closed phases, as they were in `review.md` until 24-sep 18:30 UTC, unchanged.
What is current is in `review.md`. To find a finding: `grep -n "QA-NN" docs/qa/review-archive.md`.

The body below is history and stays in Spanish. Its phase headings start with
`## Fase N` (Phase N), so `grep -n "Fase N" docs/qa/review-archive.md` finds each one.

## Index

| QA | phase |
|---|---|
| QA-01 | Phase 1: initial review ("Hallazgos" section) |
| QA-02 | Phase 1: initial review ("Hallazgos" section) |
| QA-03 | Phase 1: initial review ("Hallazgos" section) |
| QA-04 | Phase 1: initial review ("Hallazgos" section) |
| QA-05 | Phase 1: initial review ("Hallazgos" section) |
| QA-06 | Phase 1: initial review ("Hallazgos" section) |
| QA-07 | Phase 1: initial review ("Hallazgos" section) |
| QA-08 | Phase 1: initial review ("Hallazgos" section) |
| QA-09 | Phase 1: initial review ("Hallazgos" section) |
| QA-10 | Phase 1: initial review ("Hallazgos" section) |
| QA-11 | Phase 1: initial review ("Hallazgos" section) |
| QA-12 | Phase 1: initial review ("Hallazgos" section) |
| QA-13 | Phase 1: initial review ("Hallazgos" section) |
| QA-14 | Phase 1: initial review ("Hallazgos" section) |
| QA-15 | Phase 1: initial review ("Hallazgos" section) |
| QA-16 | Phase 1: initial review ("Hallazgos" section) |
| QA-17 | Phase 1: initial review ("Hallazgos" section) |
| QA-18 | Phase 1: initial review ("Hallazgos" section) |
| QA-19 | Phase 1: initial review ("Hallazgos" section) |
| QA-20 | Phase 1: initial review ("Hallazgos" section) |
| QA-21 | Phase 1: initial review ("Hallazgos" section) |
| QA-22 | Phase 2: web push, PWA, heartbeat |
| QA-23 | Phase 2: web push, PWA, heartbeat |
| QA-24 | Phase 2: web push, PWA, heartbeat |
| QA-25 | Phase 2: web push, PWA, heartbeat |
| QA-26 | Phase 2: web push, PWA, heartbeat |
| QA-27 | Phase 2: web push, PWA, heartbeat |
| QA-28 | Phase 2: web push, PWA, heartbeat |
| QA-29 | Phase 2: web push, PWA, heartbeat |
| QA-30 | Phase 2: web push, PWA, heartbeat |
| QA-31 | Phase 2: web push, PWA, heartbeat |
| QA-32 | Phase 2: web push, PWA, heartbeat |
| QA-33 | Phase 3: verification of the fixes |
| QA-34 | Phase 3: verification of the fixes |
| QA-35 | Phase 3: verification of the fixes |
| QA-36 | Phase 3: verification of the fixes |
| QA-37 | Phase 3: verification of the fixes |
| QA-38 | Phase 3: verification of the fixes |
| QA-39 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-40 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-41 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-42 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-43 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-44 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-45 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-46 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-47 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-48 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-49 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-50 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-51 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-52 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-53 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-54 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-55 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-56 | Phase 4: re-run of `aws-bootstrap.sh` on the live EC2 |
| QA-57 | Phase 5: APNs per sensor (iOS app) |
| QA-58 | Phase 5: APNs per sensor (iOS app) |
| QA-59 | Phase 5: APNs per sensor (iOS app) |
| QA-60 | Phase 6: load, watchdog, QA-59 and boot queue |
| QA-61 | Phase 6: load, watchdog, QA-59 and boot queue |
| QA-62 | Phase 6: load, watchdog, QA-59 and boot queue |
| QA-63 | Phase 6: load, watchdog, QA-59 and boot queue |
| QA-64 | Phase 6: load, watchdog, QA-59 and boot queue |
| QA-65 | Phase 6: load, watchdog, QA-59 and boot queue |
| QA-66 | Phase 6: load, watchdog, QA-59 and boot queue |
| QA-67 | Phase 6: load, watchdog, QA-59 and boot queue |
| QA-68 | Phase 6: load, watchdog, QA-59 and boot queue |
| QA-69 | Phase 7: iOS contract (`docs/ios-contract.md`) against `server.js` |
| QA-70 | Phase 7: iOS contract (`docs/ios-contract.md`) against `server.js` |
| QA-71 | Phase 7: iOS contract (`docs/ios-contract.md`) against `server.js` |
| QA-72 | Phase 7: iOS contract (`docs/ios-contract.md`) against `server.js` |
| QA-73 | Phase 7: iOS contract (`docs/ios-contract.md`) against `server.js` |
| QA-74 | Phase 7: iOS contract (`docs/ios-contract.md`) against `server.js` |
| QA-75 | Phase 7: iOS contract (`docs/ios-contract.md`) against `server.js` |
| QA-76 | Phase 7: iOS contract (`docs/ios-contract.md`) against `server.js` |
| QA-77 | Phase 8: DELETE /devices, apns_env, per-endpoint limits, QA-54/69/70/76/77 |
| QA-78 | Phase 9: certifier (`monitor/`) |
| QA-79 | Phase 9: certifier (`monitor/`) |
| QA-80 | Phase 9: certifier (`monitor/`) |
| QA-81 | Phase 9: certifier (`monitor/`) |
| QA-82 | Phase 9: certifier (`monitor/`) |
| QA-83 | Phase 9: certifier (`monitor/`) |
| QA-84 | Phase 10: real quake of 24-sep, 16:46:33 UTC (Chaparral) |
| QA-85 | Phase 10: real quake of 24-sep, 16:46:33 UTC (Chaparral) |
| QA-86 | Phase 10: real quake of 24-sep, 16:46:33 UTC (Chaparral) |

---

# Revisión adversarial del relay

24-sep-2026. Alcance: `android-listener` (CaptureService, Forwarder, RelayPolicy,
EvidenceStore), `gateway/src/server.js` tal como estaba a las ~01:00 (ya con web push,
kill switch y `/status` a medio hacer) y `scripts/lab.py`.

La pregunta fue siempre la misma: cómo se pierde una alerta real sin que nadie se
entere, o cómo sale una que no debía.

Estado: **confirmado** = reproducido con un test o sonda. **lectura** = sale del código,
no se pudo probar sin tocar producción o un device.

## Estado actual (24-sep, verificado en el código)

`npm test`: 55/55, 0 `todo`, 0 skipped. `e2e-relay.sh`: ok. Las cifras de cada fase de
abajo (36/36, 38/38) son del momento en que se cerró esa fase.

Los ids que en las tablas de abajo no dicen "arreglado", revisados uno por uno:

| id | estado real | evidencia |
|---|---|---|
| QA-07 | arreglado | `lab.py`: canario por device (`last_ok_by_device`) |
| QA-08 | arreglado | `Forwarder`: `relay.json` inválido se reporta una vez (`invalidConfigReported`) |
| QA-15 | arreglado | comentario de `CLOCK_SKEW_MAX_S` corregido a +2/−3 min |
| QA-18 | arreglado | ruta legado borrada: sin `sensor_id` → 401 (test en QA-14) |
| QA-21 | obsoleto | el test que tapaba QA-01 ya no existe |
| QA-27 | arreglado | por QA-62: 202 antes del reparto |
| QA-29 | arreglado | la PWA explica que en iPhone no salta el silencio ni los modos de concentración |
| QA-30 | arreglado | `sw.js` tolera un payload roto y siempre muestra algo |
| QA-59 | arreglado | `covered_apns` / `covered_webpush`, con test |
| QA-32 | aceptado | documentado en el comentario de `subscriptions.add` |
| QA-55 | aceptado | nota de runbook |
| QA-58 | aceptado | documentado en el comentario de `claimQuake` |
| QA-64 | resuelto en la operación | la EC2 corre la cantidad de emuladores decidida |
| QA-10 | aceptado (coordinador, 24-sep): candidato a optimización, cada emulador tiene su propio Forwarder | `SENDER` sigue siendo un solo hilo: con el gateway caído, una alerta lo ocupa ~47 s y la siguiente espera. Los duplicados sin `TIME_OCCURRED` ya los absorbe el dedup por sismo del gateway |
| QA-20 | aceptado, a propósito (comentario en `isRelayable`) | el relay solo reenvía `eew_alert*`. Un canal renombrado lo ve el operador (UPDATE urgente), pero el usuario no recibe nada |
| QA-54 | arreglado (fase 8) | `sensor-health.py:116-118`: `reboot_if_stuck` sigue después de `report` |
| QA-67 | **abierto, media**: lo mide el coordinador en la EC2 el día del sismo de validación | CPU en el momento de un evento, en la EC2: sin medir (punto 10 del checklist) |

## Hallazgos

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-01 | crítica | APNs no responde (caída, DNS, red). `http2.connect` emite `error` en la sesión sin listener y **el proceso del gateway muere**. Todas las alertas siguientes se pierden hasta que alguien lo reinicie. | `gateway/src/server.js:130` | confirmado, `relay-failures.test.js` QA-01 |
| QA-02 | crítica | APNs contesta 403/410/400 a todos los tokens (token de proveedor vencido, topic mal, device desregistrado). `sendOne` resuelve igual, el gateway responde `202 accepted` y marca el evento como visto. El sensor deja de reintentar y nadie recibió nada. Lo mismo con web push: cualquier error que no sea 404/410 se traga. Cero tokens y cero suscriptores también da 202. | `server.js:118`, `server.js:240-244`, `server.js:343` | confirmado, QA-02 |
| QA-03 | crítica | APNs tarda más de 5 s (read timeout de Forwarder). Forwarder reintenta, el gateway ve el id en `seen` y responde `202 duplicate`, Forwarder lo toma como éxito y para. Si el primer envío termina fallando, `seen` se borra pero ya no queda quien reintente. | `server.js:329-331`, `Forwarder.java:71` | confirmado, QA-03 |
| QA-05 | crítica | Disco lleno o error de IO. `EvidenceStore.append` lanza `IllegalStateException`. En `onNotificationPosted` y `onListenerConnected` eso corre en el hilo principal: el proceso cae, y con él el executor que tenía la alerta en cola. En `onListenerConnected` queda en bucle de crash, el listener no vuelve. Dentro del loop de Forwarder mata los reintentos de esa alerta. El archivo de evidencia crece sin límite, así que el disco lleno llega solo. | `EvidenceStore.java:29`, `CaptureService.java:32`, `CaptureService.java:77`, `Forwarder.java:70` | lectura |
| QA-11 | alta | APNs acepta la conexión y nunca contesta. No hay timeout en `sendOne` ni en web push: el evento queda reclamado en `seen` para siempre y cada reintento recibe `202 duplicate`. Variante permanente de QA-03. | `server.js:101-121`, `server.js:238` | lectura |
| QA-06 | alta | Las fallas del relay no las mira nadie. Forwarder escribe `RELAY_ATTEMPT` con el status, pero `lab.py` no lo lee. El canario usa el paquete fixture, que `isRelayable` rechaza, así que config, secreto, `sensor_id`, red y reloj del camino de relay no tienen canario. Ejemplo: un typo en `sensor_id` de `relay.json` hace que el gateway conteste `400 unknown sensor_id` a cada alerta, para siempre, en silencio. | `scripts/lab.py:295-318`, `RelayPolicy.java:18-23` | lectura |
| QA-07 | alta | `canary.last_ok` es uno solo para toda la flota. Si el listener muere en cuatro emuladores y sigue vivo en uno, ese uno mantiene el canario fresco y "Cadena rota" nunca sale. | `scripts/lab.py:300`, `scripts/lab.py:338` | lectura |
| QA-08 | alta | `relay.json` corrupto, truncado o sin un campo se trata igual que ausente: modo laboratorio, no se envía nada, no queda ni una línea en la evidencia. Un sensor que debía relayar deja de hacerlo sin rastro. | `Forwarder.java:38`, `Forwarder.java:113-118` | lectura |
| QA-09 | alta | Notificación publicada mientras el listener no está enlazado (arranque, rebind tras `onListenerDisconnected`, update de la app). Android no la reenvía a `onNotificationPosted` y `onListenerConnected` no revisa `getActiveNotifications()`. La alerta sigue en pantalla del emulador y nunca sale. | `CaptureService.java:30-33` | lectura |
| QA-04 | media | La escritura de evidencia falla después de un envío bueno (disco lleno, permisos). El gateway responde 400 y libera el id; cada reintento de Forwarder vuelve a despertar a todos, hasta 5 veces. Pasa lo mismo si `subscriptions.remove` falla al persistir. | `server.js:342`, `server.js:347`, `server.js:242` | confirmado, QA-04 |
| QA-10 | media | Un solo hilo de envío. Con el gateway caído una alerta ocupa hasta ~47 s (5 intentos × 8 s de timeouts + 7.5 s de backoff) y la siguiente espera detrás. Además, si falta `TIME_OCCURRED_EXTRA`, cada update de la notificación en `eew_alert*` trae otro `postTime`, otro `event_id` y otro push. | `Forwarder.java:31`, `Forwarder.java:61-74`, `RelayPolicy.java:38` | lectura |
| QA-12 | media | Doble push por sismo. `event_id` lleva el `sensor_id`, los tokens APNs son globales: un iPhone recibe un aviso por cada sensor que vio el sismo, con `apns-collapse-id` distinto, así que no se colapsan. Un iPhone que está en `APNS_DEVICE_TOKENS` y además suscrito en la PWA recibe dos. El web push por sensor no tiene el problema porque `add` borra la suscripción de otros sensores. | `RelayPolicy.java:39`, `server.js:133`, `server.js:235` | lectura |
| QA-13 | media | Alerta tardía como aviso. El TTL de 3 min cuenta desde la captura, no desde el origen del sismo, y el gateway ignora `time_occurred_s`. Si la notificación llega tarde al listener (emulador pausado, rebind), sale "Protéjase ahora" igual. | `Forwarder.java:40`, `Forwarder.java:47-48`, `server.js:41-66` | lectura |
| QA-14 | media | Un solo `RELAY_HMAC_SECRET` para todos los sensores y el gateway no ata el secreto al `sensor_id`. Con el secreto de un emulador se puede disparar una alerta para cualquier sensor, incluso con `interruption_level: critical`. | `server.js:313`, `server.js:62` | lectura |
| QA-15 | baja | La ventana de reloj real es +2/−3 min, no ±5 min como dice el comentario de lab.py: `expires_at` = captura + 180 s y el gateway rechaza expiraciones a más de 5 min, así que un reloj adelantado más de 120 s ya se rechaza. lab.py avisa a los 30 s, entonces hoy está cubierto; el comentario engaña. | `server.js:57-58`, `scripts/lab.py:185` | confirmado (+100 s ok, +130 s rechazado, −190 s rechazado) |
| QA-16 | baja | `seen` nunca se poda. Crece poco porque hay pocas alertas; el riesgo real es el opuesto: vive en memoria, así que tras un reinicio un reintento se vuelve a enviar. | `server.js:11` | lectura |
| QA-17 | baja | Magnitud o distancia `NaN`/`Infinity`: `JSONObject.put` lanza, `CaptureService.put` lo convierte en `IllegalStateException` en el hilo principal y la alerta se pierde con el crash. Improbable, pero el costo es total. | `Forwarder.java:52-53`, `CaptureService.java:149-151` | lectura |
| QA-18 | baja | Evento sin `sensor_id` se acepta y el web push se salta sin avisar. Forwarder siempre lo manda, por eso es baja. | `server.js:219`, `server.js:320` | lectura |
| QA-19 | baja | Body por encima de 16 KB: `request.destroy()` y la promesa de `readBody` nunca se resuelve. No tumba nada, deja un handler colgado. | `server.js:294` | lectura |
| QA-20 | baja | Si Google renombra el canal a otro `eew_*` que no empiece con `eew_alert`, lab.py lo marca `UPDATE` (el operador se entera) pero el relay no lo reenvía. El usuario no recibe nada. | `RelayPolicy.java:22`, `scripts/lab.py:202` | lectura |
| QA-21 | baja | El test "a failed APNs dispatch..." usa una clave inválida, falla antes de conectar y por eso no detectó QA-01. | `gateway/test/server.test.js:79` | confirmado |

## Fase 2: web push, PWA, heartbeat

Contra `server.js`, `public/index.html`, `public/sw.js` y el heartbeat de `Forwarder` del
24-sep ~02:00.

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-22 | alta | Un 503/429 o un corte de red del push service al entregar a un teléfono: ese usuario se queda sin la alerta. No hay reintento por suscripción y el evento ya cuenta como entregado. Solo queda el status en la evidencia, nadie lo mira. | `server.js:237-245` | confirmado, `web-push.test.js` QA-22 |
| QA-23 | alta | "Verde" en la PWA no significa cobertura. El heartbeat prueba listener enlazado, `relay.json`, red y reloj. No prueba que AEA siga registrado ni que el emulador conserve la ubicación. lab.py detecta las dos cosas pero solo avisa al operador: el usuario sigue viendo "Última verificación hace 3 min". | `Forwarder.java:87-110`, `scripts/lab.py:254-272`, `server.js:381-383` | lectura |
| QA-24 | alta | El usuario nunca se entera de que perdió cobertura. El estado vive en la PWA y solo se ve con la página abierta. Si el sensor se pone viejo o se activa el kill switch, no se manda nada a los suscriptores. La última fila de la tabla de riesgos de `decision.md` sigue abierta en la práctica. | `index.html:104-127` | lectura |
| QA-25 | alta | Se elige el sensor más cercano sin límite de distancia. Alguien en Bogotá o en Cali queda con un sensor a cientos de km, en verde, y un sismo cerca suyo no dispara nada en ese sensor. Hinatuan (control, Filipinas) también se puede elegir. El sensor queda fijo desde la activación: si la persona se muda, sigue en el viejo. | `index.html:145-147`, `public/sensors.json` | lectura |
| QA-26 | media | `/subscribe` no tiene auth ni límite por cliente. Un script llena el tope de 10.000 con endpoints falsos de `fcm.googleapis.com` y los usuarios reales reciben 400. Las claves basura hacen que `sendNotification` lance sin `statusCode` (status `-1`), así que nunca se borran. | `server.js:160-163`, `server.js:204-206`, `server.js:244` | confirmado (web-push lanza "p256dh should be 65 bytes", sin statusCode) |
| QA-27 | media | `/events` espera todos los web push antes de responder. Con muchos suscriptores o un push service lento la respuesta pasa los 5 s de Forwarder y cae en QA-03. `webpush` no tiene `timeout`: un push service colgado deja el evento reclamado para siempre (QA-11). | `server.js:335-338`, `server.js:227-234` | lectura |
| QA-28 | media | El service worker decide "atrasado" con el reloj del teléfono. Teléfono adelantado 3 min: una alerta a tiempo sale como "ya no es un aviso anticipado" y la persona no se protege. Atrasado: una tarde sale como "Protéjase ahora". El TTL del push service ya descarta las tardías, este chequeo es el respaldo. | `sw.js:4` | lectura |
| QA-29 | media | En iPhone, el web push de una PWA no es time-sensitive ni crítico: Focus y el modo silencio lo apagan. `requireInteraction` no existe en Safari. La persona cree que la despierta y no. Es un límite de la plataforma; la PWA debería decirlo. | `sw.js:12-14`, `index.html` | lectura |
| QA-30 | baja | Payload vacío o que no es JSON: `event.data.json()` lanza y no se muestra nada. Safari revoca la suscripción si un push no muestra notificación. | `sw.js:2` | lectura |
| QA-31 | baja | El umbral de "viejo" (15 min) vive solo en `index.html`, sin test. `/status` no marca nada. Con beat cada 5 min, un sensor muerto se ve verde hasta ~15 min; un heartbeat capturado se puede repetir 5 min más. | `index.html:57`, `index.html:116-117`, `server.js:171` | lectura |
| QA-32 | baja | `removeEverywhere` corre antes del chequeo de tope. En el tope, un teléfono que se re-suscribe pierde el sensor viejo y el nuevo lo rechaza. | `server.js:203-206` | lectura |

### Sobre "un fallo por suscripción no reintenta"

Sí hace falta reintentar, y adentro del gateway, no en el sensor. El push service guarda el
mensaje si el teléfono está apagado, así que lo único que puede fallar de nuestro lado es la
entrega al push service, y eso suele ser transitorio (429, 5xx, red). Propuesta:

- Reintentar solo 429, 5xx, timeout y error de red, con backoff corto (0.5, 1, 2, 4 s) y
  solo mientras quede TTL. `topic` ya hace que el push service reemplace la copia y el `tag`
  del SW evita el doble aviso en el teléfono, así que reintentar no molesta.
- No reintentar 400/403/413: eso es config rota (VAPID, payload). Tiene que ser ruidoso,
  igual que QA-02.
- Hacerlo después de responder al sensor, para no alargar `/events` (QA-27). No volver a
  hacer reintentable el evento entero: repetiría el push de APNs a todos.

## Fase 3: verificación de los arreglos

24-sep. Arreglos de developer contra los hallazgos de arriba. "test" = hay un test que falla
si el arreglo se revierte (probado mutando el código en una copia: 25 mutaciones, todas
detectadas). "lectura" = revisado en el código, sin test.

| id | estado | cómo se verifica |
|---|---|---|
| QA-01 | arreglado | test `relay-failures` QA-01 |
| QA-02 | arreglado, 503 si todas fallan | test QA-02 |
| QA-03 | arreglado, 409 mientras está inflight | test QA-03 |
| QA-04 | arreglado, la evidencia nunca hace fallar el envío | test QA-04 |
| QA-05 | arreglado, `EvidenceStore.append` no lanza | lectura |
| QA-06 | arreglado, canario por sensor | test `web-push` QA-06 + e2e |
| QA-09 | arreglado, `getActiveNotifications` al reconectar | lectura, ver QA-33 |
| QA-11 | arreglado, timeout de 5 s en APNs y web push | lectura |
| QA-12 | arreglado, con `sensor_id` no hay APNs | lectura |
| QA-13 | arreglado, "atrasado" desde el origen y lo decide el server | test QA-13 + e2e |
| QA-14 | arreglado, key = HMAC(master, sensor_id) | test QA-14 + e2e |
| QA-16 | arreglado, `seen` se poda a los 15 min | lectura |
| QA-17 | arreglado, `finiteOrNull` | lectura; sin JUnit, ver abajo |
| QA-19 | arreglado, 413 | test QA-19 |
| QA-22 | arreglado, reintento por suscripción dentro del TTL, sin reintentar 4xx | 2 tests QA-22 |
| QA-23 | arreglado, `covered` pide listener fresco y `aea_ok` fresco y verdadero | test QA-23, incluye watcher muerto con listener vivo |
| QA-24 | arreglado, un push por transición, persistido | test QA-24, incluye reinicio |
| QA-25 | arreglado, niveles 31/78 km, `public` falla cerrado | `coverage.test.js` con bordes exactos |
| QA-26 | arreglado, claves de 65/16 bytes y 30 por IP cada 10 min | tests `/subscribe` y QA-26 |
| QA-28 | arreglado, `late` viene del server | test QA-13 |
| QA-31 | arreglado, `stale` en el server | `coverage.test.js` |
| QA-33 | arreglado, `post_time_ms` como origen si falta `time_occurred_s` | test QA-33 (incluye precedencia y valor basura) |
| QA-34 | arreglado, `degraded_since` apaga `covered` y dispara "Sin cobertura" | test QA-34 (incluye recuperación) |
| QA-35 | arreglado, JUnit de `finiteOrNull` (NaN e infinito en las dos variantes) y `heartbeatUrl` | JUnit |
| QA-36 | arreglado: todos 404/410 → `NO_ACTIVE_RECIPIENTS`, sin degradar. 400/413 sí degradan (payload nuestro roto), decisión de developer que comparto | test QA-36 |
| QA-37 | arreglado, `RelayPolicy.isReplayable` | JUnit `replaysOnlyWarningsStillInsideTheirTtl` |
| QA-38 | arreglado, tolerancia de 30 s hacia el futuro (`CLOCK_STEP_TOLERANCE_MS`) | JUnit, bordes +30 s y +30 s+1 ms |

La unidad de `time_occurred_s` quedó verificada: 1790194179 s + 17 s da la captura real de
las 15:09:56 del 23-sep. Si fueran milisegundos, el gateway rechazaría toda alerta real.

### Hallazgos nuevos

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-33 | media | Si falta `TIME_OCCURRED_EXTRA`, una alerta reenviada al reconectar (hasta 3 min después de publicada) o capturada tarde llega con `captured_at` = ahora y el server no tiene con qué marcarla atrasada: sale "Protéjase ahora". Mandar `post_time_ms` y que el server lo use como origen cuando falta `time_occurred_s`. | `CaptureService.java:57`, `Forwarder.java:53`, `server.js:86` | lectura |
| QA-34 | media | Todos los push de una alerta fallan (VAPID mal configurado o rotado → 403 a todos): queda `DISPATCH_FAILED_ALL` y `degraded_since`, pero `covered` sigue en true, la PWA sigue verde y nadie avisa al operador. Las alertas siguientes se pierden igual. `degraded_since` debería apagar `covered` y disparar el aviso ntfy. | `server.js:405`, `server.js:471-472` | lectura |
| QA-36 | media | Si todos los suscriptores de un sensor desinstalaron (todos dan 410), la alerta cuenta como `DISPATCH_FAILED_ALL` y el sensor queda `degraded`: rojo, y "Sin cobertura" para quien se suscriba después, hasta la próxima alerta real (pueden ser semanas) o un reinicio. No se pierde nada, pero es una falsa alarma de cobertura y quita confianza. 404/410 son "el usuario se fue", no "el sistema está roto": no deberían contar para `degraded`. | `server.js:480-486` | confirmado con sonda |
| QA-37 | baja | El filtro del replay (`now - postTime < TTL`) sigue dentro de `CaptureService` y no tiene test. Hace falta sacarlo a `RelayPolicy.isReplayable(postTimeMs, nowMs)`. | `CaptureService.java:57` | lectura |
| QA-38 | baja | `isReplayable` descarta un post "en el futuro" aunque sea por 1 ms. Si el reloj del emulador se corrige hacia atrás (NTP) entre el post y el replay, una alerta real se descarta en silencio. Raro: solo afecta al replay. Una tolerancia de unos segundos lo cubre. | `RelayPolicy.java:55` | lectura |

## Fase 4: re-run de `aws-bootstrap.sh` sobre la EC2 viva

Revisado leyendo el código, sin ejecutarlo. Escenario: r8i.large (2 vCPU) con 1 AVD
arrancada y el login de Google hecho, a la que se le vuelve a correr el bootstrap y luego
`listener <apk> chaparral`.

Lo que sí está bien:

- La AVD no se recrea (se revisa el directorio `.avd`) y no se toca userdata.
- `enable --now` no reinicia un emulador que ya corre, y `daemon-reload` tampoco.
- `/etc/earthquake-gateway.env` se genera solo si no existe: ni el master ni las claves
  VAPID rotan. La key por sensor que ya se empujó sigue valiendo.
- `rsync --delete` no toca evidencia, suscripciones ni estado de cobertura (están excluidos
  y además viven en `/var/lib`).
- Con 2 vCPU queda `AVD_COUNT=1`. Si existe un `aea-emulator@2`, se para y se deshabilita,
  y su AVD se conserva.
- El reinicio del gateway cae dentro de la gracia de 15 min: no dispara "Sin cobertura".
- El paso `listener` reescribe el mapa de sensores completo, así que no quedan entradas viejas.

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-39 | **bloquea** | `adb` corre como root (paso `listener` y `sensor-health`), pero el emulador corre como `aea`. En una imagen `google_apis_playstore`, adbd exige una clave autorizada y el emulador solo autoriza sola la de quien lo arranca (`/var/lib/aea/.android/adbkey.pub`). Con la clave de root el device sale `unauthorized` y sin ventana nadie puede aceptar el diálogo: `listener` muere en "is not booted" y `sensor-health` reporta `aea_ok=false` para siempre. Por la misma razón, `adb emu` como root falla el token de consola. Arreglo: correr todo el adb como `aea` (`User=aea` en `sensor-health.service`, `sudo -u aea` en `install_listener`). | `aws-bootstrap.sh:47-66`, `:210-219` | lectura; verificar en la EC2 con `sudo /opt/android-sdk/platform-tools/adb devices` → tiene que decir `device` |
| QA-40 | **bloquea** | `sensor-health.service` tiene `ConditionPathExists=$SENSOR_MAP` y el timer usa `OnUnitActiveSec`. Si el timer dispara antes de que exista el mapa (bootstrap corrido, `listener` todavía no), la condición falla, la unidad nunca pasa a activa y el timer se queda sin próximo disparo hasta el reboot. Después del paso `listener` no se reporta `aea_ok`, el sensor queda rojo y a los 15 min sale "Sin cobertura". Arreglo: `systemctl start sensor-health.service` al final de `install_listener`, o sacar la condición y que el script salga 0 si no hay mapa. | `aws-bootstrap.sh:210-230` | lectura (semántica de systemd); verificar con `systemctl list-timers sensor-health.timer` → NEXT no puede ser `n/a` |
| QA-41 | alta | En la EC2 nadie fija la ubicación del emulador. En el lab lo hace `lab.py` en cada ciclo, pero ahí no corre. Con `-no-snapshot`, cualquier reinicio del emulador (crash con `Restart=on-failure`, reboot) arranca sin fix, AEA no sabe dónde está y `aea_ok` pasa a false. Se ve, pero no se recupera solo. Arreglo: que `sensor-health` haga `adb emu geo fix <lon> <lat>` del sensor antes de chequear (necesita QA-39 para el token de consola). | `aws-bootstrap.sh`, `sensor-health.py:37` | lectura |
| QA-42 | alta | `sdkmanager "emulator" "$SYSTEM_IMAGE"` en cada corrida puede actualizar el emulador y la imagen de sistema debajo de una AVD viva con login. No reinicia nada, pero el próximo arranque sería con otra imagen sobre la userdata vieja. Arreglo barato: instalar solo si falta el directorio del paquete. | `aws-bootstrap.sh:112` | lectura; no verifiqué si sdkmanager actualiza un paquete ya instalado |
| QA-43 | media | `npm ci` borra `node_modules` antes de reinstalar. Si falla (red, registry), `set -e` corta antes del restart: el gateway sigue vivo con el código viejo ya cargado, pero no puede volver a arrancar. El primer crash lo deja caído (el watchdog avisa). Arreglo: instalar en un directorio temporal y cambiarlo al final, o saltarlo si `package-lock.json` no cambió. | `aws-bootstrap.sh:145-146` | lectura |
| QA-44 | media | Si el emulador vivo no corre bajo `aea-emulator@1` (por ejemplo, se arrancó a mano para hacer el login), `enable --now` levanta una segunda instancia de la misma AVD. Choca con el lock y el puerto y queda reiniciando cada 30 s. Si el arranque a mano fue como root, los archivos de la AVD pueden haber quedado de root y la unidad no arranca nunca. Revisar `systemctl status aea-emulator@1` y los dueños de `/var/lib/aea/.android/avd` antes del re-run. | `aws-bootstrap.sh:300-302` | lectura |
| QA-45 | baja | `listener` no valida el `sensor_id` contra `sensors.json`: con un typo el gateway da 400 para siempre y `sensor-health` falla con KeyError. Se ve (queda rojo), pero se puede cortar en el momento. | `aws-bootstrap.sh:54` | lectura |
| QA-46 | baja | Las marcas del watchdog viven en `/run` y `degraded_since` vive en memoria del gateway. Si el re-run reinicia el gateway mientras hay un sensor degradado, llega "Las entregas de alertas vuelven a funcionar" sin que nada haya cambiado. | `aws-bootstrap.sh:254-258`, `:304` | lectura |
| QA-47 | baja | El encabezado todavía dice "2 headless AEA emulators". El loop de apagado solo mira unidades habilitadas: un `aea-emulator@2` arrancado a mano sin `enable` sigue corriendo. | `aws-bootstrap.sh:2`, `:292` | lectura |

### Verificación de los arreglos QA-39..47 (lectura, nada ejecutado)

| id | estado | nota |
|---|---|---|
| QA-39 | arreglado | todo el adb corre como `aea` con `-H`; `sensor-health` con `User=aea`. El servidor adb se reinicia solo si un serial nuestro sale `unauthorized`. Falta verificar en la EC2, ver abajo |
| QA-40 | arreglado | sin `Condition`, `OnCalendar`, y el paso `listener` arranca `sensor-health` al final |
| QA-41 | arreglado, con un efecto nuevo | ver QA-48 |
| QA-42 | arreglado | sdkmanager solo instala lo que falta |
| QA-43 | arreglado | build en `.new`, `npm ci` ahí, swap con `mv` |
| QA-44 | arreglado | si el puerto está ocupado fuera de la unidad, no arranca otra instancia; ver QA-52 |
| QA-45 | arreglado | `sensor_id` validado contra `sensors.json` antes de tocar el emulador |
| QA-46 | arreglado | el mensaje ya no afirma que las entregas volvieron |
| QA-47 | arreglado | encabezado corregido; el apagado mira unidades habilitadas y también las que corren |

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-48 | media | `sensor-health` hace `geo fix` justo antes de medir, así que el chequeo de deriva mide la ubicación que acaba de poner: siempre pasa. Después de un arranque en frío, AEA ya está `registered` pero todavía no recibió ninguna ubicación (pide cada 30 min, mínimo 5), y el sensor sale verde sin que AEA sepa dónde está. Arreglo: exigir `deliveries > 0` de `earthquake_alerting` en el `aea_health`, o medir antes del fix. | `sensor-health.py:32-36` | lectura |
| QA-49 | media | Un mapa con el formato viejo (2 columnas, del paso `listener` anterior) hace fallar el desempaquetado fuera del `try`: se cae toda la corrida y ningún sensor reporta `aea_ok`. Pasa en la EC2 viva entre el re-run del bootstrap y el nuevo paso `listener`, y también con una línea editada a mano. Arreglo: desempaquetar dentro del `try`, o saltar las líneas que no tengan 4 campos. Mientras tanto, correr `listener` justo después del bootstrap. | `sensor-health.py:73` | lectura |
| QA-50 | baja | `sensor-health` recibe todo el `.env` del gateway (master HMAC y clave privada VAPID) con el uid `aea`, el mismo que corre los emuladores. Con el master se puede firmar por cualquier sensor, y eso deshace en el host el aislamiento de QA-14. Arreglo: que el paso `listener` escriba un archivo con solo las keys por sensor (0600, `aea`), y que `sensor-health` use ese. | `aws-bootstrap.sh` (unidad `sensor-health`) | lectura |
| QA-51 | baja, arreglado | `sensor-health` reiniciaba el servidor adb también con `offline`, y un emulador offline de verdad cortaba cada 5 min las sesiones de scrcpy. Ahora los dos lados reinician solo con `unauthorized`. | `sensor-health.py:44` | lectura |
| QA-52 | baja | El aviso de "port busy" sale en stderr en medio del output y el script termina con "done." y exit 0. Es fácil no verlo y quedar con un emulador sin supervisión (no arranca en el boot ni se reinicia si se cae). Terminar con exit 1 si hubo un aviso. | `aws-bootstrap.sh:352-353` | lectura |

### Verificación de QA-48..52 y del geo fix por arranque

`scripts/test_sensor_health.py` (asserts, sin adb): `check` con el caso California →
(False, True), deliveries 0 → (False, False), ubicación desconocida nunca es deriva; reboot
recién en la 2ª deriva seguida, una corrida limpia resetea el contador, máximo uno por hora;
una fila vieja del mapa falla sola y la otra reporta (QA-49). 8 mutaciones, todas detectadas.

| id | estado | nota |
|---|---|---|
| QA-48 | arreglado | `aea_ok` pide `deliveries > 0`; el geo fix salió de `sensor-health` y pasó a `aea-geofix` |
| QA-49 | arreglado | test |
| QA-50 | arreglado | el mapa (0600, `aea`) lleva la key por sensor ya derivada; `sensor-health` no carga el `.env` |
| QA-52 | arreglado | puertos ocupados → `die "not done"` al final |

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-53 | verificado, no es bug | La duda: la deriva se mide con la última ubicación `gps` de `dumpsys location`, ¿refleja lo que tomó Play Services o lo que inyecta `geo fix`? Medido por el coordinador en la EC2, en el caso California: `last location=Location[gps 39.237255,-123.150032 ... et=+7m14s]`, y `fused` con el mismo valor, mientras se mandaba `geo fix` de Chaparral sin efecto. La línea solo cambia cuando el HAL está activo, y eso es justo lo que recibe GMS. La deriva se ve. | `lab.py:176-177`, `sensor-health.py:43` | verificado en device |
| QA-54 | baja | `reboot_if_stuck` corre después de `report`. Si el gateway no responde (por ejemplo, reiniciando), el contador de deriva no avanza y el auto-arreglo espera. Llamarlo antes de `report`. | `sensor-health.py:116-118` | lectura |
| QA-55 | info | En un deploy nuevo, y en la EC2 viva, el arranque actual del emulador nunca recibió el geo fix, porque el mapa recién aparece con `listener`. Si Play Services tomó otro lugar, `sensor-health` va a reiniciar el guest una vez, ~10 min después de `listener`. Es necesario y el login sobrevive, pero hay que esperarlo. | runbook | lectura |

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-56 | crítica, arreglado | Con targetSdk 35, Android bloquea HTTP cleartext: el listener no llegaba nunca a `http://10.0.2.2:8787`, y todo salía como `-1`, sin motivo. Relay, heartbeat y canario muertos desde el primer día en la EC2. Lo encontró developer en la EC2. Arreglo: `network_security_config.xml` con cleartext solo para `10.0.2.2`, y todo `-1` ahora lleva `error` (clase + mensaje). | `AndroidManifest.xml:7`, `res/xml/network_security_config.xml`, `Forwarder.java:181-206` | confirmado en EC2, arreglado |

Por qué QA no lo vio: `e2e-relay.sh` manda con curl desde el host. Prueba el contrato (bytes,
HMAC, respuestas), pero no la pila HTTP de Android ni su política de red. Lo que corre
dentro del emulador solo se prueba en un emulador: por eso los dos primeros puntos de abajo.

Antes del redeploy, en la EC2 y sin cambiar nada:

1. `systemctl status aea-emulator@1`: el emulador vivo tiene que ser esa unidad (QA-44).
2. `sudo -u aea -H /opt/android-sdk/platform-tools/adb devices` tiene que decir `device`. Si
   dice `unauthorized`, el emulador arrancó antes de que existiera la clave de `aea`, y
   hay que reiniciarlo una vez (el login vive en userdata y no se pierde).
3. Correr el bootstrap e inmediatamente `listener <apk> chaparral` (QA-49).
4. `systemctl list-timers sensor-health.timer gateway-watchdog.timer`: NEXT con hora.
5. A los 5 min, en `/status`, `chaparral` con `aea_ok: true` y `covered: true`.
6. Listener → gateway real sobre HTTP cleartext, desde el emulador: en `/status`,
   `last_heartbeat_at` y `last_canary_ok_at` de `chaparral` con hora reciente. Si no:
   `sudo -u aea -H adb -s emulator-5554 exec-out run-as com.earthquakes.relay cat
   files/notification-evidence.jsonl | grep -E 'HEARTBEAT_FAILED|RELAY_CANARY' | tail`.
7. Ningún `-1` sin motivo en la evidencia del listener. Tiene que dar 0:
   `... cat files/notification-evidence.jsonl | python3 -c 'import json,sys; print(sum(1 for l in sys.stdin if (e:=json.loads(l)).get("http_status")==-1 and not e.get("error")))'`

## Fase 5: APNs por sensor (app iOS)

Contrato de developer: `POST /devices`, fanout APNs por sensor después del 202, dedup por
sismo y por token, reintento dentro del TTL, sesión HTTP/2 única, cobertura también a los
iPhones. `relay-failures.test.js` quedó migrado a la ruta por sensor (QA-01..04 con su
semántica nueva) y `server.test.js` quedó solo con los tests puros: ningún test usa ya la
ruta legado. Probado: con la ruta legado reemplazada por un 400, la suite sigue verde.

Tests nuevos contra un APNs falso por HTTP/2: `/devices` (plataforma, formato del token,
minúsculas, sensores repetidos o desconocidos, más de 3, reemplazo del conjunto, sin
ubicación), fanout solo al sensor, headers (`push-type`, `priority`, `topic`, `collapse-id` =
`quakeTag`, `expiration` = `expires_at`), payload (`mutable-content`, `kind`, `late`), atrasado
→ `active`, un iPhone con 2 sensores recibe un solo aviso por sismo, un envío fallido libera
el sismo para el otro sensor, 410 y `BadDeviceToken` borran el token sin degradar, APNs caído
(QA-01), 403 a todos → degradado sin reintentar (QA-02), stream cortado → reintento del
gateway (QA-03), evidencia rota sin doble push (QA-04), cobertura a los iPhones (QA-24).
15 mutaciones: 14 detectadas. El tope de 10.000 tokens no tiene test porque el rate limit
por IP no deja llegar por HTTP.

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-57 | alta | `degraded` junta web push y APNs. Si todos los iPhones fallan (clave APNs revocada o vencida → 403 `InvalidProviderToken`) y un solo web push sale bien, el sensor no se degrada, el watchdog no avisa y todos los usuarios de iOS pierden todas las alertas sin que nadie lo sepa. Lo mismo al revés, con VAPID roto y APNs bien. Hace falta un `degraded` por canal. | `server.js` `deliverAlert` | confirmado; arreglado más abajo, el `todo` ya no existe |
| QA-58 | baja | Carrera en el dedup por token: el sensor A reclama el sismo y su envío está en curso. El sensor B llega en esos segundos y se salta ese token. Si A termina fallando, se libera, pero B ya pasó. Solo se pierde si A falla después de todos sus reintentos, y entonces B probablemente también fallaba (mismo token, mismo APNs). Aparte: dos sismos reales con menos de 30 s entre sí (un doblete) le llegan al iPhone como uno. Aceptable, el primero ya dijo "protéjase". | `server.js` `claimQuake`/`releaseQuake` | lectura |
| QA-57 | arreglado | `degraded` por canal (`apns`, `webpush`). El test marca solo `apns` con 403 mientras el web push entrega, deja `covered=false` y se limpia con una entrega buena en ese canal. Sin la marca `todo`. | `relay-failures.test.js` QA-57 | test |
| QA-59 | baja | `covered` sigue siendo por sensor, no por canal. Con solo APNs roto, los usuarios de la PWA, que sí reciben, también ven rojo y reciben "Sin cobertura". Es una falsa alarma visible, no una falla silenciosa. | `server.js` `sensorHealth` | lectura |

Ruta legado borrada por developer: un evento sin `sensor_id` da 401 (test en QA-14).
`npm test`: 36/36. `e2e-relay.sh`: ok.

Los pendientes de la pausa quedaron hechos en la fase 6.

## Fase 6: carga, watchdog, QA-59 y fila de arranque

Carga: ver `docs/qa/load.md`. Umbral de hoy para terminar el envío en menos de 3 s:
~6.000 iPhones o ~2.500 suscripciones web por sensor. Hallazgos QA-60..63 en ese archivo
(QA-60 crítica: sesión APNs con `maxSessionMemory` por defecto, 50k → 9 % entregado).

- `degraded` por canal: 6 mutaciones. Quedaba sin test el filtro `hasRecipients` (un canal
  roto que ya no tiene usuarios no bloquea `covered`); test agregado.
- `gateway-watchdog`: extraído del bootstrap y corrido contra un `/status` falso. Un aviso
  por cada cambio (`apns` → `apns webpush` → ninguno, caído → vuelve) y ninguno si no cambia.
  Cosmético: el texto queda "apns ." con un espacio antes del punto.
- QA-59: `coverage.test.js` actualizado a `covered_webpush` (un corte solo de APNs deja la
  web en verde). Test nuevo: con APNs roto, "Sin cobertura" va a los iPhones y no a la
  PWA. Si el aviso usa el `covered` global, falla.

`npm test`: 38/38. `e2e-relay.sh`: ok.

Fila de arranque (`aea-wait-previous`) y cantidad de emuladores por RAM, revisados leyendo:

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-64 | media | Re-correr el bootstrap en la EC2 viva ya no la deja con 1 emulador: con 16 GB, `AVD_COUNT` da 3, así que crea y arranca `sensor-2` y `sensor-3`. Van a estar sin login de Google y sin listener, en rojo hasta que alguien los configure. Si la idea es mantener 1, correr con `EMULATOR_COUNT=1`. | `aws-bootstrap.sh:41-51` | lectura |
| QA-65 | media | El tope de 15 min de la espera cuenta desde que arranca la unidad N, no desde que N-1 empieza a bootear. En un arranque en frío todas las unidades arrancan juntas: la k-ésima espera ~(k-1) × (boot + 90 s). Con 4-5 min por paso, desde la 5ª o 6ª unidad vence el tope y bootea a la vez que su predecesora: justo lo que la fila evita (system_server sin CPU, reinicios en bucle). Pasa en hosts de 32 GB o más (8 emuladores). Arreglo: empezar a contar recién cuando N-1 está `active`. | `aws-bootstrap.sh` `aea-wait-previous` | lectura |
| QA-66 | baja | La fila solo mira a N-1. Si @1 se cae mientras @2 está booteando, @1 rearranca sin esperar y bootean los dos juntos. Además, un rearranque por crash espera 90 s aunque la predecesora esté arriba hace horas. | `aea-wait-previous` | lectura |
| QA-67 | media | 3 emuladores con `-cores 2` en 2 vCPU, más el gateway, que por QA-62 usa ~1,3 ms de CPU por web push y bloquea el loop. En el momento de un sismo se despiertan los GMS de los 3 a la vez, más el relay y el fanout. No está medido. | runbook | a medir en la EC2 |

Arreglos de developer, verificados:

| id | estado | cómo |
|---|---|---|
| QA-60 | arreglado | `maxSessionMemory: 1000`; medido: 50.000 iPhones sin duplicados |
| QA-61 | arreglado | pool de 4 conexiones × 1.000 streams; el timer arranca en `ready`. 50.000 a 100 ms en 2,0 s |
| QA-62 | arreglado | 202 antes del reparto, web push en un pool de 500, VAPID cacheado. 202 en ≤ 10 ms, `/status` ≤ 190 ms. Header VAPID verificado (aud, exp 12 h, firma) |
| QA-63 | arreglado | keep-alive con máximo 500 sockets; 50.000 web push sin agotar puertos |
| QA-65 | arreglado | el tope cuenta desde el `ActiveEnterTimestamp` de N-1, sin reloj mientras está `activating` (leído) |
| QA-66 | arreglado | sin margen si el guest lleva más de 300 s arriba (leído). Sigue mirando solo a N-1 |

Nuevo, baja:

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-68 | baja | En `mapLimited`, un worker queda ocupado mientras duerme el backoff de un reintento (hasta 7,5 s). Si APNs o FCM dan 429/5xx un momento, los tokens que todavía no se intentaron esperan detrás de los reintentos. Mejor: primero una pasada completa y después los reintentos. Además, el comentario de `sendWithRetry` ("the send has to start before /events answers") ya no es cierto desde QA-62. | `server.js` `mapLimited`, `sendWithRetry` | lectura |
| QA-68 | arreglado | `sendAllWithRetry`: primero una pasada completa por todos y después rondas solo con los reintentables, dentro del TTL. Test con 1.000 suscripciones cargadas en el archivo, de las que 500 dan 503 una vez: el primer intento de la última sale antes que cualquier reintento. Con el reintento por ítem de antes, el test falla. Con 3 suscripciones no se distingue, porque el pool es de 500. | `web-push.test.js` QA-68 | test |

Checklist en la EC2, además de los puntos 1-7:

8. Con un emulador booteando, los ya arrancados siguen con heartbeat y `aea_ok` en `/status`
   (pedido de developer; no se pudo medir sin la EC2).
9. Tiempo del arranque en frío completo (`systemctl list-units 'aea-emulator@*'` hasta que
   todos estén `active` y con `sys.boot_completed=1`): tiene que quedar bajo el tope de
   15 min por unidad (QA-65).
10. `top` durante un canario: la CPU del gateway y de los emuladores cuando llega un evento.

QA-84, raíz: el listener mantiene el GPS abierto (`GpsKeeperService`, proceso `:gps`, FGS
de ubicación, `requestLocationUpdates(GPS, 60 s)`), y `sensor-health` hace geo fix en cada
corrida. A medir en device (el coordinador, en quibdo):

11. Antigüedad de "last location" gps (`/proc/uptime` − `et`) durante horas: tiene que
    quedar < 2 min si el emulador repite el último fix con el HAL activo. Si no lo repite,
    va a llegar hasta ~5 min (el intervalo de `sensor-health`). Las dos cosas sirven contra
    las ~24 h de QA-84, pero hay que saber cuál es.
12. Entregas de `earthquake_alerting` cada ~30 min en `dumpsys activity service
    com.google.android.gms`, no solo las 2 del boot.
13. Cambio de lat/lon en el mapa → GMS con la ubicación nueva en < 2 min, sin reboot.
14. `dumpsys package com.earthquakes.relay`: FINE, COARSE y BACKGROUND_LOCATION en
    `granted=true`.
15. `dumpsys activity services com.earthquakes.relay`: `GpsKeeperService` en foreground.
    Ningún `GPS_KEEPER_FAILED` en la evidencia del listener.
16. Matar el proceso `:gps` (`am kill` o `kill` del pid): el listener sigue vivo, con
    heartbeat, y el keeper vuelve en el próximo heartbeat (≤ 5 min).

Notas de QA sobre este diseño:
- Con el GPS abierto y el geo fix justo antes de `check()`, el chequeo de deriva mide casi
  siempre nuestra propia inyección (como en QA-48). Mientras el keeper funcione, está bien,
  porque GMS sigue al GPS. La señal que importa pasa a ser la antigüedad y las entregas.
  El reboot por "stale" queda como red de seguridad si el keeper falla.
- La Mac de control no tiene el APK nuevo: va a seguir quedándose vieja a las ~24 h y el
  certificador la va a marcar "sin control" (QA-85) hasta que se actualice o se reinicie.

Resultado en la EC2 (informado por el coordinador, 24-sep; no lo medí yo):

- 8: 2 emuladores en fila, sin GOODBYE. `chaparral` siguió sano mientras booteaba el segundo. Cubierto.
- 9: arranque en frío de ~60 s por emulador, lejos del tope de 15 min. Cubierto.
- Además se vio la autorreparación por deriva en `quibdo` (QA-53/55 en la práctica).
- 10: CPU del gateway y los emuladores durante un evento: no se informó. Queda pendiente
  junto con QA-67.

Estado al pausar: backend cerrado, `npm test` 39/39, `e2e-relay.sh` ok. Se espera el sismo
de validación.

## Fase 7: contrato iOS (`docs/ios-contract.md`) contra `server.js`

Revisado línea por línea. **Nada del documento contradice al código**: campos, códigos de
error, límites (64-200 hex, 1-3 sensores, 10.000 tokens, 16 KB, 30 por IP en 10 min),
payload de alerta y de cobertura, headers, `late` (más de 120 s, texto y `active`),
dedup (±30 s, liberar si falla), `/status` y los niveles de cobertura (≤ 31, ≤ 78, solo
`public: true`). Los hallazgos son de cosas que el documento no dice y que la app
necesita saber.

Test nuevo, "iPhone falso" (`relay-failures.test.js`, "contract: ..."): registro con 2
sensores y token en mayúsculas, el mismo sismo desde los dos, **un** push, y ese push
comparado con el documento: el conjunto exacto de claves del payload y de `aps`, valores,
headers y `collapse-id` = `quake:<minuto>`. 4 mutaciones (campo extra, sin `thread-id`,
`collapse-id` por evento, sin dedup): las 4 lo rompen.

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-69 | media | El contrato no dice qué hacer ante 429 o 5xx en `POST /devices`. El límite es 30 intentos por IP cada 10 min: cuentan también los fallidos y los de `/subscribe`, y la ventana es fija para todas las IP. Con CGNAT de operador muchos teléfonos comparten IP, y un cambio de ubicación de mucha gente a la vez puede dejar registros sin hacer. La app tiene que reintentar con backoff y mostrar "no registrado" mientras no tenga un 201. | contrato "POST /devices"; `server.js` `allowRegistration` | lectura |
| QA-70 | media | "Sin cobertura" solo sale en la transición. Un teléfono que se registra cuando su receptor ya está caído nunca recibe ese push, y más tarde le llega "Cobertura restablecida" sin haber sabido que la había perdido. El contrato tiene que decir que la app lee `/status` (`covered_apns`) al registrarse y al abrirse, no solo cuando recibe el push. | contrato "Sin cobertura"; `announceCoverageChanges` | lectura |
| QA-71 | media | `interruption-level: time-sensitive` solo funciona si la app tiene la capability Time Sensitive Notifications y el usuario no la apagó. Si no, iOS la entrega como `active` sin avisar a nadie. Tiene que figurar en el contrato como requisito de la app, y la app debería comprobarlo en `UNNotificationSettings`. | contrato "Alerta" | lectura (comportamiento de iOS) |
| QA-72 | baja | Si el evento no trae ni `time_occurred_s` ni `post_time_ms`, el `collapse-id` es el `event_id`, no `quake:<minuto>`. Y con `post_time_ms` el `event_id` es `<sensor>:p<ms>:alert`. El contrato debería decir que los dos son opacos y que la app no los parsea. | `deliverAlert` | lectura |
| QA-73 | baja | Después de reiniciar el gateway, `/status` muestra todos los receptores sin cobertura hasta el próximo heartbeat y el próximo reporte del watcher (≤ 5 min). Durante 15 min no sale ningún push de cobertura. La app va a mostrar rojo un rato en cada deploy. No es un bug, pero el contrato debería decirlo. | `handleStatus`, gracia de arranque | lectura |
| QA-74 | baja | La memoria del dedup vive en RAM. Si el gateway se reinicia en medio de un sismo, un teléfono puede recibir el mismo aviso dos veces (el `collapse-id` reemplaza la notificación, pero puede volver a sonar). Falta en "Límite aceptado". | `notifiedQuakes` | lectura |
| QA-75 | baja | `magnitude` y `distance_km` llegan crudos desde Play Services (por ejemplo `4.45852`, `18.9089`). El ejemplo del contrato muestra valores redondeados. La app tiene que redondear para mostrarlos; el `body` ya viene redondeado desde el receptor. | contrato "Alerta" | lectura |
| QA-76 | info | El servidor acepta en `/devices` sensores con `public: false` (hinatuan). Solo la app filtra. El documento es correcto ("tienen que existir"); falta decidir si el servidor debe rechazarlos. | `validateDevice` | lectura |

Queda para cuando developer lo agregue: `DELETE /devices` y `apns_env` por token.

## Fase 8: DELETE /devices, apns_env, límites por endpoint, QA-54/69/70/76/77

Contrato actualizado (`docs/ios-contract.md`) contra el código: coincide. Tests nuevos en
`relay-failures.test.js`, cada uno verificado con una mutación del server en una copia:

- `DELETE /devices` idempotente: 204 con el token en mayúsculas, repetido y desconocido;
  400 si está mal formado; después del DELETE el teléfono no recibe la alerta.
- `apns_env`: con dos APNs falsos, el token `sandbox` va solo al de sandbox, y el de
  producción (que responde `BadDeviceToken`) borra solo el suyo. `staging` → 400.
- QA-69: `/devices` (POST y DELETE juntos) corta en 120 y `/subscribe` sigue con sus 30.
- QA-76: `public: false` y un sensor sin el campo → 400 (falla cerrado).
- QA-70: un sensor caído se avisa al registrarse, uno por sensor y sin repetir al
  re-registrar; el sensor cubierto no se avisa.
- QA-77 (hallado al arreglar fixtures): un teléfono registrado durante la gracia recibía
  dos "Sin cobertura". Arreglado por developer con `coverage_told` por token. El test
  pide un solo aviso, "restablecida" solo a quien oyó "perdida", y nada a quien se
  registró con el sensor cubierto.
- QA-54: `reboot_if_stuck` va antes de `report`, con caso en `test_sensor_health.py`.

Nota de fixture: el cliente HTTP de Node no manda el body de un DELETE sin
`content-length` (URLSession sí lo manda). El helper de los tests ahora lo pone siempre.

`npm test`: 46/46. `e2e-relay.sh`: ok.

## Fase 9: certificador (`monitor/`)

Módulo nuevo, de QA. Verifica desde afuera, por HTTP a través de un túnel SSH, y escribe
`docs/qa/cert/AAAA-MM-DD.md`. Detalle en `monitor/README.md`.

- API del monitor (developer) según especificación de QA: `gateway/test/monitor-api.test.js`,
  6 tests, 3 mutaciones detectadas. QA-78 (paginación de `/evidence` atascada cuando un
  grupo con el mismo `at` no entraba en la página) hallado y arreglado.
- `monitor/test_verify.py`: fixtures reales. Chaparral 23-sep = HIT; el M3.6 del SGC del
  24-sep = HIT, porque se empareja por hora y no por magnitud; el M7.4 `us6000tjl2` del
  10-ago = NO APLICA (PREDATES_DEVICE), no MISS; causas de MISS en orden; FALSE solo pasadas
  24 h; reglas del veredicto. 10 mutaciones de `verify.py`, todas detectadas.
- `monitor/test_push_receiver.mjs`: el descifrado aes128gcm del receptor contra el mismo
  `web-push` que usa el gateway, más un push alterado y una clave equivocada.
- Probado en vivo el 24-sep: sonda Mac → túnel → gateway en la EC2 → Mozilla → Mac en
  0,72 s para los 3 receptores.

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-79 | alta | `bucaramanga-a` es `public: true` en `sensors.json`, pero no tiene receptor en AWS: en `/status` sale siempre `stale`. La PWA y la app se lo ofrecen a quien está cerca de Bucaramanga como su receptor, y esa persona queda registrada en algo que no existe (ve "sin cobertura"). El certificador lo va a marcar FALLA todos los días. Opciones: `public: false` hasta que haya receptor, o levantarlo. | `gateway/public/sensors.json` | arreglado: `public: false`, y el gateway deja un `PUBLIC_SENSOR_SILENT` (una vez por proceso) si un público nunca reporta. Test en `monitor-api.test.js`, 3 mutaciones detectadas |
| QA-80 | media | Después de cada reinicio del gateway, `/status` marca todos los sensores `covered: false` hasta el próximo heartbeat y el próximo `aea_ok` (≤ 5 min cada uno), porque viven en RAM. En el deploy del 24-sep a las 16:06 fueron más de 4 min en rojo para todos, por un reinicio de ~2 min. La PWA y la app muestran "sin cobertura" en cada deploy. Propuesta: persistirlos con su hora; la regla de 15 min sigue igual. | `server.js` `lastHeartbeatAt`, `aeaReports` | arreglado: `heartbeats.json` persistido, la regla de 15 min corre sobre las horas guardadas. Test en `web-push.test.js` (reinicio sano = cubierto y sin avisos; heartbeat guardado de hace 20 min = rojo aunque `aea` esté fresco); 3 mutaciones detectadas |
| QA-81 | media | El certificador contaba los minutos de un deploy planificado como receptor caído. Arreglado en `verify.restart_windows` / `coverage_stats` (con test): con un registro `DEPLOY` en los 10 min previos al nuevo `started_at`, hasta 15 min se listan aparte y no cuentan para el veredicto; sin `DEPLOY`, "reinicio del gateway" cuenta. Falta, del lado de developer, `started_at` en `/status` y `DEPLOY` desde el bootstrap. | `monitor/verify.py` | arreglado: `started_at` en `/status` (con test) y `DEPLOY` con `version` desde el bootstrap (leído) |
| QA-82 | baja | Dos bugs del monitor, hallados al verificar el deploy: el receptor de web push solo se revisaba cada hora (si se moría, se perdía una hora de sondas), y `kill` dejaba huérfanos el túnel y el receptor. Arreglados. | `monitor/monitor.py` | arreglado |
| QA-83 | media | Tres bugs de `restart_windows` en el monitor, hallados al revisar los reinicios reales del 24-sep: (1) el primer deploy con `started_at` no se veía como reinicio, porque los registros anteriores no tenían el campo; (2) el `DEPLOY` de las 16:17 excusaba el restart manual de las 16:22, porque la ventana era de 10 min; ahora es de 2 min y cada `DEPLOY` vale para un solo reinicio; (3) un sensor no público nunca cubierto (bucaramanga-a) dejaba toda ventana abierta los 15 min. Arreglados, con un test armado sobre la secuencia real. | `monitor/verify.py` | arreglado |

### Nota de rollout (24-sep)

- Primer deploy de QA-80 (16:17): los dos receptores estuvieron ~4 min en rojo porque
  `heartbeats.json` todavía no existía; la versión anterior no persistía nada. Pasa una
  sola vez. Desde el restart manual de las 16:22:32, chaparral y quibdo siguieron
  `covered: true` desde el primer `/status`.
- Certificado del 24-sep: el corte de las 16:17 figura como **deploy** (4 min chaparral,
  3 quibdo, no cuentan) y el de las 16:22 como **reinicio del gateway** no planificado,
  con 0 min sin cobertura. El corte de las 16:06 (el deploy de QA-78/79, anterior a
  `started_at` y a `DEPLOY`) no se puede atribuir y queda como "receptor", 5 min.
- El certificado ahora lista todos los reinicios, aunque no hayan costado cobertura.

## Fase 10: sismo real del 24-sep, 16:46:33 UTC (Chaparral)

SGC `SGC2026svonmo`, M4.1 (Google estimó M4.48, `TIME_OCCURRED` 1790268393). No está en USGS.

| receptor | resultado | tiempos |
|---|---|---|
| AWS chaparral | HIT | origen → captura 16,6 s (reloj del emulador); captura → gateway 1,9 s; captura → 1ª entrega 2,3 s; **origen → monitor 18,7 s** (solo relojes con NTP) |
| Mac chaparral (control) | UPDATE_ONLY | no llegó `eew_alert_v2`; `eew_update` a los +40 s |
| AWS quibdo | nada | fuera del radio, correcto |

Clase nueva `UPDATE_ONLY` en `verify.py` (con test sobre este sismo): llegó el aviso tardío
pero no la alerta temprana. En la Mac es informativo; en AWS es FALLA, porque AWS solo
reenvía `eew_alert` y el usuario no recibe nada. La comparación AWS contra Mac no da FALLA,
porque AWS capturó.

Investigación en la Mac (emulator-5558, solo lectura: `logcat -d`, `dumpsys location`,
`dumpsys activity service com.google.android.gms`, evidencia del listener):

- Listener: conectado todo el tiempo (`allow_listener` a las 11:45:54 locales responde
  "already bound"). No hubo `eew_alert_v2` publicado ni quitado. **Descartado.**
- Red: `NetReassign` a las 11:46:25 y 11:46:31, pero siempre online por WiFi. No explica
  que el `eew_update` llegara y la alerta no. **Descartado como causa principal.**
- Reloj: guest contra host < 0,1 s. **Descartado.**
- **Ubicación de GMS: la última es de Chaparral y correcta, pero de hace ~25,3 h** (tomada 5
  min después del boot, el 23-sep a las 15:34 UTC). `earthquake_alerting` tiene 2 entregas,
  las dos en ese momento, y ninguna después: con el HAL de GNSS apagado, los `geo fix`
  posteriores no entran. A las 11:46:32 locales (1 s antes del origen) GMS registra
  "WeatherPressureObservation was dropped due to no location data".
- AWS chaparral, que sí recibió, tiene el mismo patrón (2 entregas en el boot), pero con una
  ubicación de ~2,7 h. Las alertas tempranas anteriores de la Mac llegaron con ~4,6 h y
  ~9,8 h.

| id | sev | escenario | dónde | estado |
|---|---|---|---|---|
| QA-84 | **crítica**, arreglado en `sensor-health.py`: `aea_ok=false` con ubicación de más de 20 h o null (pasado el arranque), reboot preventivo a la 2ª corrida, máximo 1 por sensor por hora y 1 por host cada 30 min, pospuesto si hubo una `eew_*` en los últimos 10 min, flock por host. `test_sensor_health.py` reescrito por developer sin adb real ni archivos en `$HOME`, con todos los casos anteriores; 12 mutaciones, todas detectadas | Todo receptor (Mac y AWS) le da a GMS una sola ubicación, en el boot, y nunca la refresca. Con ~25 h la alerta temprana no llegó; con 2,7-9,8 h sí. Hipótesis, n = 4: GMS no usa para la alerta una ubicación de más de ~24 h. Si se confirma, cada receptor queda ciego ~24 h después de su último boot, **con `aea_ok` en true**, porque `sensor-health` no mira la antigüedad. AWS chaparral booteó a las 14:02 UTC del 24-sep: quedaría ciego desde ~14:00 UTC del 25-sep. Propuesta: (1) `sensor-health` pone `aea_ok=false` si la ubicación de GMS tiene más de 20 h (`et` de `dumpsys location` contra `/proc/uptime`); (2) remedio: reboot del guest escalonado cada ~20 h (ya existe `reboot_if_stuck` + `aea-geofix`), o un pedido de GPS activo periódico dentro del guest para que el geo fix entre. | `sensor-health.py`, operación | hipótesis fuerte, sin prueba controlada |
| QA-85 | alta, arreglado en el monitor: `poll_control` lee cada 30 min la antigüedad de la ubicación del control por adb (solo lectura); con > 20 h o null queda "sin control" y no excusa. Tests en `test_verify.py` con el dumpsys real. Primera lectura: control de la Mac entre 25,6 y 27,9 h (o null), ciego | El control de la Mac hoy está ciego por lo mismo (4 emuladores con ~25 h de uptime), pero el certificador lo toma como disponible por su `last_seen`. Ante un MISS de AWS diría "Google no alertó (la Mac tampoco)" y lo excusaría. El certificador necesita la antigüedad de la ubicación del control: leerla de la Mac por adb (solo lectura, cada 30 min) o que `lab.py` la guarde en su estado. Decisión del coordinador, porque toca la flota de la Mac. | `monitor/monitor.py` `coverage_lookup` | abierto |
| QA-86 | baja, anotado, no se hace nada | Los emuladores no tienen NTP: AWS chaparral atrasa 1,70 s y quibdo 0,31 s. `captured_at` sale corrido en ese valor. Ya está anotado en el certificado; "origen → monitor" no depende del emulador. `sensor-health` podría reportar el desfase para corregirlo. | receptores | anotado |

### Trampa medida por el coordinador (24-sep)

`cmd location set-location-enabled false` y después `true` **borra** la ubicación de GMS
(queda null) y no la refresca. No sirve para forzar una ubicación nueva: dejó a quibdo (AWS)
sin ubicación hasta que se recuperó con un reboot del guest. En el certificado del 24-sep
eso figura como intervención manual (`monitor/interventions.json`), no como falla. Quibdo
volvió a estar cubierto a las 17:10:42, dentro del tope.

## Qué quedó cubierto

- `scripts/e2e-relay.sh`: gateway local en dry-run con eventos que tienen los mismos bytes
  que Forwarder, firmados con la key por sensor. Verifica: aceptado, duplicado, firma
  mala/ausente/body alterado, key maestra y key de otro sensor → 401, expirado → 400,
  atrasado aceptado y reescrito por el server, canario, heartbeat, `/status` sin `aea_ok`
  → no cubierto, evidencia. Pasa.
- `gateway/test/relay-failures.test.js`: APNs por sensor contra un APNs falso por HTTP/2
  local: `/devices`, fanout, dedup por sismo, tokens muertos, QA-01..04, QA-19, QA-24, QA-57.
- `gateway/test/web-push.test.js`: `/subscribe`, rate limit, fanout por sensor,
  re-suscripción, 410, kill switch, key por sensor, canario, atrasado, heartbeat, cobertura
  (`covered` y avisos por transición), reintento por suscripción.
- `gateway/test/coverage.test.js`: `coverageTier`, `nearestSensor` y `coverageState` de la PWA.

## Checklist manual (necesita un teléfono)

- iPhone con la PWA instalada: activar lejos de todo sensor → dice "sin cobertura" y no se
  suscribe (el tier sale de `coverage.js`; lo que no se testea es que `index.html` lo respete).
- Con el gateway apagado, la página se pone roja en menos de un minuto.
- Con Focus activo, ver si el aviso suena (QA-29): hoy no debería.

## Correr

```bash
cd gateway && npm test          # 55 tests
./gradlew :android-listener:testDebugUnitTest
scripts/e2e-relay.sh
```

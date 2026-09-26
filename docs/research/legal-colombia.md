# Legal: Colombia (Ley 1581, alerting rules, liability, drafts)

2026-09-25. Not legal advice. I am not a lawyer and this is not a law firm's opinion: it is
a map of the rules and a first draft of the text, to hand to a Colombian lawyer before
launch. Every place that needs a lawyer's sign-off is marked **[LAWYER]**.

Tags: **[V]** read in the primary source (the law, decree, or SIC's own page). **[R]**
reported by a secondary source (news, law-firm blog), not cross-checked against the primary
text. **[U]** unverified, or a judgment call with no clean answer.

---

## Recommendation

1. **RNBD registration: not required at this size.** The obligation to register in the
   Registro Nacional de Bases de Datos falls only on companies/non-profits with total assets
   over 100,000 UVT (Decreto 090/2018 art. 1) and on public entities **[V]**. That does not
   apply here. But Ley 1581 itself applies regardless of size or registration (SIC's own FAQ
   says so explicitly **[V]**): privacy policy, consent, and data-subject rights are required
   either way. Re-check the UVT threshold before launch if the legal entity changes (a
   company with real assets, investment, etc.) — this is a size test, not a permanent
   exemption.
2. **Consent: one explicit screen before the first `POST /devices`.** A button the user taps
   ("Acepto" / toggle), never a pre-checked box or silence — Decreto 1377 art. 7 says silence
   is never enough **[V]**. The screen states what is collected (APNs token, chosen receptor
   ids, an ~11 km location cell computed on the phone) and links to the full policy. Draft
   below.
3. **International transfer: covered as a "transmisión", not a "transferencia".** AWS
   (Brazil) and Apple/APNs (US) process data as *Encargados* on the app's instructions, not
   as independent controllers. Decreto 1377 art. 24.2 exempts this kind of processing from
   the adequacy-country rule and from needing separate user consent, **as long as there is a
   contract** with the clauses in art. 25 (treat per the policy, secure the data, keep it
   confidential) **[V]**. AWS's and Apple's own standard agreements likely cover this, but
   **[LAWYER]** should confirm they satisfy art. 25 specifically, and confirm this reading of
   "transmisión" holds for a hobby-scale/non-commercial deployment. Disclose the two
   countries in the policy anyway, as a transparency matter, even though consent isn't
   legally required for it.
4. **No sensitive data (Ley 1581 art. 5) is involved.** No health, biometric, political,
   religious, union, or sexual-life data. That keeps the app out of the harder consent
   regime in art. 6. Keep it that way: don't add anything that could imply health status
   (e.g. don't ask "are you elderly / do you have a disability" even for accessibility
   purposes — offer it as a general iOS accessibility feature instead).
5. **"Alerta" carries no exclusive license in Colombian law today, but the word is loaded.**
   Nothing found bars a private app from relaying earthquake information (freedom of
   information, Constitución art. 20, cited in Ley 1581 art. 1 itself). The real risks are
   (a) being mistaken for an official channel — Código Penal art. 426, simular investidura o
   cargo, and Ley 1480 on misleading claims — and (b) the SNAST bill, which if it passes
   would make the SGC Colombia's alerting authority. It is still in its first of four debates
   as of August 2026 **[R]**; not law. Mitigation, not avoidance: never use SGC/UNGRD names,
   logos or seals; state plainly, on the first screen and in the terms, that this is not an
   official government service.
6. **Liability disclaimer: three things, in three places.** (a) "No es un servicio oficial."
   (b) "Puede fallar, llegar tarde, o no llegar." (c) "No sustituye los protocolos de
   protección civil." Show all three before the first permission prompt (onboarding), and
   keep them in the terms of use. A full exclusion of liability ("no respondemos por nada")
   risks being read as an abusive clause against a consumer under Ley 1480 — **[LAWYER]**
   should review the exact wording; draft below uses "mejor esfuerzo, sin garantía de
   resultado" instead of a blanket waiver.
7. **App Store privacy label: Data Linked to You → Identifiers (device token) + Location
   (Coarse Location); purpose App Functionality only; no tracking; no third-party sharing**
   (AWS/APNs are processors, not the "third parties" the label means, matching the
   Encargado/Responsable split above — **[U]**, Apple's own wording on this exemption was
   not directly re-read this session, confirm on the App Store Connect form itself).
   Full table below.
8. **Before it ships:** confirm with a Colombian lawyer (a) the RNBD threshold still doesn't
   apply once the legal entity is fixed, (b) the AWS/Apple transmisión reading, (c) that the
   liability wording isn't abusive under Ley 1480, and (d) whether the current SNAST bill
   text (not just the news coverage) says anything about private early-warning apps —
   nobody on this team has read the bill's actual articles, only press summaries.

---

## 1. Ley 1581 de 2012 and Decreto 1377/2013

### What the app actually collects (from `docs/ios-contract.md`)

| field | what it is | personal data? |
|---|---|---|
| `device_token` | APNs push token, hex, one per install | Yes — a persistent identifier that singles out one phone/user across sessions (used to individually address it, delete it, rate-limit it, remember its history) |
| `sensor_ids` | 1-3 receptor names the phone follows, chosen by the phone from its own location | Yes, indirectly — reveals which of a handful of Colombian regions the user is near, at city/region resolution |
| `demand_cell` | `floor(lat*10),floor(lon*10)`, ~11 km cell, computed on the phone | Yes — coarse location. The precise coordinate never leaves the phone (`docs/ios-contract.md` line 5-6) |
| `min_magnitude` | 5.5, set automatically by the app for a receptor followed only under the far rule — the user does not configure this | A preference, not identifying on its own, but stored against the same token |
| `platform`, `apns_env` | fixed technical values | No |
| `/telemetry/arrivals` (opt-in test phones only) | sent-at/received-at timestamps per alert, uploaded only if the monitor turns telemetry on for that token | Yes, but separate purpose (performance measurement, not alert delivery) and separate consent — see §4.2 point 6 |

No name, no email, no account, no precise coordinate ever reaches the server. That is a real
mitigation, not a formality: art. 3(c) Ley 1581 defines dato personal as anything that can be
"asociado a una... persona... determinada o determinable" **[V]** — the device token makes the
record determinable (it identifies one recurring device, even without a name attached), so the
conservative reading treats the whole record as personal data, not anonymous. It is not
sensitive data (art. 5): no race, politics, religion, union, sexual life, health or biometric
data anywhere in the contract **[V]**.

### Is RNBD registration required?

No, at the current size. Decreto 090 de 2018 art. 1, quoted by SIC's own FAQ: registration is
owed by "sociedades y entidades sin ánimo de lucro que tengan activos totales superiores a
100.000 UVT" and by public legal entities **[V]**, independent of employee count. The FAQ is
explicit that this does **not** exempt anyone from the substantive law — "El régimen general de
protección de datos personales es aplicable a todas las sociedades y entidades en Colombia sin
excepción" **[V]** — only from the public-registry paperwork. So: no RNBD filing needed now,
but every other duty below still applies in full.

### Consent

Art. 9 Ley 1581: treatment needs "autorización previa e informada del Titular" **[V]**. None of
the art. 10 exceptions (public entity exercising legal functions, public data, medical
emergency, historical/statistical research, civil registry) fit an earthquake-alert app **[V]**
— consent is not optional here.

Decreto 1377 art. 7 **[V]**: the authorization can be written, oral, or by "conductas
inequívocas" (unambiguous conduct), but "en ningún caso el silencio podrá asimilarse a una
conducta inequívoca" — a pre-checked box or "by using the app you agree" buried in a EULA is
the kind of thing that gets challenged. Practical read: a first-run screen with the three
disclaimer lines (§3 below) and an explicit "Acepto" tap, before the first location/notification
permission prompt and before the first `POST /devices`, satisfies both art. 9 and art. 7.

### Privacy policy vs. aviso de privacidad

Decreto 1377 draws two documents **[V]**:

- **Política de Tratamiento** (art. 13): the full document — identity/contact of the
  Responsable, what is treated and why, the Titular's rights, who handles requests, how to
  exercise rights, effective date. Required content, not optional content.
- **Aviso de privacidad** (art. 14): a short notice, used **only** "en los casos en que no sea
  posible poner a disposición del Titular las políticas" — and even then, it does not excuse
  the Responsable from separately publishing the full policy (art. 15, last paragraph) **[V]**.

Since a mobile app has room for both (a short onboarding notice plus a Settings/About screen
with the full policy), do both: the onboarding screen is the aviso de privacidad, the full
Política de Tratamiento lives in Settings and on the web, and the onboarding screen links to it.

### International transfer

Decreto 1377 art. 3 distinguishes **[V]**:

- **Transferencia**: sending data to another *Responsable* (someone who decides their own
  purposes for it) inside or outside Colombia.
- **Transmisión**: sending data to an *Encargado* who processes it only on the Responsable's
  instructions, for the Responsable's own purpose.

Ley 1581 art. 26 bans transferencia to a country without an adequate protection level, unless
an exception applies (art. 26 a-f) — express consent from the Titular is one such exception
**[V]**. But art. 24.2 of Decreto 1377 says a transmisión "no requerirán ser informadas al
Titular ni contar con su consentimiento" when there is a contract meeting art. 25 **[V]** — no
adequacy-country test at all for this path.

AWS (hosting the gateway, Brazil) and Apple/APNs (delivering the push, US) both process data
strictly on the app's own instructions — they don't decide why the data exists or what it's
used for. That makes them Encargados, and the flow a transmisión, not a transferencia. Under
art. 24.2 that removes the need to chase down whether Brazil or the US are on SIC's adequate-
country list (a 2026 secondary source claims the US is on it and Brazil is not **[R]**, not
independently verified here — moot if the transmisión reading holds, but **[LAWYER]** should
still confirm the reading itself, since it is the whole argument).

What art. 25 requires in the contract, regardless: the encargado (a) treats the data by the
Responsable's own policy, (b) safeguards the data's security, (c) keeps it confidential
**[V]**. AWS's and Apple's standard developer/customer agreements almost certainly cover (b)
and (c) as a matter of course; whether they can be read as binding the encargado to *this
project's specific* treatment policy under (a) is the part **[LAWYER]** should check — it's
likely fine (that's what "process only per customer instructions" clauses in any cloud DPA are
for) but nobody here has read AWS's or Apple's actual terms with that specific question in mind.

Recommendation either way: name both countries in the privacy policy as places the data is
processed, so the transparency principle (art. 4(e) Ley 1581, "principio de transparencia")
is satisfied even though separate consent for the transmisión itself isn't required.

### Data subject rights (build these, even without RNBD)

Ley 1581 arts. 8, 14-16: the Titular can know, update, correct, and ask for deletion of their
data, and can complain to the SIC after going through the Responsable first **[V]**. In this
app that maps directly to features that mostly already exist: `DELETE /devices` removes the
token entirely, and re-registering with new `sensor_ids`/`min_magnitude` updates it. What's
missing for full compliance: a stated channel (an email address in the policy) for a user who
wants to *ask* what is stored about their token, rather than only being able to delete it
blind — Decreto 1377 art. 23 requires "una persona o área" designated to handle these requests
**[V]**. This does not need new server code: given the app never stores a name, "what do you
have on me" can be answered by asking the user for their `device_token` (visible nowhere in the
UI today, so in practice this channel will rarely be used, which is fine — but the offer has to
exist in the policy text).

---

## 2. Who may issue an earthquake alert in Colombia

### Ley 1523 de 2012 and the SNGRD

Ley 1523 creates the Sistema Nacional de Gestión del Riesgo de Desastres (SNGRD) and defines
"alerta" as "el estado que se declara con anterioridad a la manifestación de un evento
peligroso, con base en el monitoreo del comportamiento del respectivo fenómeno" **[R, from
official summaries of the law's definitions article; the definitions article itself was not
directly re-read this session — the definitions and roles came from a secondary summary of the
Función Pública page, not the raw article text]**. It makes risk management "responsabilidad de
todas las autoridades y de los habitantes del territorio" and assigns SNGRD entities the
processes of conocimiento, reducción and manejo del riesgo. The UNGRD coordinates the national
system; the SGC is the technical body for seismic monitoring (this matches `docs/decision.md`'s
own read of it). Nothing found in the summaries reserves the *word* "alerta" or the *act* of
telling someone about an earthquake to a government body exclusively — Ley 1523 sets up who
plans and coordinates official disaster response, it doesn't appear to criminalize a private
party sharing hazard information. **[U]**: this is read from summaries, not the full statute
text; a lawyer should confirm there's no article elsewhere in Ley 1523 (or a related decree)
that does restrict who may "declare" an alert, since the definition above is written from the
state's point of view and the boundary of that restriction isn't fully clear from a summary
alone.

### Is a private relay app allowed?

Nothing found says no, today. The strongest general permission is freedom of information and
expression, Constitución arts. 15/20, which Ley 1581 art. 1 itself cites as one of the rights it
develops **[V]**. The risks are narrower and more concrete:

- **Código Penal art. 426, simulación de investidura o cargo**: 2-4 years plus a fine for
  someone who "simulare investidura o cargo público" **[R, from a secondary legal aggregator,
  not the official Diario Oficial text — confirm the current wording, since the Código Penal
  gets amended often]**. An app that uses SGC/UNGRD branding, names, or visual identity, or
  words itself to imply it *is* the official channel, would be squarely in this risk. An app
  that says "esto no es un servicio oficial" and never uses their marks is not.
- **Ley 1480 de 2011 (estatuto del consumidor)**: advertising must be truthful and sufficient;
  misleading advertising is one whose message "no corresponde a la realidad o es insuficiente,
  de tal manera que induce o podría inducir a error" **[R]**. Calling the notification an "early
  warning" without disclosing that Google's own data shows most of these alerts arrive late
  (`docs/findings.md` §8: 36% of Google's own users get it before shaking) would very plausibly
  qualify as insufficient/misleading. The app's own `late: true` flag and downgraded copy
  (`docs/ios-contract.md`, "Aviso de sismo atrasado") already builds the honest version of this
  into the product — the legal risk is in the marketing copy and onboarding text, not the code.

### The SNAST bill

A bill to create the Sistema Nacional de Alerta Sísmica Temprana (SNAST), filed by senator
María Lucía Villalba after the August 10 2026 M7.4 earthquake, would make the SGC the authority
that detects earthquakes and decides when to declare an official alert, delivered free and
universally to phones, radio and TV, with a 6-month window afterward to define technical
protocols, interoperability, cybersecurity, and pilot tests **[R, from news coverage —
elcolombiano.com, eltiempo.com, infobae.com, pulzo.com; the bill's actual article text was not
located or read this session]**. As of August 2026 it had only started its legislative process:
it needs to pass four congressional debates plus presidential sanction before it is law **[R]**.
It is not in force. `docs/decision.md` §5 already flagged this as "grey today; if the bill
passes, it gets worse" — nothing in this research changes that read. What it does add: the bill
apparently contemplates a mandatory technical/interoperability regime for alerting once it
passes, which is the scenario where a private app like this one would most plausibly need to
register, comply with a shared protocol, or stop calling its own notification an "alerta." This
needs re-checking against the actual bill text (not just press coverage) if and when it advances
past first debate — **[LAWYER]**, and worth a coordinator reminder to re-run this check
periodically rather than once.

---

## 3. Liability disclaimer

### What it needs to say

Three claims, plainly, in Spanish a general reader understands without a law degree:

1. **No es un servicio oficial.** No es del SGC, la UNGRD, ni ninguna entidad del Estado.
2. **Puede fallar.** El aviso puede llegar tarde, no llegar, o no ser exacto. Depende de
   sistemas de terceros (Google, Apple) fuera de nuestro control.
3. **No reemplaza los protocolos de protección civil.** Ante un sismo, siga las
   indicaciones oficiales de las autoridades locales.

### Where it must appear

- **Onboarding, before the first permission prompt**, as its own screen, not buried in a
  scroll of terms — this is also where consent for data collection is captured (§1 above), so
  the same screen does both jobs.
- **Terms of use**, as a section, not a single buried sentence.
- Recommended, not required: a persistent one-line version ("Servicio no oficial, mejor
  esfuerzo") somewhere always visible in the main screen — costs nothing and reduces the
  Ley 1480 exposure further, since it's now impossible to claim the user wasn't told.

### Enforceability

A full waiver ("no somos responsables por nada, bajo ninguna circunstancia") is the kind of
clause Colombian consumer law calls "abusiva" when the app is used by consumers, not
businesses — Ley 1480 gives the SIC power to declare such clauses void when they unbalance the
contract against the consumer **[R]**. Safer wording: describe the service as best-effort
without a guaranteed result ("hacemos el mejor esfuerzo razonable; no garantizamos que el aviso
llegue, sea oportuno o sea exacto"), rather than disclaiming all responsibility outright.
**[LAWYER]**: confirm the exact line between "honest disclaimer of what the product does" (fine)
and "abusive limitation of liability" (risky) under current SIC doctrine — this line moves with
case law and this research did not review SIC's abusive-clauses decisions directly.

---

## 4. Drafts (Spanish)

These match what `docs/ios-contract.md` actually does today, and §4.4 has been checked against
`ios-client/EarthquakeRelay/PrivacyInfo.xcprivacy` and `ios-client/AlertService/PrivacyInfo.xcprivacy`
(both read directly, **[V]**) — the manifests declare exactly `DeviceID` and `CoarseLocation`,
both linked, not tracking, App Functionality only, matching this doc's own §4.4 reading before
the manifest existed. Two things the manifest surfaced that the earlier draft got wrong, now
fixed here: `min_magnitude` is not something the user configures (it's set to 5.5 automatically
for a far-rule receptor — §1's data table above is corrected), and there was no in-app way to
delete data as of the previous draft — the app now adds a "Retirar consentimiento" row in the
Cobertura sheet for that (DELETE /devices plus clearing local data), and the drafts below point
to it instead of iOS Settings.

### 4.1 Aviso de privacidad (pantalla de inicio)

> **Antes de continuar**
>
> Esta aplicación no es un servicio oficial. No pertenece al Servicio Geológico Colombiano, a
> la UNGRD, ni a ninguna entidad del Estado. Los avisos pueden llegar tarde, no llegar, o no
> ser exactos: dependen de sistemas de terceros que no controlamos. No reemplazan los
> protocolos oficiales de protección civil.
>
> Para avisarle, guardamos en nuestro servidor: el identificador de notificaciones de su
> iPhone, y los sensores que usted elige seguir o una celda aproximada de ~11 km si aún no hay
> cobertura en su zona. Su ubicación exacta nunca sale de su teléfono. No pedimos su nombre ni
> su correo.
>
> Esta información se procesa en servidores en Brasil y Estados Unidos, únicamente para
> enviarle el aviso. Puede retirar su consentimiento y borrar esta información en cualquier
> momento desde la app, con "Retirar consentimiento" en la hoja de Cobertura, o escribiendo a
> [correo de contacto]. Puede leer la política completa aquí: [enlace].
>
> ( ) Acepto y quiero recibir avisos de sismo.

### 4.2 Política de tratamiento de datos personales (borrador)

> **Política de tratamiento de datos personales**
> Última actualización: [fecha]
>
> **1. Responsable del tratamiento.** [Nombre / razón social], [dirección o domicilio],
> [correo electrónico de contacto], [teléfono, si aplica].
>
> **2. Qué datos tratamos y para qué.** Para enviarle avisos de sismo, tratamos:
> - El identificador de notificaciones push de su dispositivo (device token).
> - Los sensores ("receptores") que su teléfono elige seguir, según su ubicación aproximada.
> - Si su zona aún no tiene un sensor cercano, una celda de ubicación de aproximadamente 11 x
>   11 km, calculada en su propio teléfono. Su ubicación exacta nunca se envía a nuestro
>   servidor.
>
> No recolectamos su nombre, correo, número de identificación, ni ningún dato de las
> categorías especiales del artículo 5 de la Ley 1581 de 2012 (salud, datos biométricos,
> origen étnico, orientación política o religiosa, entre otros).
>
> **3. Sus derechos.** Usted tiene derecho a conocer, actualizar, rectificar y solicitar la
> supresión de su información, y a presentar quejas ante la Superintendencia de Industria y
> Comercio si considera que no hemos cumplido esta política. Puede ejercer estos derechos
> escribiendo a [correo de contacto], o desde la app, con "Retirar consentimiento" en la hoja
> de Cobertura, que da de baja el dispositivo en nuestro servidor y borra la información local
> de inmediato.
>
> **4. Dónde se procesa la información.** Nuestro servidor corre en infraestructura de Amazon
> Web Services (Brasil). El envío de notificaciones usa el servicio de Apple (Estados Unidos).
> Ambos procesan la información únicamente siguiendo nuestras instrucciones y para el único
> fin de entregarle el aviso; no deciden ellos mismos qué hacer con su información ni la usan
> para sus propios fines.
>
> **5. Cuánto tiempo la conservamos.** Mientras usted mantenga los avisos activados. Al
> desactivarlos, su registro se elimina de nuestro servidor.
>
> **6. Finalidad opcional: pruebas de rendimiento.** Si usted participa como probador
> (opt-in, activado solo por el equipo de monitoreo, nunca por defecto), también registramos
> la hora en que cada aviso salió de nuestro servidor y la hora en que llegó a su teléfono,
> únicamente para medir y mejorar la velocidad de entrega. Esta finalidad es independiente de
> la del numeral 2 y solo aplica si usted fue invitado a probar la app y aceptó.
>
> **7. Cómo consultar esta política.** Esta política está disponible en la aplicación, en
> Ajustes, y en [sitio web], y aplicamos cualquier cambio sustancial solo después de
> avisarle y, si el cambio afecta la finalidad del tratamiento, de pedirle una nueva
> autorización.
>
> **8. Autoridad de vigilancia.** Superintendencia de Industria y Comercio, Delegatura para
> la Protección de Datos Personales.

### 4.3 Términos de uso (borrador, extracto de responsabilidad)

> **Naturaleza del servicio.** [Nombre de la app] es un servicio independiente y no oficial.
> No es operado por, ni está afiliado a, el Servicio Geológico Colombiano, la Unidad Nacional
> para la Gestión del Riesgo de Desastres, ni ninguna entidad pública. La información que
> mostramos proviene de un sistema de terceros (Google) y de sensores propios que la
> retransmiten a su teléfono.
>
> **Sin garantía de resultado.** Hacemos el mejor esfuerzo razonable para que el aviso le
> llegue de forma rápida y precisa, pero no lo garantizamos. El aviso puede llegar tarde,
> puede no llegar, o puede estar equivocado en la magnitud o el sismo reportado. Esto puede
> deberse a fallas de red, del sistema operativo, de nuestros proveedores, o del sistema de
> Google del cual depende la información original.
>
> **No reemplaza la protección civil.** Este servicio no sustituye los protocolos oficiales
> de gestión del riesgo. Ante un sismo, siga siempre las indicaciones de las autoridades
> locales y de los organismos de socorro.
>
> **Uso bajo su propio criterio.** Usted usa este servicio de forma voluntaria y bajo su
> propio criterio, entendiendo las limitaciones aquí descritas.

**[LAWYER]** should review 4.3 specifically for the line between an honest limitation and an
abusive exclusion (§3 above), and confirm the contact/authority details in 4.2 once the legal
entity is fixed.

### 4.4 App Store privacy "nutrition label" answers

Read directly from `ios-client/EarthquakeRelay/PrivacyInfo.xcprivacy` and
`ios-client/AlertService/PrivacyInfo.xcprivacy` (developer-ios, **[V]**):

| Apple category | Data type | Linked to user? | Used for tracking? | Purpose |
|---|---|---|---|---|
| Identifiers | Device ID (the APNs token) | Yes — it individually addresses one phone, and past behavior (e.g. "already sent a test alert in the last 10 min") is remembered against it | No | App Functionality |
| Location | Coarse Location (`sensor_ids` and/or `demand_cell`, ~11 km resolution) | Yes (same record as the token) | No | App Functionality |
| Performance Data | `POST /telemetry/arrivals`: sent-at/received-at timestamps for alert, test, and probe pushes | Yes (same token) | No | App Functionality — **[V]**, confirmed in the manifest. Only uploaded by phones the operator opted in server-side, but the upload code ships in every build, so it's declared for all users, not just testers (matches Apple's rule: declare what the binary can do, not the default state) |

Required-reason API declared: `NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`
(used by `TokenLifecycle` to compare `identifierForVendor` locally — that value never leaves
the phone, so it is not a collected data type, only a required-reason API usage). The
Notification Service Extension's own manifest declares no collected data types at all: it
reads the push payload but sends nothing.

Everything else: **not collected** — no name, email, precise location, financial info,
contacts, browsing/search history, health data, or usage analytics.

**Data used to track you:** None. No data is combined with third-party data for advertising,
and no data is shared with data brokers.

**Third-party data sharing:** AWS and Apple/APNs process data as service providers under this
app's instructions (matches the Encargado/transmisión reading in §1) — Apple's own privacy-
label rules exempt this kind of processing from the "third party" disclosure that applies to
partners who receive data for their own purposes **[U]**, not independently re-confirmed this
session against Apple's current guidelines text; check the exact wording on the App Store
Connect privacy questionnaire when filling it in, since Apple's own tooling asks this question
directly and is the authoritative source at that point.

---

## Unverified list, in one place

- Whether AWS's and Apple's standard agreements legally satisfy Decreto 1377 art. 25's
  specific contract requirements for a transmisión, for a project this size. **[LAWYER]**
- Whether the US and/or Brazil are on SIC's adequacy list — likely moot under the transmisión
  reading, but the "US is on the list" claim came from a secondary source and was not
  independently confirmed against SIC's own current list. **[R]/[U]**
- The exact current text and penalty range of Código Penal arts. 425-426 (usurpación /
  simulación) — read from a private legal aggregator, not the Diario Oficial. **[R]**
- Whether Ley 1523 or a related decree restricts, anywhere else in the statute, who may
  "declare" or communicate a seismic alert — only the definitions article was available via
  summary, not the full text. **[U]**
- The SNAST bill's actual article text (only press coverage was read) — whether it would
  require registration, interoperability, or an outright ban on private early-warning
  services once/if it passes. **[U]**
- Whether the line between an honest "best-effort, no guarantee" disclaimer and an abusive
  liability-limitation clause under Ley 1480 is crossed by the draft in §4.3. **[LAWYER]**
- Apple's exact current wording on when a data processor (vs. a "third party") needs
  declaring on the privacy label — not re-read this session. **[U]**

---

## Sources

- [Ley 1581 de 2012, full text (PDF)](https://www.funcionpublica.gov.co/eva/gestornormativo/norma_pdf.php?i=49981) — **[V]**, read in full this session.
- [Decreto 1377 de 2013, full text (PDF)](https://www.funcionpublica.gov.co/eva/gestornormativo/norma_pdf.php?i=53646) — **[V]**, read in full this session.
- [SIC, Preguntas frecuentes RNBD](https://sic.gov.co/preguntas-frecuentes-rnbd) — **[V]**, read in full this session (RNBD threshold, Decreto 090/2018).
- [Decreto 090 de 2018](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=85242) — cited via the SIC FAQ above; not independently re-read as a standalone PDF this session.
- Ley 1523 de 2012 — definitions and SNGRD roles from search-engine summaries of [Función Pública](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=47141) and [ANLA](https://www.anla.gov.co/eureka/normativa/leyes/ley-1523-de-2012-politica-nacional-de-gestion-del-riesgo-de-desastres); full article text not directly read. **[R]**
- Código Penal (Ley 599 de 2000) arts. 425-426 — from [leyes.co](https://leyes.co/codigo_penal/425.htm) and [leyes.co](https://leyes.co/codigo_penal/426.htm), a private aggregator, not the Diario Oficial. **[R]**
- Ley 1480 de 2011 — summarized via search results referencing [Función Pública](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=44306) and [WIPO Lex](https://www.wipo.int/wipolex/en/legislation/details/14828); full article text not directly read. **[R]**
- SNAST bill coverage: [El Colombiano](https://www.elcolombiano.com/colombia/nueva-ley-alerta-sismica-colombia-terremotos-FA40046704), [El Tiempo](https://www.eltiempo.com/politica/congreso/alerta-sismica-obligatoria-en-celulares-radio-y-tv-presentan-proyecto-de-ley-para-crear-un-sistema-nacional-de-aviso-ante-futuros-terremotos-3579089), [Infobae](https://www.infobae.com/colombia/2026/08/18/en-colombia-crearian-un-sistema-nacional-de-alerta-sismica-temprana-tras-el-terremoto-de-74-unificaria-alertas-en-telefonia-radio-y-television/) — news coverage only, bill text itself not located. **[R]**
- [Apple, App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) — data type and linkage-category definitions, fetched this session. **[V]** for the definitions quoted; the "processor vs. third party" exemption point in §4.3/4.4 was not directly re-confirmed against this page and is marked **[U]**.
- `docs/ios-contract.md`, `docs/decision.md` §5 and §10, `docs/findings.md` §5/§8 — this project's own prior work, used throughout for what the app actually does and what's already been decided about the compliance risk.
- `ios-client/EarthquakeRelay/PrivacyInfo.xcprivacy`, `ios-client/AlertService/PrivacyInfo.xcprivacy` — **[V]**, read in full this session, used to check §4.4 and correct the §1 data table and the §4.1/4.2 drafts.

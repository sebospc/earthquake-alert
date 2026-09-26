# Legal: Chile (Ley 19.628 / Ley 21.719, alerting rules, consumer law, deltas from Colombia)

2026-09-26. Not legal advice. I am not a lawyer and this is not a law firm's opinion: it is a
map of the rules and a first draft of the text changes, to hand to a Chilean lawyer before
launch in Chile. Every place that needs a lawyer's sign-off is marked **[LAWYER]**.

Tags: **[V]** read in the primary source this session (Biblioteca del Congreso Nacional,
leychile.cl, exported text of the law or code). **[R]** reported by a secondary source (law-firm
alert, news, agency web page summary), not cross-checked against primary text. **[U]**
unverified, or a judgment call with no clean answer.

This doc does not repeat what the app collects. That is `legal-colombia.md` §1 (data table:
`device_token`, `sensor_ids`, `demand_cell`, `min_magnitude`, opt-in arrival telemetry). Nothing
about the data changes for Chile. What changes is the law around it. Threads pulled from
`culture-and-apple.md` and `languages.md` are marked where used.

---

## Recommendation

1. **Build to Ley 21.719 now, whatever the calendar says.** Today (2026-09-26) the old Ley 19.628
   text is what is in force. Ley 21.719 does not create a new law number: it rewrites Ley 19.628
   from its first article ("Artículo primero.- Introdúcense las siguientes modificaciones en la
   ley N° 19.628", new name "sobre protección de los datos personales"), and BCN lists it as
   "Con Vigencia Diferida por Fecha, De: 01-DIC-2026" **[V]**. **Contested:** on 2026-08-31 the
   Executive filed a bill in the Senate to move that date to 2027-12-01 and to grow the Agency's
   board from three to five councillors **[R, two law-firm alerts: Carey, Garrigues]**. As of the
   latest report found it is not law. I did not find its bill number, and I did not verify
   whether it passed in the days since. The app is small enough that building to the new
   standard costs little (§1), so the safe plan does not depend on which date wins.
2. **No registration exists for a small private operator, before or after the reform.** The old
   registry (art. 22 Ley 19.628, kept by the Registro Civil) covers only databases of *organismos
   públicos*, and Ley 21.719 orders the Registro Civil to delete it **[V]**. The new law creates a
   *Registro Nacional de Sanciones y Cumplimiento*, but it lists only sanctioned controllers and
   those with a voluntary certified prevention model (arts. 39, 51) **[V]**. There is no
   Chilean equivalent of Colombia's RNBD threshold question. One filing does exist for a
   controller **not constituted in Chile**: it must tell the Agency an email address (of a person
   able to act on its behalf) for holder requests and notices (art. 10, new text) **[V]**. It
   cannot be filed yet, because the Agency is not operating (below).
3. **Chile's rules reach a foreign operator.** New art. 1 bis(c): the law applies when a
   controller not established in Chile targets goods or services at persons in Chile, "independientemente
   de si a éstos se les requiere un pago" **[V]**. Free alerts are inside the scope. The operator's
   Colombian or other home law does not remove this once the app is offered to Chilean users.
4. **International transfer is the biggest difference from Colombia, and it goes against us.**
   Colombia's Decreto 1377 art. 24.2 exempts a "transmisión" to an *encargado* from the adequacy
   rule. Chile's new Título V has no such exemption: art. 27 covers transfers to "el responsable o
   tercero mandatario que la reciba" **[V]**. So sending the token and cell to AWS (Brazil) and to
   Apple's push service (US) needs one of: adequate-country decision by the Agency, contractual
   clauses with adequate guarantees, or a certified compliance model. The Agency's adequate-country list
   and model clauses do not exist yet **[R]**. Interim plan: rely on the processors' standard data
   processing terms as the "cláusulas contractuales" route and disclose the two countries, and put
   the question to counsel (§1). **[LAWYER]**
5. **"Must not look official" is a real rule in Chile. It is Código Penal art. 213.** *Correction
   of `culture-and-apple.md`, which recorded "no clean equivalent found" for Chile from secondary
   sources.* Read in the primary code text, art. 213 punishes "El que se fingiere autoridad,
   funcionario público o titular de una profesión ... y ejerciere actos propios de dichos cargos"
   with presidio menor en sus grados mínimo a medio and a fine of 6 to 20 UTM, and treats the
   "mero fingimiento" as attempt **[V]**. It is the Chilean counterpart of Colombia's art. 426.
   The same mitigation applies: never use SENAPRED, SHOA, Centro Sismológico Nacional or Ministry
   names, seals or lookalike styling, and say "no oficial" on the first screen (§2).
6. **"Alerta" is a defined state in Chilean disaster law.** Ley 21.364 art. 38 makes SENAPRED
   declare "estados de alerta" and spread them to the population; "La Alerta constituye una etapa
   de la Fase de Preparación" **[V]**. Nothing found in Ley 21.364 or Ley 18.168 forbids a private
   party from passing on earthquake information (§2). But an in-app label "Alerta" collides with
   the official term. Prefer "Aviso de sismo" in Chile-facing copy, as the Colombia strings
   already do. This is a copy recommendation, not a legal requirement **[U]**.
7. **Consumer law reaches the paid tier, and may not reach the free one.** Ley 19.496 defines a
   consumer as someone acting under "cualquier acto jurídico oneroso" and a provider as one who
   charges "precio o tarifa" (art. 1) **[V]**. The free alert relay therefore sits at the edge
   of SERNAC's law; a paid Pro tier is inside it. Inside, art. 16(e) voids "limitaciones
   absolutas de responsabilidad" that strip a consumer's damages for defects in the essential
   purpose of the service **[V]**; art. 17 requires adhesion contracts in Spanish; arts. 3 bis(b)
   and 12 A add a 10-day withdrawal right and pre-contract access rules for online contracts
   **[V]**. Keep the "mejor esfuerzo, sin garantía" wording, in Spanish, for both tiers.
   **[LAWYER]** on whether the free tier is caught by any expansion of "oneroso" (personal data as
   the counterpart), which I did not research.
8. **Before it ships in Chile:** confirm with a Chilean lawyer (a) which regime applies on launch
   day (old text vs. new, and the status of the postponement bill), (b) the AWS/Apple transfer
   route under art. 27 and whether the processors' sub-processor clauses satisfy art. 15 bis,
   (c) whether an age gate is needed for children under 14 (art. 16 quáter), (d) art. 213 exposure
   for the exact icon, name and copy, (e) paid-tier consumer clauses.

---

## 1. Data protection: which regime, and how to be compliant on both sides of the date

### What the Agency is, and its status (the date problem)

Ley 21.719 creates the Agencia de Protección de Datos Personales as the control authority
(art. 30) **[V]**. It is not operating: the President's first slate of three councillors (terms of
6, 4 and 2 years) was rejected by the Senate for lack of the two-thirds quorum **[R, Senado news]**,
and Ley 21.806 (in force 2026-02-05; BCN lists it as the last modification of Ley 21.719) rewrote
the transitory article on how the first board is appointed **[V for the modification date, R for
its content]**. Until the board sits, the transitory article lets it exercise only a few
functions, and any general instruction it issues binds only from entry into force **[V]**. That
means, on 2026-12-01, the Agency may exist on paper with no adequate-country list, no model
clauses, no size-tiered standards (art. 14 septies, "por instrucción general") and no way for a
foreign controller to file its contact (art. 10).

Stated plainly: **the old text applies until the new one enters into force; if the postponement bill
becomes law, that would be 2027-12-01 [R]. I inferred that the old text stays in force in
between; none of the articles I read says so [U].**

### What the old Ley 19.628 (in force today) asks of this app **[V]**

- **Consent for anything not otherwise authorized** (art. 4): "el titular consienta expresamente";
  the person must be told the purpose of storage and possible communication to the public; the
  authorization "debe constar por escrito" and is revocable without retroactive effect, also
  in writing. A first-run tap on an explicit consent screen is the natural way to meet this in
  an app. That an electronic act counts as "por escrito" comes from the electronic-signature law
  (Ley 19.799), which I did not read **[U]**.
- **Purpose limitation** (art. 9): data used only for the purposes it was collected for.
- **Duty of care** (art. 11): the responsible party answers for damages if it does not care for the data
  with due diligence. **Mandate** (art. 8): processing through a mandatario needs a written
  mandate stating conditions; the mandatario must respect them.
- **Rights** (arts. 12-14): information about the data, its origin and recipients; correction;
  deletion; blocking; free of charge; cannot be waived. Recourse (art. 16): if the responsible party
  does not answer in **two business days** or refuses, the holder can go to a civil judge. If the
  court upholds the claim it may fine 1-10 UTM, and 2-50 UTM for late delivery of information or
  late correction; the fines are small.
- **No international-transfer regime at all**, apart from an exception for organizations under
  treaties (art. 5, last paragraph) **[V]**. Under the old law the AWS/Apple flow needs nothing
  beyond the mandate.
- **No registration** for private databases (art. 22 covers public bodies only) **[V]**.

### What Ley 21.719 asks (the standard to build to) **[V unless noted]**

| topic | rule | what it means for this app |
|---|---|---|
| Personal data | art. 2(f): any information about an identified *or identifiable* natural person, judged by "todos los medios y factores objetivos que razonablemente se podrían usar" | Same reasoning as Colombia: the persistent APNs token makes the record identifiable. Treat the whole record as personal data. |
| Sensitive data | art. 2(g): origin, politics, union, socioeconomic situation, ideology, religion, health, biometric, sexual life/orientation, gender identity | None collected. Note it lists *situación socioeconómica*, wider than Colombia's list; still none here. |
| Geolocation | art. 16 sexies: lawful under the normal bases; the holder must be told clearly "del tipo de datos de geolocalización", the purpose and duration, and whether it is passed to a third party for a value-added service | The ~11 km `demand_cell` and the chosen `sensor_ids` are geolocation data. The aviso must state type, purpose and duration (draft §4 below). |
| Principles | art. 3: lawfulness/loyalty, purpose, proportionality (keep only as long as needed, then delete or anonymise), quality, accountability, security, transparency, confidentiality | Colombia's design (delete the record when alerts are turned off) matches proportionality. |
| Consent | art. 12: free, informed, specific to each purpose, prior and unequivocal, verbal/written/electronic or "acto afirmativo"; revocable at any time "utilizando medios similares"; the means must be "expeditos, fidedignos, gratuitos y permanentemente disponibles"; the controller bears the burden of proof | The explicit "Acepto" tap fits. **Retirar consentimiento** in the Cobertura sheet is the revocation means; it must stay always available. Log when consent was given (burden of proof). |
| Other legal bases | art. 13: legal obligation, contract or pre-contract, **legitimate interest** (d), legal claims | Legitimate interest exists here (unlike the rigid Colombian rule) but needs a balancing test the holder can demand to see and can oppose (art. 8(a)). Keeping consent as the base is simpler. Choice is a **[LAWYER]** point. |
| Transparency | art. 14 ter: publish policy with date and version; identity of controller and legal representative; contact means; categories; recipients; purposes; **legal basis**; security measures; rights; right to complain to the Agency; **international transfer and whether the destination is adequate**; retention period; source; right to withdraw consent; automated decisions | Delta list in §4. The retention line is new work: state it. |
| Privacy by design and default | art. 14 quáter | The app already sends only a coarse cell and never the exact position. Say so. |
| Security | art. 14 quinquies: appropriate measures, encryption, restore capability, regular testing; the controller must prove the measures | CloudWatch alarms and drill (`STATUS.md`) help as evidence; write them into a short security note. |
| Breach | art. 14 sexies: report to the Agency "sin dilaciones indebidas" when there is reasonable risk to holders; keep a register; notify holders too only if sensitive data, children under 14 or financial data are involved | Not the case here beyond the Agency report. A breach register is a small doc. |
| Size tiers | art. 14 septies: minimum standards for information and security duties are set considering size per Ley 20.416; micro ≤ 2,400 UF annual revenue, small ≤ 25,000 UF, medium ≤ 100,000 UF (Ley 20.416 art. 2, BCN text of 2025-09-29) | Standards not written yet (Agency instruction). A small operator gets lighter duties, but only after the Agency defines them. |
| Processors | art. 15 bis: a written contract with object, duration, purpose, data type, categories of holders, rights and duties; the processor may not sub-delegate without "autorización específica y por escrito" of the controller; must return or delete data at the end | The AWS/Apple standard terms use general sub-processor authorizations; whether that satisfies the "specific and written" test is a **[LAWYER]** question. |
| Impact assessment | art. 15 ter: required *always* for, among others, "tratamiento masivo de datos o a gran escala"; the Agency will publish a guidance list | "Gran escala" is undefined. A 10,000-device cap (`STATUS.md`) is probably not it; 100k phones might be. Re-check when the Agency publishes the list **[LAWYER]**. |
| Rights | arts. 4-11: access, rectification, deletion, opposition, **portability** (arts. 9: only for automated processing based on consent) and **blocking** (art. 8 ter); free, except direct costs when access or portability is used more than once per quarter; answer within **30 calendar days**, extendable once by 30; provide "mecanismos y herramientas tecnológicas" so the holder can exercise them easily | `DELETE /devices` = deletion. Add an email or form as the request channel (art. 11). Portability is a JSON copy of the record (token, sensors, cell); trivial to produce on request. |
| Children | art. 16 quáter: children (under 14) need parental consent for any personal data; adolescents (14-17) consent like adults, except sensitive data under 16 | The app has no age gate. A device token is not age data, but the law makes the *processing* of a child's data depend on the parent. **[LAWYER]** whether a "not for under 14" statement, an age screen, or the Apple age rating is the right control. |
| International transfer | arts. 27-29: lawful if (a) the destination is adequate per the Agency's list, (b) contractual clauses, binding corporate rules or other instruments with adequate guarantees, or (c) certified compliance model; for one-off cases also express consent, contract necessity etc. Agency may inspect and suspend | See Recommendation 4. Consent (route "a" of the exceptions) is only for a "transferencia específica y que no sea habitual", so it cannot carry a continuous push flow. |
| Fines | art. 35: light up to 5,000 UTM (or written warning), serious up to 10,000 UTM, very serious up to 20,000 UTM; repeat serious/very serious offenders that are not micro/small firms can reach 2% or 4% of annual revenue. Arts. 34-34 quáter list what counts: processing without a legal basis or beyond purpose is "grave" (art. 34 ter(a)); an international transfer against the rules is "grave" (34 ter(m)), "gravísima" if knowing (34 quáter(h)) | Real money for a hobby operator if breached. Explains why the transfer route matters. |
| Transition | art. sexto transitorio: for 12 months from entry into force, for micro/small firms the Agency may apply only a written warning. The Executive's bill would extend this to all controllers **[R]** | A breathing space, not an exemption. |
| Damages | art. 47: the controller pays patrimonial and non-patrimonial damages; five-year limitation | — |
| Prevention model / DPO | arts. 48-51: voluntary certified prevention model, optional data protection delegate; in micro/small/medium firms the owner may act as delegate | Optional. Skip until scale. |

### AWS (Brazil) and Apple/APNs (US)

Under the old law: covered by the mandate rule (art. 8), no transfer regime **[V]**. Under the new
law: art. 27 route (b), contractual guarantees with rights enforceable by holders, and art. 15 bis
on the processor contract **[V]**. What I did not check: AWS's and Apple's own contract text for
either article, and whether the Agency will treat the US or Brazil as adequate. **[LAWYER]**

### Practical build list for Chile

1. Keep the Colombian consent screen and add the four items in §4.1 (basis, geolocation notice,
   transfer notice, rights channel).
2. State a retention period (the current answer, "mientras mantenga los avisos activados", is
   acceptable; add "y borramos su registro al desactivarlos").
3. A contact channel that can receive rights requests and a 30-day process behind it.
4. A written security note and a one-page breach register.
5. Age position (below).
6. Nothing to register today; put a reminder to file the foreign-controller contact with the
   Agency once it can receive it (art. 10).

---

## 2. Who may issue or relay an earthquake alert in Chile, and looking official

### Ley 21.364 (SINAPRED) and SENAPRED **[V]**

The law creates the Sistema Nacional de Prevención y Respuesta ante Desastres and turns ONEMI into
SENAPRED. Art. 38 (Sistema de Alerta Temprana): SENAPRED runs a Unidad Nacional and regional
early-warning units, receives threat reports from technical bodies (it names, among others, the
Centro Sismológico Nacional, SHOA, SERNAGEOMIN, the Dirección Meteorológica), and "deberá declarar,
en el nivel que corresponda y sobre la base de los informes de dichos organismos, la Alerta a la población
... por todos los medios de comunicación que sean necesarios". It also keeps a national communications
system that includes "mecanismos de aviso y comunicación de las alertas y emergencias preventivas
a la población".

What I did **not** find, searching the full text for prohibitions, penalties, false-alarm rules and
private actors: any article that reserves the act of *telling people about an earthquake*
to the State, restricts private dissemination, or protects the word "alerta" or the SENAPRED
name and emblems. Private entities are named only as components of the System that must
collaborate (principle of mutual support). **[V for the searched text; [LAWYER] to confirm no
regulation, decree or instruction beyond the law text says otherwise.]**

### The emergency alert channel (SAE)

Ley 18.168 (Ley General de Telecomunicaciones) art. 7 bis makes telecom concessionaires relay
"sin costo" the alert messages "que les encomienden el o los órganos a los que la ley otorgue esta
facultad", and frees them from liability for message content **[V]**. The operating system is
cell broadcast; the Subtel page for the Sistema de Alerta de Emergencias (SAE) says it covers three
hazards: tsunamis, volcanic eruptions and wildfires threatening homes **[R, page read through a
summarizer; the tool returned no text on who may send messages]**. Earthquakes are not in that
list. Whether Chile runs any official earthquake early warning is not something this session
established. **[U]**

### Código Penal art. 213 (looking official) **[V]**

Quoted above (Recommendation 5). Two features matter for the app:

1. The offence needs the person to *feign* authority, public official status or a regulated
   profession *and* "ejerciere actos propios de dichos cargos". An app that says plainly "no es
   oficial" and never uses state names or emblems is not feigning anything.
2. The mere pretence is punished as attempt, so lookalike branding without acts is not risk-free.
   The icon (white seismograph on red) uses no state emblem, per the review in
   `culture-and-apple.md`. Related but different: art. 20(a) of the industrial property law bars
   registering state emblems as trademarks **[R, via search summary, not read]**.

Contested points, not decided here: whether a private "alert" that dispatches a "Sismo detectado"
banner performs an "acto propio" of a public authority, which I read as unlikely on the text but
**[LAWYER]** should say.

---

## 3. Liability disclaimer and consumer law (Ley 19.496)

Read in the BCN text (version 2024-01-01) **[V]**:

- **Who is inside** (art. 1): consumer = acts under "cualquier acto jurídico oneroso"; provider =
  charges "precio o tarifa". A paid Pro tier is inside; the free alert relay is at the edge.
  **[LAWYER]**
- **Abusive clauses** (art. 16): inside adhesion contracts, clauses have no effect if they, among
  others, (a) let one party change or cancel at will, (d) reverse the burden of proof, (e) "Contengan
  limitaciones absolutas de responsabilidad frente al consumidor que puedan privar a éste de su
  derecho a resarcimiento frente a deficiencias que afecten la utilidad o finalidad esencial del
  producto o servicio", or (g) create a significant imbalance against good faith. The Colombia
  draft's "mejor esfuerzo razonable; no garantizamos" wording avoids (e); keep the same shape.
- **Language and form** (art. 17): adhesion contracts in Spanish, clearly legible; a contract in
  another language is valid only if the consumer accepts it through a Spanish annex. **English-only
  terms must not be the Chilean terms.**
- **Electronic contracts** (art. 12 A): consent is not formed unless the consumer first had clear,
  understandable access to the general conditions "y la posibilidad de almacenarlos o imprimirlos",
  and after the contract the provider must send a written confirmation with a full copy.
  Art. 3 bis(b): a 10-day right to withdraw from online contracts, unless the provider "haya dispuesto
  expresamente lo contrario", counted from the confirmation; for services, refunds cover only what
  was not yet provided. Whether Apple's purchase flow and receipt cover these items for a Chilean
  buyer, and whether an in-app clause can switch off withdrawal, is a **[LAWYER]** point.
- **Misleading advertising** (art. 28): infraction to induce error "a sabiendas o debiendo saberlo"
  about, among others, "la idoneidad del bien o servicio para los fines que se pretende
  satisfacer y que haya sido atribuida en forma explícita por el anunciante" and its relevant
  characteristics. This is the article that bites on any safety-benefit claim in store copy.
- **Negligence** (art. 23): infraction to cause harm "actuando con negligencia" through failures in
  the quality or safety of a service.
- **Enforcement body:** SERNAC and courts (not re-read in detail; the sanction tables are long).

The three disclaimer lines (not official; may fail; does not replace civil protection) are the
same as Colombia, with the official sources named for Chile (§4.3).

---

## 4. Deltas from the Colombian Spanish drafts (`legal-colombia.md` §4)

Register: keep **usted**. Chilean formal writing uses tuteo or usted, and voseo is informal
(`culture-and-apple.md`, [R]).

### 4.1 Aviso (first screen): what to add or rename

Replace the Colombian names and authority:

> Esta aplicación no es un servicio oficial. No pertenece al Servicio Nacional de Prevención y
> Respuesta ante Desastres (SENAPRED), al Centro Sismológico Nacional ni a ninguna entidad del
> Estado. Los avisos pueden llegar tarde, no llegar, o no ser exactos: dependen de sistemas de
> terceros que no controlamos. No reemplazan las indicaciones oficiales de SENAPRED ni de las
> autoridades locales.

Add to the data paragraph (art. 16 sexies, art. 14 ter):

> Tratamos estos datos con su consentimiento, de acuerdo con la normativa chilena de protección
> de datos personales (Ley N° 19.628, modificada por la Ley N° 21.719). Guardamos una ubicación
> aproximada (una celda de unos 11 km, calculada en su teléfono, nunca su posición exacta), solo
> para elegir qué sensor le avisa, y la eliminamos cuando desactiva los avisos. No la entregamos a
> terceros para ningún otro servicio.

Transfer line (art. 14 ter(h), art. 27; wording for a country-list that does not exist yet):

> Sus datos se procesan en servidores en Brasil (Amazon Web Services) y se envían por el servicio de
> notificaciones de Apple en Estados Unidos, únicamente para entregarle el aviso. [LAWYER:
> completar con la garantía que ampara esta transferencia (cláusulas contractuales u otra) y, cuando
> la Agencia publique su listado, si estos países tienen nivel adecuado de protección.]

Rights line (arts. 4, 10, 11, 14 ter(f)-(g)):

> Usted puede pedir acceso, rectificación, supresión, oposición, portabilidad y bloqueo de sus
> datos, sin costo, escribiendo a [correo de contacto] o con "Retirar consentimiento" en la hoja de
> Cobertura. Responderemos en un máximo de 30 días corridos. Si no le respondemos o rechazamos su
> solicitud, puede reclamar ante la Agencia de Protección de Datos Personales.

Age (art. 16 quáter), pending the lawyer's view:

> Esta aplicación no está dirigida a menores de 14 años.

### 4.2 Política de tratamiento: sections to change

- §1 Responsable: also the "representante legal" (art. 14 ter(b)) and the designated email for
  requests, plus, for a controller outside Chile, the art. 10 contact filed with the Agency once
  possible. Add "versión y fecha" (art. 14 ter(a)).
- §3 Derechos: replace SIC and the Ley 1581 rights list with the six rights above and the 30-day
  deadline; replace "SIC, Delegatura" in §8 with "Agencia de Protección de Datos Personales" once it
  operates (before that, the civil courts under the old text). **Do not name an authority that
  cannot yet receive complaints.**
- §4 Transfer: add the art. 27 route (placeholder above); remove the Colombian "transmisión"
  reasoning, which does not exist in Chilean law.
- New: legal basis (consent, revocable), retention, security measures in one paragraph, no
  automated decisions with legal effect (art. 14 ter(l): receptor selection is automated but does
  not produce legal or significant effects), source of data (the user's own phone).

### 4.3 Términos de uso: sections to change

- Name SENAPRED, the Centro Sismológico Nacional and SHOA as the official sources, in place of the
  SGC and UNGRD.
- Terms in Spanish (art. 17 Ley 19.496).
- Keep "mejor esfuerzo, sin garantía de resultado"; avoid "no respondemos por nada" (art. 16(e)).
- For the paid tier: describe what the user gets and the price (also an Apple 3.1.2(c) point), the
  confirmation of the contract with a copy, and the withdrawal position (art. 3 bis(b), art. 12 A).
  **[LAWYER]**

### 4.4 App Store privacy label

No Chile-specific delta found: the label describes what the binary collects, and that is
unchanged (`legal-colombia.md` §4.4, Device ID and Coarse Location, linked, no tracking; Performance
Data for opt-in telemetry). The Chilean age question in §1 could interact with the age rating
chosen in App Store Connect. That is a choice to make with the lawyer, not something I can
settle **[U]**.

### 4.5 Language notes (from `languages.md`, [R], not re-verified this session)

SENAPRED's protective wording is "Agáchate, Cúbrete y Afírmate"; academic critique says it may fit
Chilean building types better than "Sujétate". Keep it as a copy choice, not a legal point.

---

## Not researched, flagged rather than guessed

- Whether the postponement bill has advanced past filing (2026-08-31) and its number.
- The Agency's first instructions, size-tier standards, adequate-country list, and model clauses
  (none exist yet).
- Whether AWS's and Apple's standard data-processing terms meet art. 27(b) and art. 15 bis.
- Whether Ley 19.799 makes an electronic tap "por escrito" under art. 4 of the old text.
- Whether a Chilean regulation beyond Ley 21.364 or Ley 18.168 restricts private early-warning
  relays; Decreto 60 (Subtel, alert message interoperation) was found but not read.
- SERNAC doctrine on free digital services, the content of Ley 19.496's enforcement chapters.
  Ley 19.496 was read as of the 2024-01-01 version; later amendments were not checked.
- Whether Chile runs an official earthquake early-warning service, and how SENAPRED words
  earthquake advice in the SAE.
- Trademark rules on state emblems (industrial property law art. 20), seen only in a summary.

## Unverified list, in one place

- Postponement bill (2026-08-31): contents and status. **[R]**
- Old law still in force until the new one enters. **[U]**
- Senate rejected the first board slate; Ley 21.806's content. **[R]**
- SAE covers tsunami, volcano and wildfire only; nobody on the team read who may send. **[R]**
- Transfer route and processor sub-delegation for AWS and Apple. **[LAWYER]**
- Age gate under art. 16 quáter. **[LAWYER]**
- Art. 213 exposure for the final icon, name and copy. **[LAWYER]**
- Free-tier reach of Ley 19.496 and paid-tier withdrawal mechanics. **[LAWYER]**
- Legal-basis choice: consent vs. legitimate interest. **[LAWYER]**
- DPIA threshold ("gran escala") once the Agency publishes its list. **[LAWYER]**

---

## Sources

- [Ley 21.719, BCN export "vigencia diferida 2026-12-01"](https://www.bcn.cl/leychile/navegar?idNorma=1209272&idVersion=2026-12-01): last modification Ley 21.806 (2026-02-05). **[V]** Read: arts. 1-22 (from BCN's XML feed, which truncates this norm mid-article 22), arts. 23-43 and 47-51 and the transitory articles (from BCN's text export, which is complete). Not read: the Agency's internal articles 30 ter-32 bis, arts. 44-46 and 52-55 (public bodies, certificates).
- [Ley 19.628 (old text), BCN](https://www.bcn.cl/leychile/navegar?idNorma=141599): version 2022-11-10. **[V]** Read: arts. 1-16, 22-23; not read: arts. 17-21 (financial and commercial debt data).
- [Ley 21.364 (SINAPRED), BCN](https://www.bcn.cl/leychile/navegar?idNorma=1163423): **[V]** Read arts. 38 and the principles; the rest of the text was searched by keyword (prohibitions, penalties, false alarms, private actors, alerts), not read line by line.
- [Ley 18.168 (LGT), BCN](https://www.leychile.cl/navegar?idNorma=29591): art. 7 bis. **[V]**
- [Código Penal, BCN](https://www.bcn.cl/leychile/navegar?idNorma=1984): arts. 213-222. **[V]**
- [Ley 19.496 (consumer), BCN](https://www.bcn.cl/leychile/navegar?idNorma=61438): arts. 1, 3, 3 bis, 12, 12 A, 16, 17, 23, 28. **[V]**, version 2024-01-01.
- [Ley 20.416 (empresas de menor tamaño), BCN](https://www.bcn.cl/leychile/navegar?idNorma=1010668): art. 2 size thresholds. **[V]**
- Postponement bill: [Carey](https://www.carey.cl/gobierno-ingresa-proyecto-de-ley-que-posterga-en-un-ano-entrada-en-vigor-de-la-ley-sobre-proteccion-de-datos-personales), [Garrigues](https://www.garrigues.com/es_ES/noticia/chile-ejecutivo-refuerza-futura-agencia-proteccion-datos-concede-ano-adicional-adaptacion). **[R]**
- Agency board appointment: [Senado, "Desestiman propuesta de consejeros"](https://www.senado.cl/comunicaciones/noticias/desestiman-propuesta-de-consejeros-para-la-agencia-de-proteccion-de-datos), [Senado session 2026-05-12](https://www.senado.cl/actividad-legislativa/comisiones/1467/22535). **[R]**
- [Subtel, Sistema de Alerta de Emergencias](https://www.subtel.gob.cl/sae/). **[R]**
- Project files used: `docs/research/legal-colombia.md` (§1 data table, §4 Spanish drafts),
  `docs/research/culture-and-apple.md` (Chile tone, "must not look official" thread, corrected here),
  `docs/research/languages.md`, `docs/ios-contract.md`, `docs/STATUS.md`.

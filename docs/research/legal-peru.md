# Legal: Peru (Ley 29733, alerting rules, liability, drafts)

2026-09-26. Not legal advice. I am not a lawyer and this is not a law firm's opinion: it is
a map of the rules and a first draft of the text, to hand to a Peruvian lawyer before launch.
Every place that needs a lawyer's sign-off is marked **[LAWYER]**. Companion to
`legal-colombia.md` — the app's own data inventory is not re-derived here, see that doc §1
for the exact table (device_token, sensor_ids, demand_cell, min_magnitude, telemetry). Nothing
about it differs for Peru; only the legal treatment does.

Tags: **[V]** read in the primary source (the law, decree, or the government's own page).
**[R]** reported by a secondary source, not cross-checked against the primary text. **[U]**
unverified, or a judgment call with no clean answer.

---

## Recommendation

1. **Registro Nacional de Protección de Datos Personales: registration is required, no size
   exemption exists.** Unlike Colombia's RNBD (100,000 UVT asset threshold), Peru's Reglamento
   (DS 016-2024-JUS, arts. 42-45) requires every "banco de datos personales" — public or
   private, any size — to register **[V]**. The procedure is online, free, and
   automatically approved (art. 45.2, silencio administrativo positivo under Ley 27444)
   **[V]**. Register before launch; there is no small-operator exemption to check first,
   unlike in Colombia.
2. **A separate registration for the flujo transfronterizo (cross-border transfer) itself.**
   Even when the transfer is otherwise lawful, it "debe ponerse en conocimiento" of the
   authority and gets recorded in the Registro Nacional (Reglamento art. 21.2) **[V]**; the
   government's own procedure page confirms this is free, done online, with a 30-business-day
   resolution **[V]**. This is a step Colombia's transmisión path (Decreto 1377 art. 24.2) does
   not require at all.
3. **The AWS/Apple cross-border question does not have as clean an answer as Colombia's.**
   Peru's Reglamento defines "transferencia" broadly as sending data to "persona distinta al
   titular" (art. 12.1) and requires the titular's consent for it "salvo las excepciones del
   artículo 14 de la Ley" (art. 13.1) **[V]** — there is no separate, explicit "transmisión to
   an Encargado never needs consent" carve-out the way Decreto 1377 art. 24.2 gives Colombia.
   The most plausible exemption is Ley 29733 art. 14 numeral 5 (data necessary to perform a
   contractual relationship the titular is party to) **[R]**, but this is a different legal
   mechanism than Colombia's, resting on contract-necessity rather than a categorical
   Encargado exemption. **[LAWYER]** should confirm this reading before relying on it, and
   confirm whether Peru's ANPD has issued any resolución declaring the US or Brazil to have
   "nivel adecuado" (none was found this session — **[U]**). Either way, register the flow per
   point 2, and use contractual clauses under Reglamento art. 20 as the fallback if consent
   turns out to be required.
4. **Oficial de Datos Personales (ODP): probably not required yet, but there is a real,
   numeric trigger to watch, unlike anything in Colombia's regime.** Designation is mandatory
   for public entities, for treatments handling sensitive data as a core business, or for
   "grandes volúmenes de datos" per a 2025 directive's scoring criteria (Resolución
   100-2025-JUS/DGTAIPD, Anexo 1) **[V]**: 50,000+ data subjects alone triggers it; other
   combinations of medium-level criteria (10,000-49,999 subjects, cloud/foreign hosting,
   continuous/24-7 processing) can trigger it too **[V]**. Device tokens and coarse location
   are not sensitive data, so the size axis is what matters here — **re-check this once
   registered-device counts are known, especially once past 10,000** (the app's own
   `MAX_DEVICES` cap per `docs/STATUS.md`), since the medium-band combination rule could bite
   before 50,000 if cloud hosting (AWS, foreign) and continuous processing both count as
   medium/high on their own axes. This is genuinely different from Colombia's RNBD test, which
   is asset-based, not user-count-based.
5. **Who may relay an earthquake notice: more affirmatively permissive than Colombia's law,
   on the actual statute text.** Ley 29664 (SINAGERD) art. 18.1 states private and civil-
   society participation in disaster risk management "constituye un deber y un derecho"
   **[V]** — read directly, not from a summary. Nothing in Ley 29664 or its Reglamento (DS
   048-2011-PCM) reserves the word "alerta" or the act of notifying someone of a hazard to a
   state body; art. 20's infractions list is aimed at public officials and at fraud/false
   documentation, not at private hazard communication **[V]**. Same practical mitigation as
   Colombia: don't imply you are IGP, INDECI, or SASPe/SISMATE.
6. **A real gap the app can honestly point to, without inventing a safety claim: SASPe covers
   only part of the country, only large quakes, and is still in pilot.** SASPe (IGP detection
   + INDECI siren/cell-broadcast dissemination) only activates at magnitude ≥6.0, only covers
   10 coastal departments (~1.54 million people), and was still in "marcha blanca" calibration
   as of January 2026 **[R]**. True, sourced, and a legitimate reason a broader/finer-grained
   relay has value — say exactly this, not more.
7. **Código Penal has two provisions on point, not one, and a third worth flagging
   separately.** Art. 361 (usurpación de función pública, 4-7 years as amended) requires
   actually exercising a public function, which a passive relay app does not do **[V, read
   the primary consolidated text]**. Art. 362 (ostentación de distintivos de una función que
   no ejerce, up to 1 year) is the more directly relevant one — it targets publicly displaying
   the insignia of an office one does not hold **[V]** — so the mitigation is the same as
   Colombia's: no government seals, no IGP/INDECI branding, no implied affiliation. Separately,
   **art. 315-A (grave perturbación de la tranquilidad pública, 3-6 years, no primary text read
   this session — [R])** penalizes spreading false or non-existent news of an imminent harmful
   event via mass channels. This has no clean Colombia equivalent found in this project's prior
   work and gives the project's own "never fail silently, never send a false alarm"
   engineering discipline (already a stated value in this project) real criminal-law stakes in
   Peru specifically — **[LAWYER]** should confirm this requires intent/recklessness and would
   not reach an honest technical bug, but the project's existing test discipline (`gateway
   92/92`, the false-alarm channel-signature fix in `docs/decision.md` §6) is directly what
   keeps this risk low in practice, not just the disclaimer wording.
8. **Liability disclaimer: a blanket waiver is void outright here, not just risky.**
   Código de Protección y Defensa del Consumidor (Ley 29571) art. 50(a) makes any clause that
   "excluya o limite la responsabilidad del proveedor... por dolo o culpa" a "cláusula abusiva
   de ineficacia absoluta" — void, full stop, no balancing test **[V, read the primary text]**.
   This is sharper than Colombia's Ley 1480 doctrine (which asks whether a clause is abusive
   case by case). Use the same "mejor esfuerzo razonable, sin garantía de resultado" framing as
   the Colombia draft, adapted below — never a "no respondemos por nada" line.
9. **Response-time deadlines for data-subject rights are specific and short, unlike Colombia's
   text.** Reglamento art. 69 **[V]**: 8 days for the derecho de información, 20 days for
   acceso, 10 days for rectificación/cancelación/oposición, extendable once by an equal period
   with justification (art. 71). Build this into whatever process answers the "what do you
   have on me" channel, not just the deletion button.
10. **Sanctions, for scale.** Ley 29733 art. 39, read directly **[V]**: leves 0.5-5 UIT, graves
    >5-50 UIT, muy graves >50-100 UIT, capped at 10% of the infractor's annual gross income.
    Not registering the banco de datos is now classified as a leve infraction under the new
    Reglamento (art. 132.4) **[V]** — a downgrade from the original 2011 Ley text, which
    classified it as grave.
11. **Before it ships:** confirm with a Peruvian lawyer (a) that Ley 29733 art. 14.5 actually
    covers the AWS/Apple processing without separate consent, or that consent/contractual
    clauses are needed instead, (b) whether the app's expected device count puts it near the
    ODP "grandes volúmenes" thresholds, (c) art. 315-A's actual reach over a good-faith
    technical failure, and (d) the exact current text of Código Penal art. 362 and its
    penalties, since only the consolidated congreso.gob.pe compilation was read, not a
    Diario Oficial certified copy.

---

## 1. Ley 29733 de 2011 and its Reglamento (DS 016-2024-JUS)

### What's the same as Colombia, and what changed procedurally

The app's data inventory is identical to `legal-colombia.md` §1's table — same fields, same
"no sensitive data" conclusion (Ley 29733 art. 2.5's definition of datos sensibles is
biométricos, salud, origen racial/étnico, opiniones políticas/religiosas/filosóficas,
afiliación sindical, vida sexual — none of it applies here **[V]**). What's different is
procedural: Peru replaced its entire 2013 Reglamento (DS 003-2013-JUS) with a new one, DS
016-2024-JUS, published 2024-11-30, in force since 2025-03-30 (120 calendar days after
publication) **[V]**, 135 articles. Anything researched before that date about Peru's regime
is stale; this doc is built on the current one.

### Registration (no size exemption)

Reglamento arts. 42-45 **[V]**: any banco de datos personales, public or private, of any
size, must be registered in the Registro Nacional de Protección de Datos Personales. The
procedure is a form to the Dirección de Protección de Datos Personales, free (art. 43.3),
with automatic approval under Ley 27444 art. 31 (art. 45.2). There is no Colombia-style
asset/size threshold to check first — register regardless of how small the operator is.

### Consent

Reglamento arts. 1-10 **[V]**: valid consent must be libre, previo, expreso e inequívoco, and
informado. Digital consent is explicitly recognized — "hacer clic", "cliquear", "dar un toque"
count as expreso when they demonstrate a concrete, direct, explicit acceptance (art. 5.1.3)
**[V]**. This is functionally similar to Colombia's rule (Decreto 1377 art. 7: silence never
suffices) even though the wording differs: a first-run screen with an explicit "Acepto" tap
satisfies both regimes.

Consentimiento informado (art. 6) **[V]** requires, at minimum: identity/address of the
responsable, purpose(s), who receives the data, whether the banco de datos exists and is
identified, whether answering is obligatory or optional, consequences of refusing, national/
international transfers if any, automated decision-making if any, retention period, and how
to exercise Título III rights. The draft in §4 below covers all of these.

### International transfer / flujo transfronterizo

See Recommendation §2-3 above for the substance. Mechanically, Reglamento arts. 18-21 **[V]**:
the flow is lawful if the destination country has a "nivel adecuado" as determined by the
DGTAIPD via resolución (art. 19), or, absent that, if the exporter provides adequate
guarantees — model contractual clauses or similar instruments (art. 20) — and regardless of
which path applies, the flow "debe ponerse en conocimiento" of the authority for registration
(art. 21.2). No DGTAIPD resolución naming the US or Brazil as adequate was found this
session; a secondary, tangential source (a Colombian legal aggregator's own list of countries
Colombia's SIC considers adequate) mentions Peru itself as adequate *from Colombia's
perspective*, which says nothing about how Peru treats the US or Brazil **[R, and not
directly relevant — noted only so nobody mistakes it for an answer to the actual question]**.

### Data subject rights and response deadlines

Ley 29733 Título III (arts. 18-25) plus Reglamento arts. 62-94 **[V]**: right to información,
acceso, actualización/inclusión/rectificación/supresión, oposición, tutela before the ANPD.
Response deadlines, Reglamento art. 69 **[V]**: 8 días (información), 20 días (acceso), 10 días
(rectificación/cancelación/oposición), extendable once by an equal period if justified (art.
71) and communicated within the original deadline. As with Colombia, `DELETE /devices` plus
re-registration already covers most of the mechanical requirement; what's missing is a stated
contact channel and a commitment to these specific response windows in the policy text.

### Officer / ODP

Covered in Recommendation §4. Not required today on the facts as understood (no sensitive
data, device count well under the "grandes volúmenes" thresholds per the current
`MAX_DEVICES` cap), but re-check as the user base grows — [U] exactly where the real trigger
point sits once cloud-hosting and continuous-processing factors are weighed together.

---

## 2. Who may issue or relay an earthquake notice in Peru

### Ley 29664 (SINAGERD) and its Reglamento

Read directly, not from a summary **[V]**. Creates SINAGERD: PCM as ente rector, INDECI
(response/preparedness/rehabilitation), CENEPRED (estimation/prevention/reduction), regional
and local governments, armed forces, police, and explicitly "entidades privadas y sociedad
civil" as participants (art. 2 lists the composition; Título II, Capítulo III, Subcapítulo III
is dedicated to private/civil-society participation). Art. 18.1: "La participación de las
entidades privadas y de la sociedad civil constituye un deber y un derecho para la puesta en
marcha de una efectiva Gestión del Riesgo de Desastres" **[V]** — this is affirmatively
inviting language, stronger than anything found in Colombia's Ley 1523. Art. 44 (Reglamento)
defines the Red Nacional de Alerta Temprana with four components (conocimiento, seguimiento y
alerta, difusión y comunicación, capacidad de respuesta) administered by INDECI **[V]** — none
of this text reserves "alerta" or the act of notifying to the state.

Art. 20 (infracciones), read directly **[V]**: infractions apply to public officials and to
"personas naturales y jurídicas" for non-compliance with safety technical norms, obstructing
inspection, submitting fraudulent documentation, or false information. Honestly relaying a
public earthquake notice, disclaiming official status, does not fit any of the listed
infractions.

### IGP, INDECI, SASPe, SISMATE

- **IGP** (Instituto Geofísico del Perú) runs seismic monitoring and the "Sismos Perú" app
  **[R, from `culture-and-apple.md`, not re-derived]**.
- **INDECI** runs SISMATE, a cell-broadcast (not internet) emergency messaging system reaching
  phones without data or credit, in coordination with all four mobile carriers **[R]**.
- **SASPe** (Sistema de Alerta Sísmica Peruano): IGP detects via ~106+ accelerometers along the
  coast, INDECI disseminates via electronic sirens and the same cell-broadcast/EWBS channels;
  activates only at magnitude ≥6.0; covers 10 coastal departments and ~1.54 million people;
  still in "marcha blanca" (pilot calibration) as of January 2026, expected fully operational
  around October 2025 per one source and still calibrating per a more recent one — **[R,
  conflicting dates across sources, flagging rather than picking one]**.

This leaves a real, honest gap (magnitude threshold, geographic coverage, pilot status) that
the app can point to without exaggerating anything it does.

### Código Penal

Arts. 361, 362, read directly from the consolidated congreso.gob.pe compilation of Título
XVIII **[V]** — see Recommendation §7 for the substance and the one caveat (not a Diario
Oficial certified copy). Art. 315-A **[R, not read in primary text]** — see Recommendation §7.

---

## 3. Consumer law (Código de Protección y Defensa del Consumidor, Ley 29571)

Read directly, primary text **[V]**. Relevant provisions:

- **Art. 13 (publicidad engañosa):** protects consumers from advertising that, by omission or
  otherwise, "induzcan o puedan inducirlos a error" about attributes, benefits, or limitations
  of what's offered. Calling the notification an "aviso temprano" without disclosing that a
  meaningful share arrive late (same underlying fact as `docs/findings.md` §8, cited in the
  Colombia doc) risks this the same way it does under Colombia's Ley 1480.
- **Arts. 18-21 (idoneidad):** the service must match what a consumer would reasonably expect
  from what was offered and disclosed. This is a second, independent hook beyond the
  advertising-specific one — the fix is the same: disclose limitations plainly, keep the
  `late: true` downgraded copy the app already has.
- **Arts. 49-51 (cláusulas abusivas):** art. 50(a) makes a clause excluding or limiting the
  provider's liability for dolo o culpa void outright ("de ineficacia absoluta"), not subject
  to a case-by-case balancing test **[V]** — sharper than Colombia's doctrine. Use
  "best-effort, no guaranteed result" wording (§4 below), never a blanket waiver.
- **INDECOPI** is the enforcement body (referenced throughout the Código, e.g. art. III
  concordancias and the infractions title, not separately quoted here).

---

## 4. Drafts (Spanish), delta from the Colombia versions

These adapt `legal-colombia.md` §4's drafts to Peru's agencies, authority, and specific
requirements (arts. 6 and 69 above). Not a full rewrite — only what changes.

### 4.1 Aviso de privacidad (pantalla de inicio) — delta

> **Antes de continuar**
>
> Esta aplicación no es un servicio oficial. No pertenece al Instituto Geofísico del Perú, al
> INDECI, ni a ninguna entidad del Estado. Los avisos pueden llegar tarde, no llegar, o no ser
> exactos: dependen de sistemas de terceros que no controlamos. No reemplazan los protocolos
> oficiales de protección civil ni el Sistema de Alerta Sísmica Peruano (SASPe).
>
> [same "para avisarle guardamos..." paragraph as the Colombia draft, unchanged — the data
> collected is identical]
>
> Esta información se procesa en servidores en Brasil y Estados Unidos, únicamente para
> enviarle el aviso. Puede retirar su consentimiento y borrar esta información en cualquier
> momento desde la app, con "Retirar consentimiento" en la hoja de Cobertura, o escribiendo a
> [correo de contacto]. Responderemos su solicitud de información en un máximo de 8 días
> hábiles, y cualquier otra solicitud en 10 a 20 días según corresponda. Puede leer la política
> completa aquí: [enlace].
>
> ( ) Acepto y quiero recibir avisos de sismo.

### 4.2 Política de tratamiento — delta

Same eleven-point structure as the Colombia draft, with these Peru-specific changes:

- Point 3 ("sus derechos"): add the specific response deadlines (8/10/20 días, Reglamento art.
  69) and name the Autoridad Nacional de Protección de Datos Personales (Ministerio de
  Justicia y Derechos Humanos) instead of the SIC.
- Point 4 ("dónde se procesa"): keep as-is (AWS Brazil, Apple/APNs US), but add one sentence
  once counsel confirms the art. 14.5 reading (Recommendation §3): "Este tratamiento por
  nuestros proveedores es necesario para cumplir el servicio que usted solicitó, conforme al
  artículo 14 de la Ley N.º 29733." Do not publish this sentence until that reading is
  confirmed — **[LAWYER]**.
- New point: state that the banco de datos is registered in the Registro Nacional de
  Protección de Datos Personales, once the registration (Recommendation §1) is done.
- Point 8 ("autoridad de vigilancia"): Autoridad Nacional de Protección de Datos Personales,
  Ministerio de Justicia y Derechos Humanos (ANPD).

### 4.3 Términos de uso — delta

Same structure as the Colombia draft. Replace "Servicio Geológico Colombiano" /
"Unidad Nacional para la Gestión del Riesgo de Desastres" with "Instituto Geofísico del Perú"
/ "Instituto Nacional de Defensa Civil (INDECI)". The "sin garantía de resultado" paragraph
needs no substantive change — it was already written to avoid a blanket waiver, which Peru's
art. 50(a) (§3 above) makes doubly important to keep that way.

### 4.4 App Store privacy label

No change from `legal-colombia.md` §4.4 — the label reflects what the app collects and sends
to Apple's review process, not country-specific law. Nothing Peru-specific to add here.

---

## Unverified list, in one place

- Whether Ley 29733 art. 14.5 (contractual necessity) actually covers the AWS/Apple
  processing without separate consent — this is this doc's single biggest open legal question,
  since Peru has no clean Colombia-style Encargado/transmisión carve-out. **[LAWYER]**
- Whether Peru's ANPD has issued any resolución declaring the US and/or Brazil to have "nivel
  adecuado" for flujo transfronterizo — not found this session. **[U]**
- Exactly where the ODP "grandes volúmenes de datos" threshold would be crossed once cloud-
  hosting (medium/high on the territorial-demarcation axis) and continuous processing (likely
  high on the frequency axis) combine with a growing device count — the scoring rules are
  read directly, but applying them to this specific system's numbers was not done. **[U]**
- Código Penal art. 315-A's actual reach over a good-faith technical failure (vs. requiring
  intent/recklessness) — not read in primary text, only via secondary summaries. **[R]/[LAWYER]**
- The exact current (post-amendment) text and penalty of Código Penal art. 362 — read from a
  congreso.gob.pe consolidated compilation, not a certified Diario Oficial copy. **[R]**
- SASPe's actual current operational status (still "marcha blanca" vs. fully operational) —
  sources found this session gave conflicting timelines. **[R]**
- Whether the Reglamento's downgrade of "failure to register" from grave to leve (art. 132.4)
  survived any later amendment — read directly in the version fetched this session, dated
  2024-11-30; not cross-checked against any later modification. **[V as of that date, U
  beyond it]**

---

## Sources

- [Ley N.º 29733, Ley de Protección de Datos Personales, full text](https://www.leyes.congreso.gob.pe/documentos/leyes/29733.pdf) — **[V]**, read in full this session.
- [Decreto Supremo N.º 016-2024-JUS, Reglamento de la Ley N.º 29733 (2024-11-30)](https://img.lpderecho.pe/wp-content/uploads/2024/11/Decreto-Supremo-016-2024-JUS-LPDerecho.pdf) — **[V]**, read in full this session (135 articles).
- [Contraloría, cuadro comparativo Ley 29733 pre/post Decreto Legislativo 1353](https://doc.contraloria.gob.pe/documentos/Cuadro_Ley_Proteccion_Datos_Personales.pdf) — **[V]**, used to confirm arts. 38-39's current text and the infractions/sanciones structure.
- [Resolución Directoral N.º 100-2025-JUS/DGTAIPD, Directiva sobre el Oficial de Datos Personales, and its Anexo 1](https://cdn.www.gob.pe/uploads/document/file/9229896/) — **[V]**, read in full this session (ODP thresholds and scoring rules).
- [gob.pe, Inscribir flujo transfronterizo de datos personales](https://www.gob.pe/9253-inscribir-flujo-transfronterizo-de-datos-personales) — **[V]**, fetched this session.
- [Ley N.º 29664, que crea el SINAGERD](https://www.minam.gob.pe/wp-content/uploads/2017/04/Ley-N%C2%B0-29664.pdf) — **[V]**, read in full this session.
- [Decreto Supremo N.º 048-2011-PCM, Reglamento de la Ley N.º 29664](https://www.minam.gob.pe/prevencion/wp-content/uploads/sites/89/2014/10/2.-DS-048-2011-Reglamento-Ley-29664.pdf) — **[V]**, read in full this session.
- [Código Penal, Decreto Legislativo N.º 635, Título XVIII (consolidated)](https://www2.congreso.gob.pe/sicr/cendocbib/con5_uibd.nsf/226BC23AA90575B9052582C0005A2F85/$FILE/titulo_xviii_delitos_contra_adm_justicia.pdf) — **[V]**, read in full this session (arts. 361-366).
- Código Penal art. 315-A: [LP Derecho, jurisprudencia del artículo 315-A](https://lpderecho.pe/articulo-315-a-codigo-penal-delito-grave-perturbacion-tranquilidad-publica/) — **[R]**, not read in primary text.
- [Código de Protección y Defensa del Consumidor, Ley N.º 29571, full compiled text](https://lexsoluciones.com/wp-content/uploads/2021/11/CODIGO-DEL-CONSUMIDOR-24.10.2021.pdf) — **[V]**, read in full this session (arts. III, IV, 12-21, 49-51).
- SASPe: [IGP, SASPe](https://www.igp.gob.pe/servicios/saspe/); [gob.pe/INDECI, Sistema de Alerta Sísmica Peruano](https://www.gob.pe/institucion/indeci/campa%C3%B1as/4943-sistema-de-alerta-sismica-peruano-saspe); [Radio Nacional, enero 2026](https://www.radionacional.gob.pe/novedades/dialogo-abierto/peru-pone-en-marcha-su-primer-sistema-de-alerta-sismica-con-tecnologia-nacional) — **[R]**, fetched this session, conflicting operational-status dates noted above.
- SISMATE: cited via `docs/research/culture-and-apple.md`, not re-fetched this session — **[R]**.
- Flujo transfronterizo / adequacy cross-reference (Peru listed by Colombia's SIC): search-engine synthesis, tangential, not the actual question this doc needed answered — **[R]**, flagged as not directly relevant.
- Cross-referenced this project's own: `docs/research/legal-colombia.md` (structure and the
  app's own data inventory, not repeated here), `docs/research/culture-and-apple.md` (IGP/
  INDECI/SISMATE app-landscape findings, Código Penal art. 361 finding extended here with
  primary text), `docs/STATUS.md` (MAX_DEVICES cap, referenced for the ODP threshold discussion).

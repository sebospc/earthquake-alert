# Culture and App Store notes, first-wave countries

2026-09-25, investigator. Covers the six countries behind the Spanish + English + Turkish
recommendation in `languages.md`: Colombia (baseline, already covered by
`legal-colombia.md`), Mexico, Chile, Peru, Argentina, Philippines, Turkey.

Tags: **[V]** read/fetched directly this session. **[R]** reported by a secondary source,
not independently re-derived. **[U]** unverified or a judgment call — do not build on it
without checking.

Not legal advice. Every "no equivalent found" below means the search did not surface one
this session, not that none exists — a local lawyer should confirm before launch in that
market, same discipline as `legal-colombia.md`.

## Recommendation

1. **The "must not look official" problem is not Colombia-specific.** Mexico, Argentina,
   Peru and the Philippines each have a direct penal-code equivalent to Colombia's Código
   Penal art. 425-426 (usurping a public function/authority) [V, primary text for AR/PE,
   R for MX/PH — see §1). The same "we relay Google's alert, we are not the government"
   framing used in `legal-colombia.md` should transfer to those four. Chile and Turkey:
   no clean equivalent found this session — flag to counsel, don't assume either way [U].

2. **No color/iconography clash found.** The app's actual scheme — red for danger, orange
   for late alerts, gray for test, white seismograph mark on a red icon (checked directly
   in `AlertView.swift`, `CoverageView.swift`, `tools/app-icon.swift`) — matches "red/orange
   = danger" conventions in every country researched [R, general color-symbolism sources].
   The one real flag — yellow reads as a mourning color in parts of Latin America [R] — is
   moot: the app does not use yellow anywhere. No redesign needed.

3. **Keep "usted" as the default formal register for all Spanish markets**, not just
   Colombia. Argentina's everyday speech is voseo, but formal/official registers there
   still use usted or tú, not vos [R]; Chile's formal register is tuteo/usted, voseo is
   informal-only [R]. A safety notification in the imperative ("Agáchese, cúbrase...") reads
   as appropriately formal everywhere in this set; it does not read as cold or foreign
   anywhere researched. Native-speaker review still recommended before shipping per-country
   strings, same caveat as `languages.md`.

4. **Turkey: use "siz" (formal/plural you), matching AFAD's own communications** [R]. This
   needs no special string changes, since English and Turkish notification strings already
   drafted in `languages.md` don't carry a T-V distinction in English, but the Turkish
   translations (still needs_review, no invented strings) should be written formal.

5. **App Store is available in all six countries** [V, fetched Apple's own availability
   page]. No Iran-style hard blocker anywhere in this wave.

6. **Turkey needs a distinct App Store/consent step: VERBIS.** Data controllers must
   register with Turkey's VERBIS registry before processing Turkish residents' data, unless
   exempt (roughly: under 50 employees and under ~25M TL balance sheet, and no special-category
   data) [R]. KVKK guidance also wants consent granular per purpose, not a single accept-all
   toggle [R] — this matches the multi-purpose consent screen `legal-colombia.md` already
   describes for Colombia, so the UI likely needs no change, but registration is a new,
   Colombia-has-no-equivalent-of step. Flag to developer-ios/legal before Turkey launch.

7. **Mexico's regulator changed again since `legal-colombia.md` was scoped.** INAI is gone
   (dissolved by the "Simplificación Orgánica" reform, in force 2025-03-21) [V]. Private-sector
   data protection is now handled by the Secretaría Anticorrupción y Buen Gobierno (SABG),
   specifically its Dirección General de Datos Personales en el Sector Privado, under a new
   Ley Federal de Protección de Datos Personales en Posesión de los Particulares (2025-03-20)
   [V]. Any future Mexico legal doc should cite SABG/the new LFPDPPP, not INAI.

## Part 1 — Culture, per country

### Colombia (baseline, already live)

Already covered in depth by `legal-colombia.md`. Not repeated here except as the reference
point the other six are compared against: formal "usted", app must not look
official/governmental (Código Penal art. 425-426), red for danger with no reported clash.

### Mexico

- **Existing apps.** SASSLA is the official government-endorsed relay for SASMEX
  (Sistema de Alerta Sísmica Mexicano), explicitly described as the country's only official
  seismic alert system [R]. SASMEX itself is operated by CIRES, a non-profit civil
  association, not a government agency directly [R] — an interesting precedent: Mexico's
  own "official" alert system is technically privately-run infrastructure with government
  endorsement, not a pure state system.
- **Trust signal / legal risk of looking official.** Mexico's Código Penal Federal and
  state codes (e.g. Estado de México art. 176) criminalize "usurpación de funciones
  públicas" — attributing to oneself the character of a public official or performing acts
  reserved to authorities [R, not read in primary text this session]. This reads as a
  real, if not identically-worded, equivalent to Colombia's art. 425-426. Given SASSLA's
  precedent (a government-endorsed but not government-built app, explicitly branded as
  "the only official one"), the safer path in Mexico is the same as Colombia: never claim
  or imply "official", state plainly this is an independent relay of Google's AEA signal.
- **Color/iconography.** No Mexico-specific clash found for red/orange. Yellow-as-mourning
  is reported as a Latin-America-wide association [R], strongest around Día de Muertos
  marigold imagery — irrelevant here since the app carries no yellow.
- **Tone.** Standard formal Mexican Spanish is usted-based; no voseo. No change needed
  from the Colombia string set beyond the country-specific facts already flagged in
  `languages.md` (e.g. which agency to cite).

### Chile

- **Existing apps.** SENAPRED (the state disaster-management service) runs an informational
  hazard-exposure viewer ("Visor Chile Preparado") but the dominant earthquake-alert app in
  daily use is "Chile Alerta" — a third-party app, reportedly 500,000+ downloads, that also
  redistributes SENAPRED alerts [R]. This is the most favorable precedent found in any of
  the six countries: a non-government seismic alert app is already the market leader, which
  suggests Chilean users don't require a "looks official" app to trust it.
- **Trust signal / legal risk.** No Chilean penal-code equivalent to "usurpación de
  funciones públicas" specific to acting like an authority was found this session. Chilean
  law does cover identity impersonation generally (Código Penal art. 214, extended to
  internet/social media) [R] and misuse of state emblems (flag/shield) under the Ley de
  Seguridad del Estado or Código de Justicia Militar when done to insult the symbol [R] —
  neither is a clean match for "an app that looks governmental without claiming to be."
  Given the Chile Alerta precedent above, this is likely lower-risk than Colombia, but
  **not researched to the point of confidence** — flag to counsel, don't assume it's safe [U].
- **Color/iconography.** No clash found.
- **Tone.** Chilean formal register is tuteo/usted; voseo is informal/colloquial only [R].
  Safe to keep the same formal register as Colombia.

### Peru

- **Existing apps.** Two parallel official channels: "Sismos Perú", built by IGP (Instituto
  Geofísico del Perú) via its CENSIS seismological center [R], and SISMATE, INDECI's
  cell-broadcast (not internet-based) emergency messaging system that reaches phones even
  without data or credit [R]. A third-party "Sismo Detector" app also exists, using phone
  sensors as an informal seismograph [R]. Peru is the one country in this set with two
  distinct official/government apps already competing for the same use case.
- **Trust signal / legal risk.** Peru's Código Penal art. 361 criminalizes "usurpación de
  función pública" — exercising a public function without title or appointment [V, article
  text found and quoted by multiple legal sources, though not read in the primary Código
  Penal document itself this session — tagging [R] to be conservative]. This is functionally
  the same rule as Colombia's. Same mitigation: never claim official status, name Google AEA
  and IGP/INDECI as the real sources plainly.
- **Color/iconography.** No clash found.
- **Tone.** Standard usted-based formal Peruvian Spanish; no voseo in the mainstream
  register. No change needed.

### Argentina

- **Existing apps.** No dedicated national early-warning app surfaced under the name
  "SINAGIR" — that search came up empty [R, confirmed by absence rather than presence].
  What does exist: Google's own AEA is delivered through Android's built-in earthquake
  alert settings [R], and the official SMN (Servicio Meteorológico Nacional) app handles
  weather but not seismic alerts specifically [R]. This means Argentina, more than any
  other country in this set, currently has **no dedicated seismic-alert app of its own** —
  arguably the most receptive market for a new one, but also nothing to imitate or compete
  against on trust cues.
- **Trust signal / legal risk.** Argentina's Código Penal art. 246 ("usurpación de
  autoridad") punishes assuming or exercising a public function without title or
  appointment [V, article text found and quoted, tagging [R] since the primary Código Penal
  document was not opened directly this session]. Direct equivalent to Colombia's rule.
  Same mitigation applies.
- **Color/iconography.** No clash found.
- **Tone.** This is the one genuinely distinct case: Argentina's everyday spoken and
  written Spanish is voseo (vos, not tú), officially recognized since 1982 [R]. However,
  formal/official register — including, by report, official documents — still defaults to
  usted or tú rather than vos [R]. Recommend keeping "usted" in Argentine push strings for
  consistency with the rest of the Spanish set and because it reads as appropriately formal,
  not because vos would be wrong — but this is exactly the kind of nuance to hand to a
  native Argentine speaker during the review `languages.md` already asked for, not decide
  from search results alone [U].

### Philippines

- **Existing apps.** DOST-PHIVOLCS runs "PH Weather and Earthquakes" (formerly "PHIVOLCS
  Earthquake Alerts") and a separate hazard-assessment tool, HazardHunterPH [R]. The
  government also mandates telecoms and NDRRMC to push free cell-broadcast alerts via the
  Emergency Cell Broadcast System (ECBS) [R] — a parallel, carrier-level channel independent
  of any app, similar in spirit to Peru's SISMATE.
- **Trust signal / legal risk.** Revised Penal Code art. 177 ("usurpation of authority or
  official functions") criminalizes falsely representing oneself as an officer, agent or
  representative of a Philippine government department or agency [R]. Article 179 separately
  penalizes unauthorized use of the national seal/coat of arms [R]. Both are direct, clean
  equivalents to Colombia's rule — arguably the most explicitly on-point of any country in
  this set. Same mitigation: no government seals, no agency names implied as the source,
  name Google AEA and PHIVOLCS as the real upstream sources.
- **Color/iconography.** No clash found. (Not researched: any Philippine cultural weight on
  yellow specifically tied to the 1986 People Power movement's yellow ribbon — a political,
  not safety, connotation, and out of scope here, but worth a one-line gut-check by someone
  Filipino before any yellow UI element is ever added.)
- **Tone.** English is an official language and the dominant language of PHIVOLCS's own
  alert text (confirmed in `languages.md` §2 — PHIVOLCS/NDRRMC's "Duck, Cover, Hold" is
  published in English). No Filipino-specific formality register question arises since the
  first-wave plan uses English for the Philippines, not Filipino.

### Turkey

- **Existing apps.** AFAD (Turkey's disaster/emergency management authority) runs at least
  two official apps: "AFAD Deprem" (earthquake data/felt-reports) and "AFAD Acil Çağrı"
  (a broader emergency app with one-touch emergency calling and gathering-area maps) [R].
  Both are on iOS and Android. This is the most institutionally dense existing-app landscape
  of any country in this set — Turkish users have a specific, recent (post-2023 earthquake)
  expectation of what an official government alert app looks and behaves like.
- **Trust signal / legal risk.** No direct Turkish Penal Code (TCK) equivalent to
  "usurpación de funciones públicas" was confirmed this session. TCK art. 204 covers
  official document forgery [R] and TCK art. 264 covers unauthorized use of special
  insignia/uniforms [R] — neither is a clean match for "an app that looks like it comes
  from AFAD without saying so." Given how recent and salient the 2023 earthquakes are in
  Turkey, and how many official AFAD apps already exist, the reputational risk of looking
  official without being AFAD is plausibly high even if no specific criminal statute
  matches — but this is a judgment call, not a researched legal conclusion [U]. Flag to
  counsel explicitly; don't reuse the Colombia disclaimer wording as if it were legally
  equivalent.
- **Color/iconography.** No clash found for red/orange. The Turkish flag's red is under
  specific legal protection against defacement of the flag itself [R] — this is about the
  physical/graphic flag object, not a general restriction on using red as a UI color, so it
  does not appear to bear on the app's icon or alert colors. Noting it so nobody re-derives
  this concern from scratch later.
- **Tone.** Use "siz" (formal), matching how Turkish formal/official writing works [R] and
  how AFAD's own materials are presumed to read (not independently confirmed by reading an
  AFAD notification directly this session — [U]).

## Part 2 — Apple / App Store, per country

- **Availability.** App Store confirmed available in Mexico, Chile, Peru, Argentina,
  Philippines and Turkey [V, fetched Apple's own "Availability of Apple Media Services"
  page directly]. No sanctions-style exclusion anywhere in this wave (Iran remains the only
  one found across the whole project, per `languages.md`).
- **Data residency / local representative requirements.** Not researched per country beyond
  what's below for Turkey. No country in this set is known to require in-country data
  hosting for an app like this one; nothing found this session says otherwise, but this was
  not specifically checked for Mexico, Chile, Peru, Argentina or the Philippines — [U],
  don't assume clear.
- **Age rating norms.** Not researched. No country-specific quirk surfaced organically in
  any of the searches run this session; Apple's own global age-rating questionnaire
  (App Store Connect) is presumed to apply uniformly. Flag as genuinely unchecked, not
  confirmed-fine.
- **Export-compliance quirks.** Checked specifically for Turkey because of a known
  comparison case: France requires an ANSSI declaration for any app using encryption before
  it can be sold there [R]. No equivalent Turkish (BTK) requirement was found for
  app-level encryption declarations [R, absence of evidence, not evidence of absence — the
  search may simply not have surfaced Turkish-language sources]. Nothing checked for the
  other five countries.
- **Turkey — KVKK-specific, beyond `legal-colombia.md`'s Ley 1581 treatment:**
  - VERBIS registration: data controllers must register in the Veri Sorumluları Sicil
    Bilgi Sistemi before processing Turkish residents' data, unless exempt (roughly: fewer
    than 50 employees and under ~25 million TL balance sheet, and the main activity isn't
    processing special-category data) [R]. This is a step Colombia's Ley 1581/RNBD
    framework does not have a parallel of at the same trigger size — Colombia's RNBD
    threshold is 100,000 UVT in assets (see `legal-colombia.md` §1), much higher relative
    to a small relay operator. Whether this project's operator would be VERBIS-exempt
    depends on facts (employee count, balance sheet) not researched here — [U].
  - Consent granularity: KVKK guidance wants consent captured per distinct processing
    purpose, not one blanket "accept all" [R]. The Colombia consent design already
    described in `legal-colombia.md` §4.2 (separate coverage vs. telemetry consent) appears
    structurally compatible with this, but that's an inference, not a confirmed reading of
    KVKK requirements against this app's actual screens — [U].
- **Mexico — post-INAI, beyond `legal-colombia.md`'s treatment (which predates this
  change and does not mention it, since it was scoped to Colombia only):**
  - INAI dissolved, in force since 2025-03-21 [V]. Private-sector data protection now sits
    with SABG's Dirección General de Datos Personales en el Sector Privado, under a new
    Ley Federal de Protección de Datos Personales en Posesión de los Particulares dated
    2025-03-20 [V]. No App Store-description-specific requirement from this new law or
    regulator was found this session — [U], not researched further than confirming who the
    regulator is now.

## Not researched, flagged rather than guessed

- Chile: whether any statute functions like Colombia's art. 425-426 for "looking official"
  — genuinely unresolved, not assumed safe.
- Turkey: same question — TCK 204/264 are related but not confirmed equivalents.
- Data residency / local-representative / age-rating requirements for Mexico, Chile, Peru,
  Argentina, Philippines — not checked at all this session.
- Whether VERBIS exemption applies to this project specifically (depends on the operating
  entity's size, not on anything researchable in the abstract).
- Philippine cultural connotations of yellow (People Power association) — flagged as a
  gut-check item, not researched, and out of scope unless yellow is ever proposed for the UI.
- Whether AFAD's own push notifications actually use "siz" — inferred from general Turkish
  formal-register conventions, not confirmed by reading an actual AFAD alert.

## Sources

- SASSLA / SASMEX: [Wikipedia, Mexican Seismic Alert System](https://en.wikipedia.org/wiki/Mexican_Seismic_Alert_System); [Google Play, Alerta Sísmica México - SASSLA](https://play.google.com/store/apps/details?id=com.safelivealert.earthquake&hl=en_US) — [R]
- Chile Alerta / SENAPRED: [SENAPRED](https://senapred.cl/), [Chile Alerta](https://app.chilealerta.com/) — [R]
- Peru Sismos Perú / SISMATE: [gob.pe, Sismos Perú](https://www.gob.pe/66378-recibir-alertas-y-reportes-de-sismos-en-tu-celular-a-traves-de-la-aplicacion-sismos-peru); [El Comercio, Sismo Detector](https://elcomercio.pe/respuestas/sismo-detector-como-funciona-la-aplicacion-movil-que-alerta-sismos-temblor-hoy-en-peru-indeci-igp-revtli-noticia/) — [R]
- Argentina Google AEA / SMN: search results, no primary source for "SINAGIR" found — [R]
- Philippines PHIVOLCS/NDRRMC/ECBS: [PHIVOLCS](https://www.phivolcs.dost.gov.ph/earthquake-monitoring-system/); [Wikipedia, Emergency Cell Broadcast System](https://en.wikipedia.org/wiki/Emergency_Cell_Broadcast_System) — [R]
- Turkey AFAD apps: [AFAD](https://www.afad.gov.tr/deprem-mobil-uygulamasi) — [R]
- Mexico usurpación de funciones públicas: [Estado de México Código Penal art. 176](https://leyes-mx.com/codigo_penal_mexico/176.htm) — [R]
- Argentina Código Penal art. 246: [Pensamiento Penal](https://www.pensamientopenal.com.ar/cpcomentado/37790-art-246-247-usurpacion-autoridad-titulos-y-honores) — [R]
- Peru Código Penal art. 361: [LP Derecho](https://lpderecho.pe/articulo-361-codigo-penal-usurpacion-funcion-publica/) — [R]
- Philippines RPC art. 177/179: [jur.ph](https://jur.ph/law/summary/rules-regulations-coat-of-arms-great-seal-philippines); [Legal Resource PH, Title 4](https://library.legalresource.ph/title-4-crimes-against-public-interest-book-2-revised-penal-code/) — [R]
- Turkey TCK 204/264: [Barandoğan, TCK 264](https://barandogan.av.tr/blog/mevzuat/tck-madde-264-ozel-isaret-ve-kiyafetleri-usulsuz-kullanma-sucu.html) — [R]
- Chile identity/emblem law: [Conceptos Jurídicos, Suplantación en Chile](https://www.conceptosjuridicos.com/cl/usurpacion-del-estado-civil/); [Editorial Hammurabi, Símbolos Patrios](https://www.editorialhammurabi.com/2026/04/08/simbolos-patrios-de-chile-historia-regulacion-legal-y-uso-correcto-de-nuestros-emblemas/) — [R]
- Voseo/tuteo/usted: [RAE, voseo](https://www.rae.es/dpd/voseo); search summary of Argentine/Chilean academic sources — [R]
- Turkish formal register: [Elon.io, Formal Register siz](https://elon.io/grammar/turkish/register/formal-siz) — [R]
- Color symbolism (yellow/mourning, red/orange/danger): [Shutterstock, Color Symbolism](https://www.shutterstock.com/blog/color-symbolism-and-meanings-around-the-world); [Yatskia Urns, Mourning Colors](https://www.yatskiaurns.com/blogs/news/understanding-the-different-colors-of-mourning-in-various-countries) — [R]
- App's actual color/icon scheme: `ios-client/EarthquakeRelay/AlertView.swift`,
  `ios-client/EarthquakeRelay/CoverageView.swift`, `ios-client/tools/app-icon.swift` — [V]
- App Store availability: [Apple Support, Availability of Apple Media Services](https://support.apple.com/en-us/118205) — [V]
- Turkey VERBIS/KVKK consent: [Biscotti CMP, KVKK and VERBIS Compliance Guide](https://www.biscotti-cmp.com/en/blog/doing-business-in-turkey-what-you-need-to-know-about-the-kvkk-and-verbis); [Pandectes, Understanding KVKK](https://pandectes.io/blog/understanding-turkeys-personal-data-protection-law-kvkk/) — [R]
- Mexico post-INAI: [IAPP, nueva autoridad en protección de datos](https://iapp.org/news/a/se-establece-una-nueva-autoridad-en-materia-de-protecci-n-de-datos-personales-en-m-xico); [Grupo Animal](https://grupoanimal.mx/explicaciones/proteccion-datos-personales-inai) — [V, cross-checked across two sources]
- Cross-referenced this project's own: `docs/research/legal-colombia.md`,
  `docs/research/languages.md`

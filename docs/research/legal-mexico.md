# Legal: Mexico (LFPDPPP 2025, alerting rules, liability, drafts)

2026-09-26. Not legal advice. I am not a lawyer and this is not a law firm's opinion: it is a
map of the rules and a first draft of the delta text, to hand to a Mexican lawyer before launch
in this market. Every place needing a lawyer's sign-off is marked **[LAWYER]**.

Tags: **[V]** read in the primary source (the law's own text). **[R]** reported by a secondary
source (news, law-firm blog), not cross-checked against the primary text. **[U]** unverified,
or a judgment call with no clean answer.

This doc does not re-derive what the app collects — see `legal-colombia.md` §1's table
(`device_token`, `sensor_ids`, `demand_cell`, automatic `min_magnitude`, opt-in telemetry). It
still applies as-is; Mexico's law does not draw a different data-collection line.

---

## Recommendation

1. **No registration duty found for the private sector.** I read the new LFPDPPP end to end
   (64 articles) and found no RNBD-style public registry or padrón obligation for a private
   `responsable`, at any size **[V]**. Unlike Colombia's RNBD/UVT-threshold test, Mexico's law
   simply doesn't impose one on private parties — only SABG's own internal transparency
   registries are mentioned, and those are about the old INAI's public-sector remit, not about
   private companies. **[LAWYER]** should confirm nothing outside this law (a sector-specific
   rule, a Ciudad de México local rule) adds one; I did not check state-level rules.
2. **Consent: Mexican law is more permissive than Colombia's here — use the stricter standard
   anyway.** Art. 7 lets consent be tácito (the titular saw the aviso and didn't object) for
   anything except financial/patrimonial data or wherever another rule demands expreso
   consent **[V]** — the literal opposite of Colombia's Decreto 1377 art. 7, which says silence
   never counts. Recommendation: keep the same explicit "Acepto" tap already built for
   Colombia. It exceeds what Mexican law requires, costs nothing extra (it's the same screen),
   and removes an entire category of dispute about whether "showing the aviso" was enough.
3. **International transfer: cleaner than Colombia's reasoning, and directly in the statute's
   own definitions.** Art. 2-XX defines "transferencia" as a communication to someone *other
   than* the titular, the responsable, **or the persona encargada** **[V]** — meaning sending
   data to your own processor (AWS for hosting, Apple/APNs for push) is not a "transferencia"
   under this law's own wording, full stop, nationally or internationally. Chapter V's
   consent-for-transfer machinery (art. 35-36) never even engages. This is a stronger, more
   directly-sourced version of the "transmisión" argument used for Colombia. **[LAWYER]**
   should still confirm AWS's and Apple's contracts function as `encargado` agreements in
   substance (processing only on instructions, for the app's own purposes) — that's the fact
   the whole argument rests on, and nobody has read those contracts with this specific
   question in mind.
4. **No sensitive data, same as Colombia.** Art. 6 (fracción VI) sensitive-data categories
   (health, ethnicity, religion, genetics, political/sexual data) do not include the device
   token, receptor IDs, coarse location or magnitude preference **[V]**. Keep it that way, same
   caution as `legal-colombia.md` recommendation 4.
5. **"Alerta sísmica" is not a protected term today, but the ground is actively shifting.** A
   Mexico City legislative committee moved in 2025 to study reforming the legal framework
   specifically for private earthquake-alert apps, explicitly because many already-existing
   apps don't meet the technical norm and the authority currently has no power to limit or fine
   them **[R]**. Read that both ways: today, nothing stops a compliant private relay app; a
   change could arrive with no warning and be aimed exactly at this category. Mitigation, same
   shape as Colombia: never use SASMEX, CENAPRED, Protección Civil, or any state name/seal;
   never claim to be an official channel; monitor this specific reform thread before each
   Mexico release, not just once.
6. **Usurpación de funciones públicas is a real, direct, on-point risk — confirmed in the
   statute's own text.** Código Penal Federal art. 250 fracción I: 1-6 years prison plus a
   fine, for anyone who, "sin ser funcionario público, se atribuya ese carácter y ejerza alguna
   de las funciones de tal" **[R, quoted verbatim by a legal-database aggregator, not the raw
   DOF/diputados PDF itself this session]**. Fracción IV separately penalizes using
   credentials, uniforms, insignias or siglas ("acronyms/initials") one has no right to, with
   up to +50% penalty if they belong exclusively to the armed forces or a police force **[R]**.
   Direct equivalent of Colombia's art. 425-426. Mitigation: identical to Colombia's —  no
   government names, seals, uniforms, or acronyms implying an official body; plain "not an
   official channel" disclaimer.
7. **Liability disclaimer: same three lines as Colombia, same placement, translate only.**
   "No es un servicio oficial." / "Puede fallar, llegar tarde, o no llegar." / "No sustituye
   los protocolos de protección civil." These need no Mexico-specific content change — nothing
   found in Mexican consumer law contradicts them. What needs a Mexico-specific check: whether
   a full "mejor esfuerzo, sin garantía de resultado" framing (same as Colombia's draft) risks
   being read as an unfair/abusive clause under the Ley Federal de Protección al Consumidor
   (LFPC), enforced by PROFECO, which requires advertising and terms be truthful, verifiable
   and clear **[R]** — **[LAWYER]** should confirm the exact LFPC article and PROFECO's current
   posture on liability-limitation clauses in consumer apps; I did not read LFPC's primary
   text this session (a `.gob.mx`/`diputados.gob.mx` fetch failed and wasn't retried with the
   fallback technique in the time available — flagged, not guessed).
8. **App Store privacy label: no Mexico-specific delta.** Apple's nutrition-label mechanics and
   categories don't vary by storefront country. The Colombia table in `legal-colombia.md` §4.4
   applies as-is to the Mexico storefront listing.
9. **Before it ships in Mexico:** confirm with a Mexican lawyer (a) the LFPC/PROFECO liability
   wording, (b) that AWS's and Apple's actual contract language supports the `encargado`
   reading in recommendation 3, (c) whether any Ciudad de México or state-level rule touches
   private seismic-alert apps specifically (the 2025 CDMX committee study, not yet a law, was
   the only lead found), and (d) the practical scope of the still-unpublished new Reglamento —
   see §1 below, the old 2011 one fills the gap today but nobody has mapped exactly which
   clauses of it still bind.

---

## 1. LFPDPPP 2025 (Ley Federal de Protección de Datos Personales en Posesión de los
   Particulares)

Published in the DOF on 2025-03-20, in force since 2025-03-21, replacing the 2010 law of the
same name, as part of the same decree that dissolved INAI **[V, read the full 64-article text
via ordenjuridico.gob.mx's official mirror of the DOF publication]**.

### Scope and regulator

Applies to "personas físicas o morales de carácter privado que llevan a cabo el tratamiento de
datos personales" (art. 2-XVI, "sujetos regulados") — a small operator running this app for
Mexican users is squarely inside scope. Two exceptions (art. 1): credit-reporting companies
under their own law, and purely personal, non-commercial data collection — neither applies
here **[V]**. The regulator is the **Secretaría Anticorrupción y Buen Gobierno (SABG)**, art.
2-XV, replacing INAI, consistent with `culture-and-apple.md`'s finding **[V]**.

### Consent

Art. 7 **[V]**: consent can be expreso or tácito. Expreso is any clear signal — verbal,
written, electronic, or "signos inequívocos." Tácito is valid **by default** whenever the aviso
de privacidad was made available and the titular did not object — this is the reverse of
Colombia's Decreto 1377 art. 7, where silence is explicitly never enough. Expreso is only
mandatory for financial/patrimonial data (not collected here) or wherever another rule demands
it. Sensitive data (art. 8) always needs expreso **y por escrito** consent (signature or
electronic-authentication equivalent) — moot here since nothing sensitive is collected (art. 6
fracción VI's list: health, ethnicity, religion, genetics, political/sexual data) **[V]**.

Recommendation 2 above stands: build to the stricter Colombia standard (explicit tap) anyway.

### The aviso: two tiers, not two documents

Mexico's law does not have a separate "Política de Tratamiento" document the way Colombia's
Decreto 1377 does. Instead, art. 15 sets what the **aviso de privacidad** itself must contain,
and art. 16 splits it into two presentations of the same document **[V]**:

- **Aviso integral**: all six elements of art. 15 — identity/address of the responsable; what
  data is treated, flagging anything sensitive; the purposes, distinguishing which need
  consent; the options/means offered to limit use or disclosure; the mechanisms to exercise
  ARCO rights; and how changes to the aviso will be communicated.
- **Aviso simplificado**: required whenever data is collected electronically (this app
  qualifies). Must contain at least the first four of those six elements, and must point to
  where the aviso integral can be consulted.

Practical mapping for this app, same shape as the Colombia design: the onboarding screen is the
aviso simplificado (identity, what's collected, purposes, opt-out options), and a Settings/About
screen holds the aviso integral (adds the ARCO-exercise channel and the change-notification
procedure). No new document type needs building — only renaming and re-pointing what
`legal-colombia.md` §4.1/4.2 already drafted.

### ARCO rights and procedure

Arts. 21-34 **[V]**: access, rectification, cancellation, opposition ("ARCO"), exercised free
of charge (only reproduction/shipping costs may be charged, art. 34), with a designated
person or department to receive requests (art. 29) — this is the same functional requirement
as Colombia's Decreto 1377 art. 23 "persona o área designada", and the same channel (an email
address in the policy, answered by asking for the `device_token` since no name is ever stored)
satisfies both. Response deadline: 20 días to decide, 15 more days to make it effective, each
extendable once by an equal period on justified grounds (art. 31) — looser than nothing, but
worth stating precisely since Colombia's doc did not give exact day counts for this step.

### International transfer

Covered in Recommendation 3 above. The mechanism is art. 2-XX's own definition of
"transferencia", which excludes communications to a `persona encargada` (processor) by name
**[V]** — cleaner than needing a separate exemption article the way Colombia's Decreto 1377
art. 24.2 does. When a transfer *is* one under this definition (to a genuine third party, not a
processor), art. 35 requires passing along the aviso and stated purposes, and the aviso must
carry a clause on whether the titular accepts the transfer; art. 36 lists consent-free
exceptions (law/treaty, medical emergency, same corporate group, contract in the titular's
interest, public interest/justice, legal proceedings, maintaining the legal relationship)
**[V]** — moot here since AWS/Apple aren't "transferencia" recipients at all under this law's
own wording.

### Security and breach duties

Art. 18: administrative, technical and physical security measures, never weaker than what the
responsable uses for its own information, scaled to risk, data sensitivity and available
technology **[V]**. Art. 19: security breaches that "afecten de forma significativa" the
titular's patrimonial or moral rights must be reported to the titular "de forma inmediata"
**[V]** — notably, the statute sets no fixed deadline (no 72-hour-style clock the way some
other regimes do); "inmediata" is undefined in the text itself. **[LAWYER]**/**[U]**: whether
the still-missing Reglamento (below) is expected to add a concrete deadline is not something I
found an answer to.

### Sanctions and criminal provisions

Fines run 100-160,000 times the UMA for lighter infractions (arts. 58-I-VII, 59-II) and
200-320,000 times the UMA for heavier ones (arts. 58-VIII-XVIII, 59-III), doubling for repeat
infractions and doubling again for sensitive-data violations (art. 59-IV) **[V]**. Separately,
arts. 62-63 criminalize profit-motivated security breaches (3 months-3 years prison) and
fraud-based misuse of data for profit (6 months-5 years), doubled for sensitive data (art. 64)
**[V]**. I did not convert UMA to pesos or USD; the unit and multiples are read directly from
the statute, the peso-equivalent ceiling is not computed here — **[U]**, low priority given the
project's current scale.

### The missing Reglamento — a real gap, not fully resolved

The decree gave the Executive 90 days from 2025-03-21 to update the Reglamento. As of the most
recent secondary source checked (dated July 2026), no updated Reglamento had been published
**[R, not independently verified against a primary gazette search for a later publication date
— worth re-checking closer to launch]**. In the gap, the old 2011 Reglamento and its Lineamientos
del Aviso de Privacidad apply supplementarily wherever they don't conflict with the new law
**[R]**. What that old Reglamento is reported to still control: the exact technical detail of
aviso simplificado/corto formatting, encargado operational requirements, and security-measure
technical standards **[R]** — none of this was independently checked against the 2011
Reglamento's own text this session. **[LAWYER]** should map which specific old-Reglamento
provisions still bind before finalizing the exact aviso wording.

---

## 2. Who may issue or relay an earthquake alert in Mexico

**SASMEX** (Sistema de Alerta Sísmica Mexicano) has run since 1991, pioneering public seismic
alert broadcast; it is technically operated by **CIRES**, a non-profit civil association, not a
government agency directly **[R, consistent with `culture-and-apple.md`'s prior finding]** —
the same "official-but-not-state-run" pattern already noted there. The **Ley General de
Protección Civil (LGPC)** art. 23 gives **CENAPRED** the technical/scientific coordination role
for monitoring and alerting hazardous phenomena, seismic included **[R]**. A reform to LGPC
art. 17 Bis, proposing that alert systems ensure both audible and visual signals accessible to
people regardless of disability, was reported as under discussion, not yet law **[R]**.

The official government-endorsed relay app, **SASSLA**, explicitly brands itself as "the only
official" seismic alert system in Mexico **[R, from `culture-and-apple.md`]** — a direct
precedent for what "looking official" means in this market, and a warning not to echo that
specific "the only official" phrasing.

**Private apps today: no enforceable technical standard, but active regulatory attention.** A
2025 Mexico City Congress committee (Comisión de Gestión Integral de Riesgos y Protección
Civil) approved setting up a technical working group to study reforms to the seismic-alerting
legal framework specifically because of private apps, noting plainly that "hay un número
importante de aplicaciones disponibles que incumplen con la norma, pero la autoridad no tiene
los medios para limitarlas y obligarlas a cumplir o en su caso multarlas" **[R]**. Read this as:
no current legal bar to a compliant private relay app, but a live, moving policy question, not
a settled one — re-check before each release into this market, not just once at launch.

Separately, in late 2026 Mexico was reported to be expanding its cell-broadcast alert system
(via the telecom regulator) to cover hazards beyond earthquakes, with a distinct "Alerta
Máxima" tone for non-seismic hazards **[R]** — this is the cell-broadcast channel (like
Colombia's or the Philippines' equivalents), a separate, carrier-level system from anything a
phone app does, and not something this app needs to interoperate with, only be aware doesn't
conflict with.

### Usurpación de funciones públicas

Código Penal Federal art. 250, fracción I: 1-6 years prison and a 100-300-day fine for anyone
who, "sin ser funcionario público, se atribuya ese carácter y ejerza alguna de las funciones de
tal" **[R, verbatim text via a legal-database mirror, not the raw DOF/diputados PDF this
session — the primary PDF fetch failed and wasn't retried with the scratchpad
fetch-and-repair technique used successfully for Colombia's laws, for lack of time; redo before
relying on the exact wording for a legal filing]**. Fracción IV separately penalizes using
"credenciales de servidor público, condecoraciones, uniformes, grados jerárquicos, divisas,
insignias o siglas" without right, with up to +50% penalty when these belong exclusively to the
armed forces or a police corporation **[R]**. This is Mexico's direct equivalent of Colombia's
Código Penal art. 425-426. Same mitigation: no government names, seals, uniforms, ranks, or
acronyms ("siglas") implying an official body; a plain, visible "no es un servicio oficial"
statement, same as Colombia's draft.

---

## 3. Consumer law for the disclaimer and any paid-tier claims

**Ley Federal de Protección al Consumidor (LFPC)**, enforced by **PROFECO**: advertising must
be truthful, verifiable and clear; PROFECO can fine or force correction of deceptive or unclear
claims **[R, carried over from `positioning-and-pricing.md`'s research, not re-verified against
LFPC's primary text this session]**. This governs two things directly: (a) the liability
disclaimer's wording must not overreach into an unenforceable blanket waiver, mirroring the
Ley 1480 concern already flagged for Colombia, and (b) any future paid-tier marketing claim
must be literally true and checkable, same standard already set project-wide in
`positioning-and-pricing.md`. I did not read LFPC's own text this session — the fetch from
`diputados.gob.mx` failed and there wasn't time to retry with the curl-and-repair fallback that
worked for Colombia's laws. **[LAWYER]** should confirm the exact article numbers for abusive
consumer contract clauses (Colombia's equivalent is Ley 1480; Mexico's LFPC almost certainly has
one, likely in its "contratos de adhesión" provisions, but I'm not citing an article number I
haven't read).

---

## 4. Delta drafts (Spanish) — what changes from the Colombia text

Full redrafts are not reproduced here; `legal-colombia.md` §4.1-4.3 stay the base text. Only
the concrete sentence-level changes needed for Mexico:

- Replace every reference to "Ley 1581 de 2012" / "Decreto 1377 de 2013" with **"Ley Federal de
  Protección de Datos Personales en Posesión de los Particulares"**.
- Replace "SIC" (Superintendencia de Industria y Comercio) with **"Secretaría Anticorrupción y
  Buen Gobierno (SABG)"** everywhere it appears as the enforcement authority.
- The onboarding screen's Colombia label "Aviso de privacidad" stays the same word in Mexico,
  but its required content list changes slightly — add the "opciones y medios para limitar el
  uso o divulgación" bullet (LFPDPPP art. 15-IV), which Colombia's version does not carry as
  its own separate point.
- Rename the Settings/About full-policy screen from "Política de Tratamiento de Datos
  Personales" (Colombia's document name) to **"Aviso de Privacidad Integral"** — Mexico's law
  does not use "política de tratamiento" as a defined term; using Colombia's name here would be
  citing the wrong law's vocabulary.
- Add one sentence to the Mexico aviso, with no Colombia equivalent needed (since Colombia's
  transmisión reasoning already required no separate transfer clause for the user): explicitly
  none needed here either, for the same reason, now on stronger footing per Recommendation 3 —
  no change required, noted only so nobody re-adds a transfer-consent clause "to be safe" where
  the statute's own definition already excludes it.
- Keep "Retirar consentimiento" in the Cobertura sheet exactly as built for Colombia — nothing
  Mexico-specific changes this mechanism; it satisfies LFPDPPP's cancelación right (art. 24)
  the same way it satisfies Colombia's.
- Liability disclaimer's three lines: translate as-is, no content change (Recommendation 7).

## App Store privacy label

No delta from `legal-colombia.md` §4.4. Apple's label categories and mechanics are
storefront-independent; only the underlying legal justification text in this doc differs, not
the label itself.

---

## Unverified list, in one place

- LFPC's primary text: not read this session (fetch failed, not retried in time). Article
  numbers for abusive-clause and misleading-advertising rules are not cited because they
  weren't confirmed.
- Código Penal Federal art. 250's exact wording: read via a secondary legal-database mirror,
  not the raw DOF/diputados PDF. Likely accurate (it's a direct quote, cross-checked against a
  second aggregator that agreed), but not independently verified against the primary gazette
  text the way Colombia's laws were.
- Whether a newer Reglamento to the LFPDPPP has been published since the July 2026 secondary
  source I found — worth a fresh check close to launch, since the 90-day deadline has already
  long passed and a publication could land at any time.
- Which specific provisions of the 2011 Reglamento and its Lineamientos del Aviso de Privacidad
  still bind supplementarily — reported in general terms only, not mapped provision by
  provision.
- Whether any Ciudad de México or state-level rule already restricts private seismic-alert
  apps beyond what the federal LGPC/Código Penal Federal cover — only the 2025 CDMX committee
  study (not a law) was found.
- LFPC's abusive-clause article number, and PROFECO's current enforcement posture on
  liability-limitation language in consumer apps specifically.
- Exact UMA-to-currency conversion for the sanction ranges — not computed, low priority at
  current scale.

## Sources

- LFPDPPP 2025, full text: [Orden Jurídico Nacional, official DOF mirror](https://www.ordenjuridico.gob.mx/Documentos/Federal/html/wo125102.html) **[V, read in full this session]**
- LFPDPPP dissolution-of-INAI/SABG transition: same source, transitorios segundo/quinto/décimo **[V]**
- Reglamento status (as of July 2026, not republished): [Sharkit, "Nueva LFPDPPP Reglamento Pendiente"](https://sharkit.mx/nueva-lfpdppp-reglamento-pendiente/) **[R]**
- Código Penal Federal art. 250: [Conceptos Jurídicos](https://www.conceptosjuridicos.com/mx/articulos/codigo-penal-articulo-250/); cross-checked against [leyes-mx.com](https://leyes-mx.com/codigo_penal_federal/250.htm) **[R]**
- SASMEX/CIRES/SASSLA, LGPC/CENAPRED, INAI-to-SABG: `docs/research/culture-and-apple.md` (prior session's sourced findings, not re-fetched) **[R, carried over]**
- LGPC art. 23, art. 17 Bis reform, CDMX private-app regulatory study: [Meteored](https://www.meteored.mx/noticias/actualidad/el-sistema-de-alerta-temprana-en-mexico-necesita-mejoras-que-esta-fallando-y-como-deberia-funcionar.html); [Heraldo de México](https://heraldodemexico.com.mx/nacional/2025/2/26/preven-actualizar-marco-juridico-de-aplicaciones-de-alertamiento-sismico-679386.html); [Congreso CDMX comunicado](https://www.congresocdmx.gob.mx/comsoc-preven-actualizar-marco-juridico-aplicaciones-alertamiento-sismico-6093-1.html) **[R]**
- 2026 cell-broadcast expansion (non-seismic hazards): [La Crónica de Hoy](https://www.cronica.com.mx/nacional/2026/09/07/mexico-ampliara-alertas-de-celulares-en-2026-para-advertir-de-huracanes-incendios-y-otros/) **[R]**
- LFPC/PROFECO general standard: `docs/research/positioning-and-pricing.md` (prior session's finding, not re-verified against primary text) **[R, carried over]**
- Cross-referenced this project's own: `docs/research/legal-colombia.md` (structure and data
  inventory reused), `docs/research/culture-and-apple.md`, `docs/ios-contract.md`

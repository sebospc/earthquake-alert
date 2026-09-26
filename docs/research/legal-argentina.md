# Legal: Argentina (Ley 25.326, alerting rules, liability, drafts)

2026-09-26. Not legal advice. I am not a lawyer and this is not a law firm's opinion: it is a
map of the rules and a delta against `legal-colombia.md`'s drafts, to hand to an Argentine
lawyer before launch. Every place that needs a lawyer's sign-off is marked **[LAWYER]**.

Tags: **[V]** read in the primary source (the law, decree, resolution, or AAIP's own page).
**[R]** reported by a secondary source (news, law-firm blog), not cross-checked against the
primary text. **[U]** unverified, or a judgment call with no clean answer.

This doc does not re-derive what the app collects — see `legal-colombia.md` §1's table
(`device_token`, `sensor_ids`, `demand_cell`, `min_magnitude`, the opt-in telemetry purpose).
Nothing about that inventory changes for Argentine users; only the legal treatment does.

---

## Recommendation

1. **Registering the database is probably required here, unlike Colombia, and it's free.**
   Colombia exempts small operators from RNBD registration by an asset-size test (100,000 UVT).
   Argentina's registration duty is not sized that way: Ley 25.326 art. 21 requires registering
   any "archivo... destinado a proporcionar informes" **[V]**, and Decreto 1558/2001 art. 1
   defines that phrase to reach anything that "exceden el uso exclusivamente personal" **[V]** —
   a purpose test, not a size test. AAIP's own resolution on infractions (126/2024) lists
   *processing without being registered* as the mildest ("leve") infraction category, not an
   exemption **[V]** — meaning the expectation is that everyone registers, and skipping it is a
   (minor) violation, not a free pass. Registration is online, free, and takes two steps: the
   responsable, then the database itself **[V]**. Do it. **[U]**: whether the specific legal
   entity behind this project is "established in Argentina" changes which of two registration
   forms applies — AAIP's own site has a separate path for a responsable not established in the
   country but processing Argentines' data **[V]**, which is the likely case here; nobody has
   filed either form yet.
2. **International transfer is the one place Argentina is harder than Colombia, not easier.**
   Colombia's Decreto 1377 art. 24.2 exempts an Encargado relationship (AWS, Apple/APNs) from
   the adequacy-country test entirely. Argentina's Ley 25.326 art. 12 has no equivalent
   carve-out for service providers — it just bans transferring to a country without adequate
   protection, full stop, subject to listed exceptions **[V]**. AAIP's own current list of
   adequate countries is EU/EEA states, UK, Switzerland, Guernsey, Jersey, Isle of Man, Faroe
   Islands, Canada (private sector only), Andorra, New Zealand, Uruguay, and Israel (automated
   data only) **[V, fetched directly from AAIP's own page]**. The United States and Brazil are
   not on it. The cheap fix that's already half-built into the product: **express consent**.
   AAIP's own transfer-rules page states the adequacy prohibition doesn't apply when the titular
   has expressly consented to the cession **[V]**, and Decreto 1558 art. 12 says the same
   **[V]**. Since the app already asks for one explicit "Acepto" tap before the first
   registration, add one sentence naming Brazil and the US as processing locations and folding
   that into the same consent, rather than reaching for AAIP's heavier Cláusulas Contractuales
   Modelo (a real, free, but more paperwork-heavy path — a contract on file, points of
   difference explained to AAIP, 30-day notice window) **[V]**. **[LAWYER]**: confirm plain
   express consent is enough here and a model-clauses contract isn't separately required.
3. **The mandatory visible legend is a small, concrete addition Colombia's draft doesn't have.**
   Resolución AAIP 14/2018 requires displaying, before data collection, the art. 6 information
   (purpose, destinataries, responsable's identity, optional/mandatory nature, consequences,
   rights) plus one fixed sentence naming AAIP as the complaint authority **[V, read the
   resolution's own text]**: *"LA AGENCIA DE ACCESO A LA INFORMACIÓN PÚBLICA, en su carácter de
   Órgano de Control de la Ley N° 25.326, tiene la atribución de atender las denuncias y
   reclamos que interpongan quienes resulten afectados en sus derechos..."* That sentence has to
   appear verbatim somewhere visible (the onboarding screen or the full policy). A second legend
   about the six-month free-access right is mentioned by a secondary source **[R]** but was not
   found in the resolution text I actually read — treat that second sentence as unconfirmed,
   not as a second requirement to copy in.
4. **Refining, not confirming, the "must not look official" finding from `culture-and-apple.md`.**
   That doc flagged Código Penal art. 246 as a "direct equivalent" to Colombia's art. 425-426.
   Having now read art. 246 and 247 directly **[V]**, the fit is narrower than that. Art. 246
   punishes *assuming or exercising* a public function without title — actually acting with
   public authority (issuing orders, holding a post), not merely resembling an official source
   of information. A relay app that never claims to act with authority likely doesn't reach it.
   The closer fit is art. 247's second paragraph: a fine (750 to 12,500 pesos — a 1993-era
   amount, functionally symbolic today) for publicly wearing insignia of a position one doesn't
   hold, or arrogating titles/honors **[V]**. That reaches impersonating a specific badge or
   title, not "having an app that feels official." Net effect: Argentina's statutory risk for
   *looking* official without *claiming* to be a public officer is real but weaker and less
   squarely on point than Colombia's art. 425-426 — still worth the same mitigation (no SEGEMAR/
   INPRES/SINAGIR names or seals, plain "not an official service" disclaimer), just don't treat
   the two countries' legal risk as equivalent in strength. **[LAWYER]** should confirm there's
   no better-fitting article elsewhere in the Código Penal or a provincial statute.
5. **The seismic-authority landscape just got smaller and less visible, which lowers confusion
   risk somewhat.** INPRES (Instituto Nacional de Prevención Sísmica), the technical seismic
   body since 1972, was merged into SEGEMAR (the mining/geology service) by Decreto 396/2025 in
   June 2025, as part of a broader state-simplification round **[V and R — the merger itself is
   confirmed on argentina.gob.ar's own announcement; commentary on its reception is press-only]**.
   There is no dedicated national public earthquake-alert app to be mistaken for (confirmed
   again this session; matches the negative finding already in `languages.md`/`culture-and-
   apple.md`). SINAME, a 2019 multi-hazard monitoring platform institutionalized by Resolución
   MinSeguridad 225/2023, feeds the Agencia Federal de Emergencias and is an inter-agency tool,
   not a consumer-facing brand **[V/R]**. None of this changes the mitigation (still disclaim
   plainly), it just means the confusion risk in Argentina is lower than in Colombia or Turkey,
   where a specific, recognizable official app already exists.
6. **Ley 24.240 (consumer law) gives a more explicit textual hook than Colombia's Ley 1480 for
   both halves of the disclaimer question.** Art. 37(a) voids, as "no convenidas", any clause
   that "desnaturalice las obligaciones o limite la responsabilidad por daños" **[V]** — a
   textual answer to "is a blanket waiver void", not just doctrine. Art. 40 makes the whole
   chain (producer, distributor, provider...) jointly liable for harm from a service's defect or
   risk, with the *only* listed escape being proof the cause was external to them ("causa ajena")
   **[V]**. That means the disclaimer should say plainly that failures come from systems outside
   the app's control (Google's detection, Apple's delivery, the user's own network) — not just
   as honest description, but because that phrase is the actual legal escape hatch under art. 40.
   Ley 24.240 also applies regardless of whether the app is free: art. 1 covers services used
   "en forma gratuita u onerosa" **[V]** — no monetization exemption.
7. **Fines under Ley 25.326 are old and low; Ley 24.240's aren't.** Data-protection fines
   (Resolución 126/2024, replacing older scales) run 1,000 to 100,000 pesos across leve/grave/
   muy grave tiers **[V]** — an amount a 2026 commentator called low enough to blunt deterrence
   **[R]**. Consumer-law fines under art. 47(b) are pegged to a basket-of-goods index (0.5 to
   2,100 "canastas básicas total para el hogar") **[V]**, which moves with inflation and is the
   sharper real exposure of the two.
8. **A full statutory replacement for Ley 25.326 is proposed, not enacted.** AAIP ran its own
   participatory process in 2022, produced a draft (Mensaje 87/2023), and it lost parliamentary
   status **[V, from AAIP's own project page]**. In 2026, at least three new bills (deputy
   Martín Yeza's 1751-D-2026, plus ones from deputy Pablo Carro and senator Martín Doñate) aim
   to replace the law entirely, GDPR-style: accountability, privacy by design, breach
   notification, portability, minors' data, AI rules **[R]**. None are law. Treat this the same
   way as Colombia's SNAST bill — not a blocker today, worth a periodic re-check, not a one-time
   check.
9. **Before it ships:** confirm with an Argentine lawyer (a) whether this project's actual legal
   entity must register via the "established in Argentina" or the "not established" RNBD path,
   (b) whether express consent to the Brazil/US transfer is sufficient or the model contractual
   clauses should be filed too, (c) the art. 246/247 "looking official" reading above, and (d)
   the current status of the 2026 reform bills before launch, since any of the three could
   change the RNBD or transfer rules materially if enacted.

---

## 1. Ley 25.326 de Protección de los Datos Personales (2000), Decreto 1558/2001, AAIP

Full primary text read this session: Ley 25.326 (48 articles, `servicios.infoleg.gob.ar`) and
Decreto 1558/2001 (its implementing regulation, article-by-article) **[V]**.

**Authority.** Originally the Dirección Nacional de Protección de Datos Personales; its powers
passed to the Agencia de Acceso a la Información Pública (AAIP) by Decreto 746/2017 and
899/2017 **[V, recited in Resolución 14/2018's own preamble]**. AAIP is a decentralized body
under the Jefatura de Gabinete de Ministros, not a court or a ministry proper.

**Consent (art. 5).** Treatment is unlawful without "consentimiento libre, expreso e informado",
in writing or an equivalent medium **[V]**. Exceptions (art. 5.2): public-access sources; a
state body's own legal functions; bare name/DNI/tax-ID/occupation/birth-date/address lists;
data necessary for a contractual, scientific or professional relationship's own performance;
and financial-entity client data under Ley 21.526 **[V]**. None of these cleanly cover an
earthquake-alert relationship the way, say, "necessary for contract performance" might be
stretched to — safer to keep doing what the app already plans (an explicit onboarding
"Acepto") than to lean on an exception. **[U]**: whether the contract-performance exception
(art. 5.2.d) would also independently cover this is a judgment call not worth relying on when
explicit consent is this cheap to collect anyway.

**Information duty (art. 6).** Before collecting, state clearly: the purpose and who receives
the data; that the archive exists, and the responsable's identity and address; whether
answering is mandatory or optional; the consequences of refusing or of inaccurate data; and
that access/rectification/deletion rights exist **[V]**. This has to be shown in a visible
place, not just written somewhere in a policy — Resolución 14/2018 (below) makes that explicit.

**Data quality (art. 4) and security/confidentiality (arts. 9-10).** Data must be accurate,
relevant, not excessive, not repurposed beyond what justified its collection, and destroyed
once no longer needed **[V]**. The responsable must keep it secure and confidential, an
obligation that survives even after the relationship with the titular ends **[V]**.

**Sensitive data (art. 7).** No sensitive data is involved here (race, politics, religion,
union, sexual life, health) — same finding as Colombia. Argentina's definition (art. 2) matches
Colombia's in substance, though the statutes are worded independently.

**International transfer (art. 12) — the load-bearing difference from Colombia.** See
Recommendation §2 above for the full reasoning. In short: no service-provider carve-out exists
in the statute the way Colombia's Decreto 1377 art. 24.2 provides one; the adequate-country
list (Disposición DNPDP 60/2016, Resolución AAIP 34/2019) does not include the US or Brazil
**[V, read directly on AAIP's own page]**; and the practical, low-cost fix is express consent
to the specific transfer, which the prohibition itself doesn't reach (art. 12's ban "no regirá"
when the titular "hubiera consentido expresamente la cesión", Decreto 1558 art. 12 **[V]**).
AWS publishes its own Argentina-specific compliance page, which describes its security
commitments as consistent with the law's goals but does not claim to adopt AAIP's model clauses
specifically **[V, read AWS's own page]** — another reason to lean on user consent rather than
assume the vendor side already solved this.

Separately: Ley 25.326 art. 25 ("prestación de servicios informatizados de datos personales")
lets a third party process data strictly for the contracted purpose, never repurposing or
re-ceding it, and requires destruction once the contract ends (or up to two years' secure
storage if further work is reasonably expected) **[V]**. This is the closest Argentine analogue
to Colombia's Encargado/transmisión concept, and it matters for a different question than
adequacy: it's what keeps sending data to AWS/Apple from separately counting as a "cesión"
under art. 11 (which would need its own consent on top of everything else) — art. 25 processing
isn't a cesión, it's a service contract. It does not, on its own reading, exempt the cross-
border leg of that same processing from art. 12's adequacy test — that's a separate question,
answered by consent above, not by art. 25.

**RNBD registration — see Recommendation §1.** Free, two-step (responsable, then database),
done via Trámites a Distancia with an AFIP clave fiscal or an apoderado **[V]**. Skipping it is
classified as a "leve" infraction under Resolución 126/2024's Anexo I(1)(a) **[V]** — a real
but minor violation if missed, not framed by the statute as something small operators are
exempt from.

**Mandatory visible legend — see Recommendation §3.** Resolución AAIP 14/2018, art. 2-3 **[V]**.

**Data subject rights.** Access (art. 14): free, at intervals no shorter than six months, answer
due within 10 días corridos of a formal request **[V]**. Rectification/deletion (art. 16): the
responsable must act within 5 días hábiles of the claim or of learning of the error **[V]**.
Failing either deadline opens the habeas data judicial action (arts. 33-43) **[V]** — a formal
court proceeding, distinct from Colombia's SIC-complaint-first model. Practically: `DELETE
/devices` already satisfies the deletion right; a stated contact channel for an access request
(same "what do you have on my token" answer Colombia's draft already proposes) covers art. 14.

**Sanctions.** Leve: up to 2 apercibimientos and/or a 1,000-80,000 peso fine. Grave: up to 4
apercibimientos, 1-30 days' suspension, and/or 80,001-90,000 pesos. Muy grave: up to 6
apercibimientos, 31-365 days' suspension, closure/cancellation, and/or 90,001-100,000 pesos
**[V, Resolución 126/2024 Anexo II]**. Cumulative caps across multiple sanctions in one
proceeding (reported as 3M/10M/15M pesos by tier) are described by a secondary source **[R]**
and were not independently located in the resolution text as fetched this session.

---

## 2. Who may issue or relay an earthquake alert

See Recommendation §4-5 for the two findings that refine, rather than restate,
`culture-and-apple.md`'s earlier read. Summary of the institutional landscape, read from
primary sources this session:

- **Ley 27.287 (2016)**, full text read **[V]**: creates the Sistema Nacional para la Gestión
  Integral del Riesgo y la Protección Civil (SINAGIR), a coordinating structure (a national
  council, a federal council, an executive secretariat, national and emergency funds) spanning
  dozens of listed agencies — the Anexo lists the Instituto Nacional de Prevención Sísmica among
  them, under the then-Ministerio del Interior, Obras Públicas y Vivienda **[V]**. The law
  defines "alerta" as a declared state, prior to a threat materializing, that triggers
  pre-established action procedures, and "sistema de alerta temprana" as a mechanism for timely
  information provision by identified responsible institutions **[V]** — descriptive
  definitions, not an exclusivity clause; nothing in the 27 articles read reserves the word or
  the act to the state. Same structural conclusion as Colombia's Ley 1523: it organizes who
  coordinates official disaster response, it doesn't appear to criminalize a private party
  sharing hazard information.
- **INPRES**, created by Ley 19,616 (1972) to run the national seismic monitoring network and
  set earthquake-resistant construction standards, was merged into SEGEMAR (the geological/
  mining survey) by Decreto 396/2025, June 2025, now sitting under the Secretaría de Minería,
  Ministerio de Economía **[V, primary confirmation via argentina.gob.ar's own notice]** — no
  longer under a security or civil-protection portfolio at all.
- **SINAME**, the Sistema Nacional de Alerta y Monitoreo de Emergencias, created 2019 and
  institutionalized by Resolución del Ministerio de Seguridad 225/2023, is a multi-hazard
  monitoring platform inside the Agencia Federal de Emergencias, feeding national/provincial/
  municipal risk-management bodies through a web portal **[V/R]** — an inter-agency data tool,
  not a public-facing alert brand.
- **No dedicated national public earthquake-alert app** was found for Argentina, consistent with
  the negative finding already recorded in `languages.md` §1 and `culture-and-apple.md`.
- **Código Penal arts. 246-247** (Ley 11.179, texto ordenado 1984, read directly this session,
  upgrading the citation from `culture-and-apple.md`'s secondary-sourced [R] to [V] here) — see
  Recommendation §4 for the refined reading. Art. 246: 1 month-1 year prison plus double-length
  disqualification for assuming/exercising a public function without title, continuing after a
  legal cessation, or a public official exercising another office's functions; a separate
  paragraph (added 2008) punishes unauthorized military command. Art. 247: 15 days-1 year prison
  for practicing a regulated profession without the required title (first paragraph, not
  relevant here); 750-12,500 pesos fine for publicly wearing insignia of an unheld post or
  arrogating unearned academic/professional titles or honors (second paragraph) **[V]**.

---

## 3. Consumer law and the liability disclaimer

Ley 24.240 (Ley de Defensa del Consumidor), full text read this session for the articles that
matter here **[V]**.

**Scope.** Covers anyone acquiring or using goods/services "en forma gratuita u onerosa... como
destinatario final" (art. 1) **[V]** — a free app is squarely inside this law, no exemption for
not charging money.

**Information duty (art. 4).** Must be given "cierta, clara y detallada", free, and in a
physical medium unless the consumer opts into an alternative **[V]** — a mobile app's own
screens count as that alternative medium once the user is using the app, satisfying this
without needing a paper document.

**Advertising binds the contract (art. 8).** Claims made in advertising or "otros medios de
difusión" are read into the contract and bind the offering party **[V]** — stronger than a
"misleading ads are penalized" rule: a marketing claim about speed or reliability becomes an
enforceable term, not just an advertising-standards violation. Same practical conclusion as
Colombia's Ley 1480 point (don't call it "early warning" without the caveats already in the
product), reached by a more direct mechanism here.

**Abusive clauses (art. 37).** Clauses that "desnaturalicen las obligaciones o limiten la
responsabilidad por daños" are void — "tenidas por no convenidas" — regardless of the contract's
overall validity **[V]**. Doubt about the extent of an obligation is resolved in the sense
least burdensome to the consumer (final paragraph) **[V]**. This is the textual version of what
`legal-colombia.md` reasons toward by doctrine under Ley 1480 — here it's the statute's own
words.

**Strict, joint liability with a narrow escape (art. 40).** Everyone in the chain — producer,
importer, distributor, provider, seller, anyone whose mark is on the good or service — answers
jointly for harm from the good's or service's defect or risk. The only listed way out: proving
the cause was external to them, "causa... ajena" **[V]**. This is the concrete legal reason the
disclaimer should name external causes (Google's detection system, Apple's delivery
infrastructure, the user's own network or device) explicitly, not just as honest writing but
because that phrasing is the statute's actual escape hatch.

**Trato digno (art. 8 bis).** Consumers can't be put in "situaciones vergonzantes, vejatorias o
intimidatorias" **[V]** — a tone note for error states and rejection messages (e.g., a
"cobertura no disponible" message), not a disclaimer issue as such.

**Sanctions (art. 47, 52 bis).** Fines run 0.5 to 2,100 "canastas básicas total para el hogar"
(a basket-of-goods index published by INDEC, so it moves with inflation) **[V]**, alongside
warnings, seizure, closure up to 30 days, and up to 5 years' exclusion from state-supplier
registries. A judge may separately impose punitive damages (art. 52 bis), capped at the
maximum art. 47(b) fine **[V]**.

**Disclaimer wording, delta from Colombia's draft:** keep the same three plain claims (not
official; can fail/be late/be wrong; doesn't replace civil-protection protocols), but state the
external-cause point explicitly — e.g. "Esto puede deberse a fallas de red, del sistema
operativo, de nuestros proveedores, o del sistema de Google del cual depende la información
original" (this sentence is already in Colombia's §4.3 draft almost verbatim — keep it,
because under art. 40 it is doing real legal work here, not just honest disclosure).
**[LAWYER]** should confirm the wording sits on the "honest description" side of art. 37, same
caution as flagged for Colombia's §4.3.

---

## 4. Drafts: delta from `legal-colombia.md` §4

Same structure and tone as Colombia's drafts (usted throughout — see `culture-and-apple.md`'s
finding that Argentine formal register defaults to usted/tú despite everyday voseo; the voseo
question itself stays a native-reviewer item, not decided here, per `languages.md`). What
actually changes, line by line:

- **Authority name.** Replace every mention of "Superintendencia de Industria y Comercio" with
  "Agencia de Acceso a la Información Pública (AAIP)".
- **Mandatory legend (new, not in Colombia's draft).** Add, verbatim, somewhere visible before
  data collection: *"La Agencia de Acceso a la Información Pública, en su carácter de Órgano de
  Control de la Ley N° 25.326, tiene la atribución de atender las denuncias y reclamos que
  interpongan quienes resulten afectados en sus derechos por incumplimiento de las normas
  vigentes en materia de protección de datos personales."*
- **International transfer sentence (strengthened, not just disclosed).** Colombia's draft
  names Brazil and the US "as a transparency matter" since consent isn't strictly required
  there. For Argentina, the sentence has to do real legal work: *"Usted autoriza expresamente
  que esta información se procese en servidores ubicados en Brasil y en Estados Unidos."* —
  paired with the "Acepto" tap, so the consent is unambiguous and specific to the transfer, not
  just to the treatment in general.
- **Rights section.** Change the access-request timing language to match arts. 14 and 16 (10
  días corridos for a response to an access request; 5 días hábiles for rectification/deletion)
  rather than Colombia's framing, and add that a habeas data judicial action is available if the
  responsable doesn't answer in time — not just an SIC/AAIP complaint.
- **RNBD registration number**, once obtained, belongs in the same spot Colombia's draft
  reserves for the responsable's contact details.
- **Términos de uso.** Add one clause naming external causes explicitly for the art. 40 reason
  given in §3 above; otherwise unchanged from Colombia's §4.3 structure.

### App Store privacy label

No delta. The data actually collected and its Linked/Tracking/Purpose classification (device
token as Identifiers, `sensor_ids`/`demand_cell` as Coarse Location, opt-in arrival timestamps
as Performance Data — `legal-colombia.md` §4.4) doesn't change by the user's country. What
changes for Argentina is the consent and registration story behind the same facts, not the
facts declared to Apple.

---

## Unverified list, in one place

- Whether this project's actual legal entity would register via AAIP's "established in
  Argentina" path or its "not established, but processing Argentines' data" path — not
  something researchable in the abstract; depends on facts about the operator. **[U]**
- Whether express consent to the Brazil/US transfer is legally sufficient on its own, or
  whether AAIP's model contractual clauses (Disposición 60/2016, Resolución 198/2023) should
  also be filed for a project this size. **[LAWYER]**
- The second "access right" legend reportedly required by Resolución 14/2018 — not found in the
  resolution's own text as fetched this session; only the AAIP-denuncias legend (art. 3) was
  confirmed directly. **[R]/[U]**
- The cumulative sanction caps (3M/10M/15M pesos across tiers) reported for Resolución
  126/2024 — not independently located in the fetched text. **[R]**
- Whether any provincial statute (as opposed to the national Código Penal) creates a stronger
  "looking official" restriction than arts. 246-247 — not researched. **[U]**
- The exact current status of the 2026 reform bills (Yeza, Carro, Doñate) — committee stage,
  timeline, and whether any is likely to pass before this app's launch window. **[R]**, news-
  level only.
- Whether AWS's or Apple's standard agreements can be read as satisfying Ley 25.326 art. 25's
  service-provider contract requirements for this specific project — AWS's own Argentina page
  describes general alignment with the law's goals, not a project-specific confirmation.
  **[LAWYER]**

---

## Sources

- [Ley 25.326, texto original](https://servicios.infoleg.gob.ar/infolegInternet/anexos/60000-64999/64790/norma.htm) and [texto actualizado](https://servicios.infoleg.gob.ar/infolegInternet/anexos/60000-64999/64790/texact.htm) — **[V]**, read in full this session.
- [Decreto 1558/2001, reglamentación](https://servicios.infoleg.gob.ar/infolegInternet/anexos/70000-74999/70368/norma.htm) — **[V]**, read in full this session.
- [AAIP, Obligaciones de los responsables de bases de datos personales](https://www.argentina.gob.ar/aaip/datospersonales/responsables/obligaciones) — **[V]**.
- [AAIP, Registrar bases de datos personales privadas](https://www.argentina.gob.ar/registrar-bases-de-datos-personales-privadas) — **[V]**.
- [AAIP, Trámites ante el Registro Nacional de Bases de Datos Personales](https://www.argentina.gob.ar/aaip/datospersonales/tramites) — **[V]**, includes the "responsable not established in Argentina" branch.
- [AAIP, Transferencias internacionales](https://www.argentina.gob.ar/transferencias-internacionales) — **[V]**, includes the adequate-country list and the express-consent exception.
- [Resolución AAIP 14/2018, texto original](https://www.argentina.gob.ar/normativa/nacional/norma-307621/texto) — **[V]**, read in full.
- [Resolución AAIP 126/2024, texto actualizado](https://www.argentina.gob.ar/normativa/nacional/resoluci%C3%B3n-126-2024-399750/actualizacion) — **[V]**, Anexo I (classification) and Anexo II (sanction scale) read directly.
- [AAIP, Proyecto de Ley de Protección de Datos Personales](https://www.argentina.gob.ar/aaip/datospersonales/proyecto-ley-datos-personales) — **[V]**, on the 2022-2023 reform attempt and its loss of parliamentary status.
- [AWS, Argentina Data Privacy](https://aws.amazon.com/compliance/argentina-data-privacy/) — **[V]**, read directly; AWS's own description of its DPA and regional options.
- 2026 reform bills coverage: [Diario Judicial](https://www.diariojudicial.com/news-103126-proteccion-de-datos-personales-sigue-siendo-suficiente-la-ley-25326-en-2026), [LexLatin](https://lexlatin.com/noticias/ley-25326-argentina-reemplazar-proteccion-datos-personales), [IAPP](https://iapp.org/news/a/se-impulsa-un-nuevo-proyecto-de-reforma-del-r-gimen-de-protecci-n-de-datos-en-argentina) — **[R]**, news/analysis only.
- Convenio 108+ accession: [Abogados.com.ar, Ley 27.699](https://abogados.com.ar/promulgacion-de-la-ley-27699-de-adhesion-al-convenio-108-en-materia-de-proteccion-de-datos-personales/) — **[R]**.
- [Ley 27.287, texto original (SINAGIR)](https://servicios.infoleg.gob.ar/infolegInternet/anexos/265000-269999/266631/norma.htm) — **[V]**, read in full including the Anexo listing INPRES.
- [Decreto 383/2017, texto actualizado (reglamentación SINAGIR)](https://www.argentina.gob.ar/normativa/nacional/norma-275352/actualizacion) — **[V]**, read.
- [Argentina.gob.ar, ¿Qué es el SINAME?](https://www.argentina.gob.ar/sinagir/siname) — **[V]**.
- INPRES/SEGEMAR merger: [Argentina.gob.ar, official notice](https://www.argentina.gob.ar/noticias/el-gobierno-nacional-fusiono-el-instituto-de-prevencion-sismica-y-el-servicio-geologico) — **[V]**; press commentary via [Infobae](https://www.infobae.com/sociedad/2025/06/18/motosierra-en-el-estado-el-gobierno-fusiono-dos-organismos-vinculados-a-la-geologia-y-la-ciencia/) — **[R]**.
- [Código Penal de la Nación Argentina, Ley 11.179, texto ordenado](https://servicios.infoleg.gob.ar/infolegInternet/anexos/15000-19999/16546/texact.htm) — **[V]**, arts. 245-248 read directly.
- [Ley 24.240, texto actualizado (Defensa del Consumidor)](https://servicios.infoleg.gob.ar/infolegInternet/anexos/0-4999/638/texact.htm) — **[V]**, arts. 1-2, 4, 8, 8 bis, 10 ter, 34-38, 40, 47, 52 bis read directly.
- Cross-referenced this project's own: `docs/research/legal-colombia.md`, `docs/research/culture-and-apple.md` (the art. 246 finding this doc refines), `docs/research/languages.md`, `docs/research/positioning-and-pricing.md` (Argentina's 30% card perception tax and peso pricing already covered there, not repeated here).

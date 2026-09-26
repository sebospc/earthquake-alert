# Languages for a worldwide app

2026-09-25. Not legal advice for §3; treat it the same way as `docs/research/legal-colombia.md` —
a map to hand to a local lawyer per country, not a lawyer's opinion.

Tags: **[V]** read in the primary source, or computed directly from a primary data feed this
session. **[R]** reported by a secondary source (news, a law firm's summary), not independently
re-derived. **[U]** unverified, or a judgment call with no clean answer.

---

## The table the coordinator asked for

Felt-quake count is M4.5+ events in the last 12 months, computed directly from the USGS FDSN
event API this session (`starttime=2025-09-25&endtime=2026-09-25&minmagnitude=4.5`, 7,683 events
globally), attributed to the country named in each event's own `place` field **[V]**. That is a
proxy for "where people live", not a rigorous PAGER exposure figure — a `place` string like
"20km SW of Banda Aceh, Indonesia" names the nearest population center, but a remote-region
bucket ("South Sandwich Islands region", "southern Mid-Atlantic Ridge") means uninhabited, and
those are dropped from this table. Population is the country's total population, rounded, not
population actually exposed to shaking — a real simplification, marked **[U]** throughout,
because building an actual PAGER-style exposure model was out of scope for this pass.

| Country | Felt M4.5+/yr [V] | Population (rounded) [R] | AEA active? | Main language |
|---|---:|---:|---|---|
| Indonesia | 1,039 | 280M | **[U] — contested, see §1** | Indonesian |
| Philippines | 781 | 116M | Yes [R] | Filipino / English |
| Japan | ~653 | 124M | **No** [R] — has its own JMA warning, Google doesn't run AEA there | Japanese |
| Papua New Guinea | 301 | 10M | Yes [R] | Tok Pisin / English |
| Chile | 164 | 19.5M | Yes [R] | Spanish |
| China (mainland) | 160 | 1.41B | **No** [R] — no Google Play Services on mainland Android | Chinese |
| Mexico | 146 | 128M | Yes [R] | Spanish |
| Peru | 99 | 34M | Yes [R] | Spanish |
| Argentina | 89 | 46M | Yes [R] | Spanish |
| Colombia | 47 | 52M | Yes [V] — this project's own proof | Spanish |
| India | 44 | 1.44B | Yes [R] | Hindi / English |
| Iran | 43 | 89M | Yes [R] — **but moot, see §1** | Persian |
| Afghanistan | 40 | 42M | Yes [R] | Dari / Pashto |
| Turkey | 36 | 86M | Yes [V] | Turkish |
| Taiwan | 34 | 23M | **[U]** — has its own CWA system, unconfirmed either way | Chinese (Traditional) |
| Pakistan | 28 | 245M | Yes [R] | Urdu / English |
| Nepal | not in top 45 (infrequent, high-consequence) | 30M | Yes [R] | Nepali |
| Greece | 58 | 10.4M | Yes [R] | Greek |

Rows for Vanuatu, Tonga, Solomon Islands, Timor-Leste, Fiji and Venezuela are left out of this
table on purpose: high event counts (Vanuatu 218, Tonga 271+43, Solomon Islands 118) but
population under a million to a few million, or (Venezuela) not in the top-45 raw count despite
being the project's own worked example of AEA in Latin America.

---

## Recommendation

1. **First wave: Spanish, English, Turkish.** Spanish alone covers five AEA-confirmed countries
   in the table above (Chile, Mexico, Peru, Argentina, Colombia) for a combined 545 felt M4.5+
   events/year — more than any single other country except the Philippines and Indonesia.
   English covers the Philippines directly (its own disaster agencies publish their safety
   guidance in English, §2) plus serves as the fallback everywhere else. Turkey is a single
   country but the deadliest one in this list by outcome, not by yearly count: the number here
   (36/yr) undercounts Turkey's real risk, since a 12-month M4.5+ count misses the
   infrequent-but-catastrophic pattern that produced the 2023 Kahramanmaraş earthquakes. **This
   confirms two of the user's three guesses (Spanish, English) and replaces the third
   (Portuguese) with Turkish** — see point 2.
2. **Portuguese does not hold up as a first-wave pick.** Brazil does not appear anywhere in the
   top 45 countries by felt M4.5+ events — it is a stable continental shield, not a seismic
   country. The only AEA-confirmed Portuguese-speaking market is Portugal, added in July 2026
   [R], population ~10M, moderate risk, well below Turkey or Chile on this table. Demote
   Portuguese to second wave, kept mainly for Portugal and for reach if the user later wants
   Brazil covered for reasons other than earthquake risk.
3. **Second wave (3-5 more): Hindi, Indonesian (conditional), Greek, Nepali.** Hindi for India —
   a modest yearly count (44) but 1.44B people means even a small fraction of the country in a
   seismic zone (the Himalayan front, Gujarat, the northeast) is a large absolute number, and
   AEA is confirmed active there. Indonesian is the single highest-value language if AEA turns
   out to cover Indonesia — it has by far the highest felt-quake count of any country in the
   table (1,039/yr) — but §1 below could not confirm this either way with confidence: build it
   second, not first, and re-check before shipping it. Greek and Nepali are smaller markets but
   both AEA-confirmed and both have a clean official safety phrase already sourced (§2).
4. **Exclude, for structural reasons, not ranking:**
   - **Japanese** — Google does not run AEA in Japan; it already has the JMA's own national
     Earthquake Early Warning system, and Google's own strategy is to cover countries without
     one **[R]**. Building this app's alert path in Japanese would ship a feature that never
     fires there.
   - **Chinese (mainland)** — mainland Android ships without Google Play Services by policy, and
     AEA depends on it; the app cannot function there for reasons that have nothing to do with
     language **[R]**.
   - **Persian (Iran)** — AEA appears to be active there **[R]**, but it is moot: Apple does not
     operate the App Store in Iran at all, under US sanctions law, and has actively removed
     Iranian developers' apps in the past **[R]**. There is no distribution channel for an iOS
     app in Iran regardless of language work.
   - **Chinese Traditional (Taiwan)** — unconfirmed AEA status either way **[U]**; Taiwan's CWA
     runs its own system, similar to Japan's case, but no source found states Taiwan is
     excluded the way Japan explicitly is. Low priority either way until this resolves.
5. **iPhone share is a real factor the felt-quake table doesn't show**, and it cuts against two
   entries that otherwise look strong by count: Papua New Guinea (301/yr) and Afghanistan
   (40/yr) both have very low iPhone penetration **[U]**, general knowledge, not measured this
   session — building a good Tok Pisin or Dari/Pashto experience would reach very few iOS users
   even where AEA fires constantly. This is why they don't make either wave despite the raw
   count.
6. **Legal note (§3): scoped to the first wave only**, the same way `legal-colombia.md` was
   scoped to Colombia. Mexico, Chile, Peru, Argentina and Turkey each have their own data
   protection statute and regulator, distinct from Colombia's SIC — none of them can be assumed
   to work the same way Colombia's does. The two most load-bearing, non-obvious facts: Mexico's
   INAI (the regulator this project might have assumed still exists) was dissolved in December
   2024 and folded into a different body **[R]**; and Chile's entire data protection law changes
   on **December 1, 2026** — a new law (21.719), a new dedicated regulator that doesn't exist yet
   today, replacing the old one **[R]**. Full detail in §3.

---

## 1. Which languages, in which order — the full reasoning

### Method

1. Pull every M4.5+ earthquake globally in the last 365 days from USGS's own event API — no
   modeling, the raw catalog **[V]**.
2. Attribute each event to a country from its `place` string; drop entries that name an
   uninhabited region (ocean ridges, "south of X" for remote island groups) **[V]**.
3. Cross against AEA active/inactive per country, from Google's own blog and news coverage of
   specific alerts **[R]** — there is no single authoritative Google page enumerating all ~98-139
   countries by name that this session could locate; the figure itself is inconsistently reported
   (98 as of end-2023, a "139 countries" figure surfaced once from an unreliable fetch and is not
   trusted here, see the unverified list).
4. Cross against rough iPhone share and population, both **[U]**/general knowledge, not measured
   this session with a clean source per country.

### Why AEA-active matters more than raw risk

A country with a high felt-quake count and Google's alert system inactive there (Japan, mainland
China) cannot be helped by this app's core mechanism no matter how good the translation is. The
coordinator's instruction to filter the table down to AEA-active countries is the right call —
this is the same logic as `docs/decision.md`'s own finding that Google delivers based on where
its own system runs, not based on where the risk is.

### The user's original three-language guess, checked

- **Spanish: confirmed, strongly.** Five AEA-confirmed countries, the widest reach of any
  language in this table.
- **English: confirmed.** Directly serves the Philippines (its own PHIVOLCS/NDRRMC publish
  official guidance in English, not just Filipino, §2) and the US, and works as a fallback
  everywhere.
- **Portuguese: does not hold up**, see Recommendation point 2. Replaced by Turkish in the first
  wave.

### Indonesia, the open question

This is the single most consequential unresolved item in this whole doc, because if AEA is
active in Indonesia, it jumps to first priority outright — it has the highest felt-quake count
in the entire table, more than 30% higher than the Philippines. The evidence is genuinely mixed:
one AI-summarized search result claimed Indonesia is "one of the countries where the system
operates" **[U]**, but a first-person complaint from an Indonesian user on a public forum,
specifically asking "when will Indonesia get this feature", reads as evidence it was **not**
active as of that post **[R, dated post, exact date not confirmed]**. No official Google
statement naming Indonesia was found either way. Recommend: developer-ios or devops confirms
this directly (an Android phone physically in Indonesia, checking Settings → Safety & Emergency
→ Earthquake Alerts, the same way `docs/findings.md` §1 originally confirmed AEA delivery to
Colombia) before committing engineering time to Indonesian localization.

---

## 2. Official protective-action wording, per language

Every phrase below is the country's own civil-protection or seismological agency's guidance, not
a generic translation invented for this doc — cited to that agency by name. Colombia's is
included for comparison since it is already this project's baseline.

| Country / agency | Official phrase | Source |
|---|---|---|
| Colombia — UNGRD / IDIGER | "Agáchese, Cúbrase y Sujétese" | UNGRD's own published earthquake guidance **[R]**, matches `docs/decision.md`'s existing Spanish copy convention |
| Mexico — Protección Civil | "Agáchate, Cúbrete y Sujétate" | Widely and consistently reported as the national civil-protection protocol **[R]**; a single .gob.mx primary page was not directly located this session |
| Peru — INDECI | "Agáchate, Cúbrete y Sujétate" | Same wording as Mexico, reported directly against INDECI **[R]** |
| Chile — SENAPRED | "Agáchate, Cúbrete y Afírmate" (note: "Afírmate", not "Sujétate") | Widely reported as SENAPRED/ONEMI guidance **[R]** — **with a caveat**: an academic paper (Araya Huerta, via Academia.edu) argues this exact phrase is *not* well suited to Chile's building typology and should be reconsidered; not resolved, flagged here rather than silently smoothed over |
| Argentina | No single official phrase confirmed this session | Not found; Argentina's earthquake risk is concentrated in the Andean west (Mendoza, San Juan) and its national civil-defense messaging did not surface a distinct campaign slogan in this search — **[U]**, needs its own pass before shipping Argentina-specific copy |
| Turkey — AFAD | "Çök, Kapan, Tutun" (Drop, Cover, Hold On) | AFAD's own national drill campaign, run annually on November 12 (anniversary of the 1999 Düzce earthquake) **[R]**, consistently reported across `afad.gov.tr` and `icisleri.gov.tr` pages |
| Philippines — PHIVOLCS / NDRRMC | "Duck, Cover, Hold" (English; PHIVOLCS's own material and drills use English directly, not a Filipino translation) | PHIVOLCS's own site and drill photos **[R]** |
| Greece — OASP | "Σκύψε, Καλύψου, Κρατήσου" (Skýpse, Kalýpsou, Kratísou — "Duck, Cover, Hold") | OASP's own self-protection guidance page, oasp.gr **[R]** |
| US / generic English | "Drop, Cover, and Hold On" | ShakeOut / ShakeAlert / USGS, the origin of the whole "drop cover hold" family above **[V]**, read directly at shakeout.org |

Nepal, Indonesia (BNPB uses "merunduk, berlindung, bertahan" — crouch, take shelter, hold on,
matching the same pattern **[R]**), and Afghanistan/Pakistan were not chased to full confirmation
this session — out of the first-wave scope, see §1.

### Proposed strings

Built from `docs/ios-contract.md`'s existing payload shapes, substituting the phrase above for
"Protéjase ahora" and keeping every other field (magnitude rounding, `late` handling, coverage
tiers) identical to the Spanish version already shipped.

**English**

| kind | title | body |
|---|---|---|
| alert | Earthquake alert | M4.8 earthquake near your area. Drop, Cover, and Hold On. |
| alert, no magnitude | Earthquake alert | Possible earthquake near your area. Drop, Cover, and Hold On. |
| late | Delayed earthquake notice | The earthquake happened N min ago. This is no longer an early warning. |
| test | Test alert | This is what an earthquake alert sounds like. This is only a test. |
| coverage down | Service interrupted | We can't alert you right now. |
| coverage restored | Coverage restored | Alerts in your area are working again. |
| no coverage yet | No coverage in your area | Your area doesn't have coverage yet. |

**Turkish**

| kind | title | body |
|---|---|---|
| alert | Deprem uyarısı | Bölgenize yakın M4.8 deprem. Çök, Kapan, Tutun. |
| alert, no magnitude | Deprem uyarısı | Bölgenize yakın olası deprem. Çök, Kapan, Tutun. |
| late | Gecikmiş deprem bildirimi | Deprem N dakika önce oldu. Artık erken uyarı değildir. |
| test | Test uyarısı | Bir deprem uyarısı böyle duyulur. Bu sadece bir testtir. |
| coverage down | Hizmet kesintide | Şu anda sizi uyaramıyoruz. |
| coverage restored | Kapsama alanı yeniden aktif | Bölgenizdeki uyarılar tekrar çalışıyor. |
| no coverage yet | Bölgenizde kapsama yok | Bölgenizde henüz kapsama alanı yok. |

**[U]**: none of these were checked by a native Turkish speaker or a professional translator —
mark them `needs_review` the same way developer-ios is already handling Spanish strings that
haven't been reviewed, per the coordinator's note that developer-ios uses that convention and
does not invent translations either.

Chile's alert body should read "...Agáchate, Cúbrete y Afírmate." instead of the Mexico/Peru
wording if Chile gets its own locale variant rather than sharing generic `es`, given the phrase
difference above.

---

## 3. Legal note per first-wave country (not Colombia's law — do not assume it transfers)

Scoped to Mexico, Chile, Peru, Argentina and Turkey, matching the first-wave language list.
Philippines is included too since English is first-wave and the Philippines is its highest-value
market. Same disclaimer as `legal-colombia.md`: this is a map, not a lawyer's opinion, and every
line here should go past a local lawyer for that specific country before launch.

| Country | Law / authority | What's different from Colombia's Ley 1581 regime | Confirmed this session? |
|---|---|---|---|
| Mexico | Ley Federal de Protección de Datos Personales en Posesión de los Particulares (LFPDPPP, 2010). Regulator: **not INAI** — INAI was dissolved by a December 2024 constitutional reform; its data-protection functions moved to the Secretaría Anticorrupción y Buen Gobierno (SABG) | International transfer needs the Titular's consent, with statutory exceptions in art. 37 (legal/treaty basis, performing a contract) similar in shape to Colombia's art. 26 exceptions | [R] — regulator change and the general consent rule; the exact current SABG procedure was not read in primary form |
| Chile | **Currently** Ley 19.628 (1999, thin by regional standards). **From December 1, 2026**, Ley 21.719 replaces it entirely: new rights (access, rectification, deletion, portability), a mandatory Data Protection Officer for organizations handling significant personal data, privacy impact assessments for high-risk processing, breach notification, and Chile's **first-ever dedicated regulator**, the Agencia de Protección de Datos Personales, which does not exist yet as of this writing | Everything — Chile is mid-transition to a GDPR-shaped regime right as this app would plausibly launch there. Whatever compliance work is done for Chile before December 2026 may need redoing right after | [R] — the change and its date are well corroborated across several Chilean law-firm sources; the primary bill text (Ley 21.719 at bcn.cl) was not read directly this session |
| Peru | Ley 29733 (2011) + a new reglamento from November 2024 (Decreto Supremo 016-2024-JUS). Regulator: Autoridad Nacional de Protección de Datos Personales (ANPDP), under the Ministry of Justice | International transfer requires the destination country to have an adequate protection level (ANPDP's own assessment) or a safeguard like model contractual clauses — same shape as Colombia's Decreto 1377 transferencia/transmisión split, but Peru's guidance on the encargado exception was not directly confirmed this session | [R] |
| Argentina | Ley 25.326 (2000, one of the region's oldest). Regulator: Agencia de Acceso a la Información Pública (AAIP), whose adequacy-list model is described as "mainly reactive" (complaint-driven) rather than proactive | Same adequacy-or-consent shape as Colombia and Peru; Ibero-American Network model contractual clauses are explicitly recognized as a valid transfer mechanism, which may be simpler to rely on than negotiating custom AWS/Apple contract language country by country | [R] |
| Turkey | Law No. 6698 (KVKK, 2016), closely modeled on the old EU Directive 95/46/EC rather than GDPR directly. Regulator: the KVKK authority and its Data Protection Board. **2024 amendment (Law 7499)** replaced the old consent-heavy transfer rule with a tiered mechanism (adequacy decisions, standard contracts, binding corporate rules), and requires notifying the authority within 5 business days of using a Board-approved standard contract for a transfer | Materially different from the Colombia/Peru/Argentina "adequacy list" family — Turkey's newer tiered system is closer to GDPR's post-2021 shape. AWS and Apple's cross-border role would need to be mapped against this specific tiered structure, not assumed to work like the Decreto 1377 transmisión exception | [R] |
| Philippines | Republic Act 10173, Data Privacy Act of 2012. Regulator: National Privacy Commission (NPC) | Uses an accountability/contractual-safeguard model for cross-border transfer (the controller stays responsible and must ensure "comparable protection" via contract) rather than a fixed adequacy list — arguably an easier fit for the AWS/Apple encargado-style relationship than the Latin American adequacy-list countries | [R] |

**Not researched, ask local counsel directly, no guess offered here:** whether any of these six
countries has an equivalent to Colombia's Código Penal art. 426 (simulación de investidura) or
Ley 1480 (misleading advertising) that would bear on calling a private notification an "alerta"
or "uyarı" or "alert" — general impersonation-of-official and consumer-protection statutes almost
certainly exist in all six (they are common in most legal systems), but naming the specific
statute and confirming it applies the way Colombia's does was out of scope for this pass and
would be a guess if stated here. This is exactly the kind of item the coordinator asked not to
present as `[U]` filler — so it is stated plainly as unresearched instead.

---

## Unverified list, in one place

- **Indonesia's AEA status** — the single highest-value open question in this doc. Conflicting
  weak evidence both ways. **[U]**
- **Taiwan's AEA status** — no evidence found either way, unlike Japan's explicit exclusion.
  **[U]**
- The "139 countries" figure that surfaced once from a single fetch is not trusted — it
  contradicts Google's own "98 countries by end of 2023" figure and looks likely to have picked
  up an unrelated list from the page (e.g. a locale selector) rather than the actual supported-
  country list. Treated as noise, not evidence, anywhere in this doc.
- Population figures in the main table are total country population, not population actually
  exposed to seismic hazard (a PAGER-style exposure model was out of scope). **[U]**
- iPhone/iOS market share per country was not independently measured this session; Papua New
  Guinea and Afghanistan being excluded from both waves rests on general knowledge that their
  iPhone penetration is very low, not a cited figure. **[U]**
- Argentina's own official protective-action phrase (if one exists distinct from the generic
  Spanish-language "agáchate, cúbrete, sujétate/afírmate" family). **[U]**
- None of the English or Turkish push-notification strings in §2 have been reviewed by a native
  speaker or professional translator. **[U]** — flag as `needs_review`, matching the convention
  developer-ios is already using for Spanish strings.
- Whether Mexico, Chile, Peru, Argentina or Turkey have a Código-Penal-426-style law restricting
  who may issue something styled as an earthquake "alert" — explicitly not researched, not
  guessed at (§3).
- Chile's Ley 21.719 and its new Agencia de Protección de Datos Personales were read only through
  secondary summaries; the primary bill text at bcn.cl was not read directly this session.

---

## Sources

- USGS FDSN Event API, `https://earthquake.usgs.gov/fdsnws/event/1/query` — **[V]**, queried
  directly this session for all M4.5+ events in the trailing 365 days (7,683 events); the
  per-country counts in the main table are computed from this raw response, not copied from any
  secondary source.
- [Android Earthquake Alerts: A global system for early warning](https://research.google/blog/android-earthquake-alerts-a-global-system-for-early-warning/) — Google Research blog, fetched this session. **[V]** for the 98-countries-by-end-2023 figure and the New Zealand/Greece/Turkey/Nepal/Philippines examples it names directly.
- [Introducing Android Earthquake Alerts outside the U.S.](https://blog.google/products-and-platforms/platforms/android/introducing-android-earthquake-alerts-outside-us/) — fetched this session, the original April 2021 Greece/New Zealand announcement.
- News coverage used for per-country AEA-active status (all **[R]**, not Google primary statements): Infobae (Mexico, Chile, Peru), T13/BioBioChile/EMOL (Chile), El Comercio (Peru), Los Andes (Argentina/Mendoza), TechCrunch and Gulf News (India), The News International (Pakistan), The Portugal News (Portugal), TechRadar (Venezuela).
- [AFAD — Çök-Kapan-Tutun](https://istanbul.afad.gov.tr/deprem-sirasinda-hayat-kurtaran-uc-hareket-cok-kapan-tutun) and [afad.gov.tr](https://www.afad.gov.tr/tum-turkiyede-deprem-ani-cok-kapan-tutun-tatbikati) — **[R]**, Turkey's official phrase.
- [PHIVOLCS](https://www.phivolcs.dost.gov.ph/) — **[R]**, Philippines' official "Duck, Cover, Hold" phrase and earthquake authority.
- [OASP — Οδηγίες Αυτοπροστασίας](https://oasp.gr/odigies-aytoprostasias) — **[R]**, Greece's official phrase.
- [The Great ShakeOut — Drop, Cover, and Hold On](https://www.shakeout.org/dropcoverholdon/) — **[V]**, read directly, the origin of the English phrase and the wider drop-cover-hold family.
- Data protection law summaries (all **[R]**, secondary — see §3 for exactly what was and wasn't confirmed): Mexico (LFPDPPP, INAI dissolution), Chile (Ley 21.719 vs. 19.628), Peru (Ley 29733), Argentina (Ley 25.326, AAIP), Turkey (KVKK / Law 6698, Law 7499 amendment), Philippines (RA 10173, NPC).
- Apple App Store / Iran sanctions: [BleepingComputer](https://www.bleepingcomputer.com/news/apple/apple-bans-iran-from-the-app-store/), [United4Iran](https://united4iran.org/blog/iran-hits-back-at-apple-apps-ban/) — **[R]**.
- `docs/findings.md`, `docs/decision.md`, `docs/ios-contract.md`, `docs/research/legal-colombia.md` — this project's own prior work, used as the baseline for comparison throughout.

# Legal: Turkey (KVKK, alerting rules, liability, drafts)

2026-09-26. Not legal advice. I am not a lawyer and this is not a law firm's opinion: it is a
map of the rules and an outline of what the Turkish text needs to say, to hand to a Turkish
lawyer before launch. Every place that needs a lawyer's sign-off is marked **[LAWYER]**.

Tags: **[V]** read in the primary source (the law, the regulation, KVKK's own page/guide).
**[R]** reported by a secondary source (law-firm blog, news), not cross-checked against the
primary text. **[U]** unverified, or a judgment call with no clean answer.

Data inventory: same as Colombia. See `legal-colombia.md` §1's table (`device_token`,
`sensor_ids`, `demand_cell`, `min_magnitude`, `/telemetry/arrivals`) — nothing about what the
app collects changes for Turkey. What changes is the law applied to that same data.

The Yardım Toplama Kanunu (2860) thread from `sponsor-your-region.md` is **moot**: the paid
tier is a normal Pro-tier SKU, not a donation or crowdfunding model, so that statute no longer
applies. Not researched further here.

---

## Recommendation

1. **VERBIS (the data-controller registry): register regardless of size, because the
   controller is foreign.** Turkish-resident controllers get a small-entity exemption (fewer
   than 50 employees and under 100 million TL annual balance sheet, both conditions together,
   per Board Decision 2025/1572 of 2025-09-04 **[V]**, reported here rather than read in the
   Board's own decision text, which I could not fetch — **[R]**). That exemption is for
   entities established in Turkey. A controller with no Turkish legal presence has a different,
   harder rule: Veri Sorumluları Sicili Hakkında Yönetmelik art. 5(1)(b), quoted directly:
   "Türkiye'de yerleşik olmayan veri sorumluları, veri işlemeye başlamadan önce veri sorumlusu
   temsilcisi marifetiyle Sicile kaydolmak zorundadır" — non-resident controllers must register
   via a representative before processing begins, with **no size threshold at all** **[V]**.
   The representative (art. 4's definition) must be a Turkey-resident legal entity or a Turkish
   citizen, authorized to represent the foreign controller on VERBIS matters **[V]**. This is a
   real, concrete cost this project doesn't carry in Colombia, Mexico or any other market
   researched so far: a Turkish representative has to be found and appointed before the app can
   process any Turkish user's data, independent of how small the operation is. **[LAWYER]**
   should confirm this reading applies here (a hobby-scale relay app with a handful of Turkish
   users) and help find/appoint the representative.
2. **Explicit consent (açık rıza), not the softer conductas-inequívocas standard Colombia
   allows.** KVKK Law 6698 art. 5(1): "Kişisel veriler ilgili kişinin açık rızası olmaksızın
   işlenemez" — personal data may not be processed without the data subject's explicit consent,
   unless one of seven listed exceptions applies **[V]**. None of the seven (statutory
   requirement, life-or-limb necessity, contract performance, controller's legal obligation,
   data the subject made public themselves, establishing/exercising a right, or the
   controller's legitimate interest so long as it doesn't harm the subject's rights) obviously
   covers routine alert delivery on their own — a consent screen is still the safe path, same
   practical outcome as Colombia, but on a stricter legal basis. Separately, the aydınlatma
   (disclosure/notice) obligation under art. 10 is **not satisfied by asking for consent** —
   Tebliğ (Communiqué) art. 5 requires disclosure "in every case" personal data is processed,
   including when the legal basis is something other than consent, and requires the legal basis
   itself to be stated explicitly ("hukuki sebebin açıkça belirtilmesi gerekmektedir") **[V]**.
   Practical read: the onboarding screen needs two distinct things, not one merged screen —
   a notice (what's collected, why, legal basis, who it's shared with) and a separate consent
   tap. Colombia's single aviso+consent screen pattern doesn't fully transfer; **[LAWYER]**
   should confirm whether Turkish practice tolerates one combined screen if both elements are
   present, or genuinely wants them visually separate.
3. **International transfer to AWS (Brazil) and Apple/APNs (US): the analysis is structurally
   different from Colombia's, and less favorable.** Colombia's Decreto 1377 art. 24.2 lets a
   pure processor relationship ("transmisión") skip the whole adequacy/consent question. Turkey
   has no equivalent shortcut for processors: KVKK art. 9 (as rewritten by Law 7499, in force
   2024-06-01) applies the same transfer regime to "veri sorumluları ve veri işleyenler" —
   controllers *and* processors, together, explicitly **[V, read directly in art. 9(1)]**. There
   is a genuinely useful distinction, but it's a different one: whether the data reaches the
   foreign party by the Turkish controller *transferring* it, or the foreign party *collecting
   it directly* from the data subject (e.g., an app on the user's own phone talking straight to
   a US server). KVKK's own transfer guide (Yayın No. 48) gives worked examples of this
   distinction **[V]** — Örnek 1 and 2 hold that when a foreign company collects data straight
   from a Turkish resident with no Turkish intermediary "aktaran", it is **not** a "transfer
   abroad" under art. 9, though the substantive law still applies to the processing itself.
   Whether that helps here is genuinely unclear: the phone talks to the gateway (hosted on AWS,
   Brazil) directly, with no Turkey-based server in between, which looks more like Örnek 1/2
   than the classic "Turkish company relays to a foreign vendor" case in Örnek 4-7 — but the
   guide's examples are all e-commerce fact patterns, not push-notification infrastructure, and
   I would not stake a legal position on the analogy holding. **[LAWYER]** must decide whether
   this project's actual data flow (phone → AWS-hosted gateway → APNs) is an art. 9 "transfer"
   at all, and if it is, which safeguard route applies (below).
4. **If art. 9 does apply: no adequacy decision exists for any country yet.** KVKK has not
   issued a single adequacy decision since the power existed from 2016 **[R, one secondary
   source; not confirmed against KVKK's own published list, which I could not locate a current
   version of this session — [U]]**. That forecloses the easiest path and leaves the "uygun
   güvence" (appropriate safeguard) tier: a Board-published standard contract, signed and
   notified to the Authority within 5 business days of signature (art. 9(5) **[V]**), or a
   written undertaking approved case-by-case by the Board, or binding corporate rules (neither
   fits a small operator). Missing the 5-day standard-contract notification carries its own
   fine, 50,000-1,000,000 TL as of the 2024 amendment (art. 18(1)(d) **[V]**). Failing all of
   that, an "arızi" (incidental, one-off/irregular, not routine) transfer exception exists
   (art. 9(6)), but KVKK's own guide stresses this must be read narrowly and cannot be the
   ordinary channel for a recurring data flow **[V]** — a push notification service that runs
   continuously does not look "arızi" on its face. **[LAWYER]**: this is the single most
   consequential open question in this document. If art. 9 is found to apply to this data flow,
   the standard-contract route is probably the only realistic option, and someone has to
   actually execute and notify it before Turkish users are onboarded.
5. **Fines are real money at this scale, not symbolic.** As of the 2024 amendment: failing the
   aydınlatma obligation, 5,000-100,000 TL; failing data-security duties, 15,000-1,000,000 TL;
   ignoring a Board order, 25,000-1,000,000 TL; VERBIS/notification violations, 20,000-1,000,000
   TL; missing the standard-contract notification, 50,000-1,000,000 TL — all **[V]**, read
   directly in art. 18. These apply per violation found, at the Board's discretion within the
   range, not per user.
6. **Who may relay an earthquake alert: no Colombia-style statute confirmed, but a real
   proximate offense exists if the app's presentation crosses a line.** TCK (Turkish Penal
   Code) art. 262, "Kamu Görevini Usulsüz Üstlenme" (unlawfully assuming a public duty),
   punishes actually performing or attempting to perform a public official's function without
   authority, 3 months to 2 years **[R, secondary legal-blog source describing the article; the
   primary TCK text for this specific article was not independently opened this session]**. This
   requires *acting as* the authority (e.g., presenting the app's output as AFAD's own official
   determination), not merely relaying information — closer to Colombia's Código Penal art. 426
   than TCK art. 264 (unauthorized wearing of official uniforms/insignia, 3 months-1 year
   **[R]**), which is about physical symbols, not digital branding, and is a weaker fit for an
   app. Neither is a clean, confirmed match the way Colombia's 425-426 or Peru's art. 361 are —
   flag to **[LAWYER]**, don't assume either applies or doesn't. Mitigation, same principle as
   Colombia regardless of the exact statute: never use AFAD's name, seal, or visual identity;
   state plainly, on first screen and in the terms, that this is an independent app, not AFAD
   and not government-run.
7. **AFAD's own legal mandate (Law 5902) does not appear to grant it an exclusive monopoly
   over disseminating earthquake information** — nothing found this session states that only
   AFAD may inform the public about an earthquake. Law 5902 establishes AFAD's organization and
   coordinating role across public bodies, universities, the Red Crescent, and the private
   sector **[R]**; it reads as an institutional/coordination law, not a licensing regime for
   private information services. This is a weaker, less confirmed finding than "no exclusive
   license found" was for Colombia (which had the SNAST bill and Ley 1523 to read against) —
   Turkey's Law 5902 was not read in full primary text this session, only its stated purpose and
   general provisions. **[LAWYER]** should confirm nothing in the fuller text (or its
   post-2023-earthquake amendments, not researched) creates such a restriction.
8. **Consumer/advertising law: Law 6502, and the same "don't overstate what this does"
   discipline as Colombia's Ley 1480.** Turkey's Law 6502 (Tüketicinin Korunması Hakkında
   Kanun) prohibits misleading advertising and unfair contract terms **[R]**, and a dedicated
   Advertising Board (Reklam Kurulu) enforces it; the primary statute's abusive-clause
   provisions were not read directly this session. Same practical guidance as Colombia: state
   plainly that alerts can be late, can fail, and do not replace civil-protection instructions;
   avoid a blanket "we are not liable for anything" clause, since that is the shape of clause
   these consumer-protection regimes tend to strike down. **[LAWYER]** should review the exact
   Turkish wording before it ships, same as the Colombia draft needed review.
9. **Before it ships to Turkey:** confirm with a Turkish lawyer (a) whether this project's data
   flow is an art. 9 "transfer" at all or falls under the guide's direct-collection exception,
   (b) if it is a transfer, execute and notify the standard contract within 5 business days of
   signature, (c) appoint a VERBIS representative and register, since the small-entity
   exemption does not appear to reach a non-resident controller, (d) whether TCK art. 262 or
   264 bears on the app's planned presentation, and (e) review the Turkish consent/notice and
   liability-disclaimer text once drafted (outline only, below — no invented translations).

---

## 1. KVKK Law 6698 (as amended by Law 7499, 2024-03-02, in force 2024-06-01)

### Processing conditions and special categories

Art. 5(1): baseline is explicit consent; art. 5(2) lists seven exceptions (statutory
requirement; life/bodily-integrity necessity when consent can't be obtained or isn't legally
valid; contract performance; controller's legal obligation; data made public by the subject;
establishing/exercising/protecting a right; controller's legitimate interest without harming the
subject's fundamental rights) **[V, read directly, art. 5 full text]**. Art. 6, as amended by
Law 7499 art. 33 (2024): processing special-category data (race, ethnicity, political opinion,
philosophical belief, religion, sect, dress/attire, association/foundation/union membership,
health, sexual life, criminal conviction, security measure data, biometric and genetic data) is
prohibited by default, same structure as Colombia's art. 5-6 sensitive-data regime **[V]**. This
app processes none of that, same conclusion as Colombia.

### Notice (aydınlatma) vs. consent

Art. 10 requires the controller to inform the data subject, at the time of collection, of: the
controller's (and any representative's) identity, the purpose of processing, to whom and for
what purpose the data may be transferred, the method and legal basis of collection, and the
art. 11 rights **[V, read directly]**. The implementing Tebliğ's art. 5 adds procedural detail:
notice must be given "in every case" processing occurs regardless of legal basis (5(1)(a)),
separately for each new purpose (5(1)(b)), separately per business unit if purposes differ
(5(1)(c)), consistent with what's declared to VERBIS when registration applies (5(1)(ç)), with
the legal basis stated explicitly, and must name the transfer purpose and recipient categories,
the collection method, and must not be incomplete or misleading (5(1)(ı), (i), (j)) **[V]**.

### Data subject rights (art. 11)

Right to know if data is processed, request information about it, learn the purpose and whether
it's used consistently with that purpose, know third parties (domestic or foreign) it's shared
with, request correction of inaccurate/incomplete data, request erasure/destruction under art. 7,
have those corrections/erasures relayed to anyone the data was shared with, object to a decision
made solely by automated processing that's unfavorable to them, and claim damages for unlawful
processing **[V, read directly, all nine (a) through (ğ)]**. Same practical mapping as Colombia:
`DELETE /devices` plus a stated contact channel covers most of this; nothing here requires new
server code.

### Data security and breach notice (art. 12)

Controller must take all necessary technical/administrative measures to prevent unlawful
processing and access, and to preserve the data; stays jointly responsible for a processor's
compliance; must notify both the data subject and the Board "in the shortest time" ("en kısa
sürede") if data is unlawfully obtained by others **[V, read directly]**. No fixed hour deadline
like GDPR's 72 hours was found in the statute text itself — **[U]**, don't assume a specific
number without checking KVKK Board guidance on this point, not researched further here.

### VERBIS (art. 16, and the Yönetmelik)

Statute (art. 16): a public registry kept by the Presidency under Board oversight; anyone
processing personal data must register before starting, subject to Board-set exemption criteria
**[V, read directly]**. The exemption criteria (thresholds) live in Board decisions, not the
statute: Decision 2025/1572 (2025-09-04) sets the general exemption at fewer than 50 employees
**and** under 100 million TL annual balance sheet total, both required together for entities
that keep a balance sheet; employee-count only for those that don't **[R]**; a stricter,
smaller exemption (fewer than 10 employees, under 10 million TL) exists for controllers whose
main activity is special-category data **[R]**. None of this reaches a foreign controller: the
Yönetmelik's art. 5(1)(b) obligation for non-resident controllers to register via a
representative, with no threshold, is separate and was read directly (§ Recommendation 1
above) **[V]**.

---

## 2. Who may issue or relay an earthquake alert in Turkey

Covered in Recommendation §6-7 above. Summary: no confirmed Colombia-425/426-equivalent found,
TCK art. 262 (unlawfully performing a public function) is the closer analogy if the app's
presentation ever crosses from "relaying Google's alert" into "acting as if we are the
authority", TCK art. 264 is a weaker fit (physical insignia/uniforms). AFAD's organizing statute
(Law 5902) reads as institutional, not an information-dissemination monopoly, but was not read
in full. Mitigation: same as Colombia — never use AFAD's name/seal, state independence plainly.

---

## 3. Consumer law and liability disclaimer

Law 6502 prohibits misleading advertising and unfair terms, enforced by the Reklam Kurulu
**[R]**. Same three disclaimer facts as Colombia should appear, in Turkish, before the first
permission prompt: (a) this is not an official AFAD service; (b) the alert can fail, arrive
late, or not arrive; (c) it does not replace civil-protection instructions. **[LAWYER]** should
review the exact wording for compliance with Law 6502's unfair-terms rules before it ships —
the Colombia draft's "best-effort, no guaranteed outcome" framing (avoiding a blanket liability
waiver) is a reasonable starting point to adapt, not a ready translation.

---

## 4. Drafts: outline only, no invented Turkish text

Per instruction, no Turkish legal text is drafted here — Turkish needs a native legal drafter,
same standard already applied to Turkish push-notification strings in `languages.md`
(`needs_review`, no invented translations). What the Turkish aydınlatma metni (notice) and the
separate consent screen need to contain, in English outline, for a translator/lawyer to work
from:

**Aydınlatma metni (notice), per art. 10 + Tebliğ art. 5:**
1. Identity of the data controller (and its VERBIS representative, once appointed).
2. What is collected: device token, chosen receptor id(s), the coarse location cell computed on
   the phone (never the precise coordinate), and — separately, for opted-in test phones only —
   arrival telemetry timestamps.
3. The purpose of each: alert delivery, and (separately) performance measurement for telemetry.
4. The legal basis for each processing activity, stated explicitly (not just "consent" as a
   blanket word — state which art. 5 condition applies to which piece of data, once a lawyer
   confirms the basis).
5. Who it's transferred to and why: AWS (hosting, Brazil) and Apple/APNs (push delivery, US),
   named as processors, with the international-transfer mechanism used once §1 Recommendation 4
   is resolved by counsel.
6. The collection method (automatically, from the app running on the user's device).
7. The full list of art. 11 rights, in plain language, with a stated contact channel.

**Consent screen, separate from the notice above:**
1. A single clear action (a tap), never a pre-checked box, never bundled with another consent.
2. Distinct consent for the base alert-relay purpose vs. the opt-in telemetry purpose — this
   already matches the multi-purpose consent design in `legal-colombia.md` §4.2 and
   `culture-and-apple.md`'s KVKK granular-consent note; no new screen design needed, only
   Turkish text and a legal-basis review.
3. The three disclaimer lines from §3 above, shown before the consent action, not after.

## App Store label deltas

No deltas found. The data-linked/not-tracking analysis in `legal-colombia.md` §4.4 (Device ID,
Coarse Location, Performance Data; App Functionality purpose; no tracking) is a factual
description of what the app does, not a Colombia-specific legal conclusion, and nothing found
this session changes it for the Turkish storefront. Not deeply re-checked against Apple's
Turkey-specific requirements — **[U]**, low risk, since Apple's privacy label mechanism itself
does not vary by storefront.

---

## Unverified list, in one place

- Whether this project's specific data flow (phone → AWS-hosted gateway, no Turkish
  intermediary) is a KVKK art. 9 "transfer abroad" at all, or falls under the guide's
  direct-collection exception (Recommendation §3-4). The single highest-stakes open question
  in this document.
- Whether the VERBIS small-entity exemption (Decision 2025/1572) has ever been read to extend
  to a non-resident controller in practice, despite the Yönetmelik's plain no-threshold text —
  not found either way.
- Whether any current KVKK adequacy decision exists for any country — one secondary source says
  none does; not confirmed against KVKK's own current published list.
- The exact breach-notification deadline under art. 12 (no fixed number found in the statute
  text itself).
- Whether TCK art. 262 or 264 actually reaches an app's software presentation (as opposed to a
  person's physical conduct) — both articles read, in the secondary sources found, as written
  around a person's own conduct/attire, not an app's UI; this is my inference, not a confirmed
  legal reading.
- Law 5902's fuller text and any post-2023-earthquake amendments — only the stated purpose and
  general provisions were reviewed.
- Law 6502's specific abusive-clause/unfair-terms provisions — not read in primary text.
- Whether Apple has any Turkey-specific App Store requirement beyond the general privacy-label
  mechanism — not researched.

## Sources

- KVKK Law 6698 (current consolidated text, reflecting Law 7499): fetched and extracted
  directly from `mevzuat.gov.tr`'s PDF this session (arts. 2, 3, 5, 6, 8, 9, 10, 11, 12, 16, 17,
  18, 19, Geçici Madde 3, art. 32 read directly) [V]
- KVKK's own English-summary page for 6698: [kvkk.gov.tr](https://www.kvkk.gov.tr/Icerik/6649/Personal-Data-Protection-Law) [R]
- Veri Sorumluları Sicili Hakkında Yönetmelik (VERBIS regulation), art. 4 and 5(1)(b) quoted
  from a secondary source's direct quotation of the regulation text: [CottGroup](https://www.cottgroup.com/tr/mevzuat/item/yurt-disinda-yerlesik-veri-sorumlularinin-verbis-e-kayit-yukumlulugu-ve-sartlari) [R]; KVKK's own regulation page: [kvkk.gov.tr](https://www.kvkk.gov.tr/Icerik/5442/VERI-SORUMLULARI-SICILI-HAKKINDA-YONETMELIK) (landing page only, full text not rendered) [R]
- VERBIS exemption thresholds, Board Decision 2025/1572 (2025-09-04): [Esenyel Partners](https://www.esenyelpartners.com/tr/2026-verbis-kayit-istisnalari-100-milyon-tl-esigi-ve-guncel-kurallar/); [KVKK announcement](https://www.kvkk.gov.tr/Icerik/8577/kisisel-verileri-koruma-kurulunun-04-09-2025-tarihli-ve-2025-1572-sayili-kararinin-uygulama-esaslarina-iliskin-kamuoyu-duyurusu) [R]
- Kişisel Verilerin Yurt Dışına Aktarılmasına İlişkin Usul ve Esaslar Hakkında Yönetmelik
  (2024-07-10, Official Gazette 32598): fetched and extracted directly from `kvkk.gov.tr`'s PDF,
  arts. 1-19 read [V]
- KVKK Yayın No. 48, "Kişisel Verilerin Yurt Dışına Aktarılması Rehberi" (2025-01): fetched and
  extracted directly, the seven worked examples (Örnek 1-7) on transfer vs. direct collection
  read in full [V]
- No-adequacy-decision claim: [Mondaq/UyumBox summary](https://uyumbox.com/blog/kvkk-standart-sozlesme-yurt-disina-veri-aktarimi) [R]
- Aydınlatma Yükümlülüğü Tebliği art. 5: quoted via search-engine synthesis of the primary text,
  not opened as a standalone document this session [R, high confidence given verbatim
  quotation, but not independently re-verified against the Official Gazette text]
- TCK art. 262, 264, 158, 204 (impersonation-adjacent offenses): [mkursadari.av.tr](https://mkursadari.av.tr/ceza-hukuku/kisinin-kendisini-kamu-gorevlisi-olarak-tanitma-sucu/); [barandogan.av.tr, TCK 264](https://barandogan.av.tr/blog/mevzuat/tck-madde-264-ozel-isaret-ve-kiyafetleri-usulsuz-kullanma-sucu.html) [R]
- Law 5902 (AFAD organizing statute): [teftis.ktb.gov.tr](https://teftis.ktb.gov.tr/TR-263551/5902-sayili-afet-ve-acil-durum-yonetimi-baskanliginin-teskilat-ve-gorevleri-hakkinda-kanun.html) (landing/summary page) [R]
- Law 6502 consumer protection: [istanbullawyerfirm.com](https://istanbullawyerfirm.com/blog/consumer-protection-laws-in-turkey/) [R]
- Cross-referenced this project's own: `docs/research/legal-colombia.md`,
  `docs/research/culture-and-apple.md`, `docs/research/languages.md`,
  `docs/research/sponsor-your-region.md` (Yardım Toplama Kanunu thread, now moot)

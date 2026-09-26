# "Sponsor your region": evaluation per market

2026-09-26, investigator. Evaluates one concrete model against the seven first-wave markets
(Colombia, Mexico, Chile, Peru, Argentina, Philippines, Turkey): alerts stay free everywhere,
always; an optional pledge tied to a `demand_cell` area raises `AUTO_RECEPTOR_BUDGET_USD` for
that area; once pledges cover the real cost (about $33/month, per `docs/STATUS.md`), a receptor
gets built there and everyone in the area gets free alerts, subscriber or not. Companion to
`positioning-and-pricing.md`, which this doc does not repeat.

Tags: **[V]** read/fetched directly this session. **[R]** reported by a secondary source, not
re-derived. **[U]** unverified or my judgment. Not legal advice.

## Bottom line

The mechanic itself is sound and matches the funding framing already recommended in
`positioning-and-pricing.md`. Two real problems surfaced, both regulatory, both concrete enough
to act on before building: **Turkey and the Philippines each have a general public-fundraising
permit law that explicitly reaches this exact mechanic**, and neither has an obvious carve-out
for "we're a company selling a subscription that also happens to fund infrastructure." Everyone
else in the set (Colombia, Mexico, Chile, Peru, Argentina) has either an explicit exclusion for
donation-style crowdfunding from the regulated regime, or no permit regime found at all.

No price point is proposed anywhere below. Same finding as `positioning-and-pricing.md`:
no reliable market-level willingness-to-pay figure for this kind of pledge exists in public
sources for any of these seven countries, including a specific check against Patreon's own
published statistics, which give a global average pledge ($6) but no country breakdown [R].
Guessing a number would be worse than saying so.

## 1. Does the "X of Y needed" progress bar read as motivating or as begging?

The honest answer is that this is a much better fit in the Spanish-speaking markets than
anywhere else in the set, because of a real, well-established cultural pattern: pooling money
for a shared, concrete goal is a normal, warm, unremarkable thing to do, not a sign of
precarity.

- **Argentina and Chile**: "hacer una vaca" (Argentina) / "hacer una vaca" (Chile, same
  wording, different local flavor) means a group chipping in for something concrete, usually
  informal and among friends, with unequal amounts expected [R]. A progress bar toward a
  named, physical thing (a receptor) reads as this pattern at product scale, not as a
  donation drive.
- **Peru**: the equivalent is "hacer una chancha/chanchita" [R], same shape.
- **Colombia and Mexico**: this is not just a folk expression, it is also a proven product
  category. Vaki, a Colombian crowdfunding platform explicitly named after "la vaquita" (the
  little cow), is reported as the largest crowdfunding platform in Latin America, having
  raised over $11M from roughly 500,000 people, and expanded into Mexico in 2024 [R]. A
  visible progress bar toward a concrete goal is exactly Vaki's own product pattern. This is
  the strongest positive precedent found in this whole evaluation.
- **Philippines and Turkey**: no equivalent cultural framing was found in either language this
  session. This does not mean it would read badly, only that there is no found precedent to
  lean on, and — separately, see §4 — a highly visible public solicitation-style progress bar
  is exactly the fact pattern their fundraising-permit laws are written around.

On "does it undermine trust if a region visibly can't get funded": genuinely a judgment call,
not researched. My read: showing a stalled bar next to a life-safety feature risks reading as
"we can't afford to protect you," which cuts against trust anywhere, regardless of culture.
If this ships, I'd suggest never showing a bar with zero real chance of completing soon (for
example, an area with too few phones for the pledge math to ever close) rather than leaving a
visibly dead campaign up — but that's a product call, not something I can settle from research.

## 2. Price point

Not findable, same finding as `positioning-and-pricing.md`. I specifically checked whether
Patreon publishes country-level pledge data (it publishes a global average of about $6 per
pledge, $12 per patron across all pledges, no country breakdown) [R] and found nothing for
Turkey, the Philippines, or any Latin American market specifically. I am not proposing numbers.
What should shape a real price test, all [R] and already partly noted in `positioning-and-pricing.md`:
Turkey's chronic inflation (consumer prices up 32% year-on-year as of a recent reading) means
any lira price needs frequent review; Argentina's 30% card perception tax on foreign-currency
digital purchases inflates whatever the sticker price is; Colombia, Peru and parts of Mexico
have significant unbanked/underbanked populations where a card-only pledge excludes people who
would otherwise chip in.

## 3. Does crowdfunding register differently there than paying a company?

Yes, and the direction is favorable almost everywhere researched, with two clean cultural
precedents:

- Colombia and Mexico: Vaki again — a commercial crowdfunding platform operating in the open,
  not treated as fringe or suspect [R]. Framing the pledge as "chip in with others" rather
  than "pay us" should read as more trustworthy, not less, going by this precedent.
- Argentina, Chile, Peru: the vaca/chancha framing (§1) suggests the same direction, though
  this is inference from a linguistic/cultural pattern, not from an actual crowdfunding-app
  adoption study in those three markets specifically — [U].
- Philippines and Turkey: not researched at the "how does crowdfunding register vs. a company"
  level. What is known instead is the regulatory answer in §4, which is a stronger signal for
  these two markets than a trust-perception guess would be.

## 4. Regulatory wrinkle: does this cross into a solicitation/donation regime?

This is the one place this evaluation found something the team needs to act on, not just read.

- **Turkey — real risk, found directly in statute.** Law No. 2860 (Yardım Toplama Kanunu,
  "Law on the Collection of Aid") requires a governor's permit before collecting aid/donations
  from the public, and the implementing regulation explicitly extends this to internet-based
  collection [R, multiple Turkish legal sources describing the statute; I did not read the
  primary PDF text itself this session, tagging conservatively]. Collecting money without
  permission risks confiscation of the funds [R]. The open, unresolved question is whether a
  company selling an optional subscription with a stated use of funds counts as "yardım
  toplama" (aid collection) under this law, or is treated as an ordinary commercial
  transaction because there's a real product (the app) behind it. I found nothing that
  answers this distinction either way — **flag to Turkish counsel before building the
  region-tied pledge mechanic for Turkey specifically**, separate from and in addition to the
  KVKK/VERBIS items already in `culture-and-apple.md`.
- **Philippines — real risk, found directly in statute, and it names crowdfunding
  explicitly.** Presidential Decree 1564 (the "Solicitation Permit Law") requires a DSWD
  solicitation permit before raising funds from the public, and current DSWD guidance
  explicitly lists "crowdfunding campaigns" among the covered activities [R]. Penalties
  include a fine and up to a year of imprisonment for unauthorized solicitation [R]. Same
  open question as Turkey: this regime reads as aimed at charitable/NGO fundraising, and it
  is not obviously written with a commercial subscription-with-infrastructure-earmark in
  mind, but nothing found this session resolves that ambiguity. **Flag to Philippine counsel
  before building this mechanic there.**
- **Argentina — checked, and the news is good.** Ley 27.349 (the law that actually regulates
  "Sistemas de Financiamiento Colectivo") explicitly excludes from its scope: fundraising for
  charitable purposes, donations, direct sale of goods/services through the platform, and
  loans outside a specific carve-out [R, read via a description of the statute's Article
  1/2 text, not the primary law itself this session]. A pledge with a real product behind it
  (free alerts for everyone once funded) reads like it falls outside the regulated financing
  regime, but this is my reading of a secondary description, not a lawyer's — [U].
- **Chile — checked, inconclusive.** Ley 21.521 (Ley Fintec) regulates "plataformas de
  financiamiento colectivo" under the CMF, defined around connecting people with "investment
  projects or financing needs" to those with "the intention to participate in that financing
  operation" [R]. No donation-style exclusion was found in the sources reviewed this session,
  unlike Argentina's explicit one. This doesn't mean the pledge mechanic is caught by it —
  a pledge with no equity, interest or repayment looks far from "investment" — but I could
  not confirm an exclusion, so this is **flagged, not cleared** — [U].
- **Colombia — checked, nothing found that applies.** No public-collection permit regime
  surfaced (searches returned tax-deductibility rules for authorized non-profits, Decreto 743
  of 2020's rules for banks facilitating donations via ATMs/apps, neither of which fits a
  company selling its own subscription) [R]. Consistent with Vaki operating as an ordinary
  commercial platform. Lower apparent risk than Turkey/Philippines, not zero — not the same
  as a lawyer's clearance.
- **Mexico and Peru — not resolved.** Mexico: distinguishes "donación" (an individual,
  voluntary transfer) from "colecta" (an organized collection effort) in general civil-law
  terms, and has an SAT authorization regime specifically for tax-deductible donations to
  non-profits [R] — this doesn't obviously reach a commercial company's subscription, but no
  Mexico-specific "colecta pública permit" statute analogous to Turkey's or the Philippines'
  was found either way. Peru: not researched at all for this question. Both — **flag to
  local counsel, not cleared, not confirmed risky**.

This is a different question from the App Store 3.1.2(a) "ongoing value" issue already
flagged in `positioning-and-pricing.md` for developer-ios — that one is Apple's private
contract rule, this one is government solicitation law. Both need checking, independently,
before this mechanic ships anywhere.

## Not researched, flagged rather than guessed

- Peru: any public-solicitation/collection permit law, not checked this session.
- Mexico: whether any state or federal "colecta pública" permit statute exists beyond what
  was found (only tax-authorization rules for non-profits were found, which likely don't
  apply to a for-profit app, but "likely" is not "confirmed").
- Chile: whether Ley Fintec's crowdfunding definition would actually be read to include a
  no-return pledge like this one. Flagged, not cleared.
- Any actual price point, for any of the seven markets, for a pledge or subscription of this
  kind.
- Philippines and Turkey: cultural trust-in-crowdfunding-vs-company perception. The
  regulatory answer was strong enough that I prioritized it over a weaker cultural guess.
- Whether Turkey's Law 2860 or the Philippines' PD 1564 would actually be enforced against a
  small company like this one in practice, versus how they read on paper. Enforcement
  likelihood is a different question from legal exposure, and I did not research it.

## Sources

- Project facts: `docs/STATUS.md` (receptor cost, budget cap), `docs/siting-pilot.md`
  (`demand_cell`, `AUTO_RECEPTOR_BUDGET_USD`, `receptor-placement.py`), cross-referenced with
  `docs/research/positioning-and-pricing.md` [V]
- Vaki / vaquita: [Semana](https://www.semana.com/emprendimiento/articulo/vaki-la-vaca-entre-amigos-que-se-volvio-el-crowdfunding-mas-grande-de-latam/296869/); [Contxto](https://contxto.com/en/startups/vaki-the-colombian-crowdfunding-platform-lands-in-mexico/) [R]
- "Hacer una vaca" (Argentina/Chile), "chanchita" (Peru): WordReference forum threads, TikTok cultural-explainer content [R, informal sources, consistent across country]
- Turkey Law 2860 (Yardım Toplama Kanunu): [Lexpera summary](https://blog.lexpera.com.tr/izinsiz-yardim-toplama-faaliyeti-ve-yaptirimi/); [Altıparmak Hukuk](https://altiparmakhukuk.org/blog/bilgi-notu-2023-03-yardim-toplama-izni-90); primary text at [mevzuat.gov.tr](https://www.mevzuat.gov.tr/MevzuatMetin/1.5.2860.pdf) (not opened this session) [R]
- Philippines PD 1564 / DSWD Solicitation Permit: [DSWD](https://dswd.gov.ph/securing-a-solicitation-permit/); [DivinaLaw](https://www.divinalaw.com/dose-of-law/additional-rules-on-donations/) [R]
- Argentina Ley 27.349 donation exclusion: search-engine synthesis of the statute's text, e.g. via [argentina.gob.ar](https://www.argentina.gob.ar/normativa/nacional/ley-27349-273567/actualizacion) [R]
- Chile Ley 21.521 (Ley Fintec): [CMF Educa](https://www.cmfchile.cl/educa/621/w3-article-85169.html); [Banproyecta](https://www.banproyecta.cl/2025/04/22/ley-fintech-en-chile-ley-21-521-que-es-a-quien-afecta-y-por-que-es-clave-para-el-sistema-financiero-no-bancario/) [R]
- Colombia donation/collection rules: [INCP](https://incp.org.co/publicaciones/infoincp-publicaciones/impuestos/nacionales/2019/08/estas-serian-las-condiciones-emitir-certificados-donacion-colombia/); [Función Pública, Decreto 743 de 2020](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=126460) [R]
- Mexico donation/collection rules: [SAT](https://www.sat.gob.mx/tramites/71215/solicita-la-autorizacion-para-recibir-donativos-deducibles-del-impuesto-sobre-la-renta) [R]
- Patreon pledge statistics: [Blogging Wizard](https://bloggingwizard.com/patreon-statistics/); [Patreon Help Center, currencies](https://support.patreon.com/hc/en-us/articles/360039589091-Patreon-s-supported-currencies) [R]

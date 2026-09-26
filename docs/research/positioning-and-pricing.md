# Positioning and paid tier, first-wave markets

2026-09-26, investigator. Markets: Colombia, Mexico, Chile, Peru, Argentina, Philippines, Turkey.
Companion to `culture-and-apple.md` (legal risk of looking official, tone, colors) and
`languages.md`. Not legal advice; a lawyer per country should read any final store copy.

Tags: **[V]** read directly this session (project file or primary page). **[R]** reported by a
secondary source, not re-derived. **[U]** unverified or my judgment, do not build on it unchecked.

Hard constraint from the coordinator: no false or exaggerated safety claims. Everything below
persuades with things that are true today, or says plainly that it cannot. This doc does not
name other alert systems or third-party alert apps. Government channels are named only where
the question was how official apps position themselves.

## Recommendation

1. **Alerts stay free. The paid tier must not change whether, when or how an alert arrives, and
   the app should say so in one plain sentence** (for example: "Paying does not change when or
   whether you get an alert."). Reason: every government channel in this set is free [R], so a
   paid alert competes with free official ones in all seven markets. Failure mode of the
   alternative: a paying user believes they get faster or safer alerts, then a real quake shows
   they did not. That is real harm, consumer-law exposure (see below) and grounds for App Store
   removal (guideline 2.3.1(a), quoted below) [V for the guideline].
2. **Sell the tier as funding, not as protection.** The true, checkable mechanism today:
   extra receptors cost about $33/month each on a dedicated host, and the canary sites (glan,
   La Serena, San Salvador) "wait for dedicated hosts when there is money" [V, `docs/STATUS.md`
   line 41]; automatic receptor growth exists but is capped at `AUTO_RECEPTOR_BUDGET_USD=0`
   until the user sets a budget [V, `docs/STATUS.md` line 45, `docs/siting-pilot.md` line 97].
   So "your subscription pays for new receptors, faster than we could afford alone" is true, but
   only if the money is actually committed to that. Failure mode: subscriptions collected and
   not spent on receptors makes the claim false after the fact. Set the spend rule first, write
   it down, then market it.
3. **Do not claim redundancy yet.** The user proposed redundancy as a selling point. Today
   there is one receptor per served area (chaparral and quibdo in Colombia, general-santos as
   a lone canary in the Philippines) [V, `docs/STATUS.md`]. "More than one receptor can cover
   your area" is not true anywhere at this moment. It may be said only in the future tense
   ("we want to add a second receptor per area") and only after the receptors exist, or it is a
   promise the product cannot keep.
4. **Government-endorsement credibility is unavailable to us, and in these markets it is the
   strongest persuader for safety products.** We are not official and must not look official
   (Colombia art. 425-426; direct equivalents found for Mexico, Peru, Argentina and the
   Philippines in `culture-and-apple.md`). If the persuasion norm in a market is "the state
   backs it", say so and stop; do not imitate it with seals, agency wording or "official" hints.
   What remains is technical transparency and community trust (below).
5. **Persuade with measured numbers that carry their limits.** True and sourced: one real
   quake on 2026-09-24, receptor alert at +18.1 s after origin, about 0.78 s of that added by us
   [V, `docs/STATUS.md` "Proven"]; recovery from a lost host in 63 min, measured in a drill
   [V]; alarms for gateway down or receptor uncovered [V]. Each number must travel with its
   limit: +18.1 s after origin can be after strong shaking has already reached people near
   the epicenter, so it is an alert, not a guarantee of warning time; coverage exists only where
   a receptor exists. Never quote a number without that sentence.
6. **Do not use fear or family-protection outcome appeals** ("protect your family", "seconds
   that save lives"). They are the dominant register for safety products in the markets with
   recent big quakes (Turkey after 2023, Chile, Mexico, Peru), and every one implies an outcome
   we cannot promise. Say so and stop; use the funding and transparency framing instead.
7. **No fabricated social proof.** No invented user counts, downloads, ratings or testimonials.
   Until real numbers exist, the only honest social proof is the measured record above and the
   live coverage state the app already shows.

## Claims: allowed and not allowed

| allowed (true today, with the limit) | not allowed |
|---|---|
| Relays Google's real earthquake alert to your iPhone; added delay measured at about 0.78 s [V] | "Like having a dedicated sensor" (the coordinator refused this, correctly) |
| Subscription helps pay for new receptors, once the spend rule is written [V for cost, `STATUS.md`] | "More sensors near you" unless a receptor near that user exists |
| Shows which receptor covers you, and says plainly when you have none or a late alert [V, app contract] | "Faster / more accurate than X" of any named or unnamed system: not measured against anything |
| Measured record: real quake 2026-09-24, recovery drill 63 min [V] | Redundancy, before a second receptor covers the area |
| Independent app, not affiliated with any government agency [required by `legal-colombia.md`] | "Official", "authorized", agency seals, "endorsed by" anything |
| Paying does not change alert timing or delivery | Any wording that lets a payer infer better protection |

## Why paying users need extra care: rules that already apply

- **Apple 2.3.1(a):** marketing that promotes "content or services that it does not actually
  offer" or a false price, inside or outside the App Store, is grounds for removal [V, Apple
  App Review Guidelines, fetched today]. **3.1.2(c):** before asking anyone to subscribe, describe
  what they get for the price [V]. **2.3.2:** description and screenshots must say if features
  need a purchase [V].
- **Open question, [U]:** 3.1.2(a) says an auto-renewable subscription "must provide ongoing
  value to the customer" [V]. A tier that only funds receptors and gives the payer nothing
  extra might be read as a donation, and Apple may reject it as a subscription. I did not find
  this settled. developer-ios should ask App Review or check the guideline text on gifts and
  tips before any paid-tier build starts. Cost of not checking: a built tier that cannot ship.
- **Misleading-advertising law exists in every market.** Colombia Ley 1480 (already in
  `decision.md`); Mexico Ley Federal de Protección al Consumidor, enforced by PROFECO,
  advertising must be truthful, verifiable and clear [R]; Peru INDECOPI, fines up to 700 UIT
  for misleading advertising [R]; Argentina Ley 24.240 [R]; Turkey Law 6502 [R]; Philippines
  RA 7394, general prohibition on false or misleading advertising [R]; Chile: SERNAC exists and
  polices pricing claims [R], I did not confirm the exact statute text (Ley 19.496 is my
  recollection, [U]). A false safety claim in a paid product is the highest-exposure case in
  all seven. A local lawyer should read final copy per country.

## Per market

Cross-market facts first, since they drive most of the table:

- Institutional trust in Latin America is low across the board: Latinobarómetro 2024 puts
  armed forces at 43%, police 41%, president 37%, congress 24% [R, regional averages]. Country
  satisfaction with democracy differs (Argentina 45%, Chile 39%, Peru about 10%) [R], but that
  is a different measure from trust in a civil-protection agency, so treat it as a rough proxy
  only [U]. Reading: "the government backs it" may persuade less than it seems, which is
  convenient because we cannot say it. That is my inference, not a finding.
- WhatsApp reaches roughly 89-94% of internet users in Mexico, Colombia, Chile, Peru and
  Argentina [R, one vendor synthesis, March 2026]. Recommendation travels by group chat. What
  is forwarded is our own wording, so every claim in shareable copy must survive being pasted
  without its context [U, judgment].
- Every government channel found is free: SASSLA in Mexico is described as public and free
  [R]; Peru's SISMATE reaches phones over the operator network without data or credit [R];
  the Philippines' cell-broadcast system is mandated to be free [R]; AFAD's apps are free [R].
  The paid tier cannot lean on "safety" against free official alternatives, only on
  what it funds.

| market | what makes a safety claim credible there | price sensitivity | official apps' positioning | what we cannot say |
|---|---|---|---|---|
| Colombia | Institutional endorsement is weak-to-mixed [U]; peer trust via WhatsApp [R]; already-known constraint: must not look official | Underbanked, cash-based pockets, carrier billing matters more than cards [R] | Official channels (UNGRD, SGC) free; SNAST bill would make SGC the alerting authority [V, `legal-colombia.md`] | Official status; anything implying SGC/UNGRD backing |
| Mexico | The state system is the reference point and the government-endorsed app is marketed as "the only official one" [R]; SASMEX itself runs through a non-profit [R] | 62% of surveyed subscribers open to more if bundled [R, one vendor survey]; no per-app data found | "Only official", "public and free", shows estimated arrival time, epicenter, expected intensity at your location [R] | "Official"; any arrival-time or intensity-at-your-location promise, we compute neither |
| Chile | Not researched beyond legal context; strong quake culture, and a third-party alert app already leads the market [R] (name intentionally left out); state agency framing is informational | Not researched | State agency offers a hazard-exposure viewer, not a paid or alerting app [R] | Same as Colombia: official status, agency backing |
| Peru | Two official channels compete on trust: IGP app and INDECI cell broadcast [R] | Underbanked; carrier billing and prepaid vouchers matter [R]; low satisfaction with institutions [R] | IGP: monitoring from the national seismic network; INDECI: works with no credit or data [R] | Any claim about reaching people without data; ours needs internet |
| Argentina | No dedicated national seismic app found [R], so no incumbent style to imitate or beat | 30% perception tax added when paying foreign-currency services by card; paying in dollars avoids it [R]; price that looks fixed in USD can feel very different in pesos | Weather-focused official app, not seismic [R] | Anything implying a national alerting authority |
| Philippines | Trust runs through community: Facebook/Messenger groups and barangay-level word of mouth are how informal warnings spread [R]; English is the working language of the official agency alerts [languages.md] | GCash now works as an Apple ID payment method [R], lowering the card barrier; no willingness-to-pay data found | Agency app plus mandated free cell broadcast [R] | Government or agency affiliation; multi-receptor coverage where there is one canary |
| Turkey | After 2023 many people directed help to non-government groups as well as the state agency [R]; the state agency was criticized for slow response [R]; treat this as sensitive and do not use it as a selling point | Inflation above 30% for years (32.11% in June 2026, reported) [R]; the Turkish store is among the cheapest in the world by local price [R]; Apple price changes there are frequent [R]. Review price monthly | AFAD: several free official apps, emergency call, gathering areas [R] | Any comparison to or criticism of the state agency; any "rescue" or emergency-service claim |

For Chile, price sensitivity and credibility norms are marked not researched on purpose: the
searches returned legal and app-landscape material but nothing solid on subscription behavior,
and I will not fill it with a guess.

## Pricing: what I can and cannot say

- I found no reliable per-market willingness-to-pay figure for a safety-app subscription in any
  of the seven. Not researched beyond the directional facts above. I am not proposing price
  numbers. Number-setting needs App Store Connect's own local price points and a real test.
- Directional facts that should shape the test, all [R]: Turkey needs frequent repricing because
  of inflation and a weak lira; Argentina's card users pay a 30% perception on top of the
  converted price; Philippines has a new easy payment path; Colombia and Peru have more people
  without cards.
- Keep the tier low and optional. A small optional support amount with a plain explanation
  fits the funding framing; a premium price fits only if the product actually delivers
  something extra, which today it does not [U, judgment].

## Not researched, and what would change the advice

- Actual price points and conversion by market. Test with a small cohort before any number
  goes on a store page.
- Chile: credibility norms and price sensitivity. Nothing solid found.
- Whether Apple accepts a funding-only subscription (3.1.2(a) "ongoing value"). Ask before
  building.
- Whether real user counts exist yet for social proof. Today none should be claimed.
- Native-speaker review of any store copy per market. The words in `languages.md` are still
  `needs_review`.
- Consumer-law text per country was not read in primary source, only reported. A lawyer should
  read the final copy in each market before launch.

## Sources

- Apple App Review Guidelines, 2.3.1(a), 2.3.2, 3.1.2(a), 3.1.2(c): [developer.apple.com](https://developer.apple.com/app-store/review/guidelines/) [V]
- Project facts: `docs/STATUS.md` (measured record, receptor cost, growth budget),
  `docs/siting-pilot.md`, `docs/decision.md`, `docs/research/legal-colombia.md`,
  `docs/research/culture-and-apple.md`, `docs/research/languages.md` [V]
- Latinobarómetro 2024: [summary, La República](https://www.larepublica.co/globoeconomia/informe-latinobarometro-2024-4029870); [country tables](https://www.latinobarometro.org/documents/LAT-2024/latinobarometro-2024-resultados-por-pais.pdf) [R]
- Latin America subscriptions and payments: [Bango](https://bango.com/reports/subscription-wars-latin-america/); [Bamboo Payment Systems](https://bamboopaymentsystems.com/how-latin-america-really-pays-in-2026-and-why-it-changes-everything-for-global-merchants/) [R]
- WhatsApp penetration: [Mazkara Studio](https://mazkara.studio/en/newsletter/whatsapp-penetration-latin-america-2026/) [R]
- Turkey prices and inflation: [Turkish Minute, July 2026](https://www.turkishminute.com/2026/07/15/turkey-has-worlds-most-expensive-iphone-as-taxes-and-inflation-push-up-tech-prices/); [Adapty](https://adapty.io/blog/fastest-growing-app-markets-2026/); [Mirava](https://www.mirava.io/blog/apple-app-store-price-tiers-how-they-work-2026) [R]
- Turkey 2023 response and trust: [Time](https://time.com/6255634/earthquake-turkey-syria-erdogan-rescue/); [NHESS 2025](https://nhess.copernicus.org/articles/25/2031/2025/) [R]
- Argentina card tax: [Global66](https://www.global66.com/blog/como-afectan-los-impuestos-a-tus-gastos-digitales/); [Impuestito](https://impuestito.org/) [R]
- Philippines payments and community warning: [PAGEONE, GCash on App Store](https://pageone.ph/gcash-is-now-available-as-a-payment-method-for-the-app-store-and-other-apple-services-in-the-philippines/); [University Affairs](https://universityaffairs.ca/news/filipinos-use-facebook-to-warn-of-floods/) [R]
- Official-app positioning: see `culture-and-apple.md` sources (SASSLA, IGP, INDECI, AFAD pages) [R]
- Consumer-law overview: [Legal 500 Mexico](https://www.legal500.com/guides/chapter/mexico-advertising-marketing/); [Peru, OMC Abogados](https://omcabogados.com.pe/en/misleading-advertising-is-severely-punished-in-peru/); [Argentina, PAGBAM](https://pagbam.com/articles/consumer-protection-laws-and-regulations-argentina-2024/); [Turkey](https://istanbullawyerfirm.com/blog/consumer-protection-laws-in-turkey); [Philippines RA 7394](https://lawphil.net/statutes/repacts/ra1992/ra_7394_1992.html) [R]

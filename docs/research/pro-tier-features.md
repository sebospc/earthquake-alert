# Pro tier, indie-app framing: evaluation per market

2026-09-26, investigator. Final direction per the coordinator: B2C only, no B2G, no
donation/crowdfunding framing. `sponsor-your-region.md` is dropped from further work; this doc
does not build on it. Model evaluated: alerts free for everyone always, non-negotiable; a
normal Pro-tier SKU (Watch companion, widget, quake history/stats, multi-location tracking)
framed as supporting development and paying for real product features, not as a cause.

Tags: **[V]** read/fetched directly this session. **[R]** reported by a secondary source, not
re-derived. **[U]** unverified or my judgment. Not legal advice.

**Correction (2026-09-26, after coordinator review):** "multi-location tracking" below means
one thing only: watching a **saved place you are not currently at** (checking on a family
member's city while you're abroad). It is not, and must never be described as, "the app knows
where you are" — that's live coverage following the phone's real GPS position as it moves
(RelayCore's SubscriptionEngine/ReceptorChooser), which is core, already built, free, and not
part of this evaluation. The free live-tracking behavior is the headline pitch ("wherever you
are right now, you're covered"). The diaspora finding below (§2) is about the paid, saved-place,
not-currently-there case only, and stays a backlog nice-to-have, not the core sell.

## Recommendation

1. **This framing does not have the risk the donation framing had.** "Pay for a Pro tier that
   unlocks real features, support development" is the default global App Store pattern —
   the same shape as countless weather, fitness and utility apps already sold in all seven
   markets, on the same App Store, in the same currency-localized way. I found no market in
   this set where this pattern reads as unusual, and no cultural vocabulary problem like the
   one crowdfunding had (no "vaquita"-style translation needed, because nothing about it is
   being asked to translate — it's not a local practice, it's a store-wide default). Confidence
   here is lower than a directly-sourced local finding, since it's an absence-of-objection
   argument, not a positive confirmation from local sources — tagging the overall claim [U],
   but a low-risk one.
2. **Multi-location tracking — a saved place you are not currently at, not your own live
   position — is the one Pro feature with real, sourced, locally-differentiated pull, and it is
   strongest in Mexico, Turkey and the Philippines.** This is a backlog nice-to-have, not the
   core sell: the core, free, already-built pitch is that coverage follows the phone's real
   live position as it moves. All three have large
   populations living abroad who send money home and stay attached to home-country news:
   Mexico's diaspora is about 11.6 million [R], Turkey's is about 7.5 million (3 million in
   Germany alone) [R], and the Philippines' economy runs on this pattern explicitly —
   remittances hit $35.63 billion in 2025, 7.3% of GDP [R], from roughly 2.19 million
   overseas Filipino workers alone (the wider overseas Filipino population, including
   permanent residents, is larger than this OFW-specific figure) [R]. "Track quake activity
   for your family's location while you're abroad" is a real, honest, non-safety-claim pitch
   for a paid feature in these three markets specifically. Colombia (about 3.7-5 million
   abroad) and Peru (about 1.7 million) [R] have the same logic at smaller scale. Argentina
   (about 1.2 million) [R] and Chile (about 644,000, and unusually, over 200,000 of those are
   in Argentina, not overseas in the global-diaspora sense) [R] have the weakest version of
   this argument in the set.
3. **Watch companion and widget are safe, uncontroversial, low-risk sells everywhere**, and I
   found nothing suggesting either reads badly in any of the seven markets. What I could not
   confirm is how many users in each market actually own an Apple Watch to buy the companion
   for — see §2 below, the ownership numbers found are directional at best.
4. **No price point.** Same finding as the two prior docs in this set. Nothing found this
   session narrows it further. Do not guess a number from this research; test one.
5. **Argentina's data cost and card-tax facts (already in `positioning-and-pricing.md`) matter
   more for this model than for the dropped ones**, because a Pro tier that adds real product
   surface (history sync, multi-location background checks) uses more data than a bare alert
   relay. Argentina has the highest per-GB mobile data cost found in this set, $0.98/GB [R],
   against Colombia's $0.20/GB [R] at the cheap end. Keep any history/multi-location feature
   light on background data use, or make sync opt-in/Wi-Fi-only, regardless of market — this
   is a design note, not a blocker, and it isn't something I can decide from research alone.

## 1. Does "support independent development" framing land as normal, or as begging?

Short answer: found no evidence of a problem, in any of the seven markets, but this is an
absence-of-finding, not a positive local confirmation, so it stays [U] overall.

The reasoning: donation/crowdfunding framing needed local cultural translation because it's
asking someone to give money with nothing bought in return, and how that reads varies sharply
by market (see the "vaquita"/Vaki precedent that made this a good idea in Spanish-speaking
markets, versus the Turkey/Philippines solicitation-permit-law problem the same framing ran
into — both retired findings, cited here only to explain why this question needed asking at all
last time and needs a different answer this time). A Pro-tier IAP is different in kind: it's a
transaction with something delivered (a widget, a Watch app, a feature), sold through the same
App Store mechanism used by weather, fitness, and utility apps in every one of these seven
countries already. I did not find a single market-specific objection to this pattern, a
market where "Pro" tiers read as offensive, or a market lacking any precedent for paid utility
apps (Turkey's own top-weather-apps charts show paid tiers priced in lira, for example [R]).
That absence is itself informative, but it is not the same as a local source saying "this is
normal here" — no such source was found either, because this isn't really a country-specific
question the way donation framing was.

## 2. What non-safety features would feel worth paying for

- **Multi-location tracking (saved place, not current position), tied to diaspora size**: see
  Recommendation §2 and the correction at the top of this doc. Numbers, all [R]:

  | market | population abroad | what it means for this feature |
  |---|---|---|
  | Mexico | ~11.6 million | Strongest diaspora pull in the set |
  | Turkey | ~7.5 million (3M in Germany) | Second-strongest; large, concentrated, well-documented community |
  | Philippines | ~2.19 million OFWs (temporary workers only; total overseas Filipino population, incl. permanent residents, is larger and not pinned down this session) | Economically central to the country — remittances are 7.3% of GDP — so "watching home" is a deeply normal daily habit, not a niche one |
  | Colombia | ~3.7-5 million | Real pull, smaller than Mexico/Turkey |
  | Peru | ~1.7 million | Real pull, smaller still |
  | Argentina | ~1.2 million | Weakest pull in the set |
  | Chile | ~644,000, with an unusual pattern: 200,000+ of those are in neighboring Argentina, not overseas in the remittance-economy sense | Weakest pull, and the composition of the diaspora (mostly regional, not global) makes the "watching from far away" pitch land differently than in Mexico or Turkey |

- **Watch companion**: three [R] figures for Apple Watch ownership surfaced (Chile 22.8%,
  Colombia 19.7%, Argentina 17.9%, Philippines 14.9%), all from a single aggregator site whose
  methodology I could not verify (unclear whether this is % of population, % of iPhone owners,
  or % of smartwatch owners specifically) [R, low confidence, flagging rather than trusting].
  No figures found for Mexico, Peru or Turkey. Treat these numbers as directional only; do not
  size a launch decision on them without checking Apple's own regional sales data or a better
  source.
- **Quake history/stats**: not researched as a distinct local preference question this session.
  No market-specific signal found either way. This is a reasonable default utility-app feature
  everywhere and I have nothing country-specific to add to it.
- **A feature I did not find any evidence for, and flag as speculative if it comes up
  elsewhere in the project**: aftershock-specific tracking as a Turkey-specific pull, given how
  recent and severe the 2023 earthquakes were there. This is a plausible inference, not a
  researched finding — I did not find a source confirming Turkish users specifically want
  aftershock history more than users elsewhere. Flagging as [U], not recommending it be acted
  on without a real signal.

## 3. Price point

Not findable, third time this comes up across the three docs in this set
(`positioning-and-pricing.md`, `sponsor-your-region.md`, this one). Checked again this session
from the indie-Pro-tier angle specifically (weather-app pricing pages, Turkish App Store
listings) and found individual app prices, not a market-level willingness-to-pay figure for a
utility-app subscription. Not proposing a number. What should still shape a real price test,
all [R], carried over because they remain the most concrete facts found across all three docs:
Turkey's chronic inflation means lira prices need frequent review; Argentina's 30% card
perception tax on foreign-currency digital purchases inflates the effective price; Colombia,
Peru and parts of Mexico have meaningful unbanked/underbanked populations.

## Not researched, flagged rather than guessed

- Real Apple Watch ownership by market: the four figures found are single-source and
  methodology-unclear; Mexico, Peru and Turkey have no figure at all.
- Any local feature idea beyond multi-location tracking, Watch, widget and history — this
  session did not turn up a locally-specific feature request or complaint about existing
  earthquake apps to build from.
- Whether "support development" language should be translated literally per market or kept in
  English-derived App Store convention (many apps keep Pro-tier marketing language in English
  even in localized stores) — not researched.
- Total overseas Filipino population beyond the 2.19M OFW (temporary-worker) figure; the
  broader figure (including permanent residents and citizens abroad) exists in Philippine
  Statistics Authority data but was not pinned down precisely this session.

## Sources

- Diaspora/remittances: [BBVA Research, remittances to Argentina/Peru/Colombia](https://www.bbvaresearch.com/en/publicaciones/latam-remittances-to-argentina-peru-and-colombia/); [Rio Times, Mexico remittances 2026](https://www.riotimesonline.com/mexico-remittances-2026-structural-demographic-decline/); [Wikipedia, Emigration from Colombia](https://en.wikipedia.org/wiki/Emigration_from_Colombia) [R]
- Philippines OFW/remittances: [Gulf News, Philippine remittances 2025](https://gulfnews.com/world/asia/philippines/philippine-remittances-hit-record-3563b-in-2025-1.500445849); [BatasKo, OFW Statistics Philippines 2026](https://batasko.com/data/ofw); [Wikipedia, Overseas Filipinos](https://en.wikipedia.org/wiki/Overseas_Filipinos) [R]
- Turkish diaspora: [Center for American Progress, Turkish Diaspora in Europe](https://www.americanprogress.org/article/turkish-diaspora-europe/); [FMC Group, Turkish people in Germany](https://fmcgroup.com/turkish-people-in-germany/) [R]
- Chilean diaspora: [Wikipedia, Chileans](https://en.wikipedia.org/wiki/Chileans) [R]
- Apple Watch ownership by country: [Coolest Gadgets, Apple Watch Statistics](https://coolest-gadgets.com/apple-watches-statistics/) [R, single source, methodology unclear]
- Mobile data cost per GB: [Mappr, Mobile Data Pricing by Country 2026](https://www.mappr.co/mobile-data-pricing-by-country/) [R]
- Turkey weather-app App Store pricing: [Appfigures, Top Weather Apps Turkey](https://app.appfigures.com/top-apps/ios-app-store/turkey/iphone/weather) [R]
- Cross-referenced this project's own: `docs/research/positioning-and-pricing.md`,
  `docs/research/sponsor-your-region.md` (superseded, kept for record only per the
  coordinator's instruction, not built on further), `docs/research/culture-and-apple.md`,
  `docs/research/languages.md`

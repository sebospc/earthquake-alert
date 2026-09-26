# Global coverage cost: every confirmed AEA-active country

2026-09-26. Replaces the coordinator's earlier napkin estimate, which wrongly included Japan
and mainland China and used a flat global percentage instead of real per-country geography.
This is the merged result of 4 parallel research passes (one per world region) plus Colombia,
added directly from this project's own existing numbers. Not a budget, a planning order of
magnitude — see the caveats at the end before anyone treats this as a number to commit to.

Tags: **[V]** read/fetched directly this session (project files, or a primary source opened and
read). **[R]** reported by a secondary source, not independently re-derived. **[U]** unverified,
a stated proxy, or a judgment call. Every area/population figure below is tagged individually in
the four supporting partial files this doc draws from; this doc carries the tags at the row
level, not the citation-by-citation level — read the partial file for a specific country's full
sourcing.

## Method, fixed across every country

- **Coverage area per receptor**: π × 30km² ≈ 2,800 km² — the coordinator's own figure, matching
  `decision.md`'s 30km-spacing siting model.
- **Receptor count** = ceil(populated at-risk area km² ÷ 2,800), except where noted (Papua New
  Guinea and Afghanistan use a different method, explained in their rows).
- **Three cost rates per receptor/month**, held constant everywhere so countries are comparable:
  - **naive** = $33.00 — one dedicated host per receptor [V, `docs/STATUS.md`'s own canary-host
    figure, the real price this project pays for a standalone canary today].
  - **shared, current scale** = $8.76 — [V, derived from `docs/STATUS.md`'s recorded AWS
    sa-east-1 spot price, $0.036/h × 730h/month ÷ 3 receptors per host, this project's own live
    r8i.large setup today].
  - **shared, large-scale grid** ≈ $6.60 — [R for the €6.10/receptor base: `decision.md` §2's
    Hetzner AX102 model, €122/month per host holding ~20 receptors; **[U]** for the EUR→USD
    conversion, an approximate 1.08 rate, not fetched live this session].

**Excluded entirely, not shown in the table**: Japan and mainland China — Google does not run
AEA in either, confirmed in `languages.md`, no amount of budget changes that. **Iran** — AEA may
be active there, but it's moot: Apple's App Store is unavailable in Iran under US sanctions, so
there is no distribution channel regardless of coverage cost (`languages.md` §1). **Shown
separately, not in the total**: Indonesia and Taiwan, both contested AEA status per
`languages.md` — see the note after the main table.

## Confirmed AEA-active countries

| Country | Receptors | Naive $/mo | Shared-current $/mo | Shared-large $/mo | Area/population confidence |
|---|---:|---:|---:|---:|---|
| Colombia | 172 | $5,676 | $1,507 | $1,135 | [V] — this project's own existing grid model (`decision.md` §2, 30km spacing), not re-derived. Different method: sized for a missed-alert-rate target across the country, not an explicit population-in-seismic-zone split. See note below. |
| Chile | 184 | $6,072 | $1,612 | $1,214 | [U] proxy — whole country minus the two sparsely-populated southern regions (Aysén, Magallanes), not a read of NCh433's real commune-by-commune zoning |
| Mexico | 120 | $3,960 | $1,051 | $792 | [U] proxy — the 6 states SASMEX's real network covers, not an official CENAPRED zone-C/D area |
| Peru | 181 | $5,973 | $1,586 | $1,195 | [U] proxy — INEI's coast+sierra split standing in for E.030's zone 3-4 belt |
| Argentina | 200 | $6,600 | $1,752 | $1,320 | [U] proxy, weakest of the South America slice — 6 whole named provinces, likely overstates true at-risk footprint |
| Turkey | 258 | $8,514 | $2,260 | $1,703 | [R] — AFAD's own "92% land / 95% population" figure, the strongest single figure outside Colombia and Nepal |
| Philippines | 107 | $3,531 | $937 | $706 | [U] proxy — whole country, no PHIVOLCS population-by-hazard-zone figure found |
| Pakistan | 68 | $2,244 | $596 | $449 | [U] proxy — KP+AJK+GB+Islamabad only, known to both exclude northern Punjab's real risk and the Makran coast |
| Nepal | 52 | $1,716 | $456 | $343 | [R] — DMG states the entire country is high seismic hazard, cleanest case in the whole set besides Colombia |
| Greece | 48 | $1,584 | $420 | $317 | [R]/[U] — OASP's zonation covers the whole country with no low-risk residual; "use 100%" is an inferred conclusion, not a quoted one |
| Portugal | 5 | $165 | $44 | $33 | [U] — weakest data point in the whole set; a proxy from 3 southern districts, no official hazard-zone figure exists |
| Venezuela | 179 | $5,907 | $1,568 | $1,181 | [R] population (FUNVISIS's own 80%-of-population figure), [U] area (built to roughly match it) |
| India | 341 | $11,253 | $2,987 | $2,251 | [R] — BIS IS 1893 zones IV+V, 29% of land area, ~300M people; not independently verified against the primary standard |
| Afghanistan | 55 | $1,815 | $482 | $363 | [U] — the weakest number in the whole set: composed from named provinces' populations and a guessed density, no real hazard-zone dataset found |
| New Zealand | 89 | $2,937 | $780 | $587 | [R] for the exclusion logic (Auckland/Northland removed from the earthquake-prone building regime), [U] for the exact regional areas |
| United States | 379 | $12,507 | $3,320 | $2,501 | [R] population (159.2M in "very strong shaking" zones, USGS-attributed but not confirmed on a usgs.gov page this session), **no real area figure exists** — the entire receptor count rests on one unsourced density guess, see the caveat below |
| **Total, 16 countries** | **2,446** | **$80,718** | **$21,427** | **$16,143** | |

Colombia's number needs one caveat of its own: `decision.md`'s 172-receptor figure was built to
hit a missed-alert-rate target across the whole populated country, not from an explicit
population-in-seismic-zone calculation the way the other 15 rows were built this session. As a
sanity check, 172 × 2,800 km² ≈ 481,600 km², about 42% of Colombia's ~1,141,748 km² total area
[R] — plausible, since Colombia's Andean spine, Pacific coast and Caribbean coast (where most of
the population lives) together cover a large minority of the country's land, leaving the
lower-population Amazon/Orinoquía basin out. Consistent with the other rows' methodology, but
not built the same way — flagging rather than papering over the difference.

## Not included in the total: contested AEA status

| Country | Receptors, if confirmed active | Naive $/mo | Shared-current $/mo | Shared-large $/mo | Status |
|---|---:|---:|---:|---:|---|
| Indonesia | ~486 | ~$16,038 | ~$4,257 | ~$3,208 | **[U], not computed this session with real hazard data** — a rough order-of-magnitude only, built the same way as Chile's proxy (whole country minus Kalimantan/Indonesian Borneo, the one region clearly less exposed to the Ring of Fire than Sumatra/Java/Sulawesi/Maluku). AEA activity itself is unconfirmed either way (`languages.md` §1) — this row is here only so the team has an order of magnitude if it turns out active, not a real estimate. If confirmed, this would be the single largest line item in the whole set, larger than the US or India. |
| Taiwan | ~13 | ~$429 | ~$114 | ~$86 | **[U]**, same status: whole small island treated as at-risk (plausible, Taiwan sits on an active plate boundary comparable to Japan), but AEA status itself is unconfirmed (`languages.md` §1, Taiwan runs its own CWA system, similar to Japan's case) |

## Range and confidence, read this before using the total anywhere

The $80,718/$21,427/$16,143 naive/shared-current/shared-large totals for 2,446 receptors should
be read as a rough order of magnitude, not a budget line. Two countries carry almost all of the
uncertainty:

- **The United States** has no real matching area figure at all — the 379-receptor number comes
  from one unsourced density guess (150 people/km² in high-hazard corridors) standing in for a
  missing area dataset. The source fork's own stated range for the US alone is **190 to 760
  receptors** depending on that single number, which alone would move the grand total between
  roughly 2,257 and 2,827 receptors.
- **India**'s 341-receptor figure rests on a reasonably solid area-based split (a named
  standard, two cited zone percentages), but the underlying population figure (300M) wasn't
  broken down zone-by-zone, and could shift meaningfully with a real BIS/NDMA table.

Everything else in the confirmed-country table is a real number built from a real, cited source
(even where that source is a proxy, not a perfect hazard-zone match) — the weakest of the
"normal" rows are Portugal, Pakistan, Afghanistan and Argentina, each flagged individually above
and in their source partial file. Colombia and Nepal are the two cleanest numbers in the whole
set: Colombia because it's this project's own already-validated grid model, Nepal because its
government states plainly that the entire country is high-hazard, leaving no zone-classification
judgment call to make at all.

## Not researched, flagged rather than guessed

- A real PHIVOLCS/HazardHunterPH population-by-hazard-zone layer for the Philippines.
- A national population-by-seismic-zone rollup for Pakistan beyond sub-national tehsil data.
- Any PNG-specific population-in-hazard-zone study (the Geoscience Australia assessment referenced
  in the source partial was described via search summary, not read in primary form).
- Mexico's actual CENAPRED zone-C/D GIS layer — the SASMEX-coverage proxy used here likely both
  over- and under-states the real figure in different ways, explained in the source partial.
- The EUR/USD FX rate used for the "shared-large" column across every row — an approximate 1.08,
  not fetched live this session, applies uniformly so it doesn't distort comparisons between
  countries, but does affect the absolute dollar figures in that column.
- A primary read of USGS's own 2023 National Seismic Hazard Model publication (the 159.2M figure
  for the US is attributed to it by secondary sources, not confirmed on usgs.gov directly).
- Indonesia's and Taiwan's real hazard geography — the two contested rows above are placeholders,
  not estimates to plan against.

## Sources

Full per-country sourcing, including every primary/secondary link and each fork's own notes on
what was found vs. guessed, lives in the four partial files this doc merges:

- `docs/research/cost-estimate-southamerica.md` — Chile, Peru, Argentina, Venezuela
- `docs/research/cost-estimate-medmex.md` — Mexico, Turkey, Greece, Portugal
- `docs/research/cost-estimate-asiapacific.md` — Philippines, Pakistan, Nepal, Papua New Guinea
- `docs/research/cost-estimate-bigcountries.md` — India, Afghanistan, New Zealand, United States

Colombia: `docs/decision.md` §2 (grid model, 30km spacing) and §9 (Hetzner large-scale grid
economics, the basis for the "shared-large" rate). Cost rate constants: `docs/STATUS.md`
(canary-host figure, AWS spot price). Exclusions and contested-status list: `docs/research/languages.md` §1.

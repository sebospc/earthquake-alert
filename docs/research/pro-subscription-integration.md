# Pro subscription: StoreKit 2 and offer codes

2026-09-26, developer-ios. This is research only; nothing is built. It covers the StoreKit and
App Store Connect product side. APNs, certificates and TestFlight are in devops'
`docs/ops/apple-infra.md`. Scope for Pro v1 comes from `pro-tier-features.md`: a Watch app, a
widget and quake history. Alerts stay free for everyone.

Tags: **[V]** read in Apple's own page this session. **[R]** from a secondary source, not
checked against Apple. **[U]** my judgment or not verified.

## Recommendation

1. **No backend for Pro v1.** StoreKit 2 verifies transactions on the phone: every
   `Transaction` comes as a JWS signed by Apple, and `VerificationResult` checks it. All three
   Pro features run on the device, so the gateway does not need to know who pays. That keeps
   payment data off our servers and out of the Ley 1581 scope. [U]
2. **Buying Pro needs no consent step of its own, and Pro is independent of the alert
   consent.** Apple runs the payment. We receive nothing personal unless we send it somewhere
   ourselves, which point 1 avoids. Two things do touch the consent flow:
   - "Retirar consentimiento" does not cancel an Apple subscription. The withdraw dialog must
     say so and offer `manageSubscriptionsSheet`; otherwise the user keeps paying for an app
     they think they left.
   - If quake history is ever synced to a server, that is new data processing and needs the
     consent text and the privacy manifest updated first.
3. **Disaster-relief free Pro works with custom offer codes created ahead of time in App
   Store Connect.** The server cannot mint them. The account holder publishes a code after a
   quake. No gateway change is needed for the basic version. Details in §3.
4. **Building can start before the Apple account exists.** A local `.storekit` configuration
   file runs the whole purchase, renewal, refund and offer-code flow in the simulator and in
   XCTest (`SKTestSession`). Only the real App Store Connect products need the account. [U,
   standard Xcode feature, not tried in this project yet]

## 1. StoreKit 2 setup

### App Store Connect (needs the account)

- One subscription group, "Pro", with two auto-renewable products: monthly and yearly. The
  price is still open, see `pro-tier-features.md` §3.
- Guideline 3.1.2(a): a subscription "must provide ongoing value", lasts at least seven days
  and works on all of the user's devices. [V] A Watch app, a widget and a growing quake
  history qualify as ongoing value. The iPhone and the Watch share one Apple Account, so the
  same entitlement covers both. [U]
- 3.1.1: unlocking features must go through in-app purchase. [V] So free Pro after a disaster
  has to be an Apple offer code, not a flag we flip on our server.
- Family Sharing is a per-product switch. Turning it on is cheap goodwill, but
  `Transaction.currentEntitlements(for:)` then returns more than one entitlement. [V, WWDC25]
- Each product needs a localized display name and description in es, en and tr. It needs the
  same `needs_review` process as the app strings.

### Code layout

| where | what |
|---|---|
| App target, new `Store.swift` | `Product.products(for:)`, purchase through `@Environment(\.purchaseAction)` (iOS 18.2+ needs a UI context; the SwiftUI environment action handles it [V]), a `Transaction.updates` listener started at launch, `AppStore.sync()` for "Restaurar compras" |
| App target, paywall | `SubscriptionStoreView` for the Pro group. Apple's view already shows price, period, terms and restore, which covers the 3.1.2 disclosure rules for free. A custom paywall is more code and more review risk. |
| RelayCore | Only `ProEntitlement`: a pure function from "verified transactions seen" to on/off, plus its XCTest. RelayCore stays free of StoreKit imports so it keeps testing on macOS without a StoreKit session. |
| App Group (already exists) | The app writes the entitlement there. The widget reads it instead of asking StoreKit itself. [U: StoreKit also works in extensions, but one writer is simpler to reason about] |
| Watch app | Its own `Transaction.currentEntitlements` check (same Apple Account). [U] |

### Verification

- **On the phone only**, through `VerificationResult`: `.verified` unlocks, `.unverified`
  does not. For v1 there is no App Store Server API and no server notifications.
- Revisit this when a Pro feature needs the gateway, for example multi-location watching,
  which is backlog. Then the move is App Store Server Notifications V2 to the gateway plus
  `appAccountToken`, and that changes the privacy manifest and the consent text.
- Refunds and expiry arrive through `Transaction.updates` and through `revocationDate` and
  `expirationDate` on the transaction. `ProEntitlement` must turn Pro off on both.

## 2. Offer codes: how they work

From Apple's "Set up offer codes" page [V], unless tagged otherwise:

- **Two kinds.** One-time use codes are unique strings, 500 to 25,000 per batch, and expire
  at most 6 months after creation. Custom codes are one readable string (e.g.
  `SISMOAYUDA`) that many people redeem; the expiry and the redemption cap are both optional.
- **Limits.** 1,000,000 codes per app per quarter, shared across all subscriptions. At most 10
  active offers per subscription. One redemption per customer per offer.
- **Who can redeem.** Chosen per offer from new subscribers (never subscribed in the group),
  existing subscribers and expired subscribers. The choice cannot be edited later; changing
  it means a new offer.
- **No auto-renewal.** An offer can be set so the subscription does not renew after the free
  period. This option matters for relief, see §3.
- **Delay.** Up to 1 hour after creation before a code can be redeemed. API-generated
  one-time codes are a background job on Apple's side, so they don't appear immediately
  either. [R]
- **Who creates them.** The App Store Connect website or the App Store Connect API. [V] The
  API needs an App Store Connect API key with the right role. Our server cannot mint a valid
  code on its own.
- **Redemption.** The user enters the code in the in-app sheet (SwiftUI `offerCodeRedemption`
  or `AppStore.presentOfferCodeRedeemSheet()`), in the App Store, or through a redemption
  link. A user without the app is asked to install it first. [V] The result reaches the app
  through `Transaction.updates`, the same listener as a normal purchase. [V]
- **Promotional offers are different.** They are signed by our server (JWS, App Store Server
  Library, back-deployed to iOS 15 [V, WWDC25]) and are for current and lapsed subscribers
  [R]. They don't fit relief, which is mostly for people who never subscribed.

## 3. Disaster-relief free Pro: how it would run

### Before any quake (once, after the account exists)

1. Create a subscription offer "Ayuda sismo" on the yearly product:
   - free for a fixed period, for example 3 months;
   - eligibility: new and expired subscribers;
   - auto-renewal off, so nobody is charged by surprise after the free period.
2. Create one custom code for it in App Store Connect, keep it deactivated and unpublished.
   Pre-creating avoids the 1-hour delay and the API job at the worst moment.

### After a real quake

1. The user decides and activates the code in App Store Connect. That takes a few minutes,
   with no deploy and no backend.
2. Distribution, cheapest first:
   - (a) The redemption link in the app's own channels and on social media. No code change.
   - (b) An in-app "Canjear código" row in Coverage that opens the system redemption sheet.
     It is about 5 lines, and worth building with Pro v1 anyway.
   - (c) A banner in the app for users in the affected cells. This needs a field in the
     gateway's `/status` answer, which is the gateway team's call.
3. Deactivate the code when the relief window ends.

### Limits and risks

- **Not regional.** Anyone who gets the string can redeem it once. Accept this, since the
  cost is one free Pro period per person, or switch to one-time codes and hand them out
  through local partners. Offer codes may also be limited to countries or regions. [U, not
  confirmed on Apple's page]
- **One code per offer per person.** A second disaster needs a new offer, and there are at
  most 10 active offers per subscription, so deactivate old ones.
- **Not through the alert channel.** Sending the code as a push over the life-safety
  channel mixes promotion with alerts. Guideline 4.5.4 limits promotional push to users who
  opted in. [U: recalled, not re-read this session] It also teaches people that an
  earthquake push can be marketing.
- **Framing.** `positioning-and-pricing.md` rules out safety claims for the paid tier. The
  message has to read "Pro gratis por 3 meses para la zona afectada", never anything about
  better or faster alerts.
- **Existing Pro subscribers.** They are not the target, so they are left out of the
  eligibility. How Apple applies a code to someone who is already subscribed was not
  checked. [U]

## 4. Regional relief banner (approved 26-sep, scoped, not built)

Blocked on the real offer code, which needs the Apple account. The gateway side belongs to
developer; this is the proposal for `docs/ios-contract.md`, not a change to it.

### The /status field

A top-level `relief` array in `GET /status`, the same answer for every phone:

```json
"relief": [{
  "id": "2026-10-cali",
  "until": "2026-12-31T23:59:59Z",
  "area": { "lat": 3.45, "lon": -76.53, "radius_km": 150 },
  "redeem_url": "https://apps.apple.com/redeem?ctx=offercodes&id=<app id>&code=SISMOAYUDA"
}]
```

- **Why an area, not grid cells.** A 150 km radius is about 580 of the 0.1° demand cells. A
  cell list is long, and every relief means a big hand-edited list. A center and a radius is
  three numbers, and the phone already computes distances (`ReceptorChooser`).
- **Why the phone filters.** `/status` stays one public answer and the phone checks its own
  position against the area. Nothing about the phone is sent, so there is no new data for
  Ley 1581. A server-side check would need the phone's cell on every `/status` call.
- **The code in a public answer is fine.** Custom codes are not secret anyway, see §3
  "Not regional". The area only decides who sees the banner, not who can redeem.
- **The URL form is unverified.** `redeem_url` needs checking against the real App Store
  Connect link once the offer exists. [U] Sending the full URL keeps the app from building it.
- **Who sets it.** The gateway reads it from a small JSON file (like `sensors.json`), re-read
  without a restart. The account holder activates the code in App Store Connect first, then
  the file gets the entry. An expired entry (`until` before the server's `now`) is ignored
  by the phone even if nobody removes it.

### In the app

- **One neutral row in Cobertura, under the coverage state.** It is never on the alert
  screen and never above the alert state. The text is "Pro gratis por un tiempo para la zona
  afectada", with no safety claim (`positioning-and-pricing.md`). The row opens `redeem_url`,
  and the user can close it; the app remembers that per `id`, only on the phone.
- **Shown only when all of these hold:** the phone's last known position is inside the
  area, `until` is after `/status`'s `now`, and `ProEntitlement.isActive` is false.
  Without location permission, the app uses the center of its last demand cell.
- **No push.** The row appears the next time the user opens the app. Relief is not
  urgent, and the alert channel stays alerts only (§3).
- **Life-safety guard.** `relief` is decoded separately from `sensors`. A missing or
  malformed `relief` must never break the coverage state; it is simply ignored. The test is a
  `/status` answer with a broken `relief` that still gives the right coverage state.
- **Text.** es, en and tr, marked `needs_review`, through `tools/translations.py` like the
  rest.

### Size when built

- App: about 60 lines. `Relief` decoding and a pure `ReliefBanner.shouldShow(position:,
  now:, pro:, dismissed:)` in RelayCore, with tests; one row in `CoverageView`.
- Gateway: the file read and the field, owned by developer. QA reviews both.

## Open questions for the user

- Price and trial for the monthly and yearly products (pending from `pro-tier-features.md`).
- Whether Family Sharing is on.
- Which relief period to pre-create: 1, 3 or 6 months.
- ~~Whether distribution (c), the in-app regional banner, is wanted.~~ Approved 26-sep, scoped in
  §4.

## Sources

- Apple, Set up offer codes: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-offer-codes
- Apple, Supporting offer codes in your app: https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app
- Apple, WWDC25 "What's new in StoreKit and In-App Purchase": https://developer.apple.com/videos/play/wwdc2025/241/
- Apple, App Review Guidelines 3.1.1, 3.1.2, 3.2.2: https://developer.apple.com/app-store/review/guidelines/
- Apple, Create one-time use offer codes (API): https://developer.apple.com/documentation/appstoreconnectapi/create_one-time_use_offer_codes
- Adapty, Apple subscription offers guide (secondary): https://adapty.io/blog/apple-subscription-offers-guide/
- Action Potential, one-time codes via API are a background job (secondary): https://www.actionpotential.co/p/the-referral-system-hiding-in-app

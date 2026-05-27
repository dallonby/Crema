# CaffeCrema Labs — App Store Listing

Paste-ready text for App Store Connect.

## App Name (30 chars max)

**CaffeCrema Labs** *(15 chars)* ✓

## Subtitle (30 chars max)

**Espresso, dialed in.** *(20 chars)* ✓

Alternates if you don't love it:
- *Pressure · flow · perfect shot* (29)
- *Profile your espresso machine* (29)
- *Espresso profiling, dialed in.* (30)

## Promotional Text (170 chars, can update anytime without re-review)

Auto-tune any new bean in three guided shots. Live pressure, flow, and weight charts on every pull. Profiles you can share with one tap.

## Description (4000 chars max)

```
CaffeCrema Labs turns your Wendougee LITA espresso machine into a profiling instrument. Author multi-stage pressure and flow profiles, watch every shot in real-time, dial in new beans with the auto-tune wizard, and share your best recipes with the community.

— LIVE BREW VISUALISATION —

A custom chart shows pressure, flow, and pumped volume in real-time as your shot pulls. Ghost lines mark the target profile so you can see exactly where the puck is fighting back. Stage-by-stage breakdown updates as the shot progresses.

— MULTI-STAGE PROFILES —

Design profiles in two ways: a visual node editor where you drag nodes to reshape duration and setpoint, or a list editor with collapsible per-stage cards. Every stage is independently pressure-priority or flow-priority. Preinfusion, soak, extraction, tail — shape it however your bean wants.

— AUTO-TUNE FOR NEW BEANS —

The wizard walks you through three guided shots to dial in a recipe from scratch:
• Tell us about the bean — roast level, drink type.
• We recommend a starting grind + recipe.
• Brew, weigh the cup, get a verdict.
• Smart recommendations for shot 2 (finer or coarser grind, pressure delta).
• Best-scoring shot saves to your library, trimmed to your target brew time.

— PROFILE SHARING —

Upload any profile to the community and get a shareable link — open it in any iPhone or iPad that has CaffeCrema Labs installed and the recipe lands in their library in one tap. Browse what other coffee nerds are brewing. Like profiles you want to try later.

— SHOT HISTORY + FEEDBACK —

Every brew can be saved with a tasting note (sour / balanced / bitter) and yield. We surface targeted tweaks for the next pull.

— REQUIRES —

• A Wendougee LITA-BA, LITA-BR, or DATA-S espresso machine with Bluetooth LE.
• iOS 17 or later, iPadOS 17 or later.

Don't have the machine? Tap the Demo chip in the header to play back a real captured shot — every screen, every animation, fully interactive, no hardware needed.

Built by coffee obsessives, for coffee obsessives.
```

## Keywords (100 chars, comma-separated, no spaces around commas)

```
espresso,coffee,profiling,wendougee,lita,brew,barista,grinder,recipe,puck,bluetooth,profile,shot
```

97 chars — leaves room. App Store keyword search is exact-prefix matching, so include both the singular ("recipe") and any plural the user might search separately.

## Category

Primary: **Lifestyle**
Secondary: **Food & Drink**

(Set in App Store Connect → App Information → Category.)

## Age Rating Questionnaire

All answers are **None / No**:
- Cartoon or fantasy violence: None
- Realistic violence: None
- Sexual content: None
- Nudity: None
- Profanity: None
- Alcohol, tobacco, drugs: None *(caffeine isn't asked about)*
- Mature themes: None
- Gambling: None
- Horror themes: None
- Unrestricted web access: No
- Medical/treatment info: No
- User-generated content: **Yes** *(community profile sharing — see below)*
- Social interaction: **Yes**

Resulting rating: **4+**.

### UGC explanation (mandatory if "yes" to user-generated content)

> Users can share brew profiles with the community. Profiles are technical recipes (numerical pressure / flow / time values, equipment name, optional tasting note). The author's display name is shown. We provide moderation tools: report, hide, and account/profile deletion. Inappropriate content can be reported and is reviewed within 24 hours.

⚠️ Note: this commits us to actually having a report/moderation pipeline. Currently we don't — flag this for v0.3.

## Support URL (mandatory)

`https://caffecremalabs.com/support`

(Needs to exist before submission. Even a single-page "email da@byeq.com for support" page is enough.)

## Marketing URL (optional but recommended)

`https://caffecremalabs.com`

## Privacy Policy URL (mandatory)

`https://caffecremalabs.com/privacy`

Privacy policy must cover what the backend collects:
- Apple/Google user id (`sub`) — pseudonymous, never shared
- Display name (user-set, public)
- Uploaded profiles (public when shared)
- Likes / follows (public)

See `docs/privacy-policy.md` for a paste-ready text.

## App Privacy ("Privacy Nutrition Label" in ASC)

Data collected:
- **Identifiers**: User ID (linked to user, used for **App Functionality**)
- **Contact info**: Name (linked to user, used for **App Functionality**)
- **User content**: Other user content (brew profiles, optional notes — linked to user, used for **App Functionality**)

NOT collected:
- Location, health, contacts, browsing history, search history, financial info, sensitive info, photos.

Mark all collected categories as **linked to the user** (since they sign in) but NOT used for tracking, NOT used for third-party advertising.

## Notes for App Review (critical — apps requiring hardware get rejected without this)

```
This app pairs over Bluetooth LE with the Wendougee LITA family of espresso machines (LITA-BA, LITA-BR, DATA-S). The reviewer will not have access to the hardware.

To evaluate the full UX without a machine:

1. Launch the app. By default, Live mode shows the empty-state "Connect" CTA — this is normal without a paired machine.

2. Tap the small "Demo" chip at the top-right of the header. The app switches to Replay mode and plays back a captured real shot, exercising every screen: the live chart with pressure/flow/volume curves, ghost-line target overlays, metric HUD, stage timeline, and playback controls.

3. Profiles are fully accessible without hardware. Tap "Classic Espresso" in the header to open the library. Tap "..." on any profile → Edit to see both the visual node editor and the list editor.

4. The Auto-tune feature requires a machine to actually brew — its UI screens (bean input, recipe, prep, suggest, complete) are not reachable without a paired LITA. The wizard's intent is documented in this app's description.

5. Community sharing requires Sign In with Apple. Anonymous browse is available via the Community button in the profile library footer.

The app's purpose is technical brew profiling — there is no in-app purchase, no subscription, no third-party tracking.

Test account (not required, but provided for thoroughness):
  Apple ID: <leave blank — Sign In with Apple needs the reviewer's own ID>

Contact: da@byeq.com
```

## Demo Account

Sign in with Apple doesn't need a demo account (reviewer uses their own Apple ID). Leave the demo-account fields blank in ASC; in **Notes for Review**, mention this explicitly.

## Build to attach

Once portal capabilities are enabled and we upload, attach build **0.2 (7)** or higher.

## Pricing

**Free**. No IAP, no subscription.

## Availability

All territories (default).

## Categories of follow-up after submission

- ASC review takes 24–72h typically.
- Apple may reject for: missing privacy policy, broken demo flow, UGC moderation gap.
- We're at high risk for the UGC moderation rejection — see flag above. Recommend either (a) disable community uploads in v0.2 + add in v0.3 once moderation lands, or (b) ship with very basic email-based moderation ("report → email us") and an in-app block button.

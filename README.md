# Crema

A native client for the Wendougee LITA-BA / LITA-BR / DATA-S espresso machines, built for coffee nerds who want to author, share, and run pressure / flow / weight profiles.

Driven by the reverse-engineered protocol in [LitaLite](https://github.com/dallonby/LitaLite).

**Status:** iOS / iPadOS / macOS in active development. Live BLE connection, real-time pressure / flow / volume charting, multi-stage profile authoring, **auto-tune for new beans**, and **community profile sharing** with cross-platform Sign-In-with-Apple + Google. Android port planned (the backend already speaks Google identity).

## Features

### The hero — live brew visualization
- Real-time chart of pressure, flow, and pumped volume against the target profile (ghost setpoint lines for each stage).
- Stage labels with live setpoints float over the curve at full size (iPad / macOS).
- Metric HUD with elapsed time, pressure, flow, and volume.
- Demo mode: replay a captured shot against its real-shape profile when no machine's connected.

### Profile authoring
- **Visual node editor** — drag node-per-stage to reshape duration + setpoint live. Each stage can be pressure- or flow-priority.
- **List editor** — classic form view with collapsible per-stage cards, reorder, duplicate, delete.
- Multi-stage (more than 3, with pauses / waits between stages).
- Optional grinder settings saved on the profile (size + RPM + single-dose).

### Auto-tune — the USP
A 7-step wizard that dials in a new bean from scratch in ≤3 guided shots:
1. **Bean** — name, roast, drink type (espresso vs milk).
2. **Recipe** — dose, target yield, target brew time, ratio.
3. **Prep** — recommended grind + dose + checklist. "Set Grinder" pushes the recipe's grind size to the paired grinder via FF55.
4. **Brewing** — live chart + "Stop when cup hits Xg" CTA (the machine's volume reading is *pump* volume, pre-puck — it's not yield).
5. **Measure** — confirm cup weight (manual input or live BLE scale via `ScaleTransport` protocol).
6. **Suggest** — verdict + recommendation card for the next shot (finer / coarser grind, pressure delta), with shot-grade reveal.
7. **Complete** — save the best-scoring shot's profile, trimmed to the user's target brew time, to the library.

### Community sharing
- Sign in with **Apple** or **Google** (PKCE OAuth via ASWebAuthenticationSession — no SDK dependency).
- Upload any profile to the community backend, get a shareable URL + QR code.
- `crema://profile/<id>` deep links and `https://<host>/p/<id>` Universal Links open the app and show a preview before adding to library.
- `.crema` files (AirDrop, Messages, Files app) decode locally — no network needed.
- Browse the community feed, like, follow other coffee nerds.

### Shot history + feedback loop
- Every brew can be saved with a tasting note (sour / balanced / bitter) and yield.
- `ProfileTweakSuggester` rule engine surfaces targeted adjustments from the last shot's outcome.

## Repo layout

```
Crema/
├── Sources/
│   ├── CremaKit/                Engine — pure Swift, no UI deps. Cross-platform.
│   │   ├── Modbus.swift, FF55.swift, BLEMachineTransport.swift, …
│   │   ├── BrewProfile.swift    Domain + on-the-wire encoder
│   │   ├── ProfileLibrary.swift Observable library + Codable persistence
│   │   ├── AutoTune/            Pure-functional recommender + types + ScaleTransport
│   │   └── Sharing/             ProfileShareCodec, ShareableProfileURL, ShareAPIClient
│   └── CremaApp/                SwiftUI apps (iOS + iPadOS + macOS share 95%+)
│       ├── Views/               Live chart, profile editors, settings, sharing UI
│       ├── Views/AutoTune/      Wizard sheet + step views + confetti
│       ├── Views/Sharing/       Sign-in, share-out, browse, import, settings
│       └── Data/                Stores + drivers (LiveDriver, AutoTuneSession, etc.)
├── Tests/CremaKitTests/         71 tests across 14 suites
├── backend/                     Hono on Node 22 + Drizzle + Postgres (self-hostable)
│   ├── src/                     Routes, schema, auth (Apple + Google verify)
│   ├── db-init/                 Initial schema SQL (Postgres-init hook)
│   ├── Dockerfile, docker-compose.yml
│   └── README.md                Deploy + env vars
├── project.yml                  xcodegen multi-platform project
└── Crema-iOS.entitlements / Crema-macOS.entitlements
```

## Running

### macOS

```sh
xcodegen generate
xcodebuild -project Crema.xcodeproj -scheme Crema-macOS -configuration Release \
  -destination 'platform=macOS' -allowProvisioningUpdates build
cp -R "$(xcodebuild -showBuildSettings -project Crema.xcodeproj -scheme Crema-macOS \
  -configuration Release 2>/dev/null | awk '/ CONFIGURATION_BUILD_DIR /{print $3}')/Crema.app" /Applications/
open /Applications/Crema.app
```

(Or just `swift run` for a console build; you'll lose the system bundle ID + permission prompt nicety.)

### iOS / iPadOS

```sh
xcodegen generate
open Crema.xcodeproj
# Pick a device or simulator, ⌘R
```

For TestFlight: build the App Store archive (`xcodebuild ... archive`), export with `App Store Connect` method, upload with `xcrun altool --upload-app`. There's a working pipeline documented in the recent commits.

### Backend

```sh
cd backend
docker compose up --build
# API on :8080, Postgres on :5432, schema applied on first boot
```

See [`backend/README.md`](backend/README.md) for env vars (DATABASE_URL, JWT_SECRET, APPLE_CLIENT_ID, GOOGLE_CLIENT_IDS, Universal Links discovery, …).

The iOS app points at `http://localhost:8080` by default; change via **Settings → Backend → Base URL** in-app, or `CREMA_BACKEND_URL` env at launch.

## Tests

```sh
swift test
```

71 tests across 14 suites — Modbus framing byte-exact vs captured fixtures, FF55 checksum, BrewProfile encoder, machine registry, ShotHistory + TipPreferences, AutoTuneRecommender, profile sharing codec + URL parsing, stub transport lifecycle.

## Roadmap

- **Android client** (Kotlin / Jetpack Compose) — shares the backend; Google sign-in already wired.
- **BLE scale integration** — `ScaleTransport` protocol is defined; Bookoo Themis and Acaia drivers next.
- **Public TestFlight** + App Store submission.
- **Community v2** — comments, ratings, equipment filters, account merging (Apple ⇄ Google by email).

## License

To be decided — currently all rights reserved.

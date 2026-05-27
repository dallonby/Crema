# Crema for Android — Planning Document

The iOS / iPadOS / macOS app ships first. The Android port comes after the
iOS app has stabilised in TestFlight. This document is the architectural
plan so the Android dev (future me / future you / a contributor) walks in
with the decisions already made.

## Goal

Feature-parity with the iOS app on Pixel-class hardware:

- Live brew visualisation with the same chart shapes + ghost overlays
- Multi-stage profile authoring (visual + list editor)
- Auto-tune wizard
- Community profile sharing — sign in with Google or Apple, browse,
  share, like, follow
- BLE machine + scale integration

## Stack

| Layer        | Choice                                                                                       |
|--------------|----------------------------------------------------------------------------------------------|
| UI           | **Jetpack Compose** (no XML), Material 3 themed to match the iOS palette in `CremaTheme.swift` |
| Lang         | **Kotlin 2.x**                                                                               |
| Architecture | Single-Activity, Compose Navigation, Jetpack `ViewModel` per screen                          |
| State        | `StateFlow` / `MutableStateFlow`, mirroring iOS's `@Observable` pattern                      |
| BLE          | `androidx.bluetooth` (the new Jetpack BLE API — much nicer than raw `BluetoothGatt`)         |
| Networking   | `Ktor client` (OkHttp engine) + `kotlinx.serialization`                                      |
| Auth         | Sign in with Google (Credential Manager + Google ID Helper); Sign in with Apple via OAuth web flow |
| Persistence  | DataStore (Preferences) for sessions + small KV; Room for shot history if it grows           |
| DI           | None (keep it light) — pass dependencies down explicitly like the iOS code does              |
| Build        | Gradle (KTS), version catalog                                                                |

## Sharing the engine

Two viable paths for the protocol + domain layer (Modbus, FF55, BrewProfile,
AutoTuneRecommender):

### Option A: Hand-port to Kotlin (recommended for v1)
Translate `Sources/CremaKit/` to a Kotlin module under
`android/cremakit/`. Pros: idiomatic Kotlin, no KMP build complexity, easy
to debug. Cons: duplication — bug fixes land twice.

The translatable surface is small and pure-functional in most places
(Modbus CRC, FF55 checksum, BrewProfile encoder, AutoTuneRecommender),
which makes the port low-risk + verifiable by re-running the same
byte-exact fixtures.

### Option B: Kotlin Multiplatform
Set up the engine module as KMP, share it iOS ⇄ Android. Pros: zero
duplication. Cons: KMP-iOS-binary builds add a wrinkle to the Xcode
build (`xcodebuild` calls `gradlew assembleXCFramework`), Compose Multiplatform
isn't a fit (we want native Compose on Android + native SwiftUI on iOS),
debugging Swift → Kotlin interop is a slog.

**Decision:** Option A for v1. Re-evaluate if the engine grows or starts
seeing dual-update churn.

## Module layout

```
android/
├── app/                          UI + entry point (single-activity)
│   ├── src/main/java/coffee/crema/app/
│   │   ├── CremaApp.kt           Application class, DI bootstrap
│   │   ├── MainActivity.kt
│   │   ├── ui/
│   │   │   ├── live/             LiveShotScreen + composables (chart, HUD)
│   │   │   ├── profiles/         Library, editor (visual + list), share
│   │   │   ├── autotune/         Wizard
│   │   │   ├── community/        Browse, sign-in, settings
│   │   │   └── theme/            Crema palette, typography
│   │   └── data/                 Stores, ViewModels
│   └── src/androidTest/          Compose tests
├── cremakit/                     Engine — pure-Kotlin port of CremaKit
│   ├── src/main/java/coffee/crema/kit/
│   │   ├── Modbus.kt
│   │   ├── FF55.kt
│   │   ├── BrewProfile.kt
│   │   ├── ProfileLibrary.kt
│   │   ├── autotune/
│   │   ├── sharing/              Reuses backend JSON shapes verbatim
│   │   └── transport/
│   │       ├── MachineTransport.kt (interface)
│   │       ├── BLEMachineTransport.kt (androidx.bluetooth impl)
│   │       └── StubMachineTransport.kt
│   └── src/test/                 JUnit + Robolectric, port of CremaKitTests
└── build.gradle.kts (settings)
```

## Sharing identity

Same backend, same `users` table. Apple users keyed on `apple_user_id`;
Google users keyed on `google_user_id`. The backend already accepts
identity tokens from both providers — Android signs in via Google, the
ID token POSTs to `/auth/sign-in-with-google` which verifies it the same
way iOS Apple does.

`GOOGLE_CLIENT_IDS` env on the backend accepts a comma-separated list —
add the Android OAuth client id alongside the iOS one.

## Sharing the wire schema

Profile share JSON (the `.crema` file) is the canonical interchange
format. Both clients encode/decode the same shape:

```json
{
  "version": 1,
  "profile": { "id": "…", "name": "…", "stages": [ … ], … },
  "beanName": "…",
  "equipment": "…",
  "description": "…",
  "sharedByName": "…"
}
```

Document any schema bumps in the iOS `ShareableProfile.version` + the
Kotlin port's equivalent constant. Backends accept v1 unconditionally;
add migration once we bump.

## Cross-platform UX considerations

- **Tap targets**: Android min 48dp (vs iOS 44pt). The existing iOS
  44pt hit-target work transfers fine.
- **Back gesture**: handle predictively on Android (Compose's
  `BackHandler` + the iOS `dismiss()` semantics).
- **System theming**: iOS is dark-only by default; Android should
  follow system theme but keep the dark variant as the primary
  visual (the palette is dark-first).
- **BLE permissions**: Android 12+ needs `BLUETOOTH_CONNECT` +
  `BLUETOOTH_SCAN` runtime permissions; nothing comparable on iOS.

## Roadmap

1. Spin up Gradle skeleton + Compose hello-world.
2. Hand-port `Modbus.kt` + `FF55.kt` + `BrewProfile.kt`, verify byte-exact
   against the same fixtures used by `Tests/CremaKitTests/`.
3. Port `AutoTuneRecommender.kt` + its tests.
4. Port `Sharing/*` + `ShareAPIClient.kt`.
5. Hello-world Compose UI: connect to a paired machine, render the
   chart from a fed `StateFlow<List<Sample>>`.
6. Build out screens to feature parity.

No tracker, no PRs in the repo yet — this doc is the source of truth.

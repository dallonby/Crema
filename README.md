# Crema

A native client for the Wendougee LITA-BA / LITA-BR / DATA-S espresso machines, built for coffee nerds who want to author, share, and run pressure / flow / weight profiles.

Driven by the reverse-engineered protocol in [LitaLite](https://github.com/dallonby/LitaLite).

**Status:** macOS prototype — live BLE connection, real-time pressure / flow / volume charting, multi-machine registry with persistent pairing, brew control via Modbus, abort confirmed against real hardware. iOS and Android ports planned.

## What's in here

- `Sources/CremaKit/` — the engine. Wire-level protocol, no UI dependencies. Portable to iOS / watchOS verbatim, to Android via Kotlin port.
  - `Modbus.swift` — CRC16, frame builders + parser, byte-exact vs the captured fixtures
  - `FF55.swift` — event-channel framing (heartbeat + grinder). Includes a checksum formula `(sum + 1) mod 256` reverse-engineered against live captures
  - `BrewProfile.swift` — domain model + `encode(toSlot:)` produces the on-the-wire profile sequence (reproduces the TestyT snoop byte-exact)
  - `LiveTelemetry.swift` — decoder for the live register block at `1404+22`
  - `MachineConstants.swift` — UUIDs, register addresses, coils, slot bases, mode taxonomy
  - `MachineTransport` protocol with `StubMachineTransport` (replay-driven, no hardware) and `BLEMachineTransport` (CoreBluetooth, single-in-flight Modbus, fast reconnect via `retrievePeripherals`)
  - `MachineRegistry` — `Codable` paired machines, `UserDefaults`-backed, primary-machine semantics
- `Sources/CremaApp/` — the macOS prototype. SwiftUI, Liquid Glass surfaces, custom `Canvas` chart with monotone cubic Hermite smoothing and ghost-vs-live overlay
- `Tests/CremaKitTests/` — 41 tests covering the protocol layer and the stub transport

## Running

```sh
swift run
```

Or wrap the binary in `Crema.app/Contents/MacOS/Crema` (already done in the repo) and `open Crema.app` so the system gives it a proper Bluetooth permission prompt and a real bundle identity.

## Design

See `Sources/CremaApp/CremaApp.swift` for the app composition. The hero screen — Live Shot — is one custom `Canvas` chart plus a state-driven `BrewActionZone` that reshapes around the brew lifecycle (Set Up Machine → Connect → Brew → Abort → Save / Discard / Brew Again).

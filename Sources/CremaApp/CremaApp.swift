import SwiftUI
import CremaKit

/// Two operating modes for the prototype:
/// - `replay` — the bundled captured CSV plays back through `ShotPlayback`
/// - `live`   — `LiveDriver` connects to a real machine (or stub on simulator)
enum AppMode: Hashable, Sendable { case replay, live }

@main
struct CremaApp: App {
    @State private var mode: AppMode = .replay
    @State private var registry: MachineRegistry
    @State private var library: ProfileLibrary
    @State private var replayPlayback: ShotPlayback
    @State private var liveDriver: LiveDriver

    init() {
        let reg = MachineRegistry()
        let lib = ProfileLibrary()
        _registry = State(initialValue: reg)
        _library  = State(initialValue: lib)
        _replayPlayback = State(initialValue: Self.makeReplayPlayback(profile: lib.active))
        _liveDriver = State(initialValue: Self.makeLiveDriver(registry: reg, profile: lib.active))
    }

    var body: some Scene {
        WindowGroup("Crema") {
            LiveShotView(
                mode: $mode,
                replayPlayback: replayPlayback,
                liveDriver: liveDriver,
                library: library
            )
            #if os(macOS)
            .frame(minWidth: 1180, minHeight: 760)
            #endif
            .onAppear {
                replayPlayback.play()
                liveDriver.bootstrap()
            }
            // When the user picks a different profile from the library, rebuild
            // the engines so both REPLAY and LIVE modes use the new shape. The
            // observed key is the active profile's id, not the value — id-only
            // means we don't rebuild on slider-driven edits of the same profile.
            .onChange(of: library.activeProfileID) { _, _ in
                let newProfile = library.active
                replayPlayback = Self.makeReplayPlayback(profile: newProfile)
                replayPlayback.play()
                liveDriver = Self.makeLiveDriver(registry: registry, profile: newProfile)
                liveDriver.bootstrap()
            }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        #endif
    }

    private static func makeReplayPlayback(profile: BrewProfile) -> ShotPlayback {
        let samples = (try? BrewCSVLoader.load(resource: "brew_testyt_full")) ?? []
        return ShotPlayback(samples: samples, profile: profile)
    }

    private static func makeLiveDriver(registry: MachineRegistry, profile: BrewProfile) -> LiveDriver {
        // iOS Simulator CBCentralManager reports `.unsupported` — confirmed live
        // on Xcode 26.2 / iOS 26.3. Falls back to the stub so live mode is
        // exercisable in dev. Everywhere else (real iOS device, Mac Catalyst,
        // native macOS) gets the real CoreBluetooth path.
        #if targetEnvironment(simulator)
        let csvSamples = (try? BrewCSVLoader.load(resource: "brew_testyt_full")) ?? []
        let telemetry: [LiveTelemetry] = csvSamples.map { s in
            LiveTelemetry(
                elapsedDeciseconds: UInt16(s.t * 10),
                steamBoilerTempC: 0,
                brewBoilerTempC: s.brewTempC,
                pressureBar: s.pressureBar,
                totalVolumeMl: UInt16(s.volumeMl),
                pumpTimeS: 0,
                pumpFlowMlS: s.flowMlPerSec,
                registers: []
            )
        }
        let transport: any MachineTransport = StubMachineTransport(replayTelemetry: telemetry)
        #else
        let transport: any MachineTransport = BLEMachineTransport()
        #endif
        return LiveDriver(profile: profile, transport: transport, registry: registry)
    }
}

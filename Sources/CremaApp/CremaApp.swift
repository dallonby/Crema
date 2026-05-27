import SwiftUI
import CremaKit

/// Two operating modes for the prototype:
/// - `replay` — the bundled captured CSV plays back through `ShotPlayback`
/// - `live`   — `LiveDriver` connects to a real machine (or stub on simulator)
enum AppMode: Hashable, Sendable { case replay, live }

@main
struct CremaApp: App {
    // Live is the default for first-run users — they see the empty-state
    // "Set up your machine" CTA rather than a confusing auto-playing chart.
    // Demo/Replay is opt-in for showing off the visualization.
    @State private var mode: AppMode = .live
    @State private var registry: MachineRegistry
    @State private var library: ProfileLibrary
    @State private var history: ShotHistory
    @State private var tipPreferences: TipPreferences
    @State private var replayPlayback: ShotPlayback
    @State private var liveDriver: LiveDriver
    @State private var session: SignedInUser

    /// Backend base URL. Defaults to localhost for dev — flip to your
    /// production instance via `CREMA_BACKEND_URL` env at launch or by
    /// editing this constant.
    private static let defaultBackendURL = URL(
        string: ProcessInfo.processInfo.environment["CREMA_BACKEND_URL"]
                ?? "http://localhost:8080"
    )!

    init() {
        let reg = MachineRegistry()
        let lib = ProfileLibrary()
        let hist = ShotHistory()
        let tips = TipPreferences()
        _registry = State(initialValue: reg)
        _library  = State(initialValue: lib)
        _history  = State(initialValue: hist)
        _tipPreferences = State(initialValue: tips)
        _replayPlayback = State(initialValue: Self.makeReplayPlayback())
        _liveDriver = State(initialValue: Self.makeLiveDriver(registry: reg, profile: lib.active))
        _session = State(initialValue: SignedInUser(backendBaseURL: Self.defaultBackendURL))
    }

    var body: some Scene {
        WindowGroup("Crema") {
            LiveShotView(
                mode: $mode,
                replayPlayback: replayPlayback,
                liveDriver: liveDriver,
                library: library,
                history: history,
                tipPreferences: tipPreferences,
                session: session
            )
            #if os(macOS)
            .frame(minWidth: 1180, minHeight: 760)
            #endif
            .onAppear {
                replayPlayback.play()
                liveDriver.bootstrap()
            }
            // When the user picks a different profile, rebuild LIVE only.
            // Demo/replay stays anchored to the profile the CSV was recorded
            // against (TestyT) — overlaying that captured trace on a different
            // profile's ghost lines was visually misleading and made the demo
            // look broken.
            .onChange(of: library.activeProfileID) { _, _ in
                let newProfile = library.active
                liveDriver = Self.makeLiveDriver(registry: registry, profile: newProfile)
                liveDriver.bootstrap()
            }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        #endif
    }

    /// Replay always uses the bundled `brew_testyt_full.csv` paired with a
    /// demo profile shaped to match its actual brew duration (~30 s — the CSV
    /// is trimmed to the natural end of the shot).
    ///
    /// We DON'T use `BrewProfile.testyT` directly even though the CSV came
    /// from that recipe: that constant is the byte-exact ground truth for the
    /// 20-second-extract shot the official app captured, and the encoder unit
    /// tests depend on it remaining unchanged. The demo profile here keeps the
    /// same recipe shape but shortens the extract so the playhead stops when
    /// the data does — no dead-air timer running past the end.
    private static func makeReplayPlayback() -> ShotPlayback {
        let samples = (try? BrewCSVLoader.load(resource: "brew_testyt_full")) ?? []
        let demoProfile = BrewProfile(
            name: "Demo · TestyT",
            stages: [
                BrewStage(label: "Preinfuse", duration: 7, priority: .pressure,
                          pressureBar: 6.1, waitAfter: 8),
                BrewStage(label: "Soak",      duration: 3, priority: .pressure,
                          pressureBar: 2.3),
                BrewStage(label: "Extract",   duration: 12, priority: .flow,
                          flowMlPerSec: 1.7, waitAfter: 0),
                BrewStage(label: "Tail",      duration: 0, priority: .pressure,
                          pressureBar: 1.1),
            ],
            mode: .flowVariablePressure,
            target: .flow,
            targetVolumeMl: 68
        )
        return ShotPlayback(samples: samples, profile: demoProfile)
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

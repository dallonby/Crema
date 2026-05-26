import SwiftUI
import CremaKit

/// Two operating modes for the prototype:
/// - `replay` — the bundled captured CSV plays back through `ShotPlayback`
/// - `live`   — a `StubMachineTransport` drives a `LiveDriver`, end-to-end the
///   way it will work against a real machine. The stub plays back the same
///   captured telemetry but goes through every protocol layer (Modbus
///   builders, transport, telemetry decoder, live append).
enum AppMode: Hashable, Sendable { case replay, live }

@main
struct CremaApp: App {
    @State private var mode: AppMode = .replay
    @State private var registry: MachineRegistry = MachineRegistry()
    @State private var replayPlayback: ShotPlayback = makeReplayPlayback()
    @State private var liveDriver: LiveDriver

    init() {
        let reg = MachineRegistry()
        _registry = State(initialValue: reg)
        _liveDriver = State(initialValue: Self.makeLiveDriver(registry: reg))
    }

    var body: some Scene {
        WindowGroup("Crema") {
            LiveShotView(
                mode: $mode,
                replayPlayback: replayPlayback,
                liveDriver: liveDriver
            )
            .frame(minWidth: 1180, minHeight: 760)
            .onAppear {
                replayPlayback.play()
                liveDriver.bootstrap()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }

    private static func makeReplayPlayback() -> ShotPlayback {
        let samples = (try? BrewCSVLoader.load(resource: "brew_testyt_full")) ?? []
        return ShotPlayback(samples: samples, profile: .testyT)
    }

    private static func makeLiveDriver(registry: MachineRegistry) -> LiveDriver {
        // Real BLE transport — talks to an actual Wendougee LITA. To go back to
        // the stub for development without hardware, swap to:
        //   StubMachineTransport(replayTelemetry: …)
        // (See git history for the CSV-derived telemetry construction.)
        let transport = BLEMachineTransport()
        return LiveDriver(profile: .testyT, transport: transport, registry: registry)
    }
}

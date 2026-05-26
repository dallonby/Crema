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
            #if os(macOS)
            .frame(minWidth: 1180, minHeight: 760)
            #endif
            .onAppear {
                replayPlayback.play()
                liveDriver.bootstrap()
            }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        #endif
    }

    private static func makeReplayPlayback() -> ShotPlayback {
        let samples = (try? BrewCSVLoader.load(resource: "brew_testyt_full")) ?? []
        return ShotPlayback(samples: samples, profile: .testyT)
    }

    private static func makeLiveDriver(registry: MachineRegistry) -> LiveDriver {
        // iOS Simulator CBCentralManager reports `.unsupported` — confirmed live
        // on Xcode 26.2 / iOS 26.3. The simulator does not pass through to the
        // host Mac's Bluetooth radio. So on the simulator we fall back to the
        // stub (driven by the captured TestyT telemetry). Real iOS devices,
        // Mac Catalyst, and native macOS all use the real CoreBluetooth path.
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
        return LiveDriver(profile: .testyT, transport: transport, registry: registry)
    }
}

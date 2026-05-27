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
    @State private var pendingImportProfile: ShareAPIClient.ProfileDTO?
    @State private var importError: String?

    /// Backend base URL. Resolution order, most-specific first:
    /// 1. User override stored in UserDefaults (Settings → Backend)
    /// 2. `CREMA_BACKEND_URL` env at launch
    /// 3. localhost fallback
    private static var resolvedBackendURL: URL {
        if let stored = UserDefaults.standard.string(forKey: "crema.backend.url.override"),
           let url = URL(string: stored), url.scheme?.hasPrefix("http") == true {
            return url
        }
        if let env = ProcessInfo.processInfo.environment["CREMA_BACKEND_URL"],
           let url = URL(string: env) {
            return url
        }
        return URL(string: "http://localhost:8080")!
    }

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
        _session = State(initialValue: SignedInUser(backendBaseURL: Self.resolvedBackendURL))
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
            // crema://profile/<id> deep links → fetch + present import preview
            .onOpenURL { url in handleIncoming(url: url) }
            // Imported .crema file (Files app, AirDrop landing, etc.)
            .sheet(item: $pendingImportProfile) { dto in
                ImportProfileSheet(profile: dto, library: library,
                                     session: session,
                                     onDone: { pendingImportProfile = nil })
            }
            .alert("Couldn't open profile",
                   isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } })
            ) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
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
    /// Route an incoming URL — either a `crema://profile/<id>` deep link
    /// (fetch from backend then present preview) or a `file://…/foo.crema`
    /// file open (decode locally + present preview). Anything else is
    /// ignored.
    @MainActor
    private func handleIncoming(url: URL) {
        if let share = ShareableProfileURL(url: url) {
            Task {
                do {
                    let dto = try await session.client.fetch(id: share.id)
                    pendingImportProfile = dto
                } catch {
                    importError = "Couldn't fetch profile \(share.id): \(error)"
                }
            }
            return
        }
        if url.isFileURL && url.pathExtension == ProfileShareCodec.fileExtension {
            do {
                let shareable = try ProfileShareCodec.read(url)
                pendingImportProfile = makeDTO(from: shareable)
            } catch {
                importError = "Couldn't parse profile file: \(error)"
            }
            return
        }
    }

    /// Wrap a locally-loaded `ShareableProfile` in a `ProfileDTO` shape so it
    /// can be previewed with the same `ImportProfileSheet`. Author info
    /// reads from `sharedByName` when present; falls back to "Unknown".
    @MainActor
    private func makeDTO(from s: ShareableProfile) -> ShareAPIClient.ProfileDTO {
        let dict: [String: Any] = [
            "id": "local-\(UUID().uuidString.prefix(8))",
            "name": s.profile.name,
            "description": s.description as Any,
            "beanName": s.beanName as Any,
            "equipment": s.equipment as Any,
            "profileJson": (try? JSONSerialization.jsonObject(
                with: JSONEncoder().encode(s.profile))) ?? [:],
            "likesCount": 0,
            "downloadsCount": 0,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "author": [
                "id": "local",
                "displayName": s.sharedByName ?? "Unknown",
                "avatarUrl": NSNull(),
            ],
        ]
        let cleaned = dict.compactMapValues { $0 is NSNull ? nil : $0 }
        let data = try! JSONSerialization.data(withJSONObject: cleaned)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try! dec.decode(ShareAPIClient.ProfileDTO.self, from: data)
    }

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

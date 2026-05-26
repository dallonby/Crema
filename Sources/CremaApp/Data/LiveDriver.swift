import Foundation
import SwiftUI
import CremaKit

/// Wires a `MachineTransport` to a live-mode `ShotPlayback`. Owns:
/// - connection lifecycle (scan/retrieve, connect, disconnect)
/// - the `MachineRegistry` of paired machines
/// - the brew lifecycle (`.ready` → `.brewing` → `.done`)
/// - the telemetry ingest loop (received Modbus frames → `ShotSample`)
@MainActor
@Observable
final class LiveDriver {
    let playback: ShotPlayback
    let transport: any MachineTransport
    let registry: MachineRegistry
    let slot: Machine.Slot

    private(set) var state: MachineState = .idle
    private(set) var brewState: BrewState = .ready
    private(set) var lastError: String?
    /// Snapshot of peripherals seen in the most recent scan. Bound to the
    /// machines sheet so newly-advertising LITAs appear in real time.
    private(set) var discovered: [DiscoveredPeripheral] = []

    private var stateTask: Task<Void, Never>?
    private var framesTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var lastSampleAt: Date?
    private var brewWatchdog: Task<Void, Never>?
    private var connectingTo: String?  // identifier in flight

    /// How often the polling loop asks the machine for the live register block.
    /// Matches the cadence the official Wendougee app and the LitaLite recorder
    /// script use (~3.4 Hz). The chart's smoothing & TimelineView happily upscale
    /// this to the display's refresh rate.
    private let pollInterval: UInt64 = 290_000_000  // ns ≈ 3.4 Hz

    enum BrewState: Sendable, Hashable { case ready, brewing, done }

    var canBrew: Bool {
        if case .connected = state, brewState != .brewing { return true }
        return false
    }

    init(profile: BrewProfile,
         transport: any MachineTransport,
         registry: MachineRegistry,
         slot: Machine.Slot = .one) {
        self.playback = ShotPlayback(liveProfile: profile)
        self.transport = transport
        self.registry = registry
        self.slot = slot
    }

    /// Subscribe to transport streams. Idempotent — safe to call more than once.
    /// Must be called once at app start so the driver is ready to react to
    /// state and frame changes the moment a connection attempt happens.
    func bootstrap() {
        guard stateTask == nil else { return }

        stateTask = Task { [transport, weak self] in
            for await s in transport.stateChanges() {
                guard let self else { return }
                self.state = s
                // Bump lastConnected on the registry the moment we go connected.
                if case .connected = s, let id = self.connectingTo {
                    self.registry.markConnected(id)
                    self.connectingTo = nil
                }
            }
        }
        framesTask = Task { [transport, playback, weak self] in
            for await frame in transport.receivedFrames() {
                if case .modbus(let resp) = frame,
                   let telemetry = LiveTelemetry.decode(response: resp) {
                    let sample = ShotSample(from: telemetry)
                    playback.appendLive(sample)
                    self?.lastSampleAt = Date()
                }
            }
        }
        discoveryTask = Task { [transport, weak self] in
            for await peers in transport.discoveredPeripherals() {
                self?.discovered = peers
            }
        }
    }

    // MARK: - Connect / disconnect

    /// Connect to the primary machine in the registry. If there's no primary,
    /// transitions to `.idle` — the UI's "Set up your machine" CTA takes over.
    func connectToPrimary() {
        guard let primary = registry.primary else {
            // Nothing to connect to — keep state at idle; the UI will prompt
            // the user to set up a machine.
            return
        }
        connect(to: primary.id)
    }

    /// Connect to a specific paired machine.
    func connect(to identifier: String) {
        bootstrap()
        connectingTo = identifier
        lastError = nil
        Task { [transport] in
            do {
                try await transport.connect(identifier: identifier)
            } catch {
                self.lastError = String(describing: error)
                self.connectingTo = nil
            }
        }
    }

    /// Start scanning for new machines. Discovered peripherals appear in
    /// `discovered`. Caller should call `stopScan()` (or `pair(:)`) afterward.
    func startScan(timeout: TimeInterval = 10) {
        bootstrap()
        lastError = nil
        Task { [transport] in
            do {
                try await transport.startScan(prefix: Machine.advertisingPrefix,
                                              timeout: timeout)
            } catch {
                self.lastError = String(describing: error)
            }
        }
    }

    func stopScan() {
        Task { [transport] in await transport.stopScan() }
    }

    /// Save a discovered peripheral to the registry and (optionally) connect.
    func pair(_ peer: DiscoveredPeripheral,
              nickname: String? = nil,
              setAsPrimary: Bool = false,
              connectImmediately: Bool = true) {
        let machine = PairedMachine(
            id: peer.identifier,
            advertisedName: peer.name,
            nickname: nickname,
            firstSeen: peer.firstSeenAt
        )
        registry.upsert(machine, setAsPrimary: setAsPrimary)
        if connectImmediately {
            stopScan()
            connect(to: peer.identifier)
        }
    }

    func stop() {
        stopPolling()
        brewWatchdog?.cancel(); brewWatchdog = nil
        framesTask?.cancel(); framesTask = nil
        stateTask?.cancel();  stateTask = nil
        discoveryTask?.cancel(); discoveryTask = nil
        Task { [transport] in await transport.disconnect() }
    }

    // MARK: - Brew lifecycle

    func brew() {
        guard canBrew else { return }
        playback.reset()
        brewState = .brewing
        lastSampleAt = nil
        lastError = nil

        Task { [transport, playback, slot, weak self] in
            do {
                try await transport.sendProfile(playback.profile,
                                                 toSlot: slot, triggerBrew: true)
                // Profile and coil-150 trigger sent. Now start polling the live
                // register block — the machine doesn't push these unsolicited
                // on the Modbus channel, so we have to ask.
                self?.startPolling()
            } catch {
                self?.lastError = String(describing: error)
                self?.brewState = .ready
                playback.pause()
            }
        }

        brewWatchdog?.cancel()
        brewWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                if self.brewState != .brewing { return }
                // Telemetry has gone quiet ≥1.5 s after at least one sample —
                // treat as natural end-of-shot. Stops polling too.
                if let last = self.lastSampleAt, Date().timeIntervalSince(last) > 1.5 {
                    self.brewState = .done
                    self.playback.pause()
                    self.stopPolling()
                    return
                }
            }
        }
    }

    /// User-initiated abort. The machine's stop protocol isn't fully captured
    /// yet — we send a press-and-release of coil 150 (mirror of the start
    /// gesture, on the theory the button toggles in/out of brewing). If that
    /// turns out to be wrong, the right next step is to HCI-snoop the official
    /// app stopping a shot mid-flight.
    func abort() {
        guard brewState == .brewing else { return }
        // Stop polling first so we don't race our own outgoing reads against
        // the stop command.
        stopPolling()
        brewWatchdog?.cancel()

        // Immediately reflect the user's intent in the UI. The actual stop
        // command goes out in the background.
        brewState = .done
        playback.pause()

        Task { [transport] in
            try? await transport.sendModbus(
                Modbus.writeCoil(at: Machine.startBrewCoil, on: true), timeout: 1.0)
            try? await transport.sendModbus(
                Modbus.writeCoil(at: Machine.startBrewCoil, on: false), timeout: 1.0)
        }
    }

    func clearShot() {
        stopPolling()
        playback.reset()
        brewState = .ready
        lastError = nil
    }

    // MARK: - Polling

    /// Periodically reads the live register block (`1404 + 22`). Each response
    /// is decoded by the framesTask running on top of `transport.receivedFrames`,
    /// so the data flows through the same path the stub used.
    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [transport, pollInterval, weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.brewState != .brewing { return }
                do {
                    _ = try await transport.sendModbus(
                        Modbus.readHolding(at: Machine.liveBlockBase,
                                           count: Machine.liveBlockCount),
                        timeout: 1.0)
                } catch {
                    // Transient — keep polling. Persistent failure surfaces
                    // through the watchdog hitting its quiet-time threshold.
                }
                try? await Task.sleep(nanoseconds: pollInterval)
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}

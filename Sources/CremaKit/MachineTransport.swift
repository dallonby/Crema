import Foundation

/// Connection lifecycle of a `MachineTransport`. UI binds to `stateChanges` so
/// the chip in the title bar and the brew button know what's possible right now.
public enum MachineState: Sendable, Hashable {
    case idle
    case scanning
    case discovered(name: String, identifier: String)
    case connecting(name: String)
    case connected(name: String)
    case disconnecting
    case failed(reason: String)
}

/// Either kind of frame the machine pushes at us.
public enum ReceivedFrame: Sendable, Hashable {
    case modbus(Modbus.Response)
    case ff55(FF55.Frame)
}

/// A peripheral seen during scanning. The `identifier` is what `connect(identifier:)`
/// and the `MachineRegistry`'s `id` field both use — stable per-install.
public struct DiscoveredPeripheral: Sendable, Hashable, Identifiable {
    public var id: String { identifier }
    public let identifier: String
    public let name: String
    /// Signal strength in dBm (closer to 0 = stronger). `nil` for the stub.
    public let rssi: Int?
    /// First time we saw this peripheral in the current scan.
    public let firstSeenAt: Date

    public init(identifier: String, name: String, rssi: Int? = nil,
                firstSeenAt: Date = .now) {
        self.identifier = identifier
        self.name = name
        self.rssi = rssi
        self.firstSeenAt = firstSeenAt
    }
}

public enum TransportError: Error, Sendable {
    case notConnected
    case timeout
    case badResponse(String)
    case scanFailed(String)
    case writeFailed(String)
    case bluetoothUnavailable
}

/// The abstract surface the rest of Crema uses to talk to a machine. Real impl
/// is `BLEMachineTransport`; `StubMachineTransport` plays back recorded data
/// so the app can be developed and demoed without hardware on the bench.
public protocol MachineTransport: Sendable {

    /// Current connection state — read once.
    var state: MachineState { get async }

    /// Live state stream. Multiple subscribers OK; each gets the current state
    /// as its first value, then every subsequent transition.
    func stateChanges() -> AsyncStream<MachineState>

    /// Stream of every frame received from both characteristics. Multiple
    /// subscribers OK. `sendModbus` does NOT consume from this stream — it
    /// has its own response routing — so subscribers see Modbus responses
    /// here too, after they've been routed.
    func receivedFrames() -> AsyncStream<ReceivedFrame>

    /// Start a continuous scan for peripherals whose advertised name begins
    /// with `prefix`. Each new peripheral (and RSSI update) is pushed through
    /// `discoveredPeripherals()`. Scan auto-stops after `timeout`, or earlier
    /// via `stopScan`.
    func startScan(prefix: String, timeout: TimeInterval) async throws

    /// Stop a running scan. Idempotent.
    func stopScan() async

    /// Live stream of all peripherals discovered in the most recent scan.
    /// Emissions are full sorted snapshots (strongest RSSI first), so the UI
    /// can render each one directly.
    func discoveredPeripherals() -> AsyncStream<[DiscoveredPeripheral]>

    /// Connect to a peripheral by identifier. Works for both freshly-scanned
    /// and previously-paired peripherals (CoreBluetooth's `retrievePeripherals`
    /// path covers the latter without requiring a fresh scan).
    func connect(identifier: String) async throws

    /// Drop the connection. Idempotent.
    func disconnect() async

    /// Write a Modbus frame and wait for the corresponding response. The
    /// response is matched by waiting for the next CRC-valid frame to come
    /// back from the device — only one request can be in flight at a time.
    @discardableResult
    func sendModbus(_ frame: Data, timeout: TimeInterval) async throws -> Modbus.Response

    /// Fire-and-forget write on the FF55 characteristic. Responses (if any)
    /// arrive asynchronously via `receivedFrames`.
    func sendFF55(_ frame: Data) async throws
}

extension MachineTransport {

    /// Convenience: scan and resolve as soon as the first matching peripheral
    /// shows up. Retains the historical `discover(prefix:timeout:)` semantics
    /// for callers that just want any LITA in range — built on top of the
    /// scan/discoveredPeripherals primitives.
    public func discover(prefix: String, timeout: TimeInterval) async throws -> (name: String, identifier: String) {
        try await startScan(prefix: prefix, timeout: timeout)
        for await peers in discoveredPeripherals() {
            if let first = peers.first {
                await stopScan()
                return (name: first.name, identifier: first.identifier)
            }
        }
        throw TransportError.timeout
    }

    /// Convenience: full brew sequence. Writes the profile to the slot, sets the
    /// active mode register, and (optionally) triggers coil 150 to start the shot.
    /// Each write is awaited so we know the machine actually acknowledged.
    public func sendProfile(_ profile: BrewProfile, toSlot slot: Machine.Slot,
                            triggerBrew: Bool = true,
                            timeout: TimeInterval = 2.0) async throws {
        let steps = profile.encode(toSlot: slot, triggerBrew: triggerBrew)
        for step in steps {
            try await sendModbus(step.frame, timeout: timeout)
        }
    }
}

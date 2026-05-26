import Foundation

/// Simulated machine for development without hardware. Behaves like a real
/// `BLEMachineTransport` from the caller's perspective:
///
/// - `discover` resolves immediately to a fake peripheral
/// - `connect` flips state to `.connected`
/// - `sendModbus` echoes the appropriate canned response (writes are confirmed
///   with the expected 8-byte echo; reads return zeroed register blocks)
/// - `receivedFrames` plays back a recorded telemetry trace at the machine's
///   natural ~3.4 Hz cadence once a brew is "triggered" (coil 150 ON write)
///
/// The replay timing is wall-clock, not synthetic — that means the chart's
/// animation paths run through the same code in stub mode as they will when
/// the real machine is on the bench.
public actor StubMachineTransport: MachineTransport {

    private var _state: MachineState = .idle
    private var stateContinuations: [UUID: AsyncStream<MachineState>.Continuation] = [:]
    private var frameContinuations: [UUID: AsyncStream<ReceivedFrame>.Continuation] = [:]
    private var discoveredContinuations: [UUID: AsyncStream<[DiscoveredPeripheral]>.Continuation] = [:]
    private var discovered: [DiscoveredPeripheral] = []
    private var replayTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private let replaySource: [LiveTelemetry]
    private let simulatedPeripherals: [DiscoveredPeripheral]
    private var connectedIdentifier: String?

    public init(replayTelemetry: [LiveTelemetry] = [],
                simulatedPeripherals: [DiscoveredPeripheral] = .defaultStubFleet) {
        self.replaySource = replayTelemetry
        self.simulatedPeripherals = simulatedPeripherals
    }

    public var state: MachineState { _state }

    nonisolated public func stateChanges() -> AsyncStream<MachineState> {
        AsyncStream { cont in
            let id = UUID()
            Task { await self.registerStateContinuation(id: id, continuation: cont) }
            cont.onTermination = { _ in
                Task { await self.unregisterStateContinuation(id: id) }
            }
        }
    }

    nonisolated public func receivedFrames() -> AsyncStream<ReceivedFrame> {
        AsyncStream { cont in
            let id = UUID()
            Task { await self.registerFrameContinuation(id: id, continuation: cont) }
            cont.onTermination = { _ in
                Task { await self.unregisterFrameContinuation(id: id) }
            }
        }
    }

    nonisolated public func discoveredPeripherals() -> AsyncStream<[DiscoveredPeripheral]> {
        AsyncStream { cont in
            let id = UUID()
            Task { await self.registerDiscoveredContinuation(id: id, continuation: cont) }
            cont.onTermination = { _ in
                Task { await self.unregisterDiscoveredContinuation(id: id) }
            }
        }
    }

    private func registerStateContinuation(id: UUID, continuation: AsyncStream<MachineState>.Continuation) {
        stateContinuations[id] = continuation
        continuation.yield(_state)  // catch-up
    }
    private func unregisterStateContinuation(id: UUID) {
        stateContinuations.removeValue(forKey: id)
    }
    private func registerFrameContinuation(id: UUID, continuation: AsyncStream<ReceivedFrame>.Continuation) {
        frameContinuations[id] = continuation
    }
    private func unregisterFrameContinuation(id: UUID) {
        frameContinuations.removeValue(forKey: id)
    }
    private func registerDiscoveredContinuation(id: UUID, continuation: AsyncStream<[DiscoveredPeripheral]>.Continuation) {
        discoveredContinuations[id] = continuation
        continuation.yield(discovered)
    }
    private func unregisterDiscoveredContinuation(id: UUID) {
        discoveredContinuations.removeValue(forKey: id)
    }
    private func emitDiscovered() {
        let snapshot = discovered.sorted { ($0.rssi ?? -200) > ($1.rssi ?? -200) }
        for c in discoveredContinuations.values { c.yield(snapshot) }
    }

    private func setState(_ new: MachineState) {
        _state = new
        for c in stateContinuations.values { c.yield(new) }
    }

    private func emit(_ frame: ReceivedFrame) {
        for c in frameContinuations.values { c.yield(frame) }
    }

    // MARK: - MachineTransport

    public func startScan(prefix: String, timeout: TimeInterval) async throws {
        scanTask?.cancel()
        discovered.removeAll()
        emitDiscovered()
        setState(.scanning)

        // Trickle the simulated fleet in with a small delay between each — feels
        // like a real BLE scan where peripherals advertise one at a time. Filter
        // by prefix the same way the real BLE adapter does.
        let candidates = simulatedPeripherals.filter { $0.name.hasPrefix(prefix) }
        scanTask = Task { [weak self] in
            for (i, peer) in candidates.enumerated() {
                let delay: UInt64 = i == 0 ? 200_000_000 : 600_000_000
                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { return }
                guard let self else { return }
                await self.appendDiscovered(peer)
            }
            // Auto-stop after timeout from start.
            let remaining = timeout - Double(candidates.count) * 0.6 - 0.2
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            await self?.stopScan()
        }
    }

    public func stopScan() async {
        scanTask?.cancel()
        scanTask = nil
        if case .scanning = _state { setState(.idle) }
    }

    private func appendDiscovered(_ peer: DiscoveredPeripheral) {
        if !discovered.contains(where: { $0.identifier == peer.identifier }) {
            discovered.append(peer)
            emitDiscovered()
        }
    }

    public func connect(identifier: String) async throws {
        // Resolve the peripheral. Allow connecting to any simulated machine —
        // including ones the user hasn't scanned-and-paired in this session
        // (mirrors CoreBluetooth's `retrievePeripherals` fast-reconnect).
        let resolved = discovered.first(where: { $0.identifier == identifier })
            ?? simulatedPeripherals.first(where: { $0.identifier == identifier })
        guard let peer = resolved else {
            setState(.failed(reason: "unknown peripheral \(identifier)"))
            throw TransportError.scanFailed("unknown peripheral \(identifier)")
        }
        await stopScan()
        setState(.connecting(name: peer.name))
        try? await Task.sleep(nanoseconds: 250_000_000)
        connectedIdentifier = peer.identifier
        setState(.connected(name: peer.name))
    }

    public func disconnect() async {
        replayTask?.cancel(); replayTask = nil
        scanTask?.cancel();   scanTask = nil
        connectedIdentifier = nil
        setState(.disconnecting)
        try? await Task.sleep(nanoseconds: 80_000_000)
        setState(.idle)
    }

    public func sendModbus(_ frame: Data, timeout: TimeInterval) async throws -> Modbus.Response {
        guard case .connected = _state else { throw TransportError.notConnected }
        guard let req = Modbus.parse(frame) else {
            throw TransportError.badResponse("malformed outgoing frame")
        }

        // Synthesize the canonical Modbus response for each function code.
        let response = synthesizeResponse(to: req)

        // Side effects: starting the brew kicks off replay if we have one.
        if req.function == Modbus.FunctionCode.writeCoil.rawValue,
           let addr = address(of: req), addr == Machine.startBrewCoil,
           valueIsOn(req) {
            startReplay()
        }

        // Surface to subscribers too (mirrors what a real device does — the same
        // notification you get back to fulfill the write is also visible).
        emit(.modbus(response))
        return response
    }

    public func sendFF55(_ frame: Data) async throws {
        guard case .connected = _state else { throw TransportError.notConnected }
        // No-op for now. In future the stub could synthesize a heartbeat back.
    }

    // MARK: - Replay

    private func startReplay() {
        guard !replaySource.isEmpty else { return }
        replayTask?.cancel()
        let samples = replaySource
        replayTask = Task { [weak self] in
            let start = ContinuousClock.now
            // First sample arrives ~immediately; subsequent samples paced to elapsedSeconds.
            for sample in samples {
                let due = start.advanced(by: .seconds(sample.elapsedSeconds))
                let now = ContinuousClock.now
                if due > now {
                    try? await Task.sleep(until: due, clock: ContinuousClock())
                }
                if Task.isCancelled { return }
                guard let self else { return }
                // Synthesize a 0x03 response carrying this sample's register block.
                await self.emitReplay(sample)
            }
        }
    }

    private func emitReplay(_ sample: LiveTelemetry) {
        let resp = makeStubReadHoldingResponse(from: sample)
        emit(.modbus(resp))
    }

    // MARK: - Helpers

    /// Build the "echo" success response for a write, or a zero-filled block for
    /// a read. Matches the shape the real device sends back.
    private func synthesizeResponse(to req: Modbus.Response) -> Modbus.Response {
        switch req.function {
        case Modbus.FunctionCode.writeCoil.rawValue,
             Modbus.FunctionCode.writeRegister.rawValue:
            // Echo back addr + value (4 bytes). Same frame the device returns.
            var body = Data([0x01, req.function])
            body.append(req.data.prefix(4))
            return wrap(body)
        case Modbus.FunctionCode.writeRegisters.rawValue:
            // Echo back addr + qty (4 bytes).
            var body = Data([0x01, req.function])
            body.append(req.data.prefix(4))
            return wrap(body)
        case Modbus.FunctionCode.readHolding.rawValue,
             Modbus.FunctionCode.readCoils.rawValue:
            // Return a zero-filled block of the requested size.
            let qty = (UInt16(req.data[req.data.startIndex + 2]) << 8) |
                       UInt16(req.data[req.data.startIndex + 3])
            let byteCount = req.function == Modbus.FunctionCode.readHolding.rawValue
                ? Int(qty) * 2
                : (Int(qty) + 7) / 8
            var body = Data([0x01, req.function, UInt8(byteCount)])
            body.append(Data(repeating: 0, count: byteCount))
            return wrap(body)
        default:
            return wrap(Data([0x01, req.function]))
        }
    }

    /// Synthesize a `0x03` response carrying a `LiveTelemetry` snapshot's register
    /// block, so the receive pipeline can re-decode it through the normal path.
    /// Prefers the typed-field-derived register layout from `toRegisterBlock()`
    /// over any raw `registers` array — that way callers can pass either form
    /// and the decoded telemetry will match what they put in.
    private func makeStubReadHoldingResponse(from sample: LiveTelemetry) -> Modbus.Response {
        let regs = sample.toRegisterBlock()
        var body = Data([0x01, Modbus.FunctionCode.readHolding.rawValue, UInt8(regs.count * 2)])
        for r in regs {
            body.append(UInt8(r >> 8))
            body.append(UInt8(r & 0xFF))
        }
        return wrap(body)
    }

    /// Append a CRC and parse-wrap into a `Modbus.Response`.
    private func wrap(_ body: Data) -> Modbus.Response {
        var full = body
        let crc = Modbus.crc16(body)
        full.append(UInt8(crc & 0xFF))
        full.append(UInt8((crc >> 8) & 0xFF))
        // parse() will always succeed here — we just built it correctly.
        return Modbus.parse(full)!
    }

    private func address(of req: Modbus.Response) -> UInt16? {
        let bytes = req.data
        guard bytes.count >= 2 else { return nil }
        return (UInt16(bytes[bytes.startIndex]) << 8) |
                UInt16(bytes[bytes.startIndex + 1])
    }

    private func valueIsOn(_ req: Modbus.Response) -> Bool {
        // Write-coil value is at data[2..3], ON = 0xFF00.
        let bytes = req.data
        guard bytes.count >= 4 else { return false }
        return bytes[bytes.startIndex + 2] == 0xFF
    }
}

public extension Array where Element == DiscoveredPeripheral {
    /// Default fleet for the stub: two fake LITAs at different signal strengths,
    /// so the discovery UI can show what the multi-machine path looks like.
    /// Identifiers are stable strings (not real UUIDs) — fine for the stub since
    /// CoreBluetooth's UUIDs are also opaque strings to our layer.
    static var defaultStubFleet: [DiscoveredPeripheral] {
        [
            DiscoveredPeripheral(
                identifier: "STUB-LITA-AB071169",
                name: "WDG_Data_AB071169",
                rssi: -54
            ),
            DiscoveredPeripheral(
                identifier: "STUB-LITA-FF22DDEE",
                name: "WDG_Data_FF22DDEE",
                rssi: -72
            ),
        ]
    }
}

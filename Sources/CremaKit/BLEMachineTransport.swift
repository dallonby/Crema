#if canImport(CoreBluetooth)
import Foundation
import CoreBluetooth

/// CoreBluetooth-backed `MachineTransport`. Owns the `CBCentralManager`, enforces
/// single-central-at-a-time (the BLE protocol's own constraint, not just policy),
/// and bridges delegate callbacks into Swift's structured concurrency.
///
/// Architecture: the class is `@unchecked Sendable` because CoreBluetooth's
/// delegate callbacks fire on the `bleQueue` we configure, and all internal
/// mutable state is touched only on that queue. The actor abstraction is the
/// queue, enforced by convention rather than the type system.
///
/// **Required on macOS**: `NSBluetoothAlwaysUsageDescription` in `Info.plist`.
/// (We add it in `Crema.app/Contents/Info.plist` for the prototype.)
public final class BLEMachineTransport: NSObject, MachineTransport, @unchecked Sendable {

    private let bleQueue = DispatchQueue(label: "coffee.crema.ble", qos: .userInteractive)
    private var manager: CBCentralManager!

    private var _state: MachineState = .idle
    private var stateContinuations: [UUID: AsyncStream<MachineState>.Continuation] = [:]
    private var frameContinuations: [UUID: AsyncStream<ReceivedFrame>.Continuation] = [:]
    private var discoveredContinuations: [UUID: AsyncStream<[DiscoveredPeripheral]>.Continuation] = [:]

    // Scan support
    private var scanPrefix: String?
    private var scanTimeoutItem: DispatchWorkItem?
    private var scannedPeripherals: [String: (CBPeripheral, DiscoveredPeripheral)] = [:]

    // Bluetooth readiness — on first launch the CB manager is `.unknown` until
    // the OS responds with the user's permission decision. Anything that needs
    // a powered-on radio waits on these continuations until `centralManagerDidUpdateState`
    // is called with the actual state.
    private var readinessWaiters: [CheckedContinuation<Void, Error>] = []

    // Connect support
    private var pendingPeripheral: CBPeripheral?
    private var connectContinuation: CheckedContinuation<Void, Error>?

    // Characteristic discovery
    private var modbusChar: CBCharacteristic?
    private var eventChar:  CBCharacteristic?
    private var charsReady: CheckedContinuation<Void, Error>?

    // Modbus request/response — single in-flight at a time
    private var pendingModbus: PendingModbus?
    private var modbusBuffer = Data()
    private struct PendingModbus {
        let continuation: CheckedContinuation<Modbus.Response, Error>
        let timeoutItem: DispatchWorkItem
    }

    public override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: bleQueue)
    }

    public var state: MachineState {
        get async {
            await withCheckedContinuation { cont in
                bleQueue.async { cont.resume(returning: self._state) }
            }
        }
    }

    public func stateChanges() -> AsyncStream<MachineState> {
        AsyncStream { cont in
            let id = UUID()
            bleQueue.async {
                self.stateContinuations[id] = cont
                cont.yield(self._state)
            }
            cont.onTermination = { _ in
                self.bleQueue.async { self.stateContinuations.removeValue(forKey: id) }
            }
        }
    }

    public func receivedFrames() -> AsyncStream<ReceivedFrame> {
        AsyncStream { cont in
            let id = UUID()
            self.bleQueue.async { self.frameContinuations[id] = cont }
            cont.onTermination = { _ in
                self.bleQueue.async { self.frameContinuations.removeValue(forKey: id) }
            }
        }
    }

    public func discoveredPeripherals() -> AsyncStream<[DiscoveredPeripheral]> {
        AsyncStream { cont in
            let id = UUID()
            self.bleQueue.async {
                self.discoveredContinuations[id] = cont
                cont.yield(self.scannedPeripherals.values.map(\.1)
                    .sorted { ($0.rssi ?? -200) > ($1.rssi ?? -200) })
            }
            cont.onTermination = { _ in
                self.bleQueue.async { self.discoveredContinuations.removeValue(forKey: id) }
            }
        }
    }

    public func startScan(prefix: String, timeout: TimeInterval) async throws {
        // Wait for Bluetooth to become available. On first launch this prompts
        // the user for permission and we sit here until they answer.
        try await waitForBluetoothReady()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            bleQueue.async {
                self.scanPrefix = prefix
                self.scannedPeripherals.removeAll()
                self.emitDiscovered()
                self.setState(.scanning)
                self.manager.scanForPeripherals(withServices: nil, options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: true
                ])
                let timeoutItem = DispatchWorkItem { [weak self] in
                    self?.bleQueue.async {
                        guard let self else { return }
                        self.manager.stopScan()
                        if case .scanning = self._state { self.setState(.idle) }
                    }
                }
                self.scanTimeoutItem = timeoutItem
                self.bleQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
                cont.resume()
            }
        }
    }

    /// Wait until the central manager has settled into a known state. Returns
    /// normally once powered-on; throws a descriptive `TransportError` for
    /// every other terminal state so the UI can show the right error.
    private func waitForBluetoothReady() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            bleQueue.async {
                switch self.manager.state {
                case .poweredOn:
                    cont.resume()
                case .unknown, .resetting:
                    // OS hasn't responded yet — queue and wait.
                    self.readinessWaiters.append(cont)
                case .poweredOff:
                    cont.resume(throwing: TransportError.bluetoothUnavailable)
                case .unauthorized:
                    cont.resume(throwing: TransportError.scanFailed(
                        "Crema needs Bluetooth permission. Open System Settings → Privacy & Security → Bluetooth and enable Crema."))
                case .unsupported:
                    cont.resume(throwing: TransportError.scanFailed("This machine doesn't support Bluetooth LE."))
                @unknown default:
                    cont.resume(throwing: TransportError.bluetoothUnavailable)
                }
            }
        }
    }

    public func stopScan() async {
        await withCheckedContinuation { cont in
            bleQueue.async {
                self.manager.stopScan()
                self.scanTimeoutItem?.cancel()
                self.scanTimeoutItem = nil
                if case .scanning = self._state { self.setState(.idle) }
                cont.resume()
            }
        }
    }

    private func emitDiscovered() {
        let snapshot = scannedPeripherals.values.map(\.1)
            .sorted { ($0.rssi ?? -200) > ($1.rssi ?? -200) }
        for c in discoveredContinuations.values { c.yield(snapshot) }
    }

    public func connect(identifier: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            bleQueue.async {
                // Try the active scan results first; fall back to
                // `retrievePeripherals` for previously-paired peripherals we
                // haven't seen this session — that's the fast-reconnect path.
                let peripheral: CBPeripheral?
                if let cached = self.scannedPeripherals[identifier]?.0 {
                    peripheral = cached
                } else if let uuid = UUID(uuidString: identifier) {
                    peripheral = self.manager.retrievePeripherals(withIdentifiers: [uuid]).first
                } else {
                    peripheral = nil
                }
                guard let p = peripheral else {
                    cont.resume(throwing: TransportError.scanFailed("unknown peripheral \(identifier)"))
                    return
                }
                self.pendingPeripheral = p
                self.connectContinuation = cont
                self.setState(.connecting(name: p.name ?? identifier))
                self.manager.connect(p, options: nil)
            }
        }
    }

    public func disconnect() async {
        await withCheckedContinuation { cont in
            bleQueue.async {
                if let p = self.pendingPeripheral {
                    self.setState(.disconnecting)
                    self.manager.cancelPeripheralConnection(p)
                }
                self.modbusChar = nil
                self.eventChar = nil
                self.pendingPeripheral = nil
                self.setState(.idle)
                cont.resume()
            }
        }
    }

    public func sendModbus(_ frame: Data, timeout: TimeInterval) async throws -> Modbus.Response {
        try await withCheckedThrowingContinuation { cont in
            bleQueue.async {
                guard case .connected = self._state,
                      let p = self.pendingPeripheral,
                      let char = self.modbusChar else {
                    cont.resume(throwing: TransportError.notConnected); return
                }
                if self.pendingModbus != nil {
                    cont.resume(throwing: TransportError.writeFailed("another Modbus request is in flight"))
                    return
                }
                self.modbusBuffer.removeAll(keepingCapacity: true)
                let timeoutItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if let pending = self.pendingModbus {
                        self.pendingModbus = nil
                        pending.continuation.resume(throwing: TransportError.timeout)
                    }
                }
                self.pendingModbus = PendingModbus(continuation: cont, timeoutItem: timeoutItem)
                self.bleQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
                p.writeValue(frame, for: char, type: .withoutResponse)
            }
        }
    }

    public func sendModbusOneWay(_ frame: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            bleQueue.async {
                guard case .connected = self._state,
                      let p = self.pendingPeripheral,
                      let char = self.modbusChar else {
                    cont.resume(throwing: TransportError.notConnected); return
                }
                p.writeValue(frame, for: char, type: .withoutResponse)
                cont.resume()
            }
        }
    }

    public func sendFF55(_ frame: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            bleQueue.async {
                guard case .connected = self._state,
                      let p = self.pendingPeripheral,
                      let char = self.eventChar else {
                    cont.resume(throwing: TransportError.notConnected); return
                }
                p.writeValue(frame, for: char, type: .withoutResponse)
                cont.resume()
            }
        }
    }

    // MARK: - Internal

    private func setState(_ new: MachineState) {
        _state = new
        for c in stateContinuations.values { c.yield(new) }
    }

    private func emit(_ frame: ReceivedFrame) {
        for c in frameContinuations.values { c.yield(frame) }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEMachineTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Drain anything waiting on Bluetooth readiness.
        let waiters = readinessWaiters
        readinessWaiters.removeAll()
        switch central.state {
        case .poweredOn:
            for w in waiters { w.resume() }
        case .unauthorized:
            let msg = "Crema needs Bluetooth permission. Open System Settings → Privacy & Security → Bluetooth and enable Crema."
            for w in waiters { w.resume(throwing: TransportError.scanFailed(msg)) }
            setState(.failed(reason: msg))
        case .poweredOff:
            for w in waiters { w.resume(throwing: TransportError.bluetoothUnavailable) }
            if case .scanning = _state { setState(.failed(reason: "Bluetooth is off.")) }
        case .unsupported:
            let msg = "This Mac doesn't support Bluetooth LE."
            for w in waiters { w.resume(throwing: TransportError.scanFailed(msg)) }
            setState(.failed(reason: msg))
        case .unknown, .resetting:
            break  // keep waiting
        @unknown default:
            for w in waiters { w.resume(throwing: TransportError.bluetoothUnavailable) }
        }

        if central.state != .poweredOn, case .scanning = _state {
            scanTimeoutItem?.cancel()
            scanTimeoutItem = nil
        }
    }

    public func centralManager(_ central: CBCentralManager,
                                didDiscover peripheral: CBPeripheral,
                                advertisementData: [String : Any],
                                rssi RSSI: NSNumber) {
        guard let prefix = scanPrefix,
              let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String),
              name.hasPrefix(prefix) else { return }
        let id = peripheral.identifier.uuidString
        let now = Date()
        let existing = scannedPeripherals[id]?.1
        let peer = DiscoveredPeripheral(
            identifier: id,
            name: name,
            rssi: RSSI.intValue,
            firstSeenAt: existing?.firstSeenAt ?? now
        )
        scannedPeripherals[id] = (peripheral, peer)
        emitDiscovered()
    }

    public func centralManager(_ central: CBCentralManager,
                                didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: Machine.serviceUUID)])
    }

    public func centralManager(_ central: CBCentralManager,
                                didFailToConnect peripheral: CBPeripheral,
                                error: Error?) {
        connectContinuation?.resume(throwing: TransportError.writeFailed(error?.localizedDescription ?? "connect failed"))
        connectContinuation = nil
        setState(.failed(reason: error?.localizedDescription ?? "connect failed"))
    }

    public func centralManager(_ central: CBCentralManager,
                                didDisconnectPeripheral peripheral: CBPeripheral,
                                error: Error?) {
        modbusChar = nil
        eventChar = nil
        pendingPeripheral = nil
        setState(.idle)
    }
}

// MARK: - CBPeripheralDelegate

extension BLEMachineTransport: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == CBUUID(string: Machine.serviceUUID) {
            peripheral.discoverCharacteristics([
                CBUUID(string: Machine.modbusCharUUID),
                CBUUID(string: Machine.eventCharUUID),
            ], for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                            didDiscoverCharacteristicsFor service: CBService,
                            error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            if c.uuid == CBUUID(string: Machine.modbusCharUUID) {
                modbusChar = c
                peripheral.setNotifyValue(true, for: c)
            } else if c.uuid == CBUUID(string: Machine.eventCharUUID) {
                eventChar = c
                peripheral.setNotifyValue(true, for: c)
            }
        }
        if modbusChar != nil && eventChar != nil {
            let name = peripheral.name ?? "Wendougee"
            setState(.connected(name: name))
            connectContinuation?.resume()
            connectContinuation = nil
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                            didUpdateValueFor characteristic: CBCharacteristic,
                            error: Error?) {
        guard let data = characteristic.value else { return }

        if characteristic.uuid == CBUUID(string: Machine.eventCharUUID) {
            // FF55 notifications arrive whole — try to parse directly.
            if let frame = FF55.parse(data) {
                emit(.ff55(frame))
            }
            return
        }

        // Modbus channel — frames can arrive fragmented across notifications.
        // Accumulate and try to parse after each chunk.
        modbusBuffer.append(data)
        if let response = Modbus.parse(modbusBuffer) {
            modbusBuffer.removeAll(keepingCapacity: true)
            emit(.modbus(response))
            if let pending = pendingModbus {
                pending.timeoutItem.cancel()
                pendingModbus = nil
                pending.continuation.resume(returning: response)
            }
        }
    }
}
#endif

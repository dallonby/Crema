import Testing
import Foundation
@testable import CremaKit

@Suite("StubMachineTransport")
struct StubTransportTests {

    @Test("connect → idle lifecycle drives state correctly")
    func lifecycleStates() async throws {
        let t = StubMachineTransport()
        let stream = t.stateChanges()

        let collector = Task { () -> [MachineState] in
            var seen: [MachineState] = []
            for await s in stream {
                seen.append(s)
                if seen.count >= 5 { break }
            }
            return seen
        }

        let peer = try await t.discover(prefix: Machine.advertisingPrefix, timeout: 2)
        try await t.connect(identifier: peer.identifier)
        await t.disconnect()
        let states = await collector.value

        #expect(states.contains(.scanning))
        #expect(states.contains(where: { if case .connecting = $0 { return true } else { return false } }))
        #expect(states.contains(where: { if case .connected = $0 { return true } else { return false } }))
    }

    @Test("sendModbus returns synthesized echoes for writes")
    func writeEcho() async throws {
        let t = StubMachineTransport()
        let peer = try await t.discover(prefix: Machine.advertisingPrefix, timeout: 2)
        try await t.connect(identifier: peer.identifier)

        let response = try await t.sendModbus(
            Modbus.writeRegister(at: 87, value: 2), timeout: 1)
        #expect(response.function == Modbus.FunctionCode.writeRegister.rawValue)
    }

    @Test("sendProfile dispatches every step without error")
    func sendProfileDispatches() async throws {
        let t = StubMachineTransport()
        let peer = try await t.discover(prefix: Machine.advertisingPrefix, timeout: 2)
        try await t.connect(identifier: peer.identifier)
        try await t.sendProfile(.testyT, toSlot: .one, triggerBrew: false)
        // No throw = pass. There are 6 steps without trigger.
    }

    @Test("starting brew kicks off telemetry replay")
    func brewTriggersReplay() async throws {
        // Build a tiny 3-sample replay trace.
        var samples: [LiveTelemetry] = []
        for i in 0..<3 {
            samples.append(LiveTelemetry(
                elapsedDeciseconds: UInt16(i * 5),
                steamBoilerTempC: 100.0,
                brewBoilerTempC: 95.0,
                pressureBar: Double(i),
                totalVolumeMl: UInt16(i * 2),
                pumpTimeS: UInt16(i),
                pumpFlowMlS: Double(i),
                registers: []
            ))
        }
        let t = StubMachineTransport(replayTelemetry: samples)
        let peer = try await t.discover(prefix: Machine.advertisingPrefix, timeout: 2)
        try await t.connect(identifier: peer.identifier)

        let stream = t.receivedFrames()
        let collected = Task { () -> Int in
            var seen = 0
            for await frame in stream {
                if case .modbus(let r) = frame,
                   r.function == Modbus.FunctionCode.readHolding.rawValue {
                    seen += 1
                    if seen >= 3 { return seen }
                }
            }
            return seen
        }

        // Trigger replay
        _ = try await t.sendModbus(
            Modbus.writeCoil(at: Machine.startBrewCoil, on: true), timeout: 1)

        // Bound by total replay duration (~1s for 3 samples)
        let count = await withTaskGroup(of: Int.self) { group in
            group.addTask { await collected.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                collected.cancel()
                return -1
            }
            let first = await group.next() ?? 0
            group.cancelAll()
            return first
        }
        #expect(count >= 3)
        await t.disconnect()
    }

    @Test("rejects calls before connect")
    func rejectsBeforeConnect() async throws {
        let t = StubMachineTransport()
        await #expect(throws: TransportError.self) {
            _ = try await t.sendModbus(Modbus.writeCoil(at: 150, on: true), timeout: 1)
        }
    }
}

import Testing
import Foundation
@testable import CremaKit

@MainActor
@Suite("MachineRegistry")
struct MachineRegistryTests {

    /// Per-test UserDefaults suite so we don't pollute the user's defaults.
    private func freshRegistry() -> MachineRegistry {
        let defaults = UserDefaults(suiteName: "crema-test-\(UUID().uuidString)")!
        return MachineRegistry(defaults: defaults)
    }

    @Test("upsert adds, primary is auto-set on first add")
    func upsertSetsPrimary() {
        let r = freshRegistry()
        let m = PairedMachine(id: "abc", advertisedName: "WDG_Data_ABC")
        r.upsert(m)
        #expect(r.machines.count == 1)
        #expect(r.primary?.id == "abc")
    }

    @Test("primary stays sticky when a second machine is added")
    func primaryStaysSticky() {
        let r = freshRegistry()
        r.upsert(PairedMachine(id: "a", advertisedName: "WDG_Data_A"))
        r.upsert(PairedMachine(id: "b", advertisedName: "WDG_Data_B"))
        #expect(r.primary?.id == "a")
    }

    @Test("setPrimary switches the primary marker")
    func setPrimarySwitches() {
        let r = freshRegistry()
        r.upsert(PairedMachine(id: "a", advertisedName: "WDG_Data_A"))
        r.upsert(PairedMachine(id: "b", advertisedName: "WDG_Data_B"))
        r.setPrimary("b")
        #expect(r.primary?.id == "b")
    }

    @Test("forget removes and re-elects a primary if needed")
    func forgetRemoves() {
        let r = freshRegistry()
        r.upsert(PairedMachine(id: "a", advertisedName: "WDG_Data_A"))
        r.upsert(PairedMachine(id: "b", advertisedName: "WDG_Data_B"))
        r.forget("a")  // was primary
        #expect(r.machines.count == 1)
        #expect(r.primary?.id == "b")
    }

    @Test("rename trims whitespace and treats empty as nil")
    func renameHandlesEdges() {
        let r = freshRegistry()
        r.upsert(PairedMachine(id: "a", advertisedName: "WDG_Data_A"))
        r.rename("a", to: "  Sunday Lita  ")
        #expect(r.machines.first?.nickname == "Sunday Lita")
        r.rename("a", to: "")
        #expect(r.machines.first?.nickname == nil)
    }

    @Test("markConnected updates lastConnected so sort follows usage")
    func markConnectedSortsRecent() {
        let r = freshRegistry()
        r.upsert(PairedMachine(id: "a", advertisedName: "WDG_Data_A"))
        r.upsert(PairedMachine(id: "b", advertisedName: "WDG_Data_B"))
        r.setPrimary("a")
        r.markConnected("b", at: Date())
        // Primary still pinned first; then b (more recent) over a
        let order = r.sorted.map(\.id)
        #expect(order.first == "a")
        #expect(order.dropFirst().first == "b")
    }

    @Test("persistence round-trips through UserDefaults")
    func persistenceRoundTrips() {
        let suite = "crema-test-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let r = MachineRegistry(defaults: defaults)
        r.upsert(PairedMachine(id: "a", advertisedName: "WDG_Data_A",
                               nickname: "Sunday Lita"))
        let r2 = MachineRegistry(defaults: defaults)
        #expect(r2.machines.count == 1)
        #expect(r2.machines.first?.nickname == "Sunday Lita")
        #expect(r2.primary?.id == "a")
    }
}

@MainActor
@Suite("StubMachineTransport — discovery")
struct StubDiscoveryTests {

    @Test("scan emits the simulated fleet through discoveredPeripherals")
    func scanEmitsFleet() async throws {
        let t = StubMachineTransport()
        let stream = t.discoveredPeripherals()

        try await t.startScan(prefix: Machine.advertisingPrefix, timeout: 4)

        let collector = Task { () -> [DiscoveredPeripheral] in
            var last: [DiscoveredPeripheral] = []
            for await snapshot in stream {
                last = snapshot
                if last.count >= 2 { break }
            }
            return last
        }
        let result = await collector.value
        await t.stopScan()

        #expect(result.count >= 2)
        // Strongest signal first.
        if result.count >= 2 {
            #expect((result[0].rssi ?? -200) >= (result[1].rssi ?? -200))
        }
    }

    @Test("connect to a known simulated peripheral succeeds")
    func connectToKnown() async throws {
        let t = StubMachineTransport()
        let peer = [DiscoveredPeripheral].defaultStubFleet.first!
        // Fast-reconnect path — no scan first.
        try await t.connect(identifier: peer.identifier)
        if case .connected(let name) = await t.state {
            #expect(name == peer.name)
        } else {
            Issue.record("expected .connected, got \(await t.state)")
        }
    }

    @Test("connect to an unknown identifier throws")
    func connectUnknownThrows() async {
        let t = StubMachineTransport()
        await #expect(throws: TransportError.self) {
            try await t.connect(identifier: "nonsense")
        }
    }
}

import Foundation

/// A machine the user has seen at least once and chosen to remember. Identified
/// by the BLE peripheral's UUID, which is stable per-install on iOS/macOS
/// (CoreBluetooth assigns a deterministic UUID per peripheral so the app can
/// reconnect without a fresh scan).
///
/// We keep the user-facing fields here too (nickname, dates) so the picker
/// UI doesn't need to round-trip through a separate "profile" record.
public struct PairedMachine: Sendable, Codable, Hashable, Identifiable {
    /// The BLE peripheral's CoreBluetooth identifier as a string.
    public var id: String
    /// Advertised name from BLE (e.g. `WDG_Data_AB07116957`).
    public var advertisedName: String
    /// User-chosen nickname (e.g. "Sunday Lita"). Falls back to advertised name.
    public var nickname: String?
    /// First time we saw this machine.
    public var firstSeen: Date
    /// Most recent successful connection — used to sort the list "freshest first."
    public var lastConnected: Date?

    public var displayName: String { nickname ?? prettyAdvertisedName }

    /// `WDG_Data_AB07116957` → `Wendougee · 116957`. See `prettify(_:)`.
    public var prettyAdvertisedName: String {
        PairedMachine.prettify(advertisedName)
    }

    /// Static prettifier so the discovery UI (which only has the raw BLE
    /// advertised name in a `DiscoveredPeripheral`) gets the same friendly
    /// label as the paired list.
    public static func prettify(_ advertisedName: String) -> String {
        if let suffix = advertisedName.split(separator: "_").last, suffix.count >= 6 {
            return "Wendougee · \(suffix.suffix(6))"
        }
        return advertisedName
    }

    public init(id: String, advertisedName: String, nickname: String? = nil,
                firstSeen: Date = .now, lastConnected: Date? = nil) {
        self.id = id
        self.advertisedName = advertisedName
        self.nickname = nickname
        self.firstSeen = firstSeen
        self.lastConnected = lastConnected
    }
}

/// Observable, persistent store of paired machines. The primary machine is the
/// one Crema auto-connects to when the user enters Live mode — typically the
/// most-recently-used one, but the user can pin a different primary via the
/// machines picker.
@MainActor
@Observable
public final class MachineRegistry {

    public private(set) var machines: [PairedMachine] = []
    public private(set) var primaryID: String?

    /// Where to store the JSON blob. Defaults to `UserDefaults.standard`; tests
    /// pass a per-test suite so they don't pollute the user's defaults.
    private let defaults: UserDefaults
    private let machinesKey = "crema.machines.v1"
    private let primaryKey  = "crema.machines.primary.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// The currently-primary machine, or nil if none paired / primary missing.
    public var primary: PairedMachine? {
        guard let id = primaryID else { return machines.first }
        return machines.first(where: { $0.id == id }) ?? machines.first
    }

    public var isEmpty: Bool { machines.isEmpty }

    /// Add or update a machine. If `setAsPrimary` and there's no existing
    /// primary, this one becomes primary; otherwise the existing primary is
    /// untouched.
    @discardableResult
    public func upsert(_ machine: PairedMachine, setAsPrimary: Bool = false) -> PairedMachine {
        if let idx = machines.firstIndex(where: { $0.id == machine.id }) {
            // Preserve existing nickname/firstSeen if not provided.
            var existing = machines[idx]
            existing.advertisedName = machine.advertisedName
            if machine.nickname != nil { existing.nickname = machine.nickname }
            if let lc = machine.lastConnected { existing.lastConnected = lc }
            machines[idx] = existing
            save()
            return existing
        } else {
            machines.append(machine)
            if setAsPrimary || primaryID == nil {
                primaryID = machine.id
            }
            save()
            return machine
        }
    }

    public func forget(_ id: String) {
        machines.removeAll { $0.id == id }
        if primaryID == id { primaryID = machines.first?.id }
        save()
    }

    public func setPrimary(_ id: String) {
        guard machines.contains(where: { $0.id == id }) else { return }
        primaryID = id
        save()
    }

    public func rename(_ id: String, to nickname: String?) {
        guard let idx = machines.firstIndex(where: { $0.id == id }) else { return }
        var m = machines[idx]
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        m.nickname = (trimmed?.isEmpty == false) ? trimmed : nil
        machines[idx] = m
        save()
    }

    /// Bump `lastConnected` on a successful connection. Side-effect of every
    /// real connect, so the sort order in the picker tracks usage.
    public func markConnected(_ id: String, at date: Date = .now) {
        guard let idx = machines.firstIndex(where: { $0.id == id }) else { return }
        var m = machines[idx]
        m.lastConnected = date
        machines[idx] = m
        save()
    }

    /// Sorted view: primary first, then most-recently-connected, then by name.
    public var sorted: [PairedMachine] {
        machines.sorted { a, b in
            if a.id == primaryID { return true }
            if b.id == primaryID { return false }
            switch (a.lastConnected, b.lastConnected) {
            case (let la?, let lb?): return la > lb
            case (.some, .none):     return true
            case (.none, .some):     return false
            case (.none, .none):     return a.displayName < b.displayName
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        if let data = defaults.data(forKey: machinesKey),
           let decoded = try? JSONDecoder().decode([PairedMachine].self, from: data) {
            machines = decoded
        }
        primaryID = defaults.string(forKey: primaryKey)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(machines) {
            defaults.set(data, forKey: machinesKey)
        }
        if let primaryID {
            defaults.set(primaryID, forKey: primaryKey)
        } else {
            defaults.removeObject(forKey: primaryKey)
        }
    }
}

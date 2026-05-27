import Foundation

/// A captured shot — what the user actually pulled. Stores the brew profile
/// snapshot (so renames/deletions don't orphan history), the user's logged
/// outcome (yield, time, taste), free-text comments, and the captured
/// telemetry curve so the chart can replay it later.
public struct ShotLog: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date

    // Profile snapshot at brew time. Name is captured so the history list
    // shows the right label even if the source profile was renamed or deleted.
    public let profileID: UUID
    public let profileName: String
    public let targetYieldG: Double

    // Measured outcome
    public var measuredYieldG: Double?
    public let actualTimeS: Double
    public var taste: Taste
    public var comments: String

    /// One captured sample per ~290ms during the brew — enough to redraw the
    /// chart for the history detail view. Stored as a flat array of triples
    /// `(t, pressureBar, volumeMl)` to keep the JSON small. Flow is recoverable
    /// from dV/dt at display time.
    public let curve: [Sample]

    public struct Sample: Sendable, Hashable, Codable {
        public let t: Double
        public let pressureBar: Double
        public let volumeMl: Double
        public init(t: Double, pressureBar: Double, volumeMl: Double) {
            self.t = t; self.pressureBar = pressureBar; self.volumeMl = volumeMl
        }
    }

    public struct Taste: Sendable, Hashable, Codable {
        /// Sourness → bitterness axis. -1 = very sour, 0 = balanced, +1 = bitter.
        public var acidity: Double
        /// Weakness → strength axis. -1 = weak, 0 = balanced, +1 = strong.
        public var strength: Double
        public init(acidity: Double = 0, strength: Double = 0) {
            self.acidity = acidity; self.strength = strength
        }
        public static let unrated = Taste()
    }

    public init(id: UUID = UUID(), timestamp: Date = .now,
                profileID: UUID, profileName: String, targetYieldG: Double,
                measuredYieldG: Double? = nil, actualTimeS: Double,
                taste: Taste = .unrated, comments: String = "",
                curve: [Sample] = []) {
        self.id = id
        self.timestamp = timestamp
        self.profileID = profileID
        self.profileName = profileName
        self.targetYieldG = targetYieldG
        self.measuredYieldG = measuredYieldG
        self.actualTimeS = actualTimeS
        self.taste = taste
        self.comments = comments
        self.curve = curve
    }
}

/// Observable persistent log of every brew the user has saved. Capped at a
/// reasonable upper bound so the JSON blob doesn't grow unbounded over years.
@MainActor
@Observable
public final class ShotHistory {
    /// Most-recent first.
    public private(set) var shots: [ShotLog]

    private let defaults: UserDefaults
    private let key = "crema.shotHistory.v1"
    private let maxShots = 500   // ~years of daily use

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ShotLog].self, from: data) {
            self.shots = decoded
        } else {
            self.shots = []
        }
    }

    public var isEmpty: Bool { shots.isEmpty }

    /// Append a new shot. Newest entries are at the front; trims to `maxShots`.
    public func record(_ shot: ShotLog) {
        shots.insert(shot, at: 0)
        if shots.count > maxShots { shots.removeLast(shots.count - maxShots) }
        save()
    }

    public func updateComments(_ id: UUID, comments: String) {
        guard let idx = shots.firstIndex(where: { $0.id == id }) else { return }
        var s = shots[idx]
        s.comments = comments
        shots[idx] = s
        save()
    }

    public func updateTaste(_ id: UUID, taste: ShotLog.Taste) {
        guard let idx = shots.firstIndex(where: { $0.id == id }) else { return }
        var s = shots[idx]
        s.taste = taste
        shots[idx] = s
        save()
    }

    public func updateMeasuredYield(_ id: UUID, yield: Double?) {
        guard let idx = shots.firstIndex(where: { $0.id == id }) else { return }
        var s = shots[idx]
        s.measuredYieldG = yield
        shots[idx] = s
        save()
    }

    public func remove(_ id: UUID) {
        shots.removeAll { $0.id == id }
        save()
    }

    public func clearAll() {
        shots.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(shots) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Persistent set of tip / suggestion categories the user has dismissed
/// ("Don't show again"). Keys are stable strings so renaming a tip doesn't
/// undo a user's dismissal.
@MainActor
@Observable
public final class TipPreferences {
    public private(set) var dismissed: Set<String>

    private let defaults: UserDefaults
    private let key = "crema.tipPreferences.dismissed.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let arr = defaults.array(forKey: key) as? [String] {
            self.dismissed = Set(arr)
        } else {
            self.dismissed = []
        }
    }

    public func isDismissed(_ tipID: String) -> Bool {
        dismissed.contains(tipID)
    }

    public func dismiss(_ tipID: String) {
        dismissed.insert(tipID)
        defaults.set(Array(dismissed), forKey: key)
    }

    public func restoreAll() {
        dismissed.removeAll()
        defaults.removeObject(forKey: key)
    }
}

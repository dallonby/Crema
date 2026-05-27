import Foundation

/// User's brew profile library — observable, persistent. Exactly one profile
/// is `active` at a time; that's the one the brew button sends to the machine.
///
/// First-launch users get a small bundled library so they have something to
/// brew with immediately. Add/edit/delete from the UI; all changes persist
/// to UserDefaults via `Codable` JSON.
@MainActor
@Observable
public final class ProfileLibrary {

    public private(set) var profiles: [BrewProfile]
    public private(set) var activeProfileID: UUID

    private let defaults: UserDefaults
    private let profilesKey = "crema.profiles.v1"
    private let activeKey   = "crema.profiles.active.v1"

    public init(defaults: UserDefaults = .standard) {
        // Decide everything locally before touching self — @Observable's
        // macros require all stored properties be assigned before any other
        // self-reference, so cross-property fallbacks have to happen up here.
        let key = "crema.profiles.v1"
        let activeKey = "crema.profiles.active.v1"
        let loadedProfiles: [BrewProfile]
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([BrewProfile].self, from: data),
           !decoded.isEmpty {
            // Migration: TestyT used to ship as a bundled default but is now
            // only a test fixture. Strip any persisted copy from older installs
            // so they lose the dev artifact without losing their own profiles.
            // Older saves predate the pinned UUID, so match on name too.
            let testyTID = BrewProfile.testyT.id
            let pruned = decoded.filter { $0.id != testyTID && $0.name != "TestyT" }
            loadedProfiles = pruned.isEmpty ? ProfileLibrary.bundledDefaults : pruned
        } else {
            loadedProfiles = ProfileLibrary.bundledDefaults
        }
        let resolvedActive: UUID
        if let id = defaults.string(forKey: activeKey),
           let uuid = UUID(uuidString: id),
           loadedProfiles.contains(where: { $0.id == uuid }) {
            resolvedActive = uuid
        } else {
            resolvedActive = loadedProfiles[0].id
        }

        self.defaults = defaults
        self.profiles = loadedProfiles
        self.activeProfileID = resolvedActive
        save()  // persist any seeding we just did
    }

    /// The currently-active profile. Always non-nil because the library is
    /// guaranteed non-empty (the bundled defaults seed an empty library).
    public var active: BrewProfile {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0]
    }

    /// Add a new profile to the library. By default it becomes active so the
    /// user immediately sees what they just created.
    @discardableResult
    public func add(_ profile: BrewProfile, setActive: Bool = true) -> BrewProfile {
        profiles.append(profile)
        if setActive { activeProfileID = profile.id }
        save()
        return profile
    }

    /// Update an existing profile in place. The id is preserved, so the active
    /// pointer doesn't dangle.
    public func update(_ profile: BrewProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    /// Remove a profile. If it was active, the next remaining profile becomes
    /// active. Refuses to remove the last profile — the library can't be empty.
    public func remove(_ id: UUID) {
        guard profiles.count > 1 else { return }
        let wasActive = (id == activeProfileID)
        profiles.removeAll { $0.id == id }
        if wasActive { activeProfileID = profiles[0].id }
        save()
    }

    public func setActive(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        save()
    }

    /// Reset to the bundled defaults — useful for "restore defaults" in
    /// settings, and for tests.
    public func resetToDefaults() {
        profiles = ProfileLibrary.bundledDefaults
        activeProfileID = profiles[0].id
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
        defaults.set(activeProfileID.uuidString, forKey: activeKey)
    }
}

// MARK: - Bundled defaults

extension ProfileLibrary {
    /// Profiles every new install ships with. Classic Espresso is FIRST so it
    /// becomes the default-active for fresh installs.
    /// `BrewProfile.testyT` is intentionally NOT bundled — it's a captured
    /// dev fixture used by the encoder byte-exact tests, not a user-facing
    /// recipe. Kept around as a public static so the tests can reference it.
    public static var bundledDefaults: [BrewProfile] {
        [.classicEspresso, .turbo]
    }
}

extension BrewProfile {
    /// A traditional 1:2 espresso — gentle 4-bar preinfuse, 8 s bloom, hold
    /// flow at 1.7 mL/s during extraction, soft pressure tail. Ships with
    /// matched grinder settings (medium-fine, 567 RPM) so a fresh user can
    /// try the full grinder-write flow without authoring anything.
    public static let classicEspresso = BrewProfile(
        name: "Classic Espresso",
        stages: [
            // 2 s bloom pause after preinfuse — short enough to feel responsive,
            // long enough to let the puck saturate before extraction kicks in.
            BrewStage(label: "Preinfuse", duration: 6, priority: .pressure,
                      pressureBar: 4.0, waitAfter: 2),
            BrewStage(label: "Extract",   duration: 22, priority: .flow,
                      flowMlPerSec: 1.7, waitAfter: 0),
            BrewStage(label: "Tail",      duration: 4, priority: .pressure,
                      pressureBar: 1.0),
        ],
        mode: .flowVariablePressure,
        target: .flow,
        targetVolumeMl: 36,
        grinder: GrinderSettings(grindSizeMicrons: 76, rpm: 567, singleDose: false)
    )

    /// Turbo / "modern" espresso — no preinfusion, fast flow, low pressure.
    /// 1:3 ratio, in and out in ~15 s.
    public static let turbo = BrewProfile(
        name: "Turbo",
        stages: [
            BrewStage(label: "Extract", duration: 12, priority: .flow,
                      flowMlPerSec: 4.0, waitAfter: 0),
            BrewStage(label: "Tail",    duration: 3, priority: .pressure,
                      pressureBar: 0.8),
        ],
        mode: .flowVariablePressure,
        target: .flow,
        targetVolumeMl: 54
    )
}

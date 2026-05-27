import Testing
import Foundation
@testable import CremaKit

@MainActor
@Suite("ShotHistory")
struct ShotHistoryTests {

    private func freshHistory() -> ShotHistory {
        let defaults = UserDefaults(suiteName: "crema-history-test-\(UUID().uuidString)")!
        return ShotHistory(defaults: defaults)
    }

    private func sampleLog() -> ShotLog {
        ShotLog(
            profileID: UUID(), profileName: "Classic Espresso",
            targetYieldG: 36, measuredYieldG: 32, actualTimeS: 28,
            taste: .init(acidity: -0.5, strength: 0),
            comments: "Sour, ran short"
        )
    }

    @Test("record inserts newest-first and persists")
    func recordOrder() {
        let suite = "crema-history-order-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let h = ShotHistory(defaults: d)
        let a = sampleLog()
        let b = ShotLog(
            profileID: UUID(), profileName: "Turbo",
            targetYieldG: 54, actualTimeS: 12
        )
        h.record(a)
        h.record(b)
        #expect(h.shots.first?.id == b.id)
        #expect(h.shots.last?.id == a.id)
        // Reload and check persistence
        let h2 = ShotHistory(defaults: d)
        #expect(h2.shots.count == 2)
        #expect(h2.shots.first?.id == b.id)
    }

    @Test("updateComments and updateTaste mutate the right row")
    func mutations() {
        let h = freshHistory()
        let log = sampleLog()
        h.record(log)
        h.updateComments(log.id, comments: "Updated note")
        h.updateTaste(log.id, taste: .init(acidity: 0.5, strength: 0.3))
        let s = h.shots.first!
        #expect(s.comments == "Updated note")
        #expect(s.taste.acidity == 0.5)
        #expect(s.taste.strength == 0.3)
    }

    @Test("remove and clearAll")
    func removeAndClear() {
        let h = freshHistory()
        let a = sampleLog()
        let b = sampleLog()
        h.record(a); h.record(b)
        h.remove(a.id)
        #expect(h.shots.count == 1)
        #expect(h.shots.first?.id == b.id)
        h.clearAll()
        #expect(h.shots.isEmpty)
    }
}

@MainActor
@Suite("TipPreferences")
struct TipPreferencesTests {

    @Test("dismiss persists across reloads")
    func dismissPersists() {
        let suite = "crema-tips-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let p = TipPreferences(defaults: d)
        #expect(!p.isDismissed("yieldShort.sour"))
        p.dismiss("yieldShort.sour")
        #expect(p.isDismissed("yieldShort.sour"))
        let p2 = TipPreferences(defaults: d)
        #expect(p2.isDismissed("yieldShort.sour"))
    }

    @Test("restoreAll clears every dismissal")
    func restoreAll() {
        let p = TipPreferences(defaults: UserDefaults(suiteName: "crema-tips-r-\(UUID().uuidString)")!)
        p.dismiss("a"); p.dismiss("b")
        p.restoreAll()
        #expect(!p.isDismissed("a"))
        #expect(!p.isDismissed("b"))
    }
}

@MainActor
@Suite("ProfileTweakSuggester")
struct ProfileTweakSuggesterTests {

    private let profile = BrewProfile.classicEspresso

    @Test("yield short + sour → coarser grind, high confidence")
    func yieldShortSour() {
        let log = ShotLog(
            profileID: profile.id, profileName: profile.name,
            targetYieldG: 36, measuredYieldG: 28, actualTimeS: 38,
            taste: .init(acidity: -0.6, strength: 0)
        )
        let s = ProfileTweakSuggester.suggest(for: profile, log: log)
        #expect(s.first?.id == "yieldShort.sour")
        #expect(s.first?.confidence == .high)
        // Apply should coarsen the grinder by +8 µm
        let mutated = s.first!.apply(to: profile)
        if let g = mutated.grinder, let orig = profile.grinder {
            #expect(g.grindSizeMicrons == orig.grindSizeMicrons + 8)
        }
    }

    @Test("yield over + bitter → finer grind, high confidence")
    func yieldOverBitter() {
        let log = ShotLog(
            profileID: profile.id, profileName: profile.name,
            targetYieldG: 36, measuredYieldG: 44, actualTimeS: 18,
            taste: .init(acidity: 0.6, strength: 0)
        )
        let s = ProfileTweakSuggester.suggest(for: profile, log: log)
        #expect(s.first?.id == "yieldOver.bitter")
        #expect(s.first?.confidence == .high)
    }

    @Test("balanced shot near target → no suggestions")
    func balanced() {
        let log = ShotLog(
            profileID: profile.id, profileName: profile.name,
            targetYieldG: 36, measuredYieldG: 36, actualTimeS: 30,
            taste: .init(acidity: 0, strength: 0)
        )
        let s = ProfileTweakSuggester.suggest(for: profile, log: log)
        #expect(s.isEmpty)
    }

    @Test("sour-only at correct yield → finer grind, medium confidence")
    func sourOnly() {
        let log = ShotLog(
            profileID: profile.id, profileName: profile.name,
            targetYieldG: 36, measuredYieldG: 36, actualTimeS: 30,
            taste: .init(acidity: -0.6, strength: 0)
        )
        let s = ProfileTweakSuggester.suggest(for: profile, log: log)
        #expect(s.first?.id == "sourOnly")
        #expect(s.first?.confidence == .medium)
    }

    @Test("Apply with grinder mutation respects bounds")
    func grinderBounds() {
        let extremeFine = BrewProfile(
            name: "Test", stages: profile.stages,
            grinder: GrinderSettings(grindSizeMicrons: 25, rpm: 567)
        )
        let mutation = TweakSuggestion(
            id: "test", headline: "Finer", reason: "test",
            confidence: .high, mutation: .grinderSize(deltaMicrons: -100)
        )
        let result = mutation.apply(to: extremeFine)
        #expect(result.grinder?.grindSizeMicrons == 20)   // clamped to floor
    }
}

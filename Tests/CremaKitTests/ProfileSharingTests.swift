import Testing
import Foundation
@testable import CremaKit

@Suite("ProfileShareCodec")
struct ProfileShareCodecTests {

    @Test("encode → decode roundtrip preserves the profile")
    func roundtripPreservesProfile() throws {
        let original = ShareableProfile(
            profile: BrewProfile.classicEspresso,
            beanName: "Ethiopian Yirgacheffe",
            equipment: "Wendougee LITA-BA + Niche Zero",
            description: "Floral, bright, my house bean",
            sharedByName: "Dave"
        )
        let data = try ProfileShareCodec.encode(original)
        let decoded = try ProfileShareCodec.decode(data)

        #expect(decoded.profile.id == original.profile.id)
        #expect(decoded.profile.name == original.profile.name)
        #expect(decoded.profile.stages.count == original.profile.stages.count)
        #expect(decoded.beanName == original.beanName)
        #expect(decoded.equipment == original.equipment)
        #expect(decoded.description == original.description)
        #expect(decoded.sharedByName == original.sharedByName)
        #expect(decoded.version == 1)
    }

    @Test("writeTempFile produces a readable .crema file")
    func writeAndReadFile() throws {
        let original = ShareableProfile(profile: BrewProfile.turbo)
        let url = try ProfileShareCodec.writeTempFile(original)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.pathExtension == "crema")
        #expect(FileManager.default.fileExists(atPath: url.path))

        let reloaded = try ProfileShareCodec.read(url)
        #expect(reloaded.profile.id == original.profile.id)
        #expect(reloaded.profile.name == original.profile.name)
    }

    @Test("encoded JSON is deterministic (sorted keys)")
    func encodingIsDeterministic() throws {
        let p = ShareableProfile(profile: BrewProfile.turbo)
        let a = try ProfileShareCodec.encode(p)
        let b = try ProfileShareCodec.encode(p)
        #expect(a == b)
    }

    @Test("filename derived from profile name, sanitised")
    func filenameIsSafe() throws {
        let messy = BrewProfile(
            name: "My Bean / 18g (1:2) — Test",
            stages: [BrewStage(label: "X", duration: 1, priority: .pressure, pressureBar: 6)],
            mode: .flowVariablePressure,
            target: .flow,
            targetVolumeMl: 36
        )
        let url = try ProfileShareCodec.writeTempFile(ShareableProfile(profile: messy))
        defer { try? FileManager.default.removeItem(at: url) }
        let filename = url.lastPathComponent
        // No spaces, slashes, parens, em-dashes, colons:
        #expect(!filename.contains(" "))
        #expect(!filename.contains("/"))
        #expect(!filename.contains("("))
        #expect(!filename.contains("—"))
        #expect(filename.hasSuffix(".crema"))
    }
}

@Suite("ShareableProfileURL")
struct ShareableProfileURLTests {

    @Test("parses crema://profile/<id> deep links")
    func parsesDeepLink() {
        let u = URL(string: "crema://profile/abc12345")!
        let p = ShareableProfileURL(url: u)
        #expect(p?.id == "abc12345")
    }

    @Test("parses https://<base>/p/<id> web links")
    func parsesWebLink() {
        let u = URL(string: "https://crema.coffee/p/k7Fp2nLm")!
        let p = ShareableProfileURL(url: u)
        #expect(p?.id == "k7Fp2nLm")
    }

    @Test("rejects unrelated URLs")
    func rejectsOthers() {
        let cases = [
            "https://example.com/",
            "https://crema.coffee/some/other/path",
            "crema://",
            "crema://settings",
            "mailto:hi@crema.coffee",
        ]
        for s in cases {
            let u = URL(string: s)!
            #expect(ShareableProfileURL(url: u) == nil, "Should reject: \(s)")
        }
    }

    @Test("round-trips through deepLink + web URL")
    func roundTrip() {
        let original = ShareableProfileURL(id: "xYz9KLm2")
        let viaDeep = ShareableProfileURL(url: original.deepLink)
        let viaWeb = ShareableProfileURL(
            url: original.webURL(base: URL(string: "https://crema.coffee")!))
        #expect(viaDeep?.id == original.id)
        #expect(viaWeb?.id == original.id)
    }
}

@Suite("AutoTuneRecommender")
struct AutoTuneRecommenderTests {

    @Test("initial recommendation has grinder + sensible defaults")
    func initialHasGrinder() {
        let inputs = AutoTuneInputs(beanName: "Test", roast: .medium, drink: .espresso,
                                     dose: 18, targetYield: 36)
        let rec = AutoTuneRecommender.initial(inputs)
        #expect(rec.profile.grinder != nil)
        #expect(rec.profile.stages.contains { $0.label == "Preinfuse" })
        #expect(rec.profile.stages.contains { $0.label == "Extract" })
    }

    @Test("verdict — dialed in within window")
    func dialedInVerdict() {
        let inputs = AutoTuneInputs(roast: .medium, dose: 18, targetYield: 36)
        // Medium roast target window is 25...32 s
        let v = AutoTuneRecommender.verdict(actualTimeS: 28, actualYieldG: 36, inputs: inputs)
        #expect(v == .dialed)
    }

    @Test("verdict — too fast triggers ranTooFast")
    func tooFastVerdict() {
        let inputs = AutoTuneInputs(roast: .medium, dose: 18, targetYield: 36)
        let v = AutoTuneRecommender.verdict(actualTimeS: 18, actualYieldG: 36, inputs: inputs)
        #expect(v == .ranTooFast)
    }

    @Test("verdict — too slow triggers ranTooSlow")
    func tooSlowVerdict() {
        let inputs = AutoTuneInputs(roast: .medium, dose: 18, targetYield: 36)
        let v = AutoTuneRecommender.verdict(actualTimeS: 40, actualYieldG: 36, inputs: inputs)
        #expect(v == .ranTooSlow)
    }

    @Test("score — dialed shot gets high score")
    func scoresDialedShotHigh() {
        let inputs = AutoTuneInputs(roast: .medium, dose: 18, targetYield: 36)
        let s = AutoTuneRecommender.score(actualTimeS: 28, actualYieldG: 36, inputs: inputs)
        #expect(s >= 80)
    }

    @Test("score — way-off shot gets low score")
    func scoresBadShotLow() {
        let inputs = AutoTuneInputs(roast: .medium, dose: 18, targetYield: 36)
        let s = AutoTuneRecommender.score(actualTimeS: 12, actualYieldG: 15, inputs: inputs)
        #expect(s < 50)
    }

    @Test("next recommendation is nil when last shot was dialed")
    func dialedTerminatesIteration() {
        let inputs = AutoTuneInputs(roast: .medium, dose: 18, targetYield: 36)
        let initial = AutoTuneRecommender.initial(inputs)
        let history = [AutoTuneShotResult(
            shotNumber: 1,
            profile: initial.profile,
            grindMicrons: initial.grindMicrons,
            actualYieldG: 36,
            actualTimeS: 28,
            verdict: .dialed,
            scoreOutOf100: 95
        )]
        #expect(AutoTuneRecommender.next(inputs: inputs, history: history) == nil)
    }

    @Test("next — too-fast shot recommends finer grind")
    func suggestsFinerGrindAfterFastShot() {
        let inputs = AutoTuneInputs(roast: .medium, dose: 18, targetYield: 36)
        let initial = AutoTuneRecommender.initial(inputs)
        let history = [AutoTuneShotResult(
            shotNumber: 1,
            profile: initial.profile,
            grindMicrons: initial.grindMicrons,
            actualYieldG: 36,
            actualTimeS: 15,           // way too fast
            verdict: .ranTooFast,
            scoreOutOf100: 60
        )]
        let rec = AutoTuneRecommender.next(inputs: inputs, history: history)
        #expect(rec != nil)
        #expect(rec!.grindMicrons < initial.grindMicrons,
                "Fast shot should produce finer (lower µm) grind")
    }

    @Test("next — too-slow shot recommends coarser grind")
    func suggestsCoarserGrindAfterSlowShot() {
        let inputs = AutoTuneInputs(roast: .medium, dose: 18, targetYield: 36)
        let initial = AutoTuneRecommender.initial(inputs)
        let history = [AutoTuneShotResult(
            shotNumber: 1,
            profile: initial.profile,
            grindMicrons: initial.grindMicrons,
            actualYieldG: 36,
            actualTimeS: 45,
            verdict: .ranTooSlow,
            scoreOutOf100: 55
        )]
        let rec = AutoTuneRecommender.next(inputs: inputs, history: history)
        #expect(rec != nil)
        #expect(rec!.grindMicrons > initial.grindMicrons,
                "Slow shot should produce coarser (higher µm) grind")
    }
}

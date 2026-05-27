import Foundation

/// A suggested change to a brew profile, derived from a logged shot's outcome.
///
/// Each suggestion has:
/// - a stable `id` so "Don't show again" preferences can persist
/// - human-readable `headline` + `reason` — transparent rule-based reasoning
/// - `confidence` — how strongly the data supports it
/// - `apply(_:)` — pure function that returns a mutated profile
///
/// Rules are deliberately opinionated but explainable — every classic
/// barista-school troubleshooting rule, formalised. Users see WHY and choose
/// whether to Apply, Save as variant, or Skip.
public struct TweakSuggestion: Sendable, Hashable, Identifiable {
    public let id: String
    public let headline: String
    public let reason: String
    public let confidence: Confidence
    /// Stored as a function would prevent Codable / Hashable conformance; we
    /// model the mutation as a typed value instead and apply it in `apply(_:)`.
    public let mutation: Mutation

    public enum Confidence: String, Sendable, Hashable, Codable {
        case low, medium, high
    }

    public enum Mutation: Sendable, Hashable {
        /// Adjust grinder size by ±N µm (positive = coarser, negative = finer).
        case grinderSize(deltaMicrons: Int)
        /// Scale every flow-priority stage's setpoint by `factor` (e.g. 0.9 = slower).
        case flowSetpoint(factor: Double)
        /// Scale every flow-priority stage's duration by `factor`.
        case extractTime(factor: Double)
        /// Scale every pressure-priority stage's pressure by `factor`.
        case pressure(factor: Double)
    }

    public func apply(to profile: BrewProfile) -> BrewProfile {
        var stages = profile.stages
        var grinder = profile.grinder

        switch mutation {
        case .grinderSize(let delta):
            if var g = grinder {
                let current = Int(g.grindSizeMicrons)
                let newSize = max(20, min(255, current + delta))
                g.grindSizeMicrons = UInt8(newSize)
                grinder = g
            }
            // If no grinder settings yet, this is a no-op — the suggestion sheet
            // should surface a hint to enable grinder settings first.
        case .flowSetpoint(let factor):
            stages = stages.map { s in
                guard s.priority == .flow else { return s }
                return BrewStage(
                    id: s.id, label: s.label, duration: s.duration,
                    priority: s.priority,
                    pressureBar: s.pressureBar,
                    flowMlPerSec: max(0.1, s.flowMlPerSec * factor),
                    waitAfter: s.waitAfter
                )
            }
        case .extractTime(let factor):
            stages = stages.map { s in
                guard s.priority == .flow else { return s }
                return BrewStage(
                    id: s.id, label: s.label, duration: max(1, s.duration * factor),
                    priority: s.priority,
                    pressureBar: s.pressureBar,
                    flowMlPerSec: s.flowMlPerSec,
                    waitAfter: s.waitAfter
                )
            }
        case .pressure(let factor):
            stages = stages.map { s in
                guard s.priority == .pressure else { return s }
                return BrewStage(
                    id: s.id, label: s.label, duration: s.duration,
                    priority: s.priority,
                    pressureBar: max(0.5, min(12, s.pressureBar * factor)),
                    flowMlPerSec: s.flowMlPerSec,
                    waitAfter: s.waitAfter
                )
            }
        }

        return BrewProfile(
            id: profile.id, name: profile.name, stages: stages,
            mode: profile.mode, target: profile.target,
            directExtract: profile.directExtract,
            variableFlow: profile.variableFlow,
            targetVolumeMl: profile.targetVolumeMl,
            targetWeightG: profile.targetWeightG,
            autoLink: profile.autoLink,
            grinder: grinder
        )
    }
}

/// Rule engine: takes a profile + the user's logged outcome, returns ordered
/// suggestions (highest-confidence first). Empty when the shot was within
/// targets and tasted balanced — no changes needed.
public enum ProfileTweakSuggester {

    public static func suggest(for profile: BrewProfile, log: ShotLog) -> [TweakSuggestion] {
        var out: [TweakSuggestion] = []

        // Yield delta (%) — what fraction of the target ended up in the cup.
        // Only meaningful if the user actually measured a yield.
        let yieldDelta: Double?
        if let measured = log.measuredYieldG, log.targetYieldG > 0 {
            yieldDelta = (measured - log.targetYieldG) / log.targetYieldG
        } else {
            yieldDelta = nil
        }
        let acid = log.taste.acidity      // -1 sour .. +1 bitter
        let strength = log.taste.strength // -1 weak .. +1 strong

        // Headline rules — yield + taste agree, highest confidence.
        if let d = yieldDelta {
            // Significantly short AND sour → puck is choking. Coarsen + shorten.
            if d < -0.10 && acid < -0.25 {
                out.append(.init(
                    id: "yieldShort.sour",
                    headline: "Coarser grind",
                    reason: "Shot ran short (\(percentString(d))) and tasted sour — the puck is choking. Loosen it up so water spends less time over the grounds.",
                    confidence: .high,
                    mutation: .grinderSize(deltaMicrons: +8)
                ))
            }
            // Significantly over AND bitter → over-extracted gusher. Tighten grind, lower flow.
            if d > 0.10 && acid > 0.25 {
                out.append(.init(
                    id: "yieldOver.bitter",
                    headline: "Finer grind",
                    reason: "Shot ran long (\(percentString(d))) and tasted bitter — too much water passing through too fast and over-extracting. Tighten the grind.",
                    confidence: .high,
                    mutation: .grinderSize(deltaMicrons: -6)
                ))
            }
            // Yield short but taste OK → could just be flow setpoint
            if d < -0.10 && abs(acid) <= 0.25 {
                out.append(.init(
                    id: "yieldShort.balanced",
                    headline: "Higher flow target",
                    reason: "Yield was \(percentString(d)) short but taste was balanced. Try a slightly higher flow setpoint to hit the target without grinding coarser.",
                    confidence: .medium,
                    mutation: .flowSetpoint(factor: 1.1)
                ))
            }
            // Yield over but taste OK → trim the flow
            if d > 0.10 && abs(acid) <= 0.25 {
                out.append(.init(
                    id: "yieldOver.balanced",
                    headline: "Lower flow target",
                    reason: "Yield overshot by \(percentString(d)) but taste was balanced. Drop the flow setpoint slightly to land on target.",
                    confidence: .medium,
                    mutation: .flowSetpoint(factor: 0.92)
                ))
            }
        }

        // Taste-only signals when yield was on target (or unmeasured).
        if yieldDelta == nil || abs(yieldDelta!) <= 0.10 {
            if acid < -0.4 {
                out.append(.init(
                    id: "sourOnly",
                    headline: "Finer grind",
                    reason: "Shot tasted sour — under-extracted. A finer grind extracts more solubles in the same time.",
                    confidence: .medium,
                    mutation: .grinderSize(deltaMicrons: -4)
                ))
            }
            if acid > 0.4 {
                out.append(.init(
                    id: "bitterOnly",
                    headline: "Coarser grind",
                    reason: "Shot tasted bitter — over-extracted. Coarsen slightly to slow the extraction down.",
                    confidence: .medium,
                    mutation: .grinderSize(deltaMicrons: +4)
                ))
            }
            if strength < -0.4 {
                out.append(.init(
                    id: "weakOnly",
                    headline: "Lower yield target",
                    reason: "Shot tasted weak — try a tighter ratio (less water relative to dose) for more concentration.",
                    confidence: .low,
                    mutation: .flowSetpoint(factor: 0.95)
                ))
            }
            if strength > 0.4 {
                out.append(.init(
                    id: "strongOnly",
                    headline: "Higher yield target",
                    reason: "Shot tasted strong — try a looser ratio (more water relative to dose) for more balance.",
                    confidence: .low,
                    mutation: .flowSetpoint(factor: 1.05)
                ))
            }
        }

        // Sort by confidence descending so the most-supported suggestion leads.
        return out.sorted { confidenceRank($0.confidence) > confidenceRank($1.confidence) }
    }

    private static func confidenceRank(_ c: TweakSuggestion.Confidence) -> Int {
        switch c { case .high: 3; case .medium: 2; case .low: 1 }
    }

    private static func percentString(_ frac: Double) -> String {
        let pct = Int(abs(frac) * 100)
        return "\(pct)%"
    }
}

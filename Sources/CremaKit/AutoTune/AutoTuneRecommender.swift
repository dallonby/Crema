import Foundation

/// Pure-functional recipe recommender for the auto-tune flow. Stateless: all
/// inputs are explicit, all outputs deterministic, no mutation. Easy to unit
/// test in isolation and easy to reason about.
public enum AutoTuneRecommender {

    // MARK: - First shot

    /// Pick a sensible starting profile given bean inputs alone.
    /// Convention: bean name goes into the profile name, but the profile
    /// stays out of the library until the user chooses to save it.
    public static func initial(_ inputs: AutoTuneInputs) -> AutoTuneRecommendation {
        let grind = inputs.roast.initialGrindMicrons
        let profile = makeProfile(
            inputs: inputs,
            grindMicrons: grind,
            extractionPressureBar: inputs.drink.extractionPressureBar,
            extractionDurationS: 22
        )
        let beanLabel = inputs.beanName.isEmpty ? "this bean" : inputs.beanName
        return AutoTuneRecommendation(
            profile: profile,
            grindMicrons: grind,
            advice: "Starting point for a \(inputs.roast.display.lowercased()) roast \(inputs.drink == .milkBased ? "milk drink" : "espresso shot"). We'll refine from here based on \(beanLabel)'s shot time and yield.",
            changeSummary: "First attempt — establishing baseline",
            confidence: .medium
        )
    }

    // MARK: - Subsequent shots

    /// Compute the next recommendation given prior shots. Returns nil if the
    /// last shot was good enough to call it done.
    public static func next(
        inputs: AutoTuneInputs,
        history: [AutoTuneShotResult]
    ) -> AutoTuneRecommendation? {
        guard let last = history.last else { return initial(inputs) }
        if last.verdict == .dialed { return nil }

        // Diminishing adjustment as we get more data — each iteration tightens.
        let attempt = history.count
        let stepScale = max(0.4, 1.0 - 0.25 * Double(attempt - 1))
        let prevGrind = Double(last.grindMicrons)
        let prevPressure = extractionPressure(of: last.profile)
        let centerTime = (inputs.roast.targetTimeWindow.lowerBound
                        + inputs.roast.targetTimeWindow.upperBound) / 2.0
        let timeDelta = last.actualTimeS - centerTime
        let yieldDelta = last.actualYieldG - inputs.targetYield

        // Decide axis: prefer grind adjustment if a grinder's configured,
        // otherwise tweak extraction pressure.
        let canTuneGrind = last.profile.grinder != nil

        var newGrind = prevGrind
        var newPressure = prevPressure
        var change = ""
        var advice = ""

        switch last.verdict {
        case .ranTooFast, .yieldTooHigh:
            // Fast / gushy → tighten the grind (or push pressure down a touch).
            // 1 µm ≈ 0.5 s of contact-time shift in this size range as a heuristic.
            let µmShift = clamp(abs(timeDelta) * 2.0 * stepScale, lo: 3, hi: 18)
            if canTuneGrind {
                newGrind = clampGrind(prevGrind - µmShift)
                change = "Grind \(Int(µmShift.rounded())) µm finer"
                advice = "Shot ran \(secondsBlurb(timeDelta)) too fast. Tightening the grind slows the flow and pulls more from the puck."
            } else {
                let bShift = clamp(abs(timeDelta) * 0.05 * stepScale, lo: 0.2, hi: 1.0)
                newPressure = clampPressure(prevPressure - bShift)
                change = String(format: "Lower extraction pressure by %.1f bar", bShift)
                advice = "Shot ran \(secondsBlurb(timeDelta)) too fast. Reducing pressure slows the pump and lets the puck resist longer."
            }
        case .ranTooSlow, .yieldTooLow:
            let µmShift = clamp(abs(timeDelta) * 2.0 * stepScale, lo: 3, hi: 18)
            if canTuneGrind {
                newGrind = clampGrind(prevGrind + µmShift)
                change = "Grind \(Int(µmShift.rounded())) µm coarser"
                advice = "Shot ran \(secondsBlurb(timeDelta)) too slow. Opening up the grind lets the water flow more freely."
            } else {
                let bShift = clamp(abs(timeDelta) * 0.05 * stepScale, lo: 0.2, hi: 1.0)
                newPressure = clampPressure(prevPressure + bShift)
                change = String(format: "Raise extraction pressure by %.1f bar", bShift)
                advice = "Shot ran \(secondsBlurb(timeDelta)) too slow. More pressure will push through the resistance."
            }
        case .dialed:
            return nil  // handled above
        }

        // Tiny extra nudge if yield is also off significantly — extends or
        // shortens the extraction stage to land closer.
        var newExtractionS: Double = 22
        if let lastExtraction = last.profile.stages.first(where: { $0.label == "Extract" }) {
            newExtractionS = lastExtraction.duration
        }
        if abs(yieldDelta) > inputs.targetYield * 0.1 {
            newExtractionS += yieldDelta < 0 ? 2 : -2
            newExtractionS = clamp(newExtractionS, lo: 15, hi: 32)
        }

        let profile = makeProfile(
            inputs: inputs,
            grindMicrons: UInt8(newGrind.rounded()),
            extractionPressureBar: newPressure,
            extractionDurationS: newExtractionS
        )

        let confidence: AutoTuneRecommendation.Confidence = {
            if attempt >= 2 { return abs(timeDelta) < 4 ? .high : .medium }
            return .medium
        }()

        return AutoTuneRecommendation(
            profile: profile,
            grindMicrons: UInt8(newGrind.rounded()),
            advice: advice,
            changeSummary: change,
            confidence: confidence
        )
    }

    // MARK: - Verdict

    /// Classify a shot result against the target window/yield.
    public static func verdict(
        actualTimeS: Double,
        actualYieldG: Double,
        inputs: AutoTuneInputs
    ) -> AutoTuneShotResult.Verdict {
        let window = inputs.roast.targetTimeWindow
        let yieldOK = abs(actualYieldG - inputs.targetYield) <= inputs.targetYield * 0.15
        let timeOK  = window.contains(actualTimeS)

        if timeOK && yieldOK { return .dialed }
        if actualTimeS < window.lowerBound { return .ranTooFast }
        if actualTimeS > window.upperBound { return .ranTooSlow }
        if actualYieldG > inputs.targetYield { return .yieldTooHigh }
        return .yieldTooLow
    }

    /// 0–100 score blending time proximity + yield proximity. Pure cosmetic.
    public static func score(
        actualTimeS: Double,
        actualYieldG: Double,
        inputs: AutoTuneInputs
    ) -> Int {
        let centerTime = (inputs.roast.targetTimeWindow.lowerBound
                        + inputs.roast.targetTimeWindow.upperBound) / 2.0
        let timeWindowHalf = (inputs.roast.targetTimeWindow.upperBound - centerTime)
        let timeDelta = abs(actualTimeS - centerTime)
        let timeScore = max(0, 1 - timeDelta / (timeWindowHalf * 2))  // 0 at 2x window
        let yieldDelta = abs(actualYieldG - inputs.targetYield)
        let yieldScore = max(0, 1 - yieldDelta / (inputs.targetYield * 0.3))
        return Int(((timeScore * 0.6 + yieldScore * 0.4) * 100).rounded())
    }

    // MARK: - Helpers

    private static func makeProfile(
        inputs: AutoTuneInputs,
        grindMicrons: UInt8,
        extractionPressureBar: Double,
        extractionDurationS: Double
    ) -> BrewProfile {
        // IMPORTANT volume-target handling for auto-tune:
        //
        // The machine's volume metering is PRE-puck (pump throughput, not cup
        // weight) — typically 1.5–2× the dose mass gets absorbed by the grounds
        // before any liquid lands in the cup. If we asked the firmware to stop
        // at the user's target *cup yield* in mL, it would stop after ~5 g had
        // actually landed.
        //
        // First instinct was to leave `targetVolumeMl: nil` and run open-ended,
        // but encoding nil writes 0 into the total_flow header register and the
        // firmware silently refuses to start the brew (pumps never trigger).
        //
        // Workaround: pass a deliberately high value (200 mL) — well above any
        // realistic pump volume for an espresso shot (typically peaks ~80–120
        // mL by the time the cup hits 36 g). The brew gets stopped by:
        //   - the user tapping "Stop — Xg in cup" in the wizard, or
        //   - the session auto-stopping when a BLE scale reads target.
        // The firmware's volume target becomes a safety ceiling rather than
        // the operative stop trigger.
        let stages: [BrewStage] = [
            BrewStage(label: "Preinfuse", duration: 7,
                      priority: .pressure, pressureBar: 4.0, waitAfter: 2),
            BrewStage(label: "Extract", duration: max(extractionDurationS, 45),
                      priority: .pressure, pressureBar: extractionPressureBar, waitAfter: 0),
            BrewStage(label: "Tail", duration: 6,
                      priority: .pressure, pressureBar: 1.0, waitAfter: 0),
        ]
        let beanName = inputs.beanName.isEmpty ? "Bean" : inputs.beanName
        return BrewProfile(
            name: "Auto · \(beanName)",
            stages: stages,
            mode: .flowVariablePressure,
            target: .flow,
            targetVolumeMl: 200,  // safety ceiling, not stop trigger — see above
            grinder: GrinderSettings(grindSizeMicrons: grindMicrons, rpm: 600, singleDose: true)
        )
    }

    private static func extractionPressure(of profile: BrewProfile) -> Double {
        profile.stages.first(where: { $0.label == "Extract" })?.pressureBar ?? 9.0
    }

    private static func clampGrind(_ v: Double) -> Double { clamp(v, lo: 30, hi: 250) }
    private static func clampPressure(_ v: Double) -> Double { clamp(v, lo: 4, hi: 12) }

    private static func clamp(_ v: Double, lo: Double, hi: Double) -> Double {
        max(lo, min(hi, v))
    }

    private static func secondsBlurb(_ delta: Double) -> String {
        let s = abs(delta)
        if s < 2 { return "just a hair" }
        if s < 5 { return "a couple of seconds" }
        if s < 10 { return "noticeably" }
        return "way"
    }
}

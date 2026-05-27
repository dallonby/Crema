import Foundation
import SwiftUI
import CremaKit

/// Orchestrates the auto-tune wizard. Owns the step machine, accumulated
/// shot history, current recommendation, and ties the user-visible flow to
/// `LiveDriver` (for triggering brews) and `ScaleTransport` (for measuring
/// yield, BLE or manual).
///
/// Lifecycle:
///   `.bean` → `.recipe` → `.prep` → `.brewing` → `.measure` → `.suggest`
///   → either back to `.prep` for the next shot or `.complete`.
///
/// Stays clean: never touches `ProfileLibrary` during the session. Only at the
/// end, if the user accepts, do we save the final tuned profile.
@MainActor
@Observable
final class AutoTuneSession: Identifiable {
    nonisolated let id = UUID()

    // MARK: - State machine

    enum Step: Hashable, Sendable {
        case bean       // collect bean info (name, roast, drink)
        case recipe     // collect dose + target yield
        case prep       // "grind X g and tamp" — wait for "next"
        case brewing    // shot in progress
        case measure    // shot ended, awaiting weight (BLE or manual)
        case suggest    // recommendation card; user picks "brew again" or "done"
        case complete   // celebration + save-as-profile

        var indexForProgress: Int {
            switch self {
            case .bean:     return 0
            case .recipe:   return 1
            case .prep:     return 2
            case .brewing:  return 3
            case .measure:  return 4
            case .suggest:  return 5
            case .complete: return 6
            }
        }
        static var allCases: [Step] {
            [.bean, .recipe, .prep, .brewing, .measure, .suggest, .complete]
        }
    }

    private(set) var step: Step = .bean
    var inputs = AutoTuneInputs()
    private(set) var history: [AutoTuneShotResult] = []
    /// Writable from views so the suggest step can force-complete the session
    /// when the user taps "I'm happy — finish" mid-flow.
    var currentRecommendation: AutoTuneRecommendation?

    /// Total shot duration measured from brew start to detected end (seconds).
    /// Captured the moment we transition `.brewing → .measure`.
    private(set) var lastShotElapsedS: Double = 0
    /// Volume the machine reported in the last sample of the shot — used as
    /// a fallback yield estimate if no scale is connected.
    private(set) var lastShotMlReportedByMachine: Double = 0

    /// Live weight read during the brew. `nil` until the scale starts yielding.
    private(set) var liveWeightG: Double?
    /// Final weight at brew end (snapshot of liveWeightG, or manual input).
    var manualYieldEntryG: Double = 0  // bound to the manual-yield text field

    // MARK: - Dependencies

    /// Exposed so the brewing step view can render the live chart and read
    /// brewState. Wraps the same LiveDriver the rest of the app uses.
    let liveDriver: LiveDriver
    private let library: ProfileLibrary
    private let scale: ScaleTransport
    private var scaleTask: Task<Void, Never>?
    private var brewWatchTask: Task<Void, Never>?

    init(liveDriver: LiveDriver, library: ProfileLibrary, scale: ScaleTransport) {
        self.liveDriver = liveDriver
        self.library = library
        self.scale = scale
    }

    // No `deinit` cancellation here — Swift 6 prevents touching MainActor
    // state from a nonisolated deinit. Tasks hold a weak reference to self
    // and exit cleanly when self deallocates, and `cancel()` is the explicit
    // teardown path users invoke when closing the sheet.

    // MARK: - Step transitions

    func goNext() {
        switch step {
        case .bean:
            // Seed yield from drink type's default ratio when entering recipe.
            inputs.targetYield = (inputs.dose * inputs.drink.defaultRatio).rounded()
            currentRecommendation = AutoTuneRecommender.initial(inputs)
            step = .recipe
        case .recipe:
            currentRecommendation = AutoTuneRecommender.initial(inputs)
            step = .prep
        case .prep:
            startBrew()
        case .brewing:
            // User can't manually advance from brewing; brewWatch handles it.
            break
        case .measure:
            recordShotAndAdvance()
        case .suggest:
            // If recommender said we're done OR user accepted dialed state,
            // jump to complete. Else loop back into prep.
            if currentRecommendation == nil || history.count >= inputs.maxShots {
                step = .complete
            } else {
                step = .prep
            }
        case .complete:
            break  // terminal
        }
    }

    func goBack() {
        switch step {
        case .bean:    break
        case .recipe:  step = .bean
        case .prep:    step = .recipe
        case .brewing, .measure, .suggest, .complete: break  // can't rewind a shot
        }
    }

    func cancel() {
        scaleTask?.cancel(); scaleTask = nil
        brewWatchTask?.cancel(); brewWatchTask = nil
        if liveDriver.brewState == .brewing {
            // If we ever received a sample, the machine really IS brewing —
            // abort cleanly. If we never received one (BLE wedged before the
            // profile-write landed, etc.) abort would actually START a brew
            // because coil 150 is a toggle. In that case, reset local state
            // only.
            if liveDriver.playback.samples.isEmpty {
                liveDriver.forceResetLocalBrewState()
            } else {
                liveDriver.abort()
            }
        }
        liveDriver.setTempProfile(nil)
    }

    // MARK: - Brewing

    private func startBrew() {
        guard let rec = currentRecommendation else { return }
        liveDriver.setTempProfile(rec.profile)
        step = .brewing
        liveWeightG = nil
        manualYieldEntryG = 0
        // Grinder is NOT auto-sent here — the prep step has a separate
        // "Set Grinder" CTA the user taps explicitly (which also avoids the
        // BLE-radio wedge from racing the FF55 write against the Modbus
        // profile sequence).
        liveDriver.brew()
        watchScale()
        watchBrewCompletion()
    }

    /// Push the recommendation's grinder settings to the machine. Called by
    /// the prep step's "Set Grinder" button. Idempotent — safe to tap more
    /// than once. Returns `true` if a send was actually attempted.
    @discardableResult
    func sendGrinderForCurrentRecommendation() async -> Bool {
        guard let grinder = currentRecommendation?.profile.grinder else { return false }
        try? await liveDriver.transport.sendGrinderSettings(grinder)
        return true
    }

    /// Has the recommendation got grinder settings worth sending?
    var recommendationHasGrinder: Bool {
        currentRecommendation?.profile.grinder != nil
    }

    private func watchScale() {
        scaleTask?.cancel()
        scaleTask = Task { [weak self, scale] in
            for await w in scale.weightStream() {
                guard let self else { return }
                self.liveWeightG = w
                if Task.isCancelled { break }
            }
        }
    }

    private func watchBrewCompletion() {
        brewWatchTask?.cancel()
        brewWatchTask = Task { [weak self] in
            // Poll the @Observable brewState — when it flips to .done we
            // snapshot what we have and move to the measure step.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self else { return }
                if self.liveDriver.brewState == .done {
                    self.snapshotEndOfBrew()
                    self.step = .measure
                    return
                }
                if self.liveDriver.brewState == .ready { return }  // aborted
            }
        }
    }

    private func snapshotEndOfBrew() {
        lastShotElapsedS = liveDriver.playback.t
        lastShotMlReportedByMachine =
            Double(liveDriver.playback.samples.last?.volumeMl ?? 0)
        // Seed the manual-entry field with the best estimate we have.
        // Critically, do NOT seed from the machine's mL reading — that's
        // pump throughput pre-puck, typically 2–3× the actual cup yield.
        // Seeding from it would mislead the user into accepting an inflated
        // number and the recommender would then nudge in the wrong direction.
        if let live = liveWeightG, live > 0 {
            manualYieldEntryG = live
        } else {
            manualYieldEntryG = inputs.targetYield
        }
    }

    // MARK: - Measure → suggest

    private func recordShotAndAdvance() {
        guard let rec = currentRecommendation else { return }
        let yieldG = manualYieldEntryG
        let timeS = lastShotElapsedS
        let verdict = AutoTuneRecommender.verdict(
            actualTimeS: timeS, actualYieldG: yieldG, inputs: inputs)
        let score = AutoTuneRecommender.score(
            actualTimeS: timeS, actualYieldG: yieldG, inputs: inputs)
        let result = AutoTuneShotResult(
            shotNumber: history.count + 1,
            profile: rec.profile,
            grindMicrons: rec.grindMicrons,
            actualYieldG: yieldG,
            actualTimeS: timeS,
            verdict: verdict,
            scoreOutOf100: score
        )
        history.append(result)
        currentRecommendation = AutoTuneRecommender.next(inputs: inputs, history: history)
        // Clear the temp override now — next brew either uses an updated
        // override (loop continues) or returns to the library profile.
        liveDriver.setTempProfile(nil)
        step = .suggest
    }

    // MARK: - Discard / retry

    /// Throw out the just-completed brew (before it's been recorded to history)
    /// and return to the prep step. Use case: user realises mid-measure that
    /// the shot was botched (basket unattached, knocked the cup, etc.) — no
    /// point feeding garbage data to the recommender.
    func discardCurrentShot() {
        liveDriver.setTempProfile(nil)
        if liveDriver.brewState == .brewing {
            // Belt and braces — measure step only enters after brewState=.done,
            // but defend against races.
            if liveDriver.playback.samples.isEmpty {
                liveDriver.forceResetLocalBrewState()
            } else {
                liveDriver.abort()
            }
        }
        lastShotElapsedS = 0
        lastShotMlReportedByMachine = 0
        liveWeightG = nil
        manualYieldEntryG = 0
        // Recommendation stays as-is — it was computed for this shot number
        // and is still valid for the retry.
        step = .prep
    }

    /// Throw out the LAST recorded shot from the suggest step (user already
    /// confirmed a yield they now regret). Pops history, re-derives the prior
    /// recommendation, returns to prep so the user can brew this shot number
    /// again.
    func discardLastRecordedShot() {
        guard !history.isEmpty else { return }
        history.removeLast()
        currentRecommendation = history.isEmpty
            ? AutoTuneRecommender.initial(inputs)
            : (AutoTuneRecommender.next(inputs: inputs, history: history)
               ?? AutoTuneRecommender.initial(inputs))
        liveDriver.setTempProfile(nil)
        liveWeightG = nil
        manualYieldEntryG = 0
        lastShotElapsedS = 0
        lastShotMlReportedByMachine = 0
        step = .prep
    }

    // MARK: - Saving the final profile

    /// Save the BEST-scoring shot's profile to the library as the active
    /// recipe. Called from `.complete` step's "Save & use" button.
    ///
    /// Two transformations vs the raw shot profile:
    /// 1. **Trim the extract stage** so the total profile duration matches
    ///    `inputs.targetBrewTimeS`. During auto-tune the extract is held
    ///    open-ended (45+ s) so the user can manually stop based on cup
    ///    weight — that long extract would brew for ~50 s if used as-is
    ///    in normal mode (the firmware would just run the full profile).
    /// 2. **Use the best-scoring shot's recipe**, not the last. The
    ///    recommender can overshoot (shot 2 scores 92, shot 3 scores 75)
    ///    and the complete step's UI showcases the best — saving anything
    ///    else would be inconsistent with what the user just read.
    func saveTunedProfile(named name: String) {
        guard let source = (bestShot?.profile ?? history.last?.profile) else { return }

        // Compute non-extract time (preinfuse + waits + tail). Whatever
        // remains of the user's target brew time goes to extract.
        let nonExtractTotal = source.stages
            .filter { $0.label != "Extract" }
            .reduce(0.0) { $0 + $1.duration + $1.waitAfter }
        let extractDuration = max(3.0, inputs.targetBrewTimeS - nonExtractTotal)

        let trimmedStages: [BrewStage] = source.stages.map { s in
            if s.label == "Extract" {
                return BrewStage(
                    id: s.id,
                    label: s.label,
                    duration: extractDuration,
                    priority: s.priority,
                    pressureBar: s.pressureBar,
                    flowMlPerSec: s.flowMlPerSec,
                    waitAfter: s.waitAfter
                )
            }
            return s
        }

        let renamed = BrewProfile(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Auto · \(inputs.beanName.isEmpty ? "Bean" : inputs.beanName)"
                : name,
            stages: trimmedStages,
            mode: source.mode,
            target: source.target,
            targetVolumeMl: source.targetVolumeMl,
            grinder: source.grinder
        )
        library.add(renamed, setActive: true)
    }

    // MARK: - Derived UI helpers

    var bestShot: AutoTuneShotResult? {
        history.max(by: { $0.scoreOutOf100 < $1.scoreOutOf100 })
    }

    var canBrew: Bool { liveDriver.canBrew }
    var hasScale: Bool { scale.connectedName != nil }
    var scaleName: String? { scale.connectedName }
}

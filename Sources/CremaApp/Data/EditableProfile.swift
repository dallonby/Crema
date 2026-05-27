import Foundation
import CremaKit

/// One stage in the multi-stage editor. Wraps the immutable `BrewStage` with
/// mutable, observable fields that bind directly to the editor's controls.
/// `id` survives compilation so SwiftUI's `ForEach` doesn't lose card state
/// when the underlying profile is rebuilt during preview re-renders.
@MainActor
@Observable
final class EditableStage: Identifiable {
    let id: UUID
    var label: String
    var priority: BrewStage.Priority
    var duration: Double
    var pressureBar: Double
    var flowMlPerSec: Double
    var waitAfter: Double

    /// UI-only: whether the card is expanded to show all controls. Doesn't
    /// affect compilation.
    var isExpanded: Bool = false

    init(id: UUID = UUID(),
         label: String,
         priority: BrewStage.Priority,
         duration: Double,
         pressureBar: Double = 0,
         flowMlPerSec: Double = 0,
         waitAfter: Double = 0) {
        self.id = id
        self.label = label
        self.priority = priority
        self.duration = duration
        self.pressureBar = pressureBar
        self.flowMlPerSec = flowMlPerSec
        self.waitAfter = waitAfter
    }

    convenience init(from stage: BrewStage) {
        self.init(
            id: stage.id,
            label: stage.label,
            priority: stage.priority,
            duration: stage.duration,
            pressureBar: stage.pressureBar,
            flowMlPerSec: stage.flowMlPerSec,
            waitAfter: stage.waitAfter
        )
    }

    func toStage(isLast: Bool) -> BrewStage {
        BrewStage(
            id: id,
            label: label,
            duration: duration,
            priority: priority,
            pressureBar: priority == .pressure ? pressureBar : 0,
            flowMlPerSec: priority == .flow ? flowMlPerSec : 0,
            // Last stage's waitAfter is ignored by the firmware (it just
            // ends the brew), but we keep the UI value so a user can move
            // a stage around without losing the wait time they set.
            waitAfter: isLast ? 0 : waitAfter
        )
    }
}

/// Mutable profile model the multi-stage editor binds to. Compiles into a
/// real `BrewProfile` with arbitrary stage count.
@MainActor
@Observable
final class EditableProfile: Identifiable {
    let id: UUID
    var name: String
    var doseG: Double          // 12…22 typical
    var targetYieldG: Double   // 18…80 typical (= mL since espresso ≈ 1 g/mL)
    var stages: [EditableStage]
    /// When `true`, the profile saves grinder settings and the brew zone shows
    /// a "Set grinder" button next to Brew. When `false`, profile.grinder == nil
    /// on save and the grinder controls disappear.
    var grinderEnabled: Bool
    var grinderSizeMicrons: Double  // 30…500 µm, stored as Double for slider math
    var grinderRPM: Double           // 200…1200 typical
    var grinderSingleDose: Bool

    init(id: UUID = UUID(),
         name: String = "New profile",
         doseG: Double = 18,
         targetYieldG: Double = 36,
         stages: [EditableStage] = EditableProfile.defaultStages(),
         grinderEnabled: Bool = false,
         grinderSizeMicrons: Double = 76,
         grinderRPM: Double = 567,
         grinderSingleDose: Bool = false) {
        self.id = id
        self.name = name
        self.doseG = doseG
        self.targetYieldG = targetYieldG
        self.stages = stages
        self.grinderEnabled = grinderEnabled
        self.grinderSizeMicrons = grinderSizeMicrons
        self.grinderRPM = grinderRPM
        self.grinderSingleDose = grinderSingleDose
    }

    /// Default 4-stage shape for a new profile — gives the user a real starting
    /// point to modify instead of an empty list.
    static func defaultStages() -> [EditableStage] {
        [
            EditableStage(label: "Preinfuse", priority: .pressure,
                          duration: 6, pressureBar: 4.0, waitAfter: 6),
            EditableStage(label: "Soak", priority: .pressure,
                          duration: 3, pressureBar: 2.5, waitAfter: 0),
            EditableStage(label: "Extract", priority: .flow,
                          duration: 20, flowMlPerSec: 1.7, waitAfter: 0),
            EditableStage(label: "Tail", priority: .pressure,
                          duration: 4, pressureBar: 1.0, waitAfter: 0),
        ]
    }

    func compile() -> BrewProfile {
        let last = stages.count - 1
        let compiledStages = stages.enumerated().map { i, s in
            s.toStage(isLast: i == last)
        }
        let grinder: GrinderSettings? = grinderEnabled
            ? GrinderSettings(
                grindSizeMicrons: UInt8(min(255, max(0, grinderSizeMicrons.rounded()))),
                rpm: UInt16(min(65535, max(0, grinderRPM.rounded()))),
                singleDose: grinderSingleDose
              )
            : nil
        return BrewProfile(
            id: id,
            name: name.isEmpty ? "Untitled" : name,
            stages: compiledStages,
            mode: .flowVariablePressure,
            target: .flow,
            targetVolumeMl: UInt16(targetYieldG.rounded()),
            grinder: grinder
        )
    }

    static func from(_ profile: BrewProfile) -> EditableProfile {
        EditableProfile(
            id: profile.id,
            name: profile.name,
            doseG: 18,                      // not stored in BrewProfile yet
            targetYieldG: Double(profile.targetVolumeMl ?? 36),
            stages: profile.stages.map(EditableStage.init(from:)),
            grinderEnabled: profile.grinder != nil,
            grinderSizeMicrons: Double(profile.grinder?.grindSizeMicrons ?? 76),
            grinderRPM: Double(profile.grinder?.rpm ?? 567),
            grinderSingleDose: profile.grinder?.singleDose ?? false
        )
    }

    // MARK: - Stage list mutations

    func addStage() {
        // Insert a new stage that resembles a "continue from here" extension —
        // same priority as the last one, half its duration, copy its setpoint.
        // Better than landing the user on default zeros.
        let template = stages.last
        let new = EditableStage(
            label: "Stage \(stages.count + 1)",
            priority: template?.priority ?? .flow,
            duration: max(3, (template?.duration ?? 6) / 2),
            pressureBar: template?.pressureBar ?? 2,
            flowMlPerSec: template?.flowMlPerSec ?? 1.5,
            waitAfter: 0
        )
        new.isExpanded = true
        stages.append(new)
    }

    func remove(stageID: UUID) {
        guard stages.count > 1 else { return }   // can't have zero stages
        stages.removeAll { $0.id == stageID }
    }

    func moveStage(id: UUID, by offset: Int) {
        guard let i = stages.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard j >= 0, j < stages.count else { return }
        stages.swapAt(i, j)
    }

    var canRemoveAnyStage: Bool { stages.count > 1 }

    var totalDuration: Double {
        stages.reduce(0) { $0 + $1.duration + $1.waitAfter }
    }
}

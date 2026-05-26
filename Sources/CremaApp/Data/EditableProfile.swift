import Foundation
import CremaKit

/// Simplified mutable model the guided editor binds sliders to. Compiles into
/// a real `BrewProfile` with a fixed 3-stage shape (preinfuse → bloom-wait →
/// extract → tail). Suits ~80% of espresso recipes; the full node editor lands
/// later for the rest.
@MainActor
@Observable
final class EditableProfile: Identifiable {
    /// Backing identity — preserved through edits so the library can match the
    /// resulting BrewProfile to the existing row.
    let id: UUID

    var name: String

    /// Dose in grams, displayed in the header (informational only — the machine
    /// doesn't see this, but downstream we can use it for ratio math + scale
    /// integration).
    var doseG: Double          // typical range 14…22
    var targetYieldG: Double   // typical range 18…60 (we treat this as mL too since espresso ≈ 1 g/mL)

    // Preinfuse: gentle pressure-priority push to saturate the puck
    var preinfusionBar: Double  // 0…9
    var preinfusionTime: Double // 0…15 (0 = skip preinfuse entirely)

    // Bloom: pump-off wait after preinfuse
    var bloomTime: Double       // 0…20 (0 = skip)

    // Extract: the main flow-priority stage
    var extractFlow: Double     // 1…5 mL/s
    var extractTime: Double     // 5…40

    // Tail: short low-pressure finish (optional)
    var tailBar: Double         // 0…3 (0 = skip)
    var tailTime: Double        // 0…10

    init(id: UUID = UUID(),
         name: String = "New profile",
         doseG: Double = 18,
         targetYieldG: Double = 36,
         preinfusionBar: Double = 4,
         preinfusionTime: Double = 6,
         bloomTime: Double = 6,
         extractFlow: Double = 1.7,
         extractTime: Double = 22,
         tailBar: Double = 1.0,
         tailTime: Double = 4) {
        self.id = id
        self.name = name
        self.doseG = doseG
        self.targetYieldG = targetYieldG
        self.preinfusionBar = preinfusionBar
        self.preinfusionTime = preinfusionTime
        self.bloomTime = bloomTime
        self.extractFlow = extractFlow
        self.extractTime = extractTime
        self.tailBar = tailBar
        self.tailTime = tailTime
    }

    /// Snapshot the current edit state into a real BrewProfile that the
    /// library can store and the machine can run.
    func compile() -> BrewProfile {
        var stages: [BrewStage] = []
        if preinfusionTime > 0 && preinfusionBar > 0 {
            stages.append(BrewStage(
                label: "Preinfuse",
                duration: preinfusionTime,
                priority: .pressure,
                pressureBar: preinfusionBar,
                waitAfter: bloomTime
            ))
        }
        stages.append(BrewStage(
            label: "Extract",
            duration: extractTime,
            priority: .flow,
            flowMlPerSec: extractFlow,
            waitAfter: 0
        ))
        if tailTime > 0 && tailBar > 0 {
            stages.append(BrewStage(
                label: "Tail",
                duration: tailTime,
                priority: .pressure,
                pressureBar: tailBar,
                waitAfter: 0
            ))
        }
        return BrewProfile(
            id: id,
            name: name.isEmpty ? "Untitled" : name,
            stages: stages,
            mode: .flowVariablePressure,
            target: .flow,
            targetVolumeMl: UInt16(targetYieldG.rounded())
        )
    }

    /// Inverse — populate this editor's fields from an existing BrewProfile.
    /// Used when editing a row from the library. Unknown / advanced shapes
    /// (e.g. profiles with extra stages) are flattened down to the editor's
    /// 3-stage view; we only round-trip what the editor knows about.
    static func from(_ profile: BrewProfile) -> EditableProfile {
        let preinfuse = profile.stages.first(where: { $0.label.lowercased().contains("preinf") })
        let extractStage = profile.stages.first(where: { $0.priority == .flow })
            ?? profile.stages.first
        let tail = profile.stages.last(where: { $0.priority == .pressure
                                             && $0.label.lowercased().contains("tail") })
        return EditableProfile(
            id: profile.id,
            name: profile.name,
            doseG: 18,
            targetYieldG: Double(profile.targetVolumeMl ?? 36),
            preinfusionBar: preinfuse?.pressureBar ?? 0,
            preinfusionTime: preinfuse?.duration ?? 0,
            bloomTime: preinfuse?.waitAfter ?? 0,
            extractFlow: extractStage?.flowMlPerSec ?? 1.7,
            extractTime: extractStage?.duration ?? 22,
            tailBar: tail?.pressureBar ?? 0,
            tailTime: tail?.duration ?? 0
        )
    }
}

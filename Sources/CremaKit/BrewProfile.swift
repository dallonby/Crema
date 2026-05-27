import Foundation

/// One stage of a brew profile, in the shape the LITA firmware actually executes.
/// Mirrors the 6-reg-per-stage layout in `PROTOCOL.md §3`.
public struct BrewStage: Sendable, Hashable, Identifiable, Codable {
    public enum Priority: String, Sendable, Hashable, Codable { case pressure, flow }

    public let id: UUID
    public let label: String
    /// Pump-on duration in seconds.
    public let duration: Double
    /// Active control axis.
    public let priority: Priority
    /// Pressure setpoint (bar). Only meaningful when `priority == .pressure`.
    public let pressureBar: Double
    /// Flow setpoint (mL/s). Only meaningful when `priority == .flow`.
    public let flowMlPerSec: Double
    /// Pump-off wait *after* this stage finishes (e.g. bloom).
    public let waitAfter: Double

    public init(id: UUID = UUID(), label: String, duration: Double,
                priority: Priority, pressureBar: Double = 0,
                flowMlPerSec: Double = 0, waitAfter: Double = 0) {
        self.id = id
        self.label = label
        self.duration = duration
        self.priority = priority
        self.pressureBar = pressureBar
        self.flowMlPerSec = flowMlPerSec
        self.waitAfter = waitAfter
    }
}

/// A complete brew profile — the unit Crema lets you author, share, and send to
/// the machine. The fields below match the in-app data model captured live and
/// documented in `PROTOCOL.md §3a` (slot-header layout).
public struct BrewProfile: Sendable, Hashable, Identifiable, Codable {

    /// Whether the profile targets a flow volume (mL) or a weight (g).
    /// "Weight" mode requires a connected BLE scale — Crema enforces this at
    /// brew-time, not here.
    public enum TargetKind: String, Sendable, Hashable, Codable { case flow, weight }

    public let id: UUID
    public let name: String
    public let stages: [BrewStage]
    /// `craft.real_mode` written to `Machine.activeModeRegister` before brew start.
    public let mode: BrewMode
    public let target: TargetKind
    /// True = `direct extract` (single-stage shortcut path).
    public let directExtract: Bool
    /// True = variable flow allowed within stages.
    public let variableFlow: Bool
    /// Flow-mode target in mL. Ignored for weight-mode profiles.
    public let targetVolumeMl: UInt16?
    /// Weight-mode target in grams. Ignored for flow-mode profiles.
    public let targetWeightG: UInt16?
    /// `craft.auto_link` — unused by us so far, stored for round-trip fidelity.
    public let autoLink: UInt16
    /// Optional grinder settings to apply with this profile. When set, the UI
    /// surfaces a "Set grinder" button next to Brew so the user can push the
    /// grind size / RPM to the machine without leaving the brew screen.
    public var grinder: GrinderSettings?

    public init(
        id: UUID = UUID(),
        name: String,
        stages: [BrewStage],
        mode: BrewMode = .flowVariablePressure,
        target: TargetKind = .flow,
        directExtract: Bool = false,
        variableFlow: Bool = true,
        targetVolumeMl: UInt16? = nil,
        targetWeightG: UInt16? = nil,
        autoLink: UInt16 = 0,
        grinder: GrinderSettings? = nil
    ) {
        self.id = id
        self.name = name
        self.stages = stages
        self.mode = mode
        self.target = target
        self.directExtract = directExtract
        self.variableFlow = variableFlow
        self.targetVolumeMl = targetVolumeMl
        self.targetWeightG = targetWeightG
        self.autoLink = autoLink
        self.grinder = grinder
    }

    /// Total wall-clock duration including waits.
    public var totalDuration: Double {
        stages.reduce(0) { $0 + $1.duration + $1.waitAfter }
    }

    // MARK: - Queries (UI helpers, kept as pure step functions — the ghost on
    // the chart is a *target*, and targets switch instantaneously).

    /// Pressure setpoint at `t`, or nil if the current stage isn't pressure-priority
    /// or the pump is in a wait gap.
    public func pressure(at t: Double) -> Double? {
        guard let (stage, _, inWait) = stage(at: t) else { return nil }
        if inWait || stage.priority != .pressure { return nil }
        return stage.pressureBar
    }

    /// Flow setpoint at `t`, or nil.
    public func flow(at t: Double) -> Double? {
        guard let (stage, _, inWait) = stage(at: t) else { return nil }
        if inWait || stage.priority != .flow { return nil }
        return stage.flowMlPerSec
    }

    /// Returns `(stage, stageStartTime, isInWaitGap)`.
    public func stage(at t: Double) -> (BrewStage, Double, Bool)? {
        var cursor = 0.0
        for s in stages {
            let pumpEnd = cursor + s.duration
            let waitEnd = pumpEnd + s.waitAfter
            if t < pumpEnd { return (s, cursor, false) }
            if t < waitEnd { return (s, cursor, true) }
            cursor = waitEnd
        }
        return nil
    }
}

// MARK: - Modbus encoding

extension BrewProfile {

    /// One operation in the brew sequence — what gets sent on the wire.
    public enum WriteStep: Sendable, Hashable {
        case headerOrStage(description: String, frame: Data)
        case activeMode(frame: Data)
        case coilOn(coil: UInt16, frame: Data)
        case coilOff(coil: UInt16, frame: Data)

        public var frame: Data {
            switch self {
            case .headerOrStage(_, let f), .activeMode(let f),
                 .coilOn(_, let f),       .coilOff(_, let f): return f
            }
        }
        public var description: String {
            switch self {
            case .headerOrStage(let d, _): return d
            case .activeMode:              return "active mode reg 87"
            case .coilOn(let c, _):        return "coil \(c) ON"
            case .coilOff(let c, _):       return "coil \(c) OFF"
            }
        }
    }

    /// Compile the profile to the ordered Modbus write sequence the machine
    /// expects: header → stages → active-mode register → (optional) coil-150
    /// brew trigger. Returns frames ready to write to the 2b10 characteristic.
    ///
    /// `triggerBrew: false` is the right choice when populating a slot without
    /// pulling a shot (e.g. saving a recipe). Defaults to true since the
    /// quick-key tap-to-brew flow is the most common path.
    public func encode(toSlot slot: Machine.Slot, triggerBrew: Bool = true) -> [WriteStep] {
        var out: [WriteStep] = []
        let base = slot.rawValue

        // 1. Header (7 regs)
        let header = headerRegisters()
        out.append(.headerOrStage(
            description: "header @\(base)",
            frame: Modbus.writeRegisters(at: base, values: header)
        ))

        // 2. Stages
        if directExtract {
            // Single-stage shortcut: only 5 regs at base+8, no per-stage gap.
            // The flow value is either the explicit stage flow or the average
            // implied by total_flow/time. Falls back to a stub stage when the
            // profile has no stages (matches the Python helper behavior).
            let s = stages.first
            let flowX10: UInt16
            if let s, s.flowMlPerSec > 0 {
                flowX10 = UInt16(rounded(s.flowMlPerSec * 10))
            } else if let total = targetVolumeMl, let s, s.duration > 0 {
                flowX10 = UInt16(rounded(Double(total) * 10 / s.duration))
            } else {
                flowX10 = 0
            }
            out.append(.headerOrStage(
                description: "direct stage @\(base + 8)",
                frame: Modbus.writeRegisters(at: base + 8,
                                              values: [0, 0, flowX10, 0, 1])
            ))
        } else {
            var addr = base + Machine.firstStageOffset
            for (i, stage) in stages.enumerated() {
                let isLast = (i == stages.count - 1)
                out.append(.headerOrStage(
                    description: "stage \(i + 1) @\(addr)",
                    frame: Modbus.writeRegisters(at: addr,
                                                  values: stageRegisters(stage, isLast: isLast))
                ))
                addr += Machine.stageStride
            }
        }

        // 3. Active mode selector
        out.append(.activeMode(
            frame: Modbus.writeRegister(at: Machine.activeModeRegister,
                                         value: UInt16(mode.rawValue))
        ))

        // 4. Trigger brew (coil 150 ON then OFF — the "press the button" gesture)
        if triggerBrew {
            out.append(.coilOn(
                coil: Machine.startBrewCoil,
                frame: Modbus.writeCoil(at: Machine.startBrewCoil, on: true)
            ))
            out.append(.coilOff(
                coil: Machine.startBrewCoil,
                frame: Modbus.writeCoil(at: Machine.startBrewCoil, on: false)
            ))
        }

        return out
    }

    /// Pack the 7 header registers per `PROTOCOL.md §3a`. Two fields are inverted
    /// in the official JS — we follow the on-the-wire convention here, not the
    /// human-readable one.
    public func headerRegisters() -> [UInt16] {
        [
            target == .weight ? 0 : 1,              // 0: callswitch (inverted)
            mode.isVariablePressure ? 1 : 0,        // 1: mode (1 = variable pressure)
            directExtract ? 0 : 1,                  // 2: direct (inverted)
            variableFlow ? 1 : 0,                   // 3: changeswitch
            targetVolumeMl ?? 0,                    // 4: total_flow (mL)
            targetWeightG ?? 0,                     // 5: total_weight (g)
            autoLink,                               // 6: auto_link
        ]
    }

    /// Pack a single stage into its 6-register block.
    public func stageRegisters(_ s: BrewStage, isLast: Bool) -> [UInt16] {
        let isFlowPriority = (s.priority == .flow)
        let pressureX10 = isFlowPriority ? 0 : UInt16(rounded(s.pressureBar * 10))
        let flowX10     = isFlowPriority ? UInt16(rounded(s.flowMlPerSec * 10)) : 0
        return [
            UInt16(rounded(s.duration)),            // 0: time (seconds)
            pressureX10,                            // 1: pressure ×10
            flowX10,                                // 2: flow ×10
            isLast ? 0 : UInt16(rounded(s.waitAfter)),  // 3: wait_after (0 on last)
            isLast ? 1 : 0,                         // 4: is_end
            isFlowPriority ? 1 : 0,                 // 5: priority bit
        ]
    }

    private func rounded(_ v: Double) -> Int {
        Int(v.rounded())
    }
}

// MARK: - The canonical test fixture

extension BrewProfile {
    /// The TestyT profile captured live from the official app on 2026-05-26.
    /// Re-encoding this profile must produce the exact bytes in `PROTOCOL.md §3`.
    /// Pinned UUID so migrations (e.g. pruning the dev fixture from saved
    /// libraries in `ProfileLibrary.init`) can match it deterministically.
    public static let testyT = BrewProfile(
        id: UUID(uuidString: "7E57717E-0000-0000-0000-000000000001")!,
        name: "TestyT",
        stages: [
            BrewStage(label: "Preinfuse", duration: 7, priority: .pressure,
                      pressureBar: 6.1, waitAfter: 8),
            BrewStage(label: "Soak",      duration: 3, priority: .pressure,
                      pressureBar: 2.3),
            BrewStage(label: "Extract",   duration: 20, priority: .flow,
                      flowMlPerSec: 1.7, waitAfter: 1),
            BrewStage(label: "Tail",      duration: 4, priority: .pressure,
                      pressureBar: 1.1),
        ],
        mode: .flowVariablePressure,
        target: .flow,
        targetVolumeMl: 68
    )
}

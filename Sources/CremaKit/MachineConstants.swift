import Foundation

/// Hardware-side constants for the Wendougee LITA-BA / LITA-BR / DATA-S espresso
/// machines. All values are extracted from the official Android APK and verified
/// live against a LITA-BA on 2026-05-26 (see `LitaLite/PROTOCOL.md`).
public enum Machine {

    // MARK: - BLE

    /// Advertising name prefix. Full name is `WDG_Data_<MAC>` where the MAC has no
    /// separators (e.g. `WDG_Data_AA11BB22CC33`).
    public static let advertisingPrefix = "WDG_Data_"

    /// Custom GATT service holding both communication characteristics.
    public static let serviceUUID = "00010203-0405-0607-0809-0A0B0C0D1910"

    /// Modbus channel — read + write + notify. Carries function-code commands
    /// (`0x01/0x03/0x05/0x06/0x10`) and their responses.
    public static let modbusCharUUID = "00010203-0405-0607-0809-0A0B0C0D2B10"

    /// FF55 event channel — notify. Carries the ~2 Hz heartbeat status frame
    /// and the grinder/accessory tunnel.
    public static let eventCharUUID  = "00010203-0405-0607-0809-0A0B0C0D2C10"

    /// MTU negotiated with the machine. The protocol fits all frames under this.
    public static let mtu = 200

    // MARK: - Quick-key slot layout

    /// Quick-key slot bases — each slot holds a full profile (header + N stages).
    /// Confirmed live: slot 1 base = 2048, first stage at 2056 (=2048+8).
    public enum Slot: UInt16, CaseIterable, Sendable, Hashable {
        case one   = 2048
        case two   = 2560
        case three = 3048
        case four  = 3560
    }

    /// Distance between consecutive stage blocks within a slot: 6-reg payload
    /// + 3-reg gap = 9 registers per stage.
    public static let stageStride: UInt16 = 9

    /// The first stage sits 8 registers after the slot base (after the 7-reg
    /// header + 1-reg pad).
    public static let firstStageOffset: UInt16 = 8

    // MARK: - Control registers / coils

    /// Reg 87 — `craft.real_mode` selector. Written *after* the profile is in
    /// place and *before* the brew is triggered. See `BrewMode` for values.
    public static let activeModeRegister: UInt16 = 87

    /// Coil 150 — toggled ON then OFF to "press the brew button."
    public static let startBrewCoil: UInt16 = 150

    /// Coil 154 — raw three-way valve. Use with caution.
    public static let rawValveCoil: UInt16 = 154

    /// Coil 155 — clean cycle.
    public static let cleanCycleCoil: UInt16 = 155

    // MARK: - Live telemetry registers (block at 1404+)

    public enum LiveRegister: UInt16, CaseIterable, Sendable {
        case elapsedDeciseconds = 1405   // ÷10 = seconds since brew start
        case steamBoilerTempX10 = 1408   // ÷10 = °C
        case brewBoilerTempX10  = 1409   // ÷10 = °C
        case pressureX10        = 1410   // ÷10 = bar
        case totalVolumeMl      = 1411
        case pumpTimeS          = 1417
        /// IMPORTANT: raw mL/s, NOT ×10. See PROTOCOL.md note.
        case instantFlowMlS     = 1422
    }

    /// First register of the live telemetry block — the natural batched-read base.
    public static let liveBlockBase: UInt16 = 1404
    /// Read this many registers to cover everything we care about.
    public static let liveBlockCount: UInt16 = 22
}

/// `craft.real_mode` — the active brew mode written to `Machine.activeModeRegister`
/// before triggering coil 150. Names from `PROTOCOL.md §3 Brew mode taxonomy`.
public enum BrewMode: Int, Sendable, Hashable, CaseIterable {
    /// 流量恒压 — flow target, constant pressure.
    case flowConstantPressure   = 0
    /// 称重恒压 — weight target, constant pressure.
    case weightConstantPressure = 1
    /// 流量变压 — flow target, variable pressure profile. TestyT uses this.
    case flowVariablePressure   = 2
    /// 称重变压 — weight target, variable pressure profile.
    case weightVariablePressure = 3
    /// 自由变压 — free variable pressure (the unexplored mode 4 / 1500-block).
    case freeVariablePressure   = 4

    /// True for modes that drive a variable-pressure profile (vs. flat pressure).
    public var isVariablePressure: Bool { self == .flowVariablePressure || self == .weightVariablePressure }

    /// True for modes that target a total weight (require a scale) instead of mL.
    public var isWeightTargeted: Bool { self == .weightConstantPressure || self == .weightVariablePressure }
}

import Foundation

/// Settings sent to the Wendougee grinder over the FF55 channel before a brew.
///
/// On Wendougee machines the grinder isn't a separately-paired BLE device — it
/// shares the same connection as the espresso machine and accepts commands via
/// the FF55 event channel. From the user's perspective it still feels like a
/// "grinder" they're configuring, hence its own model + UI affordance.
///
/// Captured live (PROTOCOL.md §6) on 2026-05-26:
/// ```
/// FF 55 02 59 20 00 0A 00 00 00 00 00 00 00 4C 02 37 5F
///                   len=10  ↑─── 7 unknowns ──↑ ↑76µm ↑567RPM ↑csum
/// ```
/// - byte 7: grind size in µm (0–255)
/// - bytes 8-9: RPM, big-endian UInt16
/// - bytes 0-6: 7 unknown bytes — one likely carries the single-dose flag,
///   not yet pinned down. For now we send zeros there.
public struct GrinderSettings: Sendable, Hashable, Codable {
    /// Grind particle size in micrometers. Typical espresso range: 200–350 µm
    /// (coarse end), 100–200 µm (medium-fine), 50–100 µm (fine). Wider range
    /// allowed to support filter / pour-over crowd that might use the same
    /// profile machinery.
    public var grindSizeMicrons: UInt8
    /// Grinder motor speed, RPM. Typical: 400–800.
    public var rpm: UInt16
    /// "Single-dose" mode flag. Exact byte position not yet captured — until
    /// we HCI-snoop a grinder write with this toggled, sending it is a no-op
    /// on the wire (we store it on the profile so users can author it).
    public var singleDose: Bool

    public init(grindSizeMicrons: UInt8 = 76, rpm: UInt16 = 567, singleDose: Bool = false) {
        self.grindSizeMicrons = grindSizeMicrons
        self.rpm = rpm
        self.singleDose = singleDose
    }

    /// Build the 10-byte payload of the FF55 Variant-B grinder command.
    /// The 7-byte prefix is all zeros pending further decoding.
    public func ff55Payload() -> Data {
        var p = Data(repeating: 0, count: 7)
        // TODO: single-dose flag byte position unknown — captured fixture has
        // all 7 prefix bytes zero. When pinned via snoop, set the right bit
        // here so `singleDose` actually takes effect on the wire.
        p.append(grindSizeMicrons)
        p.append(UInt8((rpm >> 8) & 0xFF))
        p.append(UInt8(rpm & 0xFF))
        return p
    }

    /// Build the full FF55 frame ready to write to the event characteristic.
    public func ff55Frame() -> Data {
        FF55.buildData(payload: ff55Payload())
    }
}

extension MachineTransport {
    /// Push grinder settings to the machine via the FF55 channel. Fire-and-
    /// forget; the device doesn't ack grinder writes in a parseable way yet.
    public func sendGrinderSettings(_ settings: GrinderSettings) async throws {
        try await sendFF55(settings.ff55Frame())
    }
}

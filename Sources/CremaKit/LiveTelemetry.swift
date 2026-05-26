import Foundation

/// One snapshot of machine telemetry — what the chart consumes as a sample.
/// Decoded from a Modbus FC `0x03` (read holding) response covering the
/// `1404+` live block.
public struct LiveTelemetry: Sendable, Hashable {
    /// Deciseconds since coil 150 fired. `Double(value) / 10` = seconds.
    public let elapsedDeciseconds: UInt16
    /// Steam boiler temperature, °C (already scaled).
    public let steamBoilerTempC: Double
    /// Brew boiler temperature, °C (already scaled).
    public let brewBoilerTempC: Double
    /// Brew-head pressure, bar (already scaled).
    public let pressureBar: Double
    /// Cumulative pumped volume, mL.
    public let totalVolumeMl: UInt16
    /// Active pump time, seconds (excludes wait gaps).
    public let pumpTimeS: UInt16
    /// Instantaneous flow into the puck, mL/s (raw — NOT ×10).
    public let pumpFlowMlS: Double
    /// The full register block as decoded, in case downstream wants more.
    public let registers: [UInt16]

    public var elapsedSeconds: Double { Double(elapsedDeciseconds) / 10.0 }

    public init(elapsedDeciseconds: UInt16,
                steamBoilerTempC: Double,
                brewBoilerTempC: Double,
                pressureBar: Double,
                totalVolumeMl: UInt16,
                pumpTimeS: UInt16,
                pumpFlowMlS: Double,
                registers: [UInt16]) {
        self.elapsedDeciseconds = elapsedDeciseconds
        self.steamBoilerTempC   = steamBoilerTempC
        self.brewBoilerTempC    = brewBoilerTempC
        self.pressureBar        = pressureBar
        self.totalVolumeMl      = totalVolumeMl
        self.pumpTimeS          = pumpTimeS
        self.pumpFlowMlS        = pumpFlowMlS
        self.registers          = registers
    }
}

extension LiveTelemetry {
    /// Encode this telemetry snapshot into a `UInt16` register block of length
    /// `Machine.liveBlockCount` starting at `Machine.liveBlockBase`. Pure
    /// inverse of `decode(response:)` — if you do `decode(encode(x))` you get
    /// `x` back (modulo the fractional precision lost in the ×10 quantization).
    ///
    /// Primarily used by `StubMachineTransport` to round-trip typed telemetry
    /// through the actual on-wire format, so the rest of the app exercises the
    /// same decode path it will use against a real machine.
    public func toRegisterBlock() -> [UInt16] {
        var regs = [UInt16](repeating: 0, count: Int(Machine.liveBlockCount))
        func put(_ reg: Machine.LiveRegister, _ value: UInt16) {
            let idx = Int(reg.rawValue) - Int(Machine.liveBlockBase)
            if idx >= 0, idx < regs.count { regs[idx] = value }
        }
        func clamp(_ d: Double) -> UInt16 {
            UInt16(max(0, min(Double(UInt16.max), d.rounded())))
        }
        put(.elapsedDeciseconds, elapsedDeciseconds)
        put(.steamBoilerTempX10, clamp(steamBoilerTempC * 10))
        put(.brewBoilerTempX10,  clamp(brewBoilerTempC  * 10))
        put(.pressureX10,        clamp(pressureBar      * 10))
        put(.totalVolumeMl,      totalVolumeMl)
        put(.pumpTimeS,          pumpTimeS)
        put(.instantFlowMlS,     clamp(pumpFlowMlS))   // raw, NOT ×10
        return regs
    }

    /// Decode a `0x03` (read holding) response covering the live block at
    /// `Machine.liveBlockBase`. Returns `nil` if the frame's function is wrong,
    /// the byte count doesn't add up, or the block is too short to cover the
    /// registers we read out by name.
    public static func decode(response: Modbus.Response, base: UInt16 = Machine.liveBlockBase) -> LiveTelemetry? {
        guard response.function == Modbus.FunctionCode.readHolding.rawValue else { return nil }
        let bytes = Array(response.data)
        guard bytes.count >= 1 else { return nil }
        let byteCount = Int(bytes[0])
        guard byteCount > 0, byteCount % 2 == 0, bytes.count >= 1 + byteCount else { return nil }

        let regCount = byteCount / 2
        var regs = [UInt16](); regs.reserveCapacity(regCount)
        for i in 0..<regCount {
            let hi = UInt16(bytes[1 + i * 2])
            let lo = UInt16(bytes[2 + i * 2])
            regs.append((hi << 8) | lo)
        }

        // Translate each named register to its index within the read block.
        func reg(_ named: Machine.LiveRegister) -> UInt16? {
            let idx = Int(named.rawValue) - Int(base)
            guard idx >= 0, idx < regs.count else { return nil }
            return regs[idx]
        }
        guard
            let elapsed   = reg(.elapsedDeciseconds),
            let steamX10  = reg(.steamBoilerTempX10),
            let brewX10   = reg(.brewBoilerTempX10),
            let pressX10  = reg(.pressureX10),
            let volume    = reg(.totalVolumeMl),
            let pumpT     = reg(.pumpTimeS),
            let flow      = reg(.instantFlowMlS)
        else { return nil }

        return LiveTelemetry(
            elapsedDeciseconds: elapsed,
            steamBoilerTempC: Double(steamX10) / 10.0,
            brewBoilerTempC:  Double(brewX10)  / 10.0,
            pressureBar:      Double(pressX10) / 10.0,
            totalVolumeMl:    volume,
            pumpTimeS:        pumpT,
            pumpFlowMlS:      Double(flow),    // raw, no scaling — see PROTOCOL.md
            registers:        regs
        )
    }
}

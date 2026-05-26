import Foundation

/// FF55 event / provisioning channel framing (PROTOCOL.md §6).
///
/// The 2c10 characteristic carries two distinct framings under the same `FF 55`
/// magic prefix:
///
/// - **Variant A** (opcode-indexed): `FF 55 FF FF <op> 00 <len> <payload...> <csum>`
///   — used for app↔device session, naming, provisioning. Each opcode is a separate
///   command type.
///
/// - **Variant B** (position-indexed): `FF 55 02 59 20 00 <len> <payload...> <csum>`
///   — the ~2 Hz status heartbeat the device pushes unsolicited, and the inverse
///   path for grinder/accessory commands. Fields are positional within payload.
///
/// **Checksum** (both variants): `(sum_of_all_bytes_before_csum + 1) mod 256`.
/// Reverse-engineered from three live fixtures (see `FF55Tests`). Empirically
/// stable across host→device and device→host frames.
public enum FF55 {

    // MARK: - Frame model

    public enum Frame: Sendable, Hashable {
        /// Variant A — opcode-indexed command/event.
        case opcode(op: UInt8, payload: Data)
        /// Variant B — position-indexed payload (heartbeat, grinder, etc.)
        case data(payload: Data)
    }

    /// Magic prefix shared by both variants.
    public static let prefix: [UInt8] = [0xFF, 0x55]

    /// Variant A fixed prefix.
    public static let opcodePrefix: [UInt8] = [0xFF, 0x55, 0xFF, 0xFF]

    /// Variant B fixed 6-byte header.
    public static let dataPrefix: [UInt8] = [0xFF, 0x55, 0x02, 0x59, 0x20, 0x00]

    // MARK: - Checksum

    /// Compute the trailing checksum for a frame body (everything except the csum
    /// byte itself). Formula: `(sum + 1) mod 256`. Reverse-engineered, see
    /// fixtures in `FF55Tests`.
    public static func checksum(_ body: Data) -> UInt8 {
        var sum: UInt32 = 0
        for b in body { sum &+= UInt32(b) }
        return UInt8((sum &+ 1) & 0xFF)
    }

    // MARK: - Builders

    /// Wrap a Variant-A payload: `FF 55 FF FF <op> 00 <len> <payload> <csum>`.
    /// `len` is one byte — the count of payload bytes (not including the csum).
    public static func buildOpcode(_ op: UInt8, payload: Data) -> Data {
        precondition(payload.count <= 0xFF, "FF55 opcode payload exceeds 1-byte length")
        var body = Data(opcodePrefix)
        body.append(op)
        body.append(0x00)
        body.append(UInt8(payload.count))
        body.append(payload)
        body.append(checksum(body))
        return body
    }

    /// Wrap a Variant-B payload: `FF 55 02 59 20 00 <len> <payload> <csum>`.
    /// `len` is the count of payload bytes (not including the csum).
    public static func buildData(payload: Data) -> Data {
        precondition(payload.count <= 0xFF, "FF55 data payload exceeds 1-byte length")
        var body = Data(dataPrefix)
        body.append(UInt8(payload.count))
        body.append(payload)
        body.append(checksum(body))
        return body
    }

    // MARK: - Parser

    /// Validate the checksum and unpack a raw FF55 frame into its variant.
    /// Returns `nil` for short / wrong-magic / bad-checksum frames.
    public static func parse(_ raw: Data) -> Frame? {
        let bytes = Array(raw)
        guard bytes.count >= 4 else { return nil }
        guard bytes[0] == 0xFF, bytes[1] == 0x55 else { return nil }

        // Validate checksum: last byte = (sum of all preceding + 1) mod 256.
        let csumIdx = bytes.count - 1
        let body = bytes.prefix(csumIdx)
        let expected = checksum(Data(body))
        guard bytes[csumIdx] == expected else { return nil }

        // Variant A: FF 55 FF FF <op> 00 <len> <payload>
        if bytes.count >= 8 && bytes[2] == 0xFF && bytes[3] == 0xFF {
            let op  = bytes[4]
            // bytes[5] is always 0x00 in observed frames; treat as reserved.
            let len = Int(bytes[6])
            let start = 7
            guard start + len <= csumIdx else { return nil }
            return .opcode(op: op, payload: Data(bytes[start..<(start + len)]))
        }

        // Variant B: FF 55 02 59 20 00 <len> <payload>
        if bytes.count >= 8 && bytes[2] == 0x02 && bytes[3] == 0x59 &&
           bytes[4] == 0x20 && bytes[5] == 0x00 {
            let len = Int(bytes[6])
            let start = 7
            guard start + len <= csumIdx else { return nil }
            return .data(payload: Data(bytes[start..<(start + len)]))
        }

        return nil
    }
}

// MARK: - Variant-A opcodes (from PROTOCOL.md §6 table)

extension FF55 {
    /// Known opcode values for Variant-A frames. Names from observation; meanings
    /// are partially inferred — see PROTOCOL.md for what each one carries.
    public enum Opcode: UInt8, Sendable, Hashable, CaseIterable {
        case sessionToken      = 0x04   // host→dev, ASCII session id on connect
        case pushDeviceName    = 0x80   // host→dev, ASCII device name push
        case setName           = 0x81   // host→dev, ASCII set-name
        case setFlag           = 0x82   // host→dev, 1-byte boolean
        case getRequest        = 0x83   // host→dev, 1-byte
        case bondConfirmName   = 0x87   // host→dev, ASCII name push on bond
        case booleanPoll       = 0x8B   // host→dev, 1-byte
        case getSetName        = 0x8C   // bidirectional, name pair
        case modbusActivityPing = 0x9A  // dev→host, one-shot on first modbus
    }
}

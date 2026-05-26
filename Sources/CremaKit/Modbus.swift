import Foundation

/// Modbus RTU framing for the Wendougee BLE protocol.
///
/// CRC16-Modbus (poly reflected `0xA001`, init `0xFFFF`, no final xor, little-endian
/// transmit), plus builders for the function codes the espresso machine speaks.
///
/// Every builder returns the full on-the-wire bytes (slave_addr … CRC), ready to
/// hand to a BLE write. `parse(_:)` validates CRC and returns a structured view.
///
/// Direct port of `LitaLite/scripts/modbus.py`. Verified against the 19 packet
/// fixtures extracted from the Wendougee Android APK (see `ModbusTests`).
public enum Modbus {

    /// Slave address the LITA-BA / LITA-BR / DATA-S all respond to.
    public static let defaultSlave: UInt8 = 0x01

    // MARK: - CRC

    /// Standard CRC16-Modbus. Returns the integer CRC; transmit low byte first.
    public static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }

    /// Append the little-endian CRC16-Modbus to a payload.
    private static func wrap(_ payload: Data) -> Data {
        var out = payload
        let crc = crc16(payload)
        out.append(UInt8(crc & 0xFF))
        out.append(UInt8((crc >> 8) & 0xFF))
        return out
    }

    /// Two bytes, big-endian — Modbus address/value encoding.
    private static func beBytes(_ value: UInt16) -> Data {
        Data([UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    // MARK: - Function codes

    public enum FunctionCode: UInt8, Sendable, Hashable {
        case readCoils       = 0x01
        case readHolding     = 0x03
        case writeCoil       = 0x05
        case writeRegister   = 0x06
        case writeRegisters  = 0x10
    }

    // MARK: - Frame builders

    /// `0x01` — read `count` coil values starting at `address`.
    public static func readCoils(at address: UInt16, count: UInt16,
                                 slave: UInt8 = defaultSlave) -> Data {
        var p = Data([slave, FunctionCode.readCoils.rawValue])
        p.append(beBytes(address))
        p.append(beBytes(count))
        return wrap(p)
    }

    /// `0x03` — read `count` holding registers starting at `address`.
    public static func readHolding(at address: UInt16, count: UInt16,
                                   slave: UInt8 = defaultSlave) -> Data {
        var p = Data([slave, FunctionCode.readHolding.rawValue])
        p.append(beBytes(address))
        p.append(beBytes(count))
        return wrap(p)
    }

    /// `0x05` — set a single coil ON (`FF 00`) or OFF (`00 00`).
    public static func writeCoil(at address: UInt16, on: Bool,
                                 slave: UInt8 = defaultSlave) -> Data {
        var p = Data([slave, FunctionCode.writeCoil.rawValue])
        p.append(beBytes(address))
        p.append(on ? Data([0xFF, 0x00]) : Data([0x00, 0x00]))
        return wrap(p)
    }

    /// `0x06` — write a single 16-bit holding register.
    public static func writeRegister(at address: UInt16, value: UInt16,
                                     slave: UInt8 = defaultSlave) -> Data {
        var p = Data([slave, FunctionCode.writeRegister.rawValue])
        p.append(beBytes(address))
        p.append(beBytes(value))
        return wrap(p)
    }

    /// `0x10` — write a contiguous run of holding registers in one frame.
    /// Used to stream the profile header and per-stage blocks during a brew.
    public static func writeRegisters(at address: UInt16, values: [UInt16],
                                      slave: UInt8 = defaultSlave) -> Data {
        let qty = UInt16(values.count)
        var p = Data([slave, FunctionCode.writeRegisters.rawValue])
        p.append(beBytes(address))
        p.append(beBytes(qty))
        p.append(UInt8(values.count * 2))
        for v in values { p.append(beBytes(v)) }
        return wrap(p)
    }

    // MARK: - Response parsing

    public struct Response: Sendable, Hashable {
        public let slave: UInt8
        public let function: UInt8
        /// Bytes after the function code, before the CRC.
        public let data: Data
        /// The raw frame as received, CRC and all.
        public let raw: Data
    }

    /// Validate a received frame's CRC and unpack it. Returns `nil` for frames
    /// shorter than 4 bytes or with a bad CRC.
    public static func parse(_ raw: Data) -> Response? {
        let bytes = Array(raw)
        guard bytes.count >= 4 else { return nil }
        let bodyCount = bytes.count - 2
        let body = Array(bytes.prefix(bodyCount))
        let expected = UInt16(bytes[bodyCount]) | (UInt16(bytes[bodyCount + 1]) << 8)
        guard crc16(Data(body)) == expected else { return nil }
        return Response(
            slave:    body[0],
            function: body[1],
            data:     Data(body.dropFirst(2)),
            raw:      raw
        )
    }
}

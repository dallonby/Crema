import Testing
import Foundation
@testable import CremaKit

/// Verified packet fixtures pulled from the Wendougee Android APK (`libapp.so`
/// AOT constants) and confirmed live. Mirrors the `KNOWN_PACKETS` table in
/// `LitaLite/scripts/modbus.py`. Each entry is `(description, full-frame hex)`.
private let knownPackets: [(String, String)] = [
    ("read 37 holding from 0",      "0103000000258411"),
    ("read 20 holding from 1404",   "0103057C001484D1"),
    ("read 22 holding from 1404",   "0103057C00160510"),
    ("read 16 holding from 387",    "010301830010B412"),
    ("read 1 holding from 1441",    "010305A10001D524"),
    ("read 7 coils from 182",       "010100B600079C2E"),
    ("read 8 coils from 193",       "010100C100086C30"),
    ("coil 150 ON (start brew)",    "01050096FF006C16"),
    ("coil 150 OFF",                "0105009600002DE6"),
    ("coil 154 ON",                 "0105009AFF00AC15"),
    ("coil 154 OFF",                "0105009A0000EDE5"),
    ("coil 155 ON",                 "0105009BFF00FDD5"),
    ("coil 155 OFF",                "0105009B0000BC25"),
    ("coil 157 ON (test)",          "0105009DFF001DD4"),
    ("coil 157 OFF",                "0105009D00005C24"),
    ("reg 15 <- 4 (active model)",  "0106000F0004B80A"),
    ("reg 1459 <- 1",               "010605B30001B921"),
    ("reg 1459 <- 0",               "010605B3000078E1"),
]

@Suite("Modbus")
struct ModbusTests {

    // MARK: - CRC validation against known fixtures

    @Test("CRC16-Modbus matches every known packet")
    func crcMatchesKnownPackets() throws {
        for (desc, hex) in knownPackets {
            let frame = try #require(Data(hex: hex), "bad fixture hex: \(desc)")
            let body = frame.prefix(frame.count - 2)
            let expected = UInt16(frame[frame.count - 2]) |
                           (UInt16(frame[frame.count - 1]) << 8)
            let actual = Modbus.crc16(Data(body))
            #expect(actual == expected,
                    "\(desc): expected \(String(expected, radix: 16)), got \(String(actual, radix: 16))")
        }
    }

    // MARK: - Builder round-trips

    @Test("readHolding builder matches fixtures")
    func readHoldingBuilder() {
        #expect(Modbus.readHolding(at: 0, count: 37).hex     == "0103000000258411")
        #expect(Modbus.readHolding(at: 1404, count: 20).hex  == "0103057C001484D1")
        #expect(Modbus.readHolding(at: 1404, count: 22).hex  == "0103057C00160510")
        #expect(Modbus.readHolding(at: 387, count: 16).hex   == "010301830010B412")
        #expect(Modbus.readHolding(at: 1441, count: 1).hex   == "010305A10001D524")
    }

    @Test("readCoils builder matches fixtures")
    func readCoilsBuilder() {
        #expect(Modbus.readCoils(at: 182, count: 7).hex == "010100B600079C2E")
        #expect(Modbus.readCoils(at: 193, count: 8).hex == "010100C100086C30")
    }

    @Test("writeCoil builder matches every known fixture")
    func writeCoilBuilder() {
        #expect(Modbus.writeCoil(at: 150, on: true).hex  == "01050096FF006C16")
        #expect(Modbus.writeCoil(at: 150, on: false).hex == "0105009600002DE6")
        #expect(Modbus.writeCoil(at: 154, on: true).hex  == "0105009AFF00AC15")
        #expect(Modbus.writeCoil(at: 154, on: false).hex == "0105009A0000EDE5")
        #expect(Modbus.writeCoil(at: 155, on: true).hex  == "0105009BFF00FDD5")
        #expect(Modbus.writeCoil(at: 155, on: false).hex == "0105009B0000BC25")
        #expect(Modbus.writeCoil(at: 157, on: true).hex  == "0105009DFF001DD4")
        #expect(Modbus.writeCoil(at: 157, on: false).hex == "0105009D00005C24")
    }

    @Test("writeRegister builder matches fixtures")
    func writeRegisterBuilder() {
        #expect(Modbus.writeRegister(at: 15,   value: 4).hex == "0106000F0004B80A")
        #expect(Modbus.writeRegister(at: 1459, value: 1).hex == "010605B30001B921")
        #expect(Modbus.writeRegister(at: 1459, value: 0).hex == "010605B3000078E1")
    }

    // MARK: - Multi-register writes (the profile-write path)

    /// Recreate the captured TestyT profile-write sequence from `PROTOCOL.md §3`:
    /// four 6-reg stage blocks at slots 2056/2065/2074/2083. Each frame is the
    /// exact bytes the official Android app put on the wire — by reproducing
    /// them byte-exact we prove the Swift port can drive a real brew.
    @Test("writeRegisters reproduces TestyT profile-write transcript")
    func writeRegistersReproducesTestyTSnoop() {
        #expect(Modbus.writeRegisters(at: 2056, values: [7, 61, 0, 8, 0, 0]).hex
                == "0110080800060C0007003D00000008000000007DF7")
        #expect(Modbus.writeRegisters(at: 2065, values: [3, 23, 0, 0, 0, 0]).hex
                == "0110081100060C000300170000000000000000A5FD")
        #expect(Modbus.writeRegisters(at: 2074, values: [20, 0, 17, 1, 0, 1]).hex
                == "0110081A00060C001400000011000100000001BA8F")
        #expect(Modbus.writeRegisters(at: 2083, values: [4, 11, 0, 0, 1, 0]).hex
                == "0110082300060C0004000B0000000000010000E3FC")
    }

    // MARK: - Round trip

    @Test("parse round-trips every fixture")
    func parseRoundTripsFixtures() throws {
        for (desc, hex) in knownPackets {
            let frame = try #require(Data(hex: hex), "bad fixture hex: \(desc)")
            let parsed = try #require(Modbus.parse(frame), "parse failed: \(desc)")
            #expect(parsed.slave == 0x01)
            #expect(parsed.raw == frame)
        }
    }

    @Test("parse rejects corrupted CRC")
    func parseRejectsBadCRC() throws {
        // Flip a CRC byte → must fail.
        var bad = try #require(Data(hex: "01050096FF006C16"))
        bad[bad.count - 1] ^= 0x01
        #expect(Modbus.parse(bad) == nil)
    }

    @Test("parse rejects short frames")
    func parseRejectsShort() {
        #expect(Modbus.parse(Data([0x01, 0x05, 0x96])) == nil)
        #expect(Modbus.parse(Data()) == nil)
    }
}

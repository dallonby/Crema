import Testing
import Foundation
@testable import CremaKit

@Suite("FF55 framing")
struct FF55Tests {

    // Three live-captured fixtures. The checksum formula was reverse-engineered
    // against all three (PROTOCOL.md §6 documents the frame shape but not the
    // checksum algorithm).
    private let heartbeatFrame    = "FF 55 02 59 20 00 0C 00 36 00 03 00 11 02 58 00 0B 03 84 12"
    private let grinderWriteFrame = "FF 55 02 59 20 00 0A 00 00 00 00 00 00 00 4C 02 37 5F"
    private let modbusPingFrame   = "FF 55 FF FF 9A 00 01 01 EF"

    @Test("checksum formula matches all known fixtures")
    func checksumMatchesFixtures() throws {
        for hex in [heartbeatFrame, grinderWriteFrame, modbusPingFrame] {
            let frame = try #require(Data(hex: hex))
            let body = frame.prefix(frame.count - 1)
            let csum = frame[frame.count - 1]
            #expect(FF55.checksum(Data(body)) == csum,
                    "checksum mismatch for \(hex)")
        }
    }

    @Test("parse identifies Variant-B heartbeat")
    func parsesHeartbeat() throws {
        let frame = try #require(Data(hex: heartbeatFrame))
        let parsed = try #require(FF55.parse(frame))
        guard case let .data(payload) = parsed else {
            Issue.record("expected .data variant, got \(parsed)")
            return
        }
        #expect(payload.count == 12)
        // Reg 33 (steam standby setpoint) = 600 → bytes 0x02 0x58 at payload index 6..7
        #expect(payload[6] == 0x02 && payload[7] == 0x58)
    }

    @Test("parse identifies Variant-A opcode 0x9A modbus-activity ping")
    func parsesModbusPing() throws {
        let frame = try #require(Data(hex: modbusPingFrame))
        let parsed = try #require(FF55.parse(frame))
        guard case let .opcode(op, payload) = parsed else {
            Issue.record("expected .opcode variant, got \(parsed)")
            return
        }
        #expect(op == FF55.Opcode.modbusActivityPing.rawValue)
        #expect(payload == Data([0x01]))
    }

    @Test("buildOpcode round-trips the modbus-activity ping fixture")
    func buildOpcodeRoundTrip() throws {
        let built = FF55.buildOpcode(0x9A, payload: Data([0x01]))
        let expected = try #require(Data(hex: modbusPingFrame))
        #expect(built == expected)
    }

    @Test("buildData round-trips the grinder-write fixture")
    func buildDataRoundTrip() throws {
        // 10-byte payload from the grinder write: 7 unknowns + 4C 02 37
        let payload = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4C, 0x02, 0x37])
        let built = FF55.buildData(payload: payload)
        let expected = try #require(Data(hex: grinderWriteFrame))
        #expect(built == expected)
    }

    @Test("parse rejects bad checksum")
    func rejectsBadChecksum() throws {
        var bad = try #require(Data(hex: modbusPingFrame))
        bad[bad.count - 1] ^= 0x01
        #expect(FF55.parse(bad) == nil)
    }

    @Test("parse rejects wrong magic prefix")
    func rejectsWrongMagic() throws {
        var bad = try #require(Data(hex: modbusPingFrame))
        bad[0] = 0xFE
        #expect(FF55.parse(bad) == nil)
    }

    @Test("parse rejects truncated payload")
    func rejectsTruncated() {
        // Variant-A header claiming len=5 but only 2 payload bytes provided.
        // Note: the checksum needs to match the (corrupt) body for the length
        // check (not the csum check) to be the rejection reason.
        var body = Data([0xFF, 0x55, 0xFF, 0xFF, 0x80, 0x00, 0x05, 0x41, 0x42])
        body.append(FF55.checksum(body))
        #expect(FF55.parse(body) == nil)
    }
}

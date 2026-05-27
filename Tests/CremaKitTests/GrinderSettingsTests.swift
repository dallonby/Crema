import Testing
import Foundation
@testable import CremaKit

@Suite("GrinderSettings")
struct GrinderSettingsTests {

    /// Captured live grinder write from PROTOCOL.md §6:
    /// `FF 55 02 59 20 00 0A 00 00 00 00 00 00 00 4C 02 37 5F`
    /// - 76 µm grind size (byte 7 = 0x4C)
    /// - 567 RPM (bytes 8-9 = 0x02 0x37)
    /// - 7 prefix bytes all zero
    @Test("ff55Frame reproduces the captured grinder write byte-exact")
    func reproducesCapturedGrinderWrite() throws {
        let g = GrinderSettings(grindSizeMicrons: 76, rpm: 567, singleDose: false)
        let frame = g.ff55Frame()
        let expected = try #require(Data(hex: "FF55025920000A000000000000004C02375F"))
        #expect(frame == expected)
    }

    @Test("payload encodes size and RPM at the correct positions")
    func payloadLayout() {
        let g = GrinderSettings(grindSizeMicrons: 100, rpm: 1000)
        let p = g.ff55Payload()
        #expect(p.count == 10)
        // 7 zero bytes
        for i in 0..<7 { #expect(p[i] == 0) }
        // grind size at index 7
        #expect(p[7] == 100)
        // RPM big-endian at 8..9
        #expect(p[8] == UInt8((1000 >> 8) & 0xFF))
        #expect(p[9] == UInt8(1000 & 0xFF))
    }

    @Test("frame parses back through FF55 with correct checksum")
    func frameRoundTrip() throws {
        let g = GrinderSettings(grindSizeMicrons: 200, rpm: 450)
        let frame = g.ff55Frame()
        let parsed = try #require(FF55.parse(frame))
        if case let .data(payload) = parsed {
            #expect(payload == g.ff55Payload())
        } else {
            Issue.record("expected .data variant")
        }
    }
}

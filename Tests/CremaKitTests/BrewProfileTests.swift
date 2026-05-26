import Testing
import Foundation
@testable import CremaKit

@Suite("BrewProfile encoder")
struct BrewProfileEncoderTests {

    /// The captured TestyT snoop transcript from `PROTOCOL.md §3` —
    /// every byte the official app put on the wire. Encoding our own
    /// `BrewProfile.testyT` to slot 1 must reproduce these byte-exact.
    /// (The header frame is computed and CRC-validated below; the snoop
    /// only published the four stage writes and the active-mode write.)
    @Test("TestyT → slot 1 reproduces the live snoop byte-exact")
    func testyTReproducesSnoop() {
        let steps = BrewProfile.testyT.encode(toSlot: .one, triggerBrew: true)
        let frames = steps.map { $0.frame.hex }

        // 1 header + 4 stages + 1 active mode + 2 coil = 8 frames
        #expect(frames.count == 8)

        // header (computed from headerRegisters() = [1,1,1,1,68,0,0] at addr 2048)
        // We don't have a captured fixture for the header — but Modbus.parse() must
        // accept it (CRC valid) and the slave/function bytes must be correct.
        let header = steps[0].frame
        let headerParsed = Modbus.parse(header)
        #expect(headerParsed?.function == Modbus.FunctionCode.writeRegisters.rawValue)
        #expect(headerParsed?.slave == 0x01)

        // Four stage writes — every byte verified live.
        #expect(frames[1] == "0110080800060C0007003D00000008000000007DF7")
        #expect(frames[2] == "0110081100060C000300170000000000000000A5FD")
        #expect(frames[3] == "0110081A00060C001400000011000100000001BA8F")
        #expect(frames[4] == "0110082300060C0004000B0000000000010000E3FC")

        // Active mode reg 87 ← 2 (Flow variable pressure) — captured.
        #expect(frames[5] == "0106005700 02B9DB".replacingOccurrences(of: " ", with: ""))

        // Coil 150 ON / OFF — same fixtures as in ModbusTests.
        #expect(frames[6] == "01050096FF006C16")
        #expect(frames[7] == "0105009600002DE6")
    }

    @Test("headerRegisters matches the captured value layout")
    func headerRegistersAreCorrect() {
        let h = BrewProfile.testyT.headerRegisters()
        // callswitch=1 (flow), mode=1 (variable pressure), direct=1 (NOT direct, inverted),
        // changeswitch=1 (variable), total_flow=68, total_weight=0, auto_link=0
        #expect(h == [1, 1, 1, 1, 68, 0, 0])
    }

    @Test("stageRegisters packs pressure & flow stages correctly")
    func stageRegistersAreCorrect() {
        let p = BrewProfile.testyT
        let s0 = p.stageRegisters(p.stages[0], isLast: false)
        #expect(s0 == [7, 61, 0, 8, 0, 0])   // Preinfuse — pressure priority, 6.1 bar, 8s wait
        let s2 = p.stageRegisters(p.stages[2], isLast: false)
        #expect(s2 == [20, 0, 17, 1, 0, 1])  // Extract — flow priority, 1.7 mL/s, 1s wait
        let s3 = p.stageRegisters(p.stages[3], isLast: true)
        #expect(s3 == [4, 11, 0, 0, 1, 0])   // Tail — last stage so wait=0, is_end=1
    }

    @Test("triggerBrew:false omits the coil-150 trigger")
    func triggerBrewFalseOmitsCoil() {
        let steps = BrewProfile.testyT.encode(toSlot: .one, triggerBrew: false)
        // 1 header + 4 stages + 1 active mode = 6 frames
        #expect(steps.count == 6)
        for step in steps {
            switch step {
            case .coilOn, .coilOff: Issue.record("unexpected coil step: \(step.description)")
            default: continue
            }
        }
    }

    @Test("slot 2 uses base address 2560")
    func slotTwoUsesCorrectBase() {
        let steps = BrewProfile.testyT.encode(toSlot: .two, triggerBrew: false)
        // The first stage writeRegisters frame addresses 2560+8 = 2568 = 0x0A08
        let stage1 = Modbus.parse(steps[1].frame)
        #expect(stage1?.function == Modbus.FunctionCode.writeRegisters.rawValue)
        // Bytes 0..1 of data carry the address (big-endian)
        let addr = (UInt16(stage1!.data[stage1!.data.startIndex]) << 8) |
                   UInt16(stage1!.data[stage1!.data.startIndex + 1])
        #expect(addr == 2568)
    }
}

@Suite("LiveTelemetry decoder")
struct LiveTelemetryTests {

    /// Build a synthetic 0x03 response covering registers 1404..1425 (22 regs)
    /// with known values, then verify the decoder picks them apart correctly.
    @Test("decodes a typical live block")
    func decodesTypicalLiveBlock() throws {
        // Register values at 1404..1425 (22 regs). Indexes into this array
        // map to: index = regNumber - 1404.
        var regs = [UInt16](repeating: 0, count: 22)
        regs[1405 - 1404] = 154    // elapsedDeciseconds → 15.4 s
        regs[1408 - 1404] = 1263   // steam °C × 10 → 126.3
        regs[1409 - 1404] = 954    // brew  °C × 10 →  95.4
        regs[1410 - 1404] = 61     // pressure ×10 → 6.1 bar
        regs[1411 - 1404] = 24     // volume mL
        regs[1417 - 1404] = 6      // pump time s
        regs[1422 - 1404] = 4      // raw flow mL/s → 4 mL/s (NOT divided!)

        // Synthesize the 0x03 response frame: [slave=01, fc=03, byteCount, regbytes..., CRC]
        var payload = Data([0x01, 0x03, UInt8(regs.count * 2)])
        for r in regs {
            payload.append(UInt8(r >> 8))
            payload.append(UInt8(r & 0xFF))
        }
        var frame = payload
        let crc = Modbus.crc16(payload)
        frame.append(UInt8(crc & 0xFF))
        frame.append(UInt8((crc >> 8) & 0xFF))

        let parsed = try #require(Modbus.parse(frame))
        let live = try #require(LiveTelemetry.decode(response: parsed))

        #expect(live.elapsedDeciseconds == 154)
        #expect(live.elapsedSeconds == 15.4)
        #expect(live.steamBoilerTempC == 126.3)
        #expect(live.brewBoilerTempC == 95.4)
        #expect(live.pressureBar == 6.1)
        #expect(live.totalVolumeMl == 24)
        #expect(live.pumpTimeS == 6)
        #expect(live.pumpFlowMlS == 4.0)   // raw — not ÷10
    }

    @Test("rejects non-readHolding frames")
    func rejectsWrongFunction() throws {
        let writeCoilFrame = Modbus.writeCoil(at: 150, on: true)
        let parsed = try #require(Modbus.parse(writeCoilFrame))
        #expect(LiveTelemetry.decode(response: parsed) == nil)
    }

    @Test("toRegisterBlock round-trips through decode")
    func registerBlockRoundTrip() throws {
        let original = LiveTelemetry(
            elapsedDeciseconds: 154,
            steamBoilerTempC: 126.3,
            brewBoilerTempC: 95.4,
            pressureBar: 6.1,
            totalVolumeMl: 24,
            pumpTimeS: 6,
            pumpFlowMlS: 4.0,
            registers: []
        )
        let regs = original.toRegisterBlock()

        // Re-encode as a 0x03 response and decode
        var body = Data([0x01, 0x03, UInt8(regs.count * 2)])
        for r in regs {
            body.append(UInt8(r >> 8))
            body.append(UInt8(r & 0xFF))
        }
        let crc = Modbus.crc16(body)
        body.append(UInt8(crc & 0xFF))
        body.append(UInt8((crc >> 8) & 0xFF))
        let parsed = try #require(Modbus.parse(body))
        let recovered = try #require(LiveTelemetry.decode(response: parsed))

        #expect(recovered.elapsedDeciseconds == original.elapsedDeciseconds)
        #expect(recovered.steamBoilerTempC == original.steamBoilerTempC)
        #expect(recovered.brewBoilerTempC == original.brewBoilerTempC)
        #expect(recovered.pressureBar == original.pressureBar)
        #expect(recovered.totalVolumeMl == original.totalVolumeMl)
        #expect(recovered.pumpTimeS == original.pumpTimeS)
        #expect(recovered.pumpFlowMlS == original.pumpFlowMlS)
    }

    @Test("rejects truncated response data")
    func rejectsShort() throws {
        var payload = Data([0x01, 0x03, 0x04, 0x00, 0x00, 0x00, 0x00])  // only 2 regs, base read needs 1422
        let crc = Modbus.crc16(payload)
        payload.append(UInt8(crc & 0xFF))
        payload.append(UInt8((crc >> 8) & 0xFF))
        let parsed = try #require(Modbus.parse(payload))
        #expect(LiveTelemetry.decode(response: parsed) == nil)
    }
}

import XCTest
@testable import EasyMacBord

final class DeviceProtocolTests: XCTestCase {
    func testCRC16StandardVector() {
        XCTAssertEqual(DeviceProtocol.crc16CCITT(Data("123456789".utf8)), 0x29b1)
    }

    func testConfigurationFrameBoundaries() throws {
        let oneFrame = try DeviceProtocol.makeConfigurationFrames(json: Data(repeating: 0x61, count: 52))
        XCTAssertEqual(oneFrame.count, 1)
        XCTAssertEqual(oneFrame[0].payload.count, 63)
        XCTAssertEqual(Array(oneFrame[0].payload.prefix(6)), [0x53, 0x33, 0x43, 0x01, 0, 1])

        let twoFrames = try DeviceProtocol.makeConfigurationFrames(json: Data(repeating: 0x61, count: 53))
        XCTAssertEqual(twoFrames.count, 2)
        XCTAssertEqual(twoFrames[0].payload[8], 52)
        XCTAssertEqual(twoFrames[1].payload[4], 1)
        XCTAssertEqual(twoFrames[1].payload[8], 1)
    }

    func testConfigurationRejectsOutOfRangePayloads() {
        XCTAssertThrowsError(try DeviceProtocol.makeConfigurationFrames(json: Data()))
        XCTAssertThrowsError(try DeviceProtocol.makeConfigurationFrames(json: Data(repeating: 0, count: 2_049)))
    }

    func testDecodesOnlyCanonicalLowercaseHostAction() throws {
        var report = Data(repeating: 0, count: 63)
        report[0] = 0x05
        report[1] = 0
        report[2] = 1
        report[3] = 36
        let raw = "123e4567-e89b-12d3-a456-426614174000"
        report.replaceSubrange(4 ..< 40, with: raw.utf8)

        XCTAssertEqual(try DeviceProtocol.decodeAppCommand(payload: report), .hostAction(UUID(uuidString: raw)!))

        report.replaceSubrange(4 ..< 40, with: raw.uppercased().utf8)
        XCTAssertThrowsError(try DeviceProtocol.decodeAppCommand(payload: report))
    }

    func testAcknowledgementRequiresItsOwnKindAndSevenBytes() throws {
        var report = Data(repeating: 0, count: 63)
        report[0] = 0x03
        report[1] = 0
        report[2] = 1
        report[3] = 7
        report[4] = 1
        report[5] = 1
        report[6] = 0x34
        report[7] = 0x12
        report[8] = 0xcd
        report[9] = 0xab
        report[10] = 1

        XCTAssertEqual(
            try DeviceProtocol.decodeAppCommand(payload: report),
            .configurationAcknowledgement(.init(phase: 1, ok: true, bytes: 0x1234, crc16: 0xabcd, saved: true))
        )
    }

    func testAcknowledgementRejectsUnexpectedFragmentFields() {
        var report = Data(repeating: 0, count: 63)
        report[0] = 0x03
        report[1] = 1
        report[2] = 1
        report[3] = 7

        XCTAssertThrowsError(try DeviceProtocol.decodeAppCommand(payload: report))
    }

    func testStatusResponseNeverBecomesHostAction() throws {
        var report = Data(repeating: 0, count: 63)
        report[0] = 0x04
        XCTAssertEqual(try DeviceProtocol.decodeAppCommand(payload: report), .statusResponse)
    }
}

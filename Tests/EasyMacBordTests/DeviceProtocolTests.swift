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

    func testMakesExactS3RStatusRequestBody() throws {
        let request = try DeviceProtocol.makeStatusRequest(requestID: 0x7856_3412, fresh: true)
        XCTAssertEqual(request.count, 16)
        XCTAssertEqual(
            Array(request),
            [0x53, 0x33, 0x52, 0x01, 0x12, 0x34, 0x56, 0x78, 0x01, 0, 0, 0, 0, 0, 0, 0]
        )
        XCTAssertThrowsError(try DeviceProtocol.makeStatusRequest(requestID: 0))
    }

    func testMakesIOKitStatusFeatureReportWithReportIDPrefix() throws {
        let report = try DeviceProtocol.makeStatusFeatureReport(requestID: 0x7856_3412, fresh: true)

        XCTAssertEqual(
            Array(report),
            [0x13, 0x53, 0x33, 0x52, 0x01, 0x12, 0x34, 0x56, 0x78, 0x01, 0, 0, 0, 0, 0, 0, 0]
        )
    }

    func testNormalizesBothIOKitAppCommandReportLayouts() {
        let payload = Data(repeating: 0x04, count: DeviceProtocol.appCommandPayloadLength)
        let prefixed = Data([DeviceProtocol.appCommandReportID]) + payload

        XCTAssertEqual(
            DeviceProtocol.normalizeIOKitAppCommandReport(
                reportID: DeviceProtocol.appCommandReportID,
                report: payload
            ),
            payload
        )
        XCTAssertEqual(
            DeviceProtocol.normalizeIOKitAppCommandReport(
                reportID: DeviceProtocol.appCommandReportID,
                report: prefixed
            ),
            payload
        )
        XCTAssertNil(
            DeviceProtocol.normalizeIOKitAppCommandReport(
                reportID: DeviceProtocol.appCommandReportID,
                report: Data(repeating: 0, count: DeviceProtocol.appCommandPayloadLength + 1)
            )
        )
    }

    func testStatusRequestFailureMessagesDoNotContainDeviceDetails() {
        XCTAssertEqual(StatusRequestFailure.deviceNotOpen.displayMessage, "HID 设备未打开")
        XCTAssertEqual(StatusRequestFailure.inputMonitoringNotGranted.displayMessage, "输入监控授权未对当前应用生效")
        XCTAssertEqual(StatusRequestFailure.featureReportNotPermitted.displayMessage, "输入监控已授权，但系统拒绝 HID Feature Report")
    }

    func testReassemblesStatusChunksAndExposesFirmwareFields() throws {
        let json = Data("""
        {"schema":"ai_keyboard.config_status.v1","firmware":"0.1.26","capabilities":{"config_max_bytes":2048,"host_action_v1":true},"ptt_hotkey":"RightMeta","edit_ptt_hotkey":"RightOption"}
        """.utf8)
        let reports = makeStatusReports(json: json, requestID: 0x1234_5678)
        XCTAssertGreaterThan(reports.count, 1)

        var reassembler = DeviceProtocol.StatusResponseReassembler()
        try reassembler.begin(requestID: 0x1234_5678)
        for report in reports.dropLast() {
            XCTAssertNil(try reassembler.receive(payload: report))
        }
        let status = try XCTUnwrap(reassembler.receive(payload: try XCTUnwrap(reports.last)))
        XCTAssertEqual(status.firmware, "0.1.26")
        XCTAssertEqual(status.capabilities["config_max_bytes"], .integer(2_048))
        XCTAssertEqual(status.capabilities["host_action_v1"], .boolean(true))
        XCTAssertEqual(status.pttHotkey, "RightMeta")
        XCTAssertEqual(status.editPTTHotkey, "RightOption")
    }

    func testStatusReassemblerRejectsMismatchedRequestOrderAndCRC() throws {
        let json = Data("""
        {"schema":"ai_keyboard.config_status.v1","firmware":"0.1.26","capabilities":{},"ptt_hotkey":"RightMeta","edit_ptt_hotkey":"RightOption"}
        """.utf8)
        let reports = makeStatusReports(json: json, requestID: 0x1020_3040)
        XCTAssertGreaterThan(reports.count, 1)

        var reassembler = DeviceProtocol.StatusResponseReassembler()
        try reassembler.begin(requestID: 0x1020_3040)
        XCTAssertThrowsError(try reassembler.receive(payload: reports[1])) { error in
            XCTAssertEqual(error as? DeviceProtocol.Error, .statusResponseOutOfOrder)
        }

        try reassembler.begin(requestID: 0x0102_0304)
        XCTAssertThrowsError(try reassembler.receive(payload: reports[0])) { error in
            XCTAssertEqual(error as? DeviceProtocol.Error, .statusResponseRequestMismatch)
        }

        var badCRCReports = reports
        for index in badCRCReports.indices {
            badCRCReports[index][11] ^= 0x01
        }
        try reassembler.begin(requestID: 0x1020_3040)
        for report in badCRCReports.dropLast() {
            XCTAssertNil(try reassembler.receive(payload: report))
        }
        XCTAssertThrowsError(try reassembler.receive(payload: try XCTUnwrap(badCRCReports.last))) { error in
            XCTAssertEqual(error as? DeviceProtocol.Error, .statusResponseCRCMismatch)
        }
    }

    func testStatusChunkRejectsOversizedDeclaredJSON() {
        var report = Data(repeating: 0, count: 63)
        report[0] = 0x04
        report[1] = 0
        report[2] = 1
        report[3] = 59
        report[4] = 1
        report[5] = 1
        report[9] = 0x01
        report[10] = 0x02
        XCTAssertThrowsError(try DeviceProtocol.decodeStatusResponseChunk(payload: report)) { error in
            XCTAssertEqual(error as? DeviceProtocol.Error, .malformedStatusResponse)
        }
    }

    func testDecodesBLEStatusDocumentWithoutHIDFraming() {
        let payload = Data("""
        {"schema":"ai_keyboard.config_status.v1","firmware":"0.1.26","capabilities":{"semantic_actions":true},"ptt_hotkey":"RightMeta","edit_ptt_hotkey":"RightOption"}
        """.utf8)
        let status = DeviceProtocol.decodeBLEDeviceStatus(payload)
        XCTAssertEqual(status?.firmware, "0.1.26")
        XCTAssertEqual(status?.capabilities["semantic_actions"], .boolean(true))
        XCTAssertNil(DeviceProtocol.decodeBLEDeviceStatus(Data("{}".utf8)))
    }

    func testDecodesStatusDocumentWithoutPTTHotkeys() throws {
        let payload = Data("""
        {"schema":"ai_keyboard.config_status.v1","firmware":"0.1.26","capabilities":{"semantic_actions":true}}
        """.utf8)

        let status = try XCTUnwrap(DeviceProtocol.decodeBLEDeviceStatus(payload))

        XCTAssertEqual(status.capabilities["semantic_actions"], .boolean(true))
        XCTAssertNil(status.pttHotkey)
        XCTAssertNil(status.editPTTHotkey)
    }

    func testDecodesStatusDocumentWhenOnePTTHotkeyIsAbsent() throws {
        let payload = Data("""
        {"schema":"ai_keyboard.config_status.v1","firmware":"0.1.26","capabilities":{"semantic_actions":true},"ptt_hotkey":"RightMeta"}
        """.utf8)

        let status = try XCTUnwrap(DeviceProtocol.decodeBLEDeviceStatus(payload))

        XCTAssertEqual(status.pttHotkey, "RightMeta")
        XCTAssertNil(status.editPTTHotkey)
    }

    private func makeStatusReports(json: Data, requestID: UInt32) -> [Data] {
        precondition(!json.isEmpty && json.count <= DeviceProtocol.statusResponseMaximumJSONLength)
        let chunkLength = DeviceProtocol.statusResponseChunkDataLength
        let totalChunks = UInt8((json.count + chunkLength - 1) / chunkLength)
        let crc16 = DeviceProtocol.crc16CCITT(json)

        return (0 ..< Int(totalChunks)).map { index in
            let offset = index * chunkLength
            let fragment = Data(json[offset ..< min(offset + chunkLength, json.count)])
            var report = Data(repeating: 0, count: DeviceProtocol.appCommandPayloadLength)
            report[0] = DeviceProtocol.statusResponseKind
            report[1] = UInt8(index)
            report[2] = totalChunks
            report[3] = UInt8(DeviceProtocol.statusResponseMetadataLength + fragment.count)
            report[4] = 1
            report[5] = UInt8(requestID & 0xff)
            report[6] = UInt8((requestID >> 8) & 0xff)
            report[7] = UInt8((requestID >> 16) & 0xff)
            report[8] = UInt8((requestID >> 24) & 0xff)
            report[9] = UInt8(json.count & 0xff)
            report[10] = UInt8((json.count >> 8) & 0xff)
            report[11] = UInt8(crc16 & 0xff)
            report[12] = UInt8((crc16 >> 8) & 0xff)
            report.replaceSubrange(13 ..< 13 + fragment.count, with: fragment)
            return report
        }
    }
}

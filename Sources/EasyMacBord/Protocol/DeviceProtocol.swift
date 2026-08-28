import Foundation

enum DeviceProtocol {
    static let configurationReportID: UInt8 = 0x10
    static let appCommandReportID: UInt8 = 0x11
    static let statusRequestReportID: UInt8 = 0x13
    static let appCommandPayloadLength = 63
    static let configurationHeaderLength = 11
    static let configurationChunkDataLength = 52
    static let configurationMaximumLength = 2_048
    static let statusRequestLength = 16
    static let statusResponseMetadataLength = 9
    static let statusResponseChunkDataLength = appCommandPayloadLength - 4 - statusResponseMetadataLength
    static let statusResponseMaximumJSONLength = 512
    static let hostActionKind: UInt8 = 0x05
    static let configurationAcknowledgementKind: UInt8 = 0x03
    static let statusResponseKind: UInt8 = 0x04
    static let statusSchema = "ai_keyboard.config_status.v1"

    enum Error: Swift.Error, Equatable {
        case emptyConfiguration
        case configurationTooLarge
        case invalidReportLength
        case malformedConfigurationAcknowledgement
        case invalidHostAction
        case invalidStatusRequest
        case malformedStatusResponse
        case statusResponseRequestMismatch
        case statusResponseOutOfOrder
        case statusResponseCRCMismatch
        case invalidStatusDocument
    }

    struct ConfigurationFrame: Equatable {
        let chunkIndex: UInt8
        let totalChunks: UInt8
        let payload: Data
    }

    struct ConfigurationAcknowledgement: Equatable {
        let phase: UInt8
        let ok: Bool
        let bytes: UInt16
        let crc16: UInt16
        let saved: Bool
    }

    struct StatusResponseChunk: Equatable {
        let requestID: UInt32
        let chunkIndex: UInt8
        let totalChunks: UInt8
        let declaredJSONLength: UInt16
        let crc16: UInt16
        let jsonFragment: Data
    }

    enum CapabilityValue: Equatable {
        case boolean(Bool)
        case integer(Int)
        case string(String)
    }

    struct DeviceStatus: Equatable {
        let firmware: String
        let capabilities: [String: CapabilityValue]
        let pttHotkey: String?
        let editPTTHotkey: String?
    }

    enum IncomingMessage: Equatable {
        case configurationAcknowledgement(ConfigurationAcknowledgement)
        case hostAction(UUID)
        case statusResponse
        case unknown(UInt8)
    }

    static func makeConfigurationFrames(json: Data) throws -> [ConfigurationFrame] {
        guard !json.isEmpty else { throw Error.emptyConfiguration }
        guard json.count <= configurationMaximumLength else { throw Error.configurationTooLarge }

        let chunks = stride(from: 0, to: json.count, by: configurationChunkDataLength).map {
            Data(json[$0 ..< min($0 + configurationChunkDataLength, json.count)])
        }
        let totalChunks = UInt8(chunks.count)
        let length = UInt16(json.count)
        let crc = crc16CCITT(json)

        return chunks.enumerated().map { index, chunk in
            var frame = Data([0x53, 0x33, 0x43, 0x01, UInt8(index), totalChunks])
            frame.append(UInt8(length & 0xff))
            frame.append(UInt8((length >> 8) & 0xff))
            frame.append(UInt8(chunk.count))
            frame.append(UInt8(crc & 0xff))
            frame.append(UInt8((crc >> 8) & 0xff))
            frame.append(chunk)
            return ConfigurationFrame(chunkIndex: UInt8(index), totalChunks: totalChunks, payload: frame)
        }
    }

    static func crc16CCITT(_ data: Data) -> UInt16 {
        data.reduce(UInt16(0xffff)) { crc, byte in
            var next = crc ^ (UInt16(byte) << 8)
            for _ in 0 ..< 8 {
                next = (next & 0x8000) == 0 ? next << 1 : (next << 1) ^ 0x1021
            }
            return next
        }
    }

    /// S3R v1 protocol body. The protocol body is always exactly 16 bytes.
    static func makeStatusRequest(requestID: UInt32, fresh: Bool = false) throws -> Data {
        guard requestID != 0 else { throw Error.invalidStatusRequest }

        var payload = Data(repeating: 0, count: statusRequestLength)
        payload[0] = 0x53
        payload[1] = 0x33
        payload[2] = 0x52
        payload[3] = 0x01
        payload[4] = UInt8(requestID & 0xff)
        payload[5] = UInt8((requestID >> 8) & 0xff)
        payload[6] = UInt8((requestID >> 16) & 0xff)
        payload[7] = UInt8((requestID >> 24) & 0xff)
        payload[8] = fresh ? 0x01 : 0x00
        return payload
    }

    /// IOKit requires the Report ID to be the first byte of a multi-report
    /// Feature Report buffer, while the S3R v1 body itself remains 16 bytes.
    static func makeStatusFeatureReport(requestID: UInt32, fresh: Bool = false) throws -> Data {
        var report = Data([statusRequestReportID])
        report.append(try makeStatusRequest(requestID: requestID, fresh: fresh))
        return report
    }

    /// Normalizes the two input-report layouts observed from IOKit. Some
    /// drivers retain the Report ID in the callback buffer while others pass
    /// only the 63-byte payload.
    static func normalizeIOKitAppCommandReport(reportID: UInt8, report: Data) -> Data? {
        guard reportID == appCommandReportID else { return nil }
        if report.count == appCommandPayloadLength {
            return report
        }
        guard report.count == appCommandPayloadLength + 1,
              report.first == appCommandReportID else {
            return nil
        }
        return Data(report.dropFirst())
    }

    /// Decodes a single 63-byte `0x11 / kind 0x04` status response chunk.
    /// The contract fixes the fragment length for every chunk, so malformed
    /// partial chunks are rejected before JSON assembly begins.
    static func decodeStatusResponseChunk(payload: Data) throws -> StatusResponseChunk {
        guard payload.count == appCommandPayloadLength,
              payload[0] == statusResponseKind else {
            throw Error.malformedStatusResponse
        }

        let chunkIndex = payload[1]
        let totalChunks = payload[2]
        let declaredDataLength = Int(payload[3])
        guard payload[4] == 0x01,
              totalChunks > 0,
              chunkIndex < totalChunks,
              declaredDataLength >= statusResponseMetadataLength,
              declaredDataLength <= statusResponseMetadataLength + statusResponseChunkDataLength else {
            throw Error.malformedStatusResponse
        }

        let requestID = UInt32(payload[5])
            | (UInt32(payload[6]) << 8)
            | (UInt32(payload[7]) << 16)
            | (UInt32(payload[8]) << 24)
        let declaredJSONLength = UInt16(payload[9]) | (UInt16(payload[10]) << 8)
        let crc16 = UInt16(payload[11]) | (UInt16(payload[12]) << 8)
        let jsonLength = Int(declaredJSONLength)
        let fragmentLength = declaredDataLength - statusResponseMetadataLength
        let expectedChunkCount = (jsonLength + statusResponseChunkDataLength - 1) / statusResponseChunkDataLength
        let expectedOffset = Int(chunkIndex) * statusResponseChunkDataLength
        let expectedFragmentLength = min(statusResponseChunkDataLength, jsonLength - expectedOffset)

        guard requestID != 0,
              jsonLength > 0,
              jsonLength <= statusResponseMaximumJSONLength,
              totalChunks == UInt8(expectedChunkCount),
              expectedOffset < jsonLength,
              fragmentLength == expectedFragmentLength else {
            throw Error.malformedStatusResponse
        }

        let fragmentStart = 4 + statusResponseMetadataLength
        let fragmentEnd = fragmentStart + fragmentLength
        guard payload[fragmentEnd ..< payload.count].allSatisfy({ $0 == 0 }) else {
            throw Error.malformedStatusResponse
        }
        return StatusResponseChunk(
            requestID: requestID,
            chunkIndex: chunkIndex,
            totalChunks: totalChunks,
            declaredJSONLength: declaredJSONLength,
            crc16: crc16,
            jsonFragment: Data(payload[fragmentStart ..< fragmentEnd])
        )
    }

    /// Reassembles one response for one S3R request. A new request replaces
    /// any previous stream, matching the Maker firmware's retry behavior.
    struct StatusResponseReassembler {
        private var expectedRequestID: UInt32?
        private var nextChunkIndex: UInt8 = 0
        private var totalChunks: UInt8?
        private var declaredJSONLength: UInt16?
        private var expectedCRC16: UInt16?
        private var collectedJSON = Data()

        mutating func begin(requestID: UInt32) throws {
            guard requestID != 0 else { throw Error.invalidStatusRequest }
            reset()
            expectedRequestID = requestID
        }

        mutating func reset() {
            expectedRequestID = nil
            nextChunkIndex = 0
            totalChunks = nil
            declaredJSONLength = nil
            expectedCRC16 = nil
            collectedJSON.removeAll(keepingCapacity: false)
        }

        mutating func receive(payload: Data) throws -> DeviceStatus? {
            do {
                let chunk = try DeviceProtocol.decodeStatusResponseChunk(payload: payload)
                guard let expectedRequestID,
                      chunk.requestID == expectedRequestID else {
                    throw Error.statusResponseRequestMismatch
                }
                guard chunk.chunkIndex == nextChunkIndex else {
                    throw Error.statusResponseOutOfOrder
                }

                if nextChunkIndex == 0 {
                    totalChunks = chunk.totalChunks
                    declaredJSONLength = chunk.declaredJSONLength
                    expectedCRC16 = chunk.crc16
                } else {
                    guard let totalChunks,
                          let declaredJSONLength,
                          let expectedCRC16,
                          totalChunks == chunk.totalChunks,
                          declaredJSONLength == chunk.declaredJSONLength,
                          expectedCRC16 == chunk.crc16 else {
                        throw Error.malformedStatusResponse
                    }
                }

                collectedJSON.append(chunk.jsonFragment)
                guard let declaredJSONLength,
                      collectedJSON.count <= Int(declaredJSONLength) else {
                    throw Error.malformedStatusResponse
                }

                nextChunkIndex &+= 1
                guard nextChunkIndex == chunk.totalChunks else { return nil }

                guard let expectedCRC16 = self.expectedCRC16 else {
                    throw Error.malformedStatusResponse
                }
                let json = collectedJSON
                reset()
                guard json.count == Int(chunk.declaredJSONLength) else {
                    throw Error.malformedStatusResponse
                }
                guard crc16CCITT(json) == expectedCRC16 else {
                    throw Error.statusResponseCRCMismatch
                }
                return try parseDeviceStatus(json: json)
            } catch {
                reset()
                throw error
            }
        }
    }

    static func decodeAppCommand(payload: Data) throws -> IncomingMessage {
        guard payload.count == appCommandPayloadLength else { throw Error.invalidReportLength }
        let kind = payload[payload.startIndex]
        switch kind {
        case configurationAcknowledgementKind:
            guard payload[1] == 0, payload[2] == 1, payload[3] == 7 else {
                throw Error.malformedConfigurationAcknowledgement
            }
            let data = payload.dropFirst(4)
            let bytes = UInt16(data[data.startIndex + 2]) | UInt16(data[data.startIndex + 3]) << 8
            let crc = UInt16(data[data.startIndex + 4]) | UInt16(data[data.startIndex + 5]) << 8
            return .configurationAcknowledgement(
                ConfigurationAcknowledgement(
                    phase: data[data.startIndex],
                    ok: data[data.startIndex + 1] == 1,
                    bytes: bytes,
                    crc16: crc,
                    saved: data[data.startIndex + 6] == 1
                )
            )
        case hostActionKind:
            guard payload[1] == 0, payload[2] == 1, payload[3] == 36 else { throw Error.invalidHostAction }
            let bytes = payload[4 ..< 40]
            guard let raw = String(data: bytes, encoding: .ascii),
                  let uuid = UUID(uuidString: raw),
                  raw == uuid.uuidString.lowercased() else {
                throw Error.invalidHostAction
            }
            return .hostAction(uuid)
        case statusResponseKind:
            return .statusResponse
        default:
            return .unknown(kind)
        }
    }

    private static func parseDeviceStatus(json: Data) throws -> DeviceStatus {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              root["schema"] as? String == statusSchema,
              let firmware = root["firmware"] as? String,
              let capabilityObject = root["capabilities"] as? [String: Any] else {
            throw Error.invalidStatusDocument
        }

        let pttHotkey = root["ptt_hotkey"] as? String
        let editPTTHotkey = root["edit_ptt_hotkey"] as? String
        guard (root["ptt_hotkey"] == nil || pttHotkey != nil),
              (root["edit_ptt_hotkey"] == nil || editPTTHotkey != nil) else {
            throw Error.invalidStatusDocument
        }

        var capabilities: [String: CapabilityValue] = [:]
        for (name, value) in capabilityObject {
            if let boolean = value as? Bool {
                capabilities[name] = .boolean(boolean)
            } else if let integer = value as? Int {
                capabilities[name] = .integer(integer)
            } else if let string = value as? String {
                capabilities[name] = .string(string)
            } else {
                throw Error.invalidStatusDocument
            }
        }
        return DeviceStatus(
            firmware: firmware,
            capabilities: capabilities,
            pttHotkey: pttHotkey,
            editPTTHotkey: editPTTHotkey
        )
    }

    /// BLE publishes the same status document directly as JSON, rather than
    /// inside an App Command report. It has no request/response framing.
    static func decodeBLEDeviceStatus(_ data: Data) -> DeviceStatus? {
        try? parseDeviceStatus(json: data)
    }

    /// BLE confirmation notifications are JSON, unlike the HID acknowledgement.
    /// They may be delivered alongside a complete status document.
    static func decodeBLEConfirmationStatus(_ data: Data) -> ConfigurationAcknowledgement? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bytes = object["bytes"] as? Int,
              let crc16 = object["crc16"] as? Int,
              let saved = object["saved"] as? Bool,
              let phase = object["phase"] as? String,
              phase == "push" || phase == "confirmation" else {
            return nil
        }
        return ConfigurationAcknowledgement(
            phase: 1,
            ok: (object["ok"] as? Bool) ?? saved,
            bytes: UInt16(clamping: bytes),
            crc16: UInt16(clamping: crc16),
            saved: saved
        )
    }
}

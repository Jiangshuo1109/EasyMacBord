import Foundation

enum DeviceProtocol {
    static let configurationReportID: UInt8 = 0x10
    static let appCommandReportID: UInt8 = 0x11
    static let appCommandPayloadLength = 63
    static let configurationHeaderLength = 11
    static let configurationChunkDataLength = 52
    static let configurationMaximumLength = 2_048
    static let hostActionKind: UInt8 = 0x05
    static let configurationAcknowledgementKind: UInt8 = 0x03
    static let statusResponseKind: UInt8 = 0x04

    enum Error: Swift.Error, Equatable {
        case emptyConfiguration
        case configurationTooLarge
        case invalidReportLength
        case malformedConfigurationAcknowledgement
        case invalidHostAction
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

    /// BLE status is JSON, unlike the HID acknowledgement. Only the receipt
    /// fields are consumed; all other device status remains device-owned.
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

import Foundation

enum FirmwareProfileSerializer {
    enum Error: Swift.Error, Equatable {
        case invalidHostActionID
        case nonASCIIValue
        case unsupportedBinding
    }

    static func makeConfiguration(from profile: Profile) throws -> Data {
        var keys: [String: Any] = [:]
        for control in ControlID.keys {
            keys[control.rawValue] = ["press": try firmwareAction(for: profile.binding(for: control))]
        }
        let encoder = [
            "left": try firmwareAction(for: profile.binding(for: .encoderLeft)),
            "right": try firmwareAction(for: profile.binding(for: .encoderRight)),
            "press": try firmwareAction(for: profile.binding(for: .encoderPress))
        ]
        let document: [String: Any] = [
            "schema": "ai_keyboard.v1",
            "target_platform": "macos",
            "profiles": [[
                "id": profile.firmwareID,
                "keys": keys,
                "encoder": encoder
            ]]
        ]
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    private static func firmwareAction(for binding: ActionBinding) throws -> Any {
        switch binding.kind {
        case .disabled:
            return "disabled"
        case .hostAction:
            guard let uuid = UUID(uuidString: binding.value),
                  binding.value == uuid.uuidString.lowercased() else {
                throw Error.invalidHostActionID
            }
            return "host_action:" + binding.value
        case .fixedText:
            return ["text": binding.value]
        case .keyChord:
            guard binding.value.unicodeScalars.allSatisfy({ $0.isASCII }) else {
                throw Error.nonASCIIValue
            }
            return ["hotkey": binding.value]
        }
    }
}

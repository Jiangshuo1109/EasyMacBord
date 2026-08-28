import Foundation

enum ControlID: String, CaseIterable, Codable, Identifiable, Hashable {
    case key1 = "KEY1"
    case key2 = "KEY2"
    case key3 = "KEY3"
    case key4 = "KEY4"
    case key5 = "KEY5"
    case key6 = "KEY6"
    case key7 = "KEY7"
    case key8 = "KEY8"
    case encoderLeft = "ENCODER_LEFT"
    case encoderRight = "ENCODER_RIGHT"
    case encoderPress = "ENCODER_PRESS"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .key1, .key2, .key3, .key4, .key5, .key6, .key7, .key8:
            rawValue
        case .encoderLeft: "旋钮左转"
        case .encoderRight: "旋钮右转"
        case .encoderPress: "旋钮按下"
        }
    }

    static var keys: [ControlID] {
        [.key1, .key2, .key3, .key4, .key5, .key6, .key7, .key8]
    }
}

enum BindingKind: String, CaseIterable, Codable, Identifiable {
    case hostAction
    case semanticAction
    case fixedText
    case keyChord
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hostAction: "本机动作"
        case .semanticAction: "设备语义动作"
        case .fixedText: "固定文本"
        case .keyChord: "键盘组合键"
        case .disabled: "禁用"
        }
    }
}

/// Firmware-resident actions. Their raw values are part of the EasyInput V2
/// configuration contract and therefore must not be localized or transformed.
enum SemanticAction: String, CaseIterable, Codable, Identifiable, Hashable {
    case voicePTTHold = "voice_ptt_hold"
    case editPTTHold = "edit_ptt_hold"
    case selectAll = "select_all"
    case copy
    case paste
    case undo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voicePTTHold: "语音按住说话"
        case .editPTTHold: "编辑按住说话"
        case .selectAll: "全选"
        case .copy: "复制"
        case .paste: "粘贴"
        case .undo: "撤销"
        }
    }

    var symbolName: String {
        switch self {
        case .voicePTTHold: "mic.fill"
        case .editPTTHold: "pencil.tip"
        case .selectAll: "selection.pin.in.out"
        case .copy: "doc.on.doc"
        case .paste: "clipboard"
        case .undo: "arrow.uturn.backward"
        }
    }

    /// The Maker parser accepts these actions for all eight keys and all
    /// encoder controls. Restricting this list in the UI would create a
    /// configuration that the firmware already supports but the app cannot edit.
    var allowedControls: Set<ControlID> {
        Set(ControlID.allCases)
    }

    /// The Maker parser accepts these values on every control. The desktop
    /// editor narrows its default choices to controls that match the gesture.
    var recommendedControls: Set<ControlID> {
        switch self {
        case .voicePTTHold, .editPTTHold:
            return Set(ControlID.keys)
        case .selectAll, .copy, .paste, .undo:
            return Set(ControlID.keys + [.encoderPress])
        }
    }
}

struct ActionBinding: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: BindingKind
    var value: String
    var title: String

    init(id: UUID = UUID(), kind: BindingKind, value: String = "", title: String) {
        self.id = id
        self.kind = kind
        self.value = value
        self.title = title
    }

    static let disabled = ActionBinding(kind: .disabled, title: "未设置")
}

struct Profile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var firmwareID: String
    var bindings: [ControlID: ActionBinding]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        firmwareID: String = "default",
        bindings: [ControlID: ActionBinding] = [:],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.firmwareID = firmwareID
        self.bindings = bindings
        self.updatedAt = updatedAt
    }

    func binding(for control: ControlID) -> ActionBinding {
        bindings[control] ?? .disabled
    }

    static let preview = Profile(
        name: "日常",
        bindings: [
            .key1: ActionBinding(kind: .keyChord, value: "Meta+Space", title: "聚焦搜索"),
            .key2: ActionBinding(kind: .fixedText, value: "待办：", title: "输入待办前缀")
        ]
    )

    static func nextName(existingNames: [String]) -> String {
        let base = "新建配置档"
        guard existingNames.contains(base) else { return base }

        var suffix = 2
        while existingNames.contains("\(base) \(suffix)") {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }
}

extension Profile {
    /// Existing profiles can outlive a device capability change. Refuse to
    /// resend their semantic mappings until the current device confirms them.
    func firstUnsupportedSemanticAction(for deviceDetails: DeviceDetails) -> SemanticAction? {
        bindings.values.lazy.compactMap { binding in
            guard binding.kind == .semanticAction else { return nil }
            return SemanticAction(rawValue: binding.value)
        }.first(where: { !deviceDetails.supports($0) })
    }
}

enum TransportChannel: String, Codable, CaseIterable, Identifiable {
    case usb
    case bluetooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usb: "USB"
        case .bluetooth: "蓝牙配置通道"
        }
    }
}

struct ConfigurationAcknowledgementExpectation: Equatable {
    enum Assessment: Equatable {
        case accepted
        case ignoredDifferentChannel
        case rejected
    }

    let channel: TransportChannel
    let bytes: UInt16
    let crc16: UInt16

    func assess(
        _ acknowledgement: DeviceProtocol.ConfigurationAcknowledgement,
        from channel: TransportChannel
    ) -> Assessment {
        guard self.channel == channel else { return .ignoredDifferentChannel }

        guard acknowledgement.phase == 1,
              acknowledgement.ok,
              acknowledgement.saved,
              acknowledgement.bytes == bytes,
              acknowledgement.crc16 == crc16 else {
            return .rejected
        }
        return .accepted
    }

    func matches(
        _ acknowledgement: DeviceProtocol.ConfigurationAcknowledgement,
        from channel: TransportChannel
    ) -> Bool {
        assess(acknowledgement, from: channel) == .accepted
    }
}

struct DeviceConnection: Equatable {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected(TransportChannel)
        case unavailable(String)
    }

    var state: State
    var name: String
    /// The HID source that can currently emit device input. This is separate
    /// from the GATT or USB path that can receive configuration frames.
    var activeInputChannel: TransportChannel? = nil
    var configurationChannel: TransportChannel? = nil

    static let preview = DeviceConnection(state: .connected(.usb), name: "EasyInput AI")

    static func current(
        name: String,
        activeInputChannel: TransportChannel?,
        configurationChannel: TransportChannel?
    ) -> Self {
        let state: State
        if let activeInputChannel {
            state = .connected(activeInputChannel)
        } else if let configurationChannel {
            state = .connected(configurationChannel)
        } else {
            state = .disconnected
        }
        return Self(
            state: state,
            name: name,
            activeInputChannel: activeInputChannel,
            configurationChannel: configurationChannel
        )
    }
}

enum SyncState: Equatable {
    case idle
    case sending
    case confirmed(Date)
    case failed(String)

    var title: String {
        switch self {
        case .idle: "未同步"
        case .sending: "正在确认"
        case .confirmed: "已确认"
        case .failed: "同步失败"
        }
    }
}

enum DeviceInformationState: Equatable {
    case unknown
    case value(String)

    var title: String {
        switch self {
        case .unknown: "未读取"
        case .value(let value): value
        }
    }
}

struct DeviceDetails: Equatable {
    var firmwareVersion: DeviceInformationState = .unknown
    var backupTransport: DeviceInformationState = .unknown
    var capabilities: DeviceInformationState = .unknown
    var pttHotkey: DeviceInformationState = .unknown
    var editPTTHotkey: DeviceInformationState = .unknown
    var semanticActionsAvailable: Bool?

    func supports(_ action: SemanticAction) -> Bool {
        guard semanticActionsAvailable == true else {
            return false
        }
        switch action {
        case .voicePTTHold:
            return pttHotkey != .unknown
        case .editPTTHold:
            return editPTTHotkey != .unknown
        case .selectAll, .copy, .paste, .undo:
            return true
        }
    }
}

struct DeviceStatusReadState: Equatable {
    private var latestGeneration: UInt64 = 0
    private(set) var activeGeneration: UInt64?

    mutating func begin() -> UInt64 {
        latestGeneration &+= 1
        activeGeneration = latestGeneration
        return latestGeneration
    }

    mutating func finish() {
        activeGeneration = nil
    }

    func isActive(_ generation: UInt64) -> Bool {
        activeGeneration == generation
    }
}

struct SyncReceipt: Codable, Equatable {
    let phase: UInt8
    let bytes: UInt16
    let crc16: UInt16
    let saved: Bool

    init(_ acknowledgement: DeviceProtocol.ConfigurationAcknowledgement) {
        phase = acknowledgement.phase
        bytes = acknowledgement.bytes
        crc16 = acknowledgement.crc16
        saved = acknowledgement.saved
    }
}

struct SyncHistory: Codable, Equatable {
    private(set) var lastConfirmedAt: Date?
    private(set) var lastReceipt: SyncReceipt?
    private(set) var latestFailure: String?

    mutating func recordConfirmation(_ acknowledgement: DeviceProtocol.ConfigurationAcknowledgement, at date: Date = .now) {
        lastConfirmedAt = date
        lastReceipt = SyncReceipt(acknowledgement)
        latestFailure = nil
    }

    mutating func recordFailure(_ reason: String) {
        latestFailure = reason
    }
}

enum LocalSaveState: Equatable {
    case saving
    case saved
    case failed

    var title: String {
        switch self {
        case .saving: "正在保存本地更改"
        case .saved: "本地更改已保存"
        case .failed: "本地保存失败"
        }
    }
}

struct ExecutionRecord: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let actionTitle: String
    let result: ResultState
    let source: Source

    enum Source: Equatable {
        case device
        case manualTest

        var title: String {
            switch self {
            case .device: "设备触发"
            case .manualTest: "手动测试"
            }
        }
    }

    enum ResultState: Equatable {
        case success
        case warning
        case failed
    }
}

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
    case fixedText
    case keyChord
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hostAction: "本机动作"
        case .fixedText: "固定文本"
        case .keyChord: "键盘组合键"
        case .disabled: "禁用"
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
}

enum TransportChannel: String, Codable, CaseIterable, Identifiable {
    case usb
    case bluetooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usb: "USB"
        case .bluetooth: "蓝牙"
        }
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

    static let preview = DeviceConnection(state: .connected(.usb), name: "EasyInput AI")
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

struct ExecutionRecord: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let actionTitle: String
    let result: ResultState

    enum ResultState: Equatable {
        case success
        case warning
        case failed
    }
}

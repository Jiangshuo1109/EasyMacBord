import ApplicationServices
import Foundation

enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility
    case screenRecording
    case automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "辅助功能"
        case .screenRecording: "屏幕录制"
        case .automation: "自动化"
        }
    }
}

enum PermissionState: Equatable {
    case granted
    case required
    case notChecked

    var title: String {
        switch self {
        case .granted: "已授权"
        case .required: "需要授权"
        case .notChecked: "按需检查"
        }
    }
}

@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var states: [PermissionKind: PermissionState] = [:]

    init() {
        refresh()
    }

    func refresh() {
        states[.accessibility] = AXIsProcessTrusted() ? .granted : .required
        states[.screenRecording] = CGPreflightScreenCaptureAccess() ? .granted : .required
        states[.automation] = .notChecked
    }

    func state(for kind: PermissionKind) -> PermissionState {
        states[kind] ?? .notChecked
    }
}

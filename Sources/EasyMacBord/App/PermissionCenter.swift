import ApplicationServices
import AppKit
import Foundation

enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility
    case automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "辅助功能"
        case .automation: "自动化"
        }
    }
}

enum PermissionState: Equatable {
    case granted
    case required
    case notChecked
    case actionFailed

    var title: String {
        switch self {
        case .granted: "已授权"
        case .required: "需要授权"
        case .notChecked: "按需检查"
        case .actionFailed: "调用失败"
        }
    }
}

@MainActor
protocol AccessibilityAuthorizing: AnyObject {
    func isTrusted() -> Bool
    func requestTrustPrompt() -> Bool
}

@MainActor
final class SystemAccessibilityAuthorizer: AccessibilityAuthorizing {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestTrustPrompt() -> Bool {
        AXIsProcessTrustedWithOptions([
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary)
    }
}

@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var states: [PermissionKind: PermissionState] = [:]
    private let accessibilityAuthorizer: any AccessibilityAuthorizing
    private var activationObserver: NSObjectProtocol?

    init(accessibilityAuthorizer: any AccessibilityAuthorizing = SystemAccessibilityAuthorizer()) {
        self.accessibilityAuthorizer = accessibilityAuthorizer
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    isolated deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func refresh() {
        states[.accessibility] = accessibilityAuthorizer.isTrusted() ? .granted : .required
        if states[.automation] == nil {
            states[.automation] = .notChecked
        }
    }

    func requestAccessibility() {
        states[.accessibility] = accessibilityAuthorizer.requestTrustPrompt() ? .granted : .required
    }

    func recordAutomationSuccess() {
        states[.automation] = .granted
    }

    func recordAutomationFailure() {
        states[.automation] = .actionFailed
    }

    func state(for kind: PermissionKind) -> PermissionState {
        states[kind] ?? .notChecked
    }

    func canOpenSettings(for kind: PermissionKind) -> Bool {
        kind == .accessibility
    }

    func openSettings(for kind: PermissionKind) {
        let anchor: String
        switch kind {
        case .accessibility:
            anchor = "Privacy_Accessibility"
        case .automation:
            return
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

#if DEBUG
    func applyDebugStates(_ values: [PermissionKind: PermissionState]) {
        states = values
    }
#endif
}

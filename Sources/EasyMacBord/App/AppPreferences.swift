import Combine
import Foundation
import ServiceManagement
import SwiftUI

enum LoginItemStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var detail: String {
        switch self {
        case .disabled: "未在登录时启动"
        case .enabled: "将在登录时启动"
        case .requiresApproval: "等待系统在“登录项”中批准"
        case .unavailable: "当前构建无法登记登录项"
        }
    }
}

@MainActor
protocol LoginItemControlling: AnyObject {
    var status: LoginItemStatus { get }

    func setEnabled(_ enabled: Bool) throws -> LoginItemStatus
}

@MainActor
final class SystemLoginItemController: LoginItemControlling {
    var status: LoginItemStatus {
        LoginItemStatus(serviceStatus: SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) throws -> LoginItemStatus {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status != .notRegistered {
            try service.unregister()
        }
        return LoginItemStatus(serviceStatus: service.status)
    }
}

private extension LoginItemStatus {
    init(serviceStatus: SMAppService.Status) {
        switch serviceStatus {
        case .notRegistered: self = .disabled
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .unavailable
        @unknown default: self = .unavailable
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    static let menuBarVisibilityKey = "preferences.menuBarVisible"

    @Published private(set) var isMenuBarVisible: Bool
    @Published private(set) var loginItemStatus: LoginItemStatus
    @Published private(set) var loginItemMessage: String?

    private let defaults: UserDefaults
    private let loginItemController: any LoginItemControlling

    init(
        defaults: UserDefaults = .standard,
        loginItemController: any LoginItemControlling = SystemLoginItemController()
    ) {
        self.defaults = defaults
        self.loginItemController = loginItemController
        if defaults.object(forKey: Self.menuBarVisibilityKey) == nil {
            isMenuBarVisible = true
        } else {
            isMenuBarVisible = defaults.bool(forKey: Self.menuBarVisibilityKey)
        }
        loginItemStatus = loginItemController.status
    }

    var isLaunchAtLoginRequested: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    var menuBarVisibility: Binding<Bool> {
        Binding(
            get: { self.isMenuBarVisible },
            set: { self.setMenuBarVisible($0) }
        )
    }

    func setMenuBarVisible(_ isVisible: Bool) {
        guard isMenuBarVisible != isVisible else { return }
        isMenuBarVisible = isVisible
        defaults.set(isVisible, forKey: Self.menuBarVisibilityKey)
    }

    func refreshLoginItemStatus() {
        loginItemStatus = loginItemController.status
        loginItemMessage = nil
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            loginItemStatus = try loginItemController.setEnabled(enabled)
            loginItemMessage = loginItemStatus == .requiresApproval ? loginItemStatus.detail : nil
        } catch {
            loginItemStatus = loginItemController.status
            loginItemMessage = "无法更新登录项，请在系统设置中检查。"
        }
    }
}

struct AppBuildInfo: Equatable {
    let version: String
    let build: String
    let architecture: String
    let signingSummary: String

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        version = infoDictionary["CFBundleShortVersionString"] as? String ?? "开发构建"
        build = infoDictionary["CFBundleVersion"] as? String ?? "-"
        architecture = infoDictionary["EasyMacBordBuildArchitecture"] as? String ?? Self.currentBuildArchitecture
        signingSummary = infoDictionary["EasyMacBordSigningSummary"] as? String
            ?? "开发构建：签名状态由当前 Xcode 设置决定"
    }

    private static var currentBuildArchitecture: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "未知"
#endif
    }
}

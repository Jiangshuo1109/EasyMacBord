import Foundation
import XCTest
@testable import EasyMacBord

final class AppPreferencesTests: XCTestCase {
    @MainActor
    func testMenuBarIsVisibleByDefaultAndPersistsChanges() {
        let defaults = makeDefaults()
        let preferences = AppPreferences(
            defaults: defaults,
            loginItemController: FakeLoginItemController(status: .disabled)
        )

        XCTAssertTrue(preferences.isMenuBarVisible)
        preferences.setMenuBarVisible(false)

        let restored = AppPreferences(
            defaults: defaults,
            loginItemController: FakeLoginItemController(status: .disabled)
        )
        XCTAssertFalse(restored.isMenuBarVisible)
    }

    @MainActor
    func testLaunchAtLoginDelegatesToInjectedSystemController() {
        let controller = FakeLoginItemController(status: .disabled)
        controller.nextStatus = .enabled
        let preferences = AppPreferences(defaults: makeDefaults(), loginItemController: controller)

        preferences.setLaunchAtLogin(true)

        XCTAssertEqual(controller.requests, [true])
        XCTAssertEqual(preferences.loginItemStatus, .enabled)
        XCTAssertTrue(preferences.isLaunchAtLoginRequested)
        XCTAssertNil(preferences.loginItemMessage)
    }

    @MainActor
    func testLaunchAtLoginApprovalStateIsVisibleWithoutClaimingItIsEnabled() {
        let controller = FakeLoginItemController(status: .disabled)
        controller.nextStatus = .requiresApproval
        let preferences = AppPreferences(defaults: makeDefaults(), loginItemController: controller)

        preferences.setLaunchAtLogin(true)

        XCTAssertEqual(preferences.loginItemStatus, .requiresApproval)
        XCTAssertTrue(preferences.isLaunchAtLoginRequested)
        XCTAssertEqual(preferences.loginItemMessage, "等待系统在“登录项”中批准")
    }

    @MainActor
    func testLaunchAtLoginFailureKeepsActualStatusAndShowsError() {
        let controller = FakeLoginItemController(status: .disabled)
        controller.error = TestError.failed
        let preferences = AppPreferences(defaults: makeDefaults(), loginItemController: controller)

        preferences.setLaunchAtLogin(true)

        XCTAssertEqual(preferences.loginItemStatus, .disabled)
        XCTAssertEqual(preferences.loginItemMessage, "无法更新登录项，请在系统设置中检查。")
    }

    func testBuildInfoReadsVersionAndBuildFromPackageMetadata() {
        let buildInfo = AppBuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.1.0-beta.1",
            "CFBundleVersion": "42",
            "EasyMacBordBuildArchitecture": "arm64",
            "EasyMacBordSigningSummary": "内部 ad-hoc 签名（未公证，无开发团队标识）"
        ])

        XCTAssertEqual(buildInfo.version, "0.1.0-beta.1")
        XCTAssertEqual(buildInfo.build, "42")
        XCTAssertEqual(buildInfo.architecture, "arm64")
        XCTAssertEqual(buildInfo.signingSummary, "内部 ad-hoc 签名（未公证，无开发团队标识）")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "EasyMacBordTests.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class FakeLoginItemController: LoginItemControlling {
    var status: LoginItemStatus
    var nextStatus: LoginItemStatus?
    var error: Error?
    private(set) var requests: [Bool] = []

    init(status: LoginItemStatus) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) throws -> LoginItemStatus {
        requests.append(enabled)
        if let error {
            throw error
        }
        status = nextStatus ?? (enabled ? .enabled : .disabled)
        return status
    }
}

private enum TestError: Error {
    case failed
}

import Foundation
import XCTest
@testable import EasyMacBord

final class UpdatePreferencesTests: XCTestCase {
    @MainActor
    func testNoPublishedReleaseIsShownAsCompletedCheck() async {
        let preferences = AppPreferences(
            defaults: makeDefaults(),
            loginItemController: UpdateTestLoginItemController(),
            buildInfo: AppBuildInfo(infoDictionary: ["CFBundleShortVersionString": "0.1.0-beta.1"]),
            releaseChecker: StaticReleaseChecker(result: .noUsableRelease)
        )

        preferences.checkForUpdates()
        await waitForUpdateCheck(on: preferences)

        guard case .completed(.noUsableRelease, _) = preferences.updateCheckState else {
            return XCTFail("Expected a completed no-release result")
        }
    }

    @MainActor
    func testNonSemanticDevelopmentBuildDoesNotStartNetworkCheck() async {
        let checker = StaticReleaseChecker(result: .upToDate)
        let preferences = AppPreferences(
            defaults: makeDefaults(),
            loginItemController: UpdateTestLoginItemController(),
            buildInfo: AppBuildInfo(infoDictionary: ["CFBundleShortVersionString": "开发构建"]),
            releaseChecker: checker
        )

        preferences.checkForUpdates()

        guard case .failed(let message, _) = preferences.updateCheckState else {
            return XCTFail("Expected an invalid-build error")
        }
        XCTAssertEqual(message, "当前构建版本无法检查更新。")
        let numberOfChecks = await checker.numberOfChecks()
        XCTAssertEqual(numberOfChecks, 0)
    }

    @MainActor
    private func waitForUpdateCheck(on preferences: AppPreferences) async {
        for _ in 0..<20 {
            if case .checking = preferences.updateCheckState {
                await Task.yield()
            } else {
                return
            }
        }
        XCTFail("Update check did not finish")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "EasyMacBordTests.update.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class UpdateTestLoginItemController: LoginItemControlling {
    var status: LoginItemStatus = .disabled

    func setEnabled(_ enabled: Bool) throws -> LoginItemStatus {
        status = enabled ? .enabled : .disabled
        return status
    }
}

private actor StaticReleaseChecker: GitHubReleaseChecking {
    let result: GitHubReleaseCheckResult
    private var checkCount = 0

    init(result: GitHubReleaseCheckResult) {
        self.result = result
    }

    func check(currentVersion: SemanticVersion) async throws -> GitHubReleaseCheckResult {
        checkCount += 1
        return result
    }

    func numberOfChecks() -> Int {
        checkCount
    }
}

import XCTest
@testable import EasyMacBord

final class ProfileActivationRuleTests: XCTestCase {
    func testMatchingRuleUsesEnabledRuleWithExistingProfile() {
        let profile = Profile(name: "开发")
        let rule = ProfileActivationRule(
            profileID: profile.id,
            applicationBundleID: "com.openai.codex",
            applicationName: "Codex"
        )

        XCTAssertEqual(
            ProfileActivationRules.matchingRule(
                bundleIdentifier: "com.openai.codex",
                rules: [rule],
                profiles: [profile]
            ),
            rule
        )
    }

    func testDuplicateEnabledBundleIdentifierIsRejected() {
        let profile = Profile(name: "开发")
        let existing = ProfileActivationRule(
            profileID: profile.id,
            applicationBundleID: "com.openai.codex",
            applicationName: "Codex"
        )
        let duplicate = ProfileActivationRule(
            profileID: profile.id,
            applicationBundleID: "COM.OPENAI.CODEX",
            applicationName: "Codex Beta"
        )

        XCTAssertEqual(
            ProfileActivationRules.validate(duplicate, profiles: [profile], existingRules: [existing]),
            .duplicateApplication("COM.OPENAI.CODEX")
        )
    }

    func testAutoSyncWaitsForLocalSaveAndConnection() {
        let first = Profile(name: "日常")
        let second = Profile(name: "开发")
        let rule = ProfileActivationRule(
            profileID: second.id,
            applicationBundleID: "com.openai.codex",
            applicationName: "Codex"
        )

        XCTAssertEqual(
            ProfileAutoSyncPlan.make(
                bundleIdentifier: "com.openai.codex",
                rules: [rule],
                profiles: [first, second],
                selectedProfileID: first.id,
                isEnabled: true,
                isDeviceConnected: false,
                isSyncing: false,
                isLocalSaveComplete: true
            ),
            .selectOnly(second.id)
        )
        XCTAssertEqual(
            ProfileAutoSyncPlan.make(
                bundleIdentifier: "com.openai.codex",
                rules: [rule],
                profiles: [first, second],
                selectedProfileID: first.id,
                isEnabled: true,
                isDeviceConnected: true,
                isSyncing: false,
                isLocalSaveComplete: true
            ),
            .selectAndSchedule(second.id)
        )
    }

    func testPendingAutomaticSyncRetriesOnlyWhenItsApplicationMatchesAgain() {
        let first = Profile(name: "日常")
        let second = Profile(name: "开发")
        let rule = ProfileActivationRule(
            profileID: second.id,
            applicationBundleID: "com.openai.codex",
            applicationName: "Codex"
        )

        XCTAssertTrue(
            ProfileAutoSyncPlan.shouldRetryPendingSync(
                bundleIdentifier: "com.openai.codex",
                pendingProfileID: second.id,
                rules: [rule],
                profiles: [first, second],
                isEnabled: true
            )
        )
        XCTAssertFalse(
            ProfileAutoSyncPlan.shouldRetryPendingSync(
                bundleIdentifier: "com.netease.cloudmusic",
                pendingProfileID: second.id,
                rules: [rule],
                profiles: [first, second],
                isEnabled: true
            )
        )
    }
}

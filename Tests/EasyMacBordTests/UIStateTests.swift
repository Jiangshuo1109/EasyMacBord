import XCTest
@testable import EasyMacBord

final class UIStateTests: XCTestCase {
    @MainActor
    func testMenuBarLogoUsesTemplateImageWithStatusBarSize() {
        guard let logo = BrandMark.menuBarLogo else {
            return XCTFail("Missing menu bar logo")
        }

        XCTAssertTrue(logo.isTemplate)
        XCTAssertEqual(logo.size, NSSize(width: 18, height: 18))
    }

    @MainActor
    func testDebugFixtureIsReadyWithoutLoadingUserData() {
        let model = AppModel(startServices: false)

        XCTAssertTrue(model.isLocalStateReady)
    }

    @MainActor
    func testSyncFailureFixtureRetainsPreviousReceipt() {
        let model = AppModel(startServices: false)
        model.applyDebugUIState(.syncFailed)

        XCTAssertEqual(model.syncState, .failed("等待设备保存确认超时"))
        XCTAssertEqual(model.syncHistory.latestFailure, "等待设备保存确认超时")
        XCTAssertEqual(model.syncHistory.lastReceipt?.bytes, 256)
    }

    @MainActor
    func testPermissionDeniedFixtureShowsActionFailures() {
        let model = AppModel(startServices: false)
        model.applyDebugUIState(.permissionDenied)

        XCTAssertEqual(model.permissions.state(for: .automation), .actionFailed)
        XCTAssertEqual(model.permissions.state(for: .notifications), .actionFailed)
    }

    @MainActor
    func testNoResultsFixtureSuppliesAnActionLibrarySearchTerm() {
        let model = AppModel(startServices: false)
        model.applyDebugUIState(.noResults)

        XCTAssertEqual(model.debugActionLibrarySearchText, "没有匹配项")
    }

    func testDebugUIStateParsesKnownLaunchArgument() {
        XCTAssertEqual(
            DebugUIState(arguments: ["EasyMacBord", "--ui-state", "sync-failed"]),
            .syncFailed
        )
        XCTAssertEqual(
            DebugUIState(arguments: ["EasyMacBord", "--ui-state", "semantic-actions-unavailable"]),
            .semanticActionsUnavailable
        )
    }

    func testDebugUIStateIgnoresMissingOrUnknownLaunchArgument() {
        XCTAssertNil(DebugUIState(arguments: ["EasyMacBord"]))
        XCTAssertNil(DebugUIState(arguments: ["EasyMacBord", "--ui-state", "unsupported"]))
    }

    func testDebugWindowSizeParsesOnlyPositiveDimensions() {
        XCTAssertEqual(
            DebugWindowSize(arguments: ["EasyMacBord", "--window-size", "1120x720"]),
            DebugWindowSize(width: 1120, height: 720)
        )
        XCTAssertNil(DebugWindowSize(arguments: ["EasyMacBord", "--window-size", "0x720"]))
        XCTAssertNil(DebugWindowSize(arguments: ["EasyMacBord", "--window-size", "1120"]))
    }

    func testNewProfileNameAvoidsExistingNames() {
        XCTAssertEqual(Profile.nextName(existingNames: ["日常"]), "新建配置档")
        XCTAssertEqual(
            Profile.nextName(existingNames: ["新建配置档", "新建配置档 2", "新建配置档 4"]),
            "新建配置档 3"
        )
    }

    func testDeviceDetailsStartUnread() {
        let details = DeviceDetails()

        XCTAssertEqual(details.firmwareVersion.title, "未读取")
        XCTAssertEqual(details.backupTransport.title, "未读取")
        XCTAssertEqual(details.capabilities.title, "未读取")
    }

    func testStatusReadTimeoutTracksTheLatestRequestInsteadOfOldDetails() {
        var state = DeviceStatusReadState()
        let first = state.begin()
        state.finish()
        let second = state.begin()

        XCTAssertFalse(state.isActive(first))
        XCTAssertTrue(state.isActive(second))
    }

    func testSemanticActionsRequireConfirmedCapability() {
        var details = DeviceDetails(
            firmwareVersion: .value("0.1.26"),
            capabilities: .value("semantic_actions=true"),
            pttHotkey: .value("RightMeta"),
            editPTTHotkey: .value("RightOption"),
            semanticActionsAvailable: false
        )

        XCTAssertFalse(details.supports(.copy))
        details.semanticActionsAvailable = true
        XCTAssertTrue(details.supports(.copy))
        XCTAssertTrue(details.supports(.voicePTTHold))
    }

    func testProfileWithUnsupportedSemanticActionIsHeldBackFromSync() {
        let profile = Profile(
            name: "语义动作",
            bindings: [
                .key1: ActionBinding(kind: .semanticAction, value: SemanticAction.copy.rawValue, title: "复制")
            ]
        )
        let unavailableDevice = DeviceDetails(semanticActionsAvailable: false)

        XCTAssertEqual(profile.firstUnsupportedSemanticAction(for: unavailableDevice), .copy)
    }

    func testFailureKeepsLastConfirmedReceipt() {
        let acknowledgement = DeviceProtocol.ConfigurationAcknowledgement(
            phase: 1,
            ok: true,
            bytes: 128,
            crc16: 0x12ab,
            saved: true
        )
        let confirmedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var history = SyncHistory()

        history.recordConfirmation(acknowledgement, at: confirmedAt)
        history.recordFailure("等待设备保存确认超时")

        XCTAssertEqual(history.lastConfirmedAt, confirmedAt)
        XCTAssertEqual(history.lastReceipt, SyncReceipt(acknowledgement))
        XCTAssertEqual(history.latestFailure, "等待设备保存确认超时")
    }

    func testManualTestRecordsHaveAnExplicitSource() {
        let record = ExecutionRecord(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            actionTitle: "打开备忘录",
            result: .success,
            source: .manualTest
        )

        XCTAssertEqual(record.source.title, "手动测试")
    }
}

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

    func testDebugUIStateParsesKnownLaunchArgument() {
        XCTAssertEqual(
            DebugUIState(arguments: ["EasyMacBord", "--ui-state", "sync-failed"]),
            .syncFailed
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

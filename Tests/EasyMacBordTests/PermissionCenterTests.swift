import AppKit
import XCTest
@testable import EasyMacBord

final class PermissionCenterTests: XCTestCase {
    @MainActor
    func testPermissionKindsMatchCurrentCapabilities() {
        XCTAssertEqual(PermissionKind.allCases, [.accessibility, .automation, .notifications])
    }

    @MainActor
    func testAccessibilityRequestUsesExplicitPromptAndUpdatesState() {
        let authorizer = FakeAccessibilityAuthorizer(isTrusted: false, promptResult: true)
        let center = PermissionCenter(accessibilityAuthorizer: authorizer)

        XCTAssertEqual(center.state(for: .accessibility), .required)
        center.requestAccessibility()

        XCTAssertEqual(authorizer.promptCount, 1)
        XCTAssertEqual(center.state(for: .accessibility), .granted)
    }

    @MainActor
    func testActivationRefreshesAccessibilityStateWithoutResettingAutomationResult() async {
        let authorizer = FakeAccessibilityAuthorizer(isTrusted: false, promptResult: false)
        let center = PermissionCenter(accessibilityAuthorizer: authorizer)
        center.recordAutomationSuccess()
        authorizer.isTrustedValue = true

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()

        XCTAssertEqual(center.state(for: .accessibility), .granted)
        XCTAssertEqual(center.state(for: .automation), .granted)
    }

    @MainActor
    func testAutomationFailureDoesNotPretendItIsAPermissionDenial() {
        let center = PermissionCenter(
            accessibilityAuthorizer: FakeAccessibilityAuthorizer(isTrusted: true, promptResult: true)
        )

        XCTAssertFalse(center.canOpenSettings(for: .automation))
        XCTAssertEqual(center.state(for: .automation), .notChecked)
        center.recordAutomationFailure()
        XCTAssertEqual(center.state(for: .automation), .actionFailed)
    }

    @MainActor
    func testNotificationStateOnlyChangesAfterReminderExecution() {
        let center = PermissionCenter(
            accessibilityAuthorizer: FakeAccessibilityAuthorizer(isTrusted: true, promptResult: true)
        )

        XCTAssertEqual(center.state(for: .notifications), .notChecked)
        center.recordNotificationSuccess()
        XCTAssertEqual(center.state(for: .notifications), .granted)
        center.recordNotificationFailure()
        XCTAssertEqual(center.state(for: .notifications), .actionFailed)
    }
}

@MainActor
private final class FakeAccessibilityAuthorizer: AccessibilityAuthorizing {
    var isTrustedValue: Bool
    var promptResult: Bool
    private(set) var promptCount = 0

    init(isTrusted: Bool, promptResult: Bool) {
        isTrustedValue = isTrusted
        self.promptResult = promptResult
    }

    func isTrusted() -> Bool {
        isTrustedValue
    }

    func requestTrustPrompt() -> Bool {
        promptCount += 1
        return promptResult
    }
}

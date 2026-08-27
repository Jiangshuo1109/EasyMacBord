import XCTest
@testable import EasyMacBord

final class HostActionPresentationTests: XCTestCase {
    func testUsesSpecificSystemToolSymbolsAndGenericKindSymbols() {
        let volume = HostActionTarget(kind: .system, title: "音量增加", payload: "volumeUp")
        let app = HostActionTarget(kind: .application, title: "备忘录", payload: "application")

        XCTAssertEqual(HostActionPresentation.symbol(for: volume), "speaker.wave.2")
        XCTAssertEqual(HostActionPresentation.symbol(for: app), "app")
    }

    func testOnlyApplicationTargetsAttemptBookmarkIconResolution() {
        XCTAssertTrue(HostActionPresentation.usesApplicationIcon(for: HostActionTarget(kind: .application, title: "备忘录", payload: "application", bookmark: Data([1]))))
        XCTAssertFalse(HostActionPresentation.usesApplicationIcon(for: HostActionTarget(kind: .url, title: "网站", payload: "https://example.com")))
    }
}

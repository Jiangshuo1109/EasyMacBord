import XCTest
@testable import EasyMacBord

final class KeyChordTests: XCTestCase {
    func testCanonicalizesModifiersAndLetterInMacDisplayOrder() {
        XCTAssertEqual(
            KeyChord.make(modifiers: [.meta, .shift], key: .letter("p")),
            "Meta+Shift+P"
        )
        XCTAssertEqual(
            KeyChord.make(modifiers: [.control, .option, .meta], key: .arrowLeft),
            "Meta+Ctrl+Alt+ArrowLeft"
        )
    }

    func testSupportsFirmwareKeyTokenSet() {
        XCTAssertEqual(KeyChord.key(forKeyCode: 49), .space)
        XCTAssertEqual(KeyChord.key(forKeyCode: 123), .arrowLeft)
        XCTAssertEqual(KeyChord.key(forKeyCode: 122), .function(1))
        XCTAssertEqual(KeyChord.key(forKeyCode: 18), .digit("1"))
        XCTAssertEqual(KeyChord.key(forKeyCode: 35), .letter("p"))
    }

    func testRejectsUnsupportedOrModifierOnlyInput() {
        XCTAssertNil(KeyChord.make(modifiers: [], key: nil))
        XCTAssertNil(KeyChord.key(forKeyCode: 63))
        XCTAssertNil(KeyChord.make(modifiers: [.function], key: .letter("f")))
    }

    func testBuiltInTextCommandTemplatesUseCanonicalFirmwareChords() {
        XCTAssertEqual(
            InputPresetTemplate.allCases.map(\.chord),
            ["Meta+X", "Backspace", "Return", "Meta+Space", "Ctrl+Space"]
        )
    }
}

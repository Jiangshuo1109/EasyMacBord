import XCTest
@testable import EasyMacBord

final class FirmwareProfileSerializerTests: XCTestCase {
    func testSerializesAllEightKeysAndEncoder() throws {
        let hostID = "123e4567-e89b-12d3-a456-426614174000"
        var profile = Profile(name: "日常")
        profile.bindings[.key1] = ActionBinding(kind: .hostAction, value: hostID, title: "打开备忘录")
        profile.bindings[.key2] = ActionBinding(kind: .fixedText, value: "待办：", title: "待办前缀")
        profile.bindings[.encoderPress] = ActionBinding(kind: .keyChord, value: "Meta+Space", title: "聚焦搜索")

        let data = try FirmwareProfileSerializer.makeConfiguration(from: profile)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["schema"] as? String, "ai_keyboard.v1")
        let profiles = try XCTUnwrap(root["profiles"] as? [[String: Any]])
        let serialized = try XCTUnwrap(profiles.first)
        let keys = try XCTUnwrap(serialized["keys"] as? [String: [String: Any]])
        XCTAssertEqual(keys.count, 8)
        XCTAssertEqual(keys["KEY1"]?["press"] as? String, "host_action:" + hostID)
        XCTAssertEqual((keys["KEY2"]?["press"] as? [String: String])?["text"], "待办：")
        let encoder = try XCTUnwrap(serialized["encoder"] as? [String: Any])
        XCTAssertEqual((encoder["press"] as? [String: String])?["hotkey"], "Meta+Space")
    }

    func testRejectsNonCanonicalHostActionID() {
        var profile = Profile(name: "日常")
        profile.bindings[.key1] = ActionBinding(kind: .hostAction, value: "123E4567-e89b-12d3-a456-426614174000", title: "错误 UUID")
        XCTAssertThrowsError(try FirmwareProfileSerializer.makeConfiguration(from: profile))
    }
}

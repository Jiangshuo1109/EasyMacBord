import XCTest
@testable import EasyMacBord

final class InputPresetStoreTests: XCTestCase {
    func testStoreRoundTripPreservesTextAndChordPresets() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("input-presets.json")
        let presets = [
            InputPreset(id: UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!, kind: .fixedText, title: "待办前缀", value: "待办："),
            InputPreset(id: UUID(uuidString: "123e4567-e89b-12d3-a456-426614174001")!, kind: .keyChord, title: "聚焦搜索", value: "Meta+Space")
        ]

        try await InputPresetStore(fileURL: fileURL).save(presets)
        let loaded = try await InputPresetStore(fileURL: fileURL).load()

        XCTAssertEqual(loaded, presets)
        try? FileManager.default.removeItem(at: directory)
    }

    func testLegacyBareArrayMigratesAtReadTime() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("input-presets.json")
        let presets = [InputPreset(kind: .keyChord, title: "切换窗口", value: "Meta+Tab")]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder.pretty.encode(presets).write(to: fileURL)
        let loaded = try await InputPresetStore(fileURL: fileURL).load()

        XCTAssertEqual(loaded, presets)
        try? FileManager.default.removeItem(at: directory)
    }

    func testPresetCreatesAnIndependentBindingSnapshot() {
        let preset = InputPreset(kind: .fixedText, title: "会议前缀", value: "会议记录：")
        let first = preset.makeBinding()
        let second = preset.makeBinding()

        XCTAssertEqual(first.kind, .fixedText)
        XCTAssertEqual(first.title, "会议前缀")
        XCTAssertEqual(first.value, "会议记录：")
        XCTAssertNotEqual(first.id, second.id)
    }

    func testEditingPresetDoesNotChangeAnExistingBindingSnapshot() {
        let presetID = UUID()
        let original = InputPreset(id: presetID, kind: .fixedText, title: "会议前缀", value: "会议记录：")
        let binding = original.makeBinding()
        let edited = InputPreset(id: presetID, kind: .fixedText, title: "复盘前缀", value: "复盘记录：")

        XCTAssertEqual(binding.title, "会议前缀")
        XCTAssertEqual(binding.value, "会议记录：")
        XCTAssertEqual(edited.makeBinding().value, "复盘记录：")
    }
}

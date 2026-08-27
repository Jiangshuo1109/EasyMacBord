import XCTest
@testable import EasyMacBord

final class SystemToolTests: XCTestCase {
    func testBuiltInToolIdentifiersAreUnique() {
        let identifiers = SystemTool.builtIn.map(\.rawValue)

        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    func testShortcutTemplatesDescribeUnsupportedSystemIntegrations() {
        XCTAssertEqual(
            SystemShortcutTemplate.all.map(\.title),
            [
                "切换深色模式", "启动屏保", "清洁键盘", "隐藏桌面文件", "隐藏 Dock",
                "分屏布局", "调节显示器亮度", "调节键盘亮度", "Siri",
                "网易云音乐控制", "剪贴板历史（EasyInput）"
            ]
        )
    }

    func testWaterReminderIdentifierHasStrictMinuteRange() {
        XCTAssertEqual(SystemTool.tool(forActionIdentifier: "waterReminder:30"), .waterReminder)
        XCTAssertEqual(SystemTool.waterReminderMinutes(from: "waterReminder:30"), 30)
        XCTAssertNil(SystemTool.waterReminderMinutes(from: "waterReminder:0"))
        XCTAssertNil(SystemTool.waterReminderMinutes(from: "waterReminder:1441"))
    }
}

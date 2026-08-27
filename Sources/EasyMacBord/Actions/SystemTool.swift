import Foundation

enum SystemTool: String, CaseIterable, Identifiable, Sendable {
    case screenCapture = "screenshot"
    case lockScreen
    case keepAwake
    case wallpaper
    case volumeUp
    case volumeDown
    case volumeMute
    case hideFrontmostApplication
    case musicPlayPause
    case musicPrevious
    case musicNext
    case openTerminal
    case screenCleaner
    case waterReminder
    case emptyTrash
    case arrangeDesktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenCapture: "截屏与录屏"
        case .lockScreen: "锁定屏幕"
        case .keepAwake: "保持亮屏"
        case .wallpaper: "切换壁纸"
        case .volumeUp: "音量增加"
        case .volumeDown: "音量降低"
        case .volumeMute: "静音切换"
        case .hideFrontmostApplication: "隐藏当前应用"
        case .musicPlayPause: "Apple Music 播放/暂停"
        case .musicPrevious: "Apple Music 上一首"
        case .musicNext: "Apple Music 下一首"
        case .openTerminal: "打开终端"
        case .screenCleaner: "清洁屏幕遮罩"
        case .waterReminder: "喝水提醒"
        case .emptyTrash: "清空废纸篓"
        case .arrangeDesktop: "整理桌面"
        }
    }

    var symbol: String {
        switch self {
        case .screenCapture: "camera"
        case .lockScreen: "lock"
        case .keepAwake: "cup.and.saucer"
        case .wallpaper: "photo.on.rectangle"
        case .volumeUp: "speaker.wave.2"
        case .volumeDown: "speaker.wave.1"
        case .volumeMute: "speaker.slash"
        case .hideFrontmostApplication: "rectangle.compress.vertical"
        case .musicPlayPause: "playpause"
        case .musicPrevious: "backward.end"
        case .musicNext: "forward.end"
        case .openTerminal: "terminal"
        case .screenCleaner: "rectangle.on.rectangle.slash"
        case .waterReminder: "drop"
        case .emptyTrash: "trash"
        case .arrangeDesktop: "rectangle.3.group"
        }
    }

    static let builtIn: [SystemTool] = [
        .screenCapture,
        .lockScreen,
        .keepAwake,
        .wallpaper,
        .volumeUp,
        .volumeDown,
        .volumeMute,
        .hideFrontmostApplication,
        .musicPlayPause,
        .musicPrevious,
        .musicNext,
        .openTerminal,
        .screenCleaner,
        .waterReminder,
        .emptyTrash,
        .arrangeDesktop
    ]

    static func tool(forActionIdentifier identifier: String) -> SystemTool? {
        if identifier.hasPrefix("waterReminder:") { return .waterReminder }
        return SystemTool(rawValue: identifier)
    }

    static func waterReminderMinutes(from identifier: String) -> Int? {
        guard identifier.hasPrefix("waterReminder:"),
              let minutes = Int(identifier.dropFirst("waterReminder:".count)),
              (1...1_440).contains(minutes) else {
            return nil
        }
        return minutes
    }
}

struct SystemShortcutTemplate: Identifiable, Equatable, Sendable {
    let title: String
    let symbol: String

    var id: String { title }

    static let all: [SystemShortcutTemplate] = [
        .init(title: "切换深色模式", symbol: "circle.lefthalf.filled"),
        .init(title: "启动屏保", symbol: "play.rectangle"),
        .init(title: "清洁键盘", symbol: "keyboard"),
        .init(title: "隐藏桌面文件", symbol: "eye.slash"),
        .init(title: "隐藏 Dock", symbol: "dock.rectangle"),
        .init(title: "分屏布局", symbol: "rectangle.split.2x1"),
        .init(title: "调节显示器亮度", symbol: "sun.max"),
        .init(title: "调节键盘亮度", symbol: "keyboard.chevron.compact.down"),
        .init(title: "Siri", symbol: "sparkles"),
        .init(title: "网易云音乐控制", symbol: "music.note.list"),
        .init(title: "剪贴板历史（EasyInput）", symbol: "clipboard")
    ]
}

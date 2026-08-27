import AppKit
import Foundation

enum ActionExecutionResult: Equatable {
    case succeeded
    case failed(String)
}

@MainActor
final class ActionExecutor {
    private var activeShortcutProcesses: [ObjectIdentifier: Process] = [:]
    private let displayWakeLock = DisplayWakeLock()
    private let systemVolume = SystemVolumeController()
    private let waterReminderScheduler: (any WaterReminderScheduling)?

    init(waterReminderScheduler: (any WaterReminderScheduling)? = nil) {
        self.waterReminderScheduler = waterReminderScheduler
    }

    func execute(_ target: HostActionTarget) async -> ActionExecutionResult {
        switch target.kind {
        case .application:
            return await openApplication(target)
        case .url:
            return openURL(target)
        case .shortcut:
            return await runShortcut(target)
        case .script:
            return await runScript(target)
        case .system:
            return await openSystemAction(target)
        }
    }

    private func openApplication(_ target: HostActionTarget) async -> ActionExecutionResult {
        guard let bookmark = target.bookmark else { return .failed("未找到已授权的应用") }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            guard !stale else { return .failed("应用位置已变更，请重新选择") }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return .succeeded
        } catch {
            return .failed("无法打开所选应用")
        }
    }

    private func openURL(_ target: HostActionTarget) -> ActionExecutionResult {
        guard let url = URL(string: target.payload),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            return .failed("网址格式无效")
        }
        return NSWorkspace.shared.open(url) ? .succeeded : .failed("无法打开网址")
    }

    private func runShortcut(_ target: HostActionTarget) async -> ActionExecutionResult {
        guard !target.payload.isEmpty else { return .failed("未选择快捷指令") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", target.payload]
        return await waitForShortcut(process)
    }

    private func runScript(_ target: HostActionTarget) async -> ActionExecutionResult {
        guard let bookmark = target.bookmark else { return .failed("未找到已授权的脚本") }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            guard !stale else { return .failed("脚本位置已变更，请重新选择") }
            let supportedExtensions = ["scpt", "applescript", "command", "sh"]
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                return .failed("脚本类型不受支持")
            }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let process = Process()
            if ["scpt", "applescript"].contains(url.pathExtension.lowercased()) {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = [url.path]
            } else {
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = [url.path]
            }
            return await waitForShortcut(process, failureMessage: "授权脚本执行失败")
        } catch {
            return .failed("无法读取已授权的脚本")
        }
    }

    private func waitForShortcut(_ process: Process, failureMessage: String = "快捷指令执行失败") async -> ActionExecutionResult {
        let identifier = ObjectIdentifier(process)
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { [weak self] completed in
                let result: ActionExecutionResult = completed.terminationStatus == 0 ? .succeeded : .failed(failureMessage)
                Task { @MainActor in
                    self?.activeShortcutProcesses.removeValue(forKey: identifier)
                    continuation.resume(returning: result)
                }
            }
            do {
                try process.run()
                activeShortcutProcesses[identifier] = process
            } catch {
                continuation.resume(returning: .failed("系统未提供快捷指令命令"))
            }
        }
    }

    private func openSystemAction(_ target: HostActionTarget) async -> ActionExecutionResult {
        switch target.payload {
        case "screenshot":
            let screenshot = URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Screenshot.app")
            return NSWorkspace.shared.open(screenshot) ? .succeeded : .failed("无法打开截屏工具")
        case "lockScreen":
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession")
            process.arguments = ["-suspend"]
            do {
                try process.run()
                return .succeeded
            } catch {
                return .failed("无法锁定屏幕")
            }
        case "keepAwake":
            return displayWakeLock.toggle() ? .succeeded : .failed("无法更新保持亮屏状态")
        case "wallpaper":
            return changeWallpaper(target)
        case "volumeUp":
            return systemVolume.increase() ? .succeeded : .failed("当前音频输出不支持音量控制")
        case "volumeDown":
            return systemVolume.decrease() ? .succeeded : .failed("当前音频输出不支持音量控制")
        case "volumeMute":
            return systemVolume.toggleMute() ? .succeeded : .failed("当前音频输出不支持静音控制")
        case "hideFrontmostApplication":
            guard let application = NSWorkspace.shared.frontmostApplication else {
                return .failed("没有可隐藏的前台应用")
            }
            return application.hide() ? .succeeded : .failed("无法隐藏当前应用")
        case "musicPlayPause":
            return runAppleMusic(command: "playpause")
        case "musicPrevious":
            return runAppleMusic(command: "previous track")
        case "musicNext":
            return runAppleMusic(command: "next track")
        case "openTerminal":
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            return NSWorkspace.shared.open(terminal) ? .succeeded : .failed("无法打开终端")
        case "screenCleaner":
            // The view layer presents the temporary full-screen overlay. There
            // is intentionally no attempt to suppress physical keyboard input.
            return .succeeded
        case "emptyTrash":
            return runFinder(command: "empty the trash")
        case "arrangeDesktop":
            return runFinder(command: "clean up window of desktop")
        default:
            if let minutes = SystemTool.waterReminderMinutes(from: target.payload) {
                let scheduler = waterReminderScheduler ?? WaterReminderScheduler()
                return await scheduler.schedule(everyMinutes: minutes)
            }
            return .failed("此系统动作尚不可用")
        }
    }

    private func changeWallpaper(_ target: HostActionTarget) -> ActionExecutionResult {
        guard let bookmark = target.bookmark else { return .failed("未选择壁纸图片") }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            guard !stale else { return .failed("壁纸位置已变更，请重新选择") }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            for screen in NSScreen.screens {
                let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
            }
            return .succeeded
        } catch {
            return .failed("无法设置所选壁纸")
        }
    }

    private func runAppleMusic(command: String) -> ActionExecutionResult {
        var error: NSDictionary?
        let source = #"tell application "Music" to "# + command
        let script = NSAppleScript(source: source)
        guard script?.executeAndReturnError(&error) != nil else {
            return .failed("Apple Music 未能执行，请检查自动化授权")
        }
        return .succeeded
    }

    private func runFinder(command: String) -> ActionExecutionResult {
        var error: NSDictionary?
        let source = #"tell application "Finder" to "# + command
        let script = NSAppleScript(source: source)
        guard script?.executeAndReturnError(&error) != nil else {
            return .failed("Finder 未能执行，请检查自动化授权")
        }
        return .succeeded
    }
}

import AppKit
import Foundation

enum ActionExecutionResult: Equatable {
    case succeeded
    case failed(String)
}

@MainActor
final class ActionExecutor {
    private var activeShortcutProcesses: [ObjectIdentifier: Process] = [:]

    func execute(_ target: HostActionTarget) async -> ActionExecutionResult {
        switch target.kind {
        case .application:
            return await openApplication(target)
        case .url:
            return openURL(target)
        case .shortcut:
            return await runShortcut(target)
        case .system:
            return openSystemAction(target)
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

    private func waitForShortcut(_ process: Process) async -> ActionExecutionResult {
        let identifier = ObjectIdentifier(process)
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { [weak self] completed in
                let result: ActionExecutionResult = completed.terminationStatus == 0 ? .succeeded : .failed("快捷指令执行失败")
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

    private func openSystemAction(_ target: HostActionTarget) -> ActionExecutionResult {
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
        default:
            return .failed("此系统动作尚不可用")
        }
    }
}

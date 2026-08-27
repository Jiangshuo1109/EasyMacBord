import AppKit
import Foundation

enum HostActionPresentation {
    static func symbol(for target: HostActionTarget) -> String {
        if target.kind == .system, let tool = SystemTool.tool(forActionIdentifier: target.payload) {
            return tool.symbol
        }
        return switch target.kind {
        case .application: "app"
        case .url: "link"
        case .shortcut: "command"
        case .script: "doc.badge.gearshape"
        case .system: "gearshape"
        }
    }

    static func usesApplicationIcon(for target: HostActionTarget) -> Bool {
        target.kind == .application && target.bookmark != nil
    }

    @MainActor
    static func applicationIcon(for target: HostActionTarget) -> NSImage? {
        guard usesApplicationIcon(for: target), let bookmark = target.bookmark else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale else {
            return nil
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func kindTitle(_ kind: HostActionTarget.Kind) -> String {
        switch kind {
        case .application: "应用"
        case .url: "网址"
        case .shortcut: "快捷指令"
        case .script: "授权脚本"
        case .system: "系统"
        }
    }
}

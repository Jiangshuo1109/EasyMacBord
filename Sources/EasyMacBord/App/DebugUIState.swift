#if DEBUG
import Foundation

/// Debug-only launch fixtures for repeatable visual acceptance screenshots.
enum DebugUIState: String, CaseIterable, Equatable {
    case disconnected
    case connecting
    case syncSending = "sync-sending"
    case syncConfirmed = "sync-confirmed"
    case syncFailed = "sync-failed"
    case emptyActions = "empty-actions"
    case permissionDenied = "permission-denied"
    case longNames = "long-names"

    init?(arguments: [String]) {
        guard let flagIndex = arguments.firstIndex(of: "--ui-state"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        self.init(rawValue: arguments[flagIndex + 1])
    }
}

struct DebugWindowSize: Equatable {
    let width: CGFloat
    let height: CGFloat

    init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }

    init?(arguments: [String]) {
        guard let flagIndex = arguments.firstIndex(of: "--window-size"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        let parts = arguments[flagIndex + 1].split(separator: "x", maxSplits: 1)
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width > 0,
              height > 0 else {
            return nil
        }
        self.width = width
        self.height = height
    }
}
#endif

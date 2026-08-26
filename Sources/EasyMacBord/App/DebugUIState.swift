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
#endif

import Foundation

struct HostActionTarget: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case application
        case url
        case shortcut
        case system
    }

    var id: UUID
    var kind: Kind
    var title: String
    var payload: String
    var bookmark: Data?

    init(id: UUID = UUID(), kind: Kind, title: String, payload: String, bookmark: Data? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.payload = payload
        self.bookmark = bookmark
    }
}

extension HostActionTarget {
    var isAppleMusicAction: Bool {
        kind == .system && ["musicPlayPause", "musicPrevious", "musicNext"].contains(payload)
    }
}

actor HostActionRegistry {
    private var targets: [UUID: HostActionTarget]

    init(targets: [HostActionTarget] = []) {
        self.targets = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
    }

    func register(_ target: HostActionTarget) {
        targets[target.id] = target
    }

    func target(for id: UUID) -> HostActionTarget? {
        targets[id]
    }

    func allTargets() -> [HostActionTarget] {
        targets.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func replace(with targets: [HostActionTarget]) {
        self.targets = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
    }

    func remove(_ id: UUID) {
        targets.removeValue(forKey: id)
    }

    func makeApplicationTarget(url: URL) throws -> HostActionTarget {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let title = url.deletingPathExtension().lastPathComponent
        let target = HostActionTarget(kind: .application, title: title, payload: "application", bookmark: bookmark)
        targets[target.id] = target
        return target
    }

    func makeSystemTarget(title: String, identifier: String, fileURL: URL? = nil) throws -> HostActionTarget {
        let bookmark = try fileURL.map {
            try $0.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }

        if let existing = targets.values.first(where: { $0.kind == .system && $0.payload == identifier }) {
            var updated = existing
            updated.title = title
            updated.bookmark = bookmark
            targets[updated.id] = updated
            return updated
        }

        let target = HostActionTarget(kind: .system, title: title, payload: identifier, bookmark: bookmark)
        targets[target.id] = target
        return target
    }
}

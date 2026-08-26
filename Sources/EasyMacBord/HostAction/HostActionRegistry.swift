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
}

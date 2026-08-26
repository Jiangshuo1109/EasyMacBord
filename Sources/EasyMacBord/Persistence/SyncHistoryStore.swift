import Foundation

actor SyncHistoryStore {
    private let fileURL: URL
    private var latestWriteRevision: UInt64 = 0

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = support
            .appendingPathComponent("EasyMacBord", isDirectory: true)
            .appendingPathComponent("sync-history.json")
    }

    func load() throws -> SyncHistory {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return SyncHistory() }
        return try JSONDecoder.iso8601.decode(SyncHistory.self, from: Data(contentsOf: fileURL))
    }

    func save(_ history: SyncHistory) throws {
        latestWriteRevision &+= 1
        try save(history, revision: latestWriteRevision)
    }

    func save(_ history: SyncHistory, revision: UInt64) throws {
        guard revision >= latestWriteRevision else { return }
        latestWriteRevision = revision
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder.pretty.encode(history).write(to: fileURL, options: .atomic)
    }
}

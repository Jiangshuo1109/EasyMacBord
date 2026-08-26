import Foundation

actor HostActionStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = support
            .appendingPathComponent("EasyMacBord", isDirectory: true)
            .appendingPathComponent("host-actions.json")
    }

    func load() throws -> [HostActionTarget] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([HostActionTarget].self, from: Data(contentsOf: fileURL))
    }

    func save(_ targets: [HostActionTarget]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(targets)
        try data.write(to: fileURL, options: .atomic)
    }
}

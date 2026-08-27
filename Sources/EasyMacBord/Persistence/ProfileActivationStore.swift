import Foundation

actor ProfileActivationStore {
    private struct Document: Codable {
        let schemaVersion: Int
        let rules: [ProfileActivationRule]
    }

    enum StoreError: Swift.Error, Equatable {
        case unsupportedSchema(Int)
    }

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
            .appendingPathComponent("profile-activation-rules.json")
    }

    func load() throws -> [ProfileActivationRule] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder.iso8601
        if let document = try? decoder.decode(Document.self, from: data) {
            guard document.schemaVersion == 1 else {
                throw StoreError.unsupportedSchema(document.schemaVersion)
            }
            return document.rules
        }
        // The first preview build stored a plain array. Retain it as a
        // non-destructive migration path before the next local save.
        return try decoder.decode([ProfileActivationRule].self, from: data)
    }

    func save(_ rules: [ProfileActivationRule], revision: UInt64) throws {
        guard revision >= latestWriteRevision else { return }
        latestWriteRevision = revision
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let document = Document(schemaVersion: 1, rules: rules)
        try JSONEncoder.pretty.encode(document).write(to: fileURL, options: .atomic)
    }
}

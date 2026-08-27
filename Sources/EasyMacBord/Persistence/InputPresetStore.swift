import Foundation

actor InputPresetStore {
    private struct Document: Codable {
        let schemaVersion: Int
        let presets: [InputPreset]
    }

    enum StoreError: Swift.Error {
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
            .appendingPathComponent("input-presets.json")
    }

    func load() throws -> [InputPreset] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder.iso8601
        if let document = try? decoder.decode(Document.self, from: data) {
            guard document.schemaVersion == 1 else {
                throw StoreError.unsupportedSchema(document.schemaVersion)
            }
            return document.presets
        }
        return try decoder.decode([InputPreset].self, from: data)
    }

    func save(_ presets: [InputPreset]) throws {
        latestWriteRevision &+= 1
        try save(presets, revision: latestWriteRevision)
    }

    func save(_ presets: [InputPreset], revision: UInt64) throws {
        guard revision >= latestWriteRevision else { return }
        latestWriteRevision = revision
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(Document(schemaVersion: 1, presets: presets))
        try data.write(to: fileURL, options: .atomic)
    }
}

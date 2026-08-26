import Foundation

actor ProfileStore {
    private struct Document: Codable {
        let schemaVersion: Int
        let profiles: [Profile]
    }

    enum StoreError: Swift.Error {
        case unsupportedSchema(Int)
    }

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = support
            .appendingPathComponent("EasyMacBord", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    func load() throws -> [Profile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [.preview] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder.iso8601
        if let document = try? decoder.decode(Document.self, from: data) {
            guard document.schemaVersion == 1 else {
                throw StoreError.unsupportedSchema(document.schemaVersion)
            }
            return document.profiles
        }
        // v0 used a bare array. Keeping this read path makes local upgrades non-destructive.
        return try decoder.decode([Profile].self, from: data)
    }

    func save(_ profiles: [Profile]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(Document(schemaVersion: 1, profiles: profiles))
        try data.write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

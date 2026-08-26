import XCTest
@testable import EasyMacBord

final class ProfileStoreTests: XCTestCase {
    func testStoreRoundTrip() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("profiles.json"))
        let profiles = [Profile.preview]

        try await store.save(profiles)
        let loadedProfiles = try await store.load()
        XCTAssertEqual(loadedProfiles, profiles)
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingStoreStartsWithDailyProfile() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("profiles.json")
        let store = ProfileStore(fileURL: url)
        let profiles = try await store.load()
        XCTAssertEqual(profiles.count, 1)
    }

    func testLegacyArrayMigratesAtReadTime() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("profiles.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder.pretty.encode([Profile.preview]).write(to: url)

        let profiles = try await ProfileStore(fileURL: url).load()
        XCTAssertEqual(profiles, [.preview])
        try? FileManager.default.removeItem(at: directory)
    }
}

import XCTest
@testable import EasyMacBord

final class ProfileStoreTests: XCTestCase {
    private let fixtureProfile = Profile(
        id: UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!,
        name: "日常",
        bindings: Profile.preview.bindings,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    func testStoreRoundTrip() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("profiles.json"))
        let profiles = [fixtureProfile]

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
        try JSONEncoder.pretty.encode([fixtureProfile]).write(to: url)

        let profiles = try await ProfileStore(fileURL: url).load()
        XCTAssertEqual(profiles, [fixtureProfile])
        try? FileManager.default.removeItem(at: directory)
    }
}

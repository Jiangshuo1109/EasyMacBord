import XCTest
@testable import EasyMacBord

final class ProfileActivationStoreTests: XCTestCase {
    func testStoreRoundTripsVersionedRules() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileActivationStore(fileURL: directory.appendingPathComponent("rules.json"))
        let profile = Profile(name: "日常")
        let rule = ProfileActivationRule(
            profileID: profile.id,
            applicationBundleID: "com.apple.TextEdit",
            applicationName: "TextEdit"
        )

        try await store.save([rule], revision: 1)
        let loadedRules = try await store.load()
        XCTAssertEqual(loadedRules, [rule])
    }
}

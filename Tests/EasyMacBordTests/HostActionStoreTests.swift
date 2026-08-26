import XCTest
@testable import EasyMacBord

final class HostActionStoreTests: XCTestCase {
    func testStorePreservesTargetAndBookmark() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = HostActionStore(fileURL: directory.appendingPathComponent("host-actions.json"))
        let target = HostActionTarget(
            id: UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!,
            kind: .application,
            title: "Notes",
            payload: "application",
            bookmark: Data([1, 2, 3])
        )

        try await store.save([target])
        let loaded = try await store.load()
        XCTAssertEqual(loaded, [target])
        try? FileManager.default.removeItem(at: directory)
    }
}

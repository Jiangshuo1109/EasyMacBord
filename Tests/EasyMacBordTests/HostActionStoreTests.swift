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

    func testNewerSaveRevisionWinsWhenRequestsArriveOutOfOrder() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = HostActionStore(fileURL: directory.appendingPathComponent("host-actions.json"))
        let older = [HostActionTarget(kind: .url, title: "旧动作", payload: "https://example.com/old")]
        let newer = [HostActionTarget(kind: .url, title: "新动作", payload: "https://example.com/new")]

        try await store.save(newer, revision: 2)
        try await store.save(older, revision: 1)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, newer)
        try? FileManager.default.removeItem(at: directory)
    }
}

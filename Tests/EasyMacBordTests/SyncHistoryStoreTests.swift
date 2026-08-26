import XCTest
@testable import EasyMacBord

final class SyncHistoryStoreTests: XCTestCase {
    func testStoreRoundTripPreservesConfirmedReceiptAndFailure() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = SyncHistoryStore(fileURL: directory.appendingPathComponent("sync-history.json"))
        let acknowledgement = DeviceProtocol.ConfigurationAcknowledgement(
            phase: 1,
            ok: true,
            bytes: 64,
            crc16: 0x1234,
            saved: true
        )
        var history = SyncHistory()
        history.recordConfirmation(acknowledgement, at: Date(timeIntervalSince1970: 1_700_000_000))
        history.recordFailure("配置帧写入失败")

        try await store.save(history)
        let loaded = try await store.load()

        XCTAssertEqual(loaded, history)
        try? FileManager.default.removeItem(at: directory)
    }

    func testNewerSaveRevisionWinsWhenRequestsArriveOutOfOrder() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = SyncHistoryStore(fileURL: directory.appendingPathComponent("sync-history.json"))
        let acknowledgement = DeviceProtocol.ConfigurationAcknowledgement(
            phase: 1,
            ok: true,
            bytes: 64,
            crc16: 0x1234,
            saved: true
        )
        var older = SyncHistory()
        older.recordFailure("旧失败")
        var newer = SyncHistory()
        newer.recordConfirmation(acknowledgement, at: Date(timeIntervalSince1970: 1_700_000_000))

        try await store.save(newer, revision: 2)
        try await store.save(older, revision: 1)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, newer)
        try? FileManager.default.removeItem(at: directory)
    }
}

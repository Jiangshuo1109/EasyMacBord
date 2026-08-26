import XCTest
@testable import EasyMacBord

@MainActor
final class TransportRouterTests: XCTestCase {
    private let frame = DeviceProtocol.ConfigurationFrame(chunkIndex: 0, totalChunks: 1, payload: Data([0x53]))

    func testUSBIsChosenWhenBothChannelsAreAvailable() async throws {
        let usb = InMemoryTransport(channel: .usb, isAvailable: true)
        let bluetooth = InMemoryTransport(channel: .bluetooth, isAvailable: true)
        let router = TransportRouter(usb: usb, bluetooth: bluetooth)

        let channel = try await router.send([frame])
        XCTAssertEqual(channel, .usb)
        XCTAssertEqual(usb.frames, [frame])
        XCTAssertTrue(bluetooth.frames.isEmpty)
    }

    func testFailedUSBDoesNotFallBackToBluetooth() async {
        let usb = InMemoryTransport(channel: .usb, isAvailable: true)
        usb.failWrites = true
        let bluetooth = InMemoryTransport(channel: .bluetooth, isAvailable: true)
        let router = TransportRouter(usb: usb, bluetooth: bluetooth)

        await XCTAssertThrowsErrorAsync(try await router.send([frame]))
        XCTAssertTrue(bluetooth.frames.isEmpty)
    }

    func testBluetoothIsUsedOnlyWhenUSBIsAbsent() async throws {
        let usb = InMemoryTransport(channel: .usb, isAvailable: false)
        let bluetooth = InMemoryTransport(channel: .bluetooth, isAvailable: true)
        let router = TransportRouter(usb: usb, bluetooth: bluetooth)

        let channel = try await router.send([frame])
        XCTAssertEqual(channel, .bluetooth)
        XCTAssertEqual(bluetooth.frames, [frame])
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        // Expected.
    }
}

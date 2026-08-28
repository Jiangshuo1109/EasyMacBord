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

        do {
            _ = try await router.send([frame])
            XCTFail("Expected USB write failure")
        } catch {
            // Expected: USB failures do not fall back to Bluetooth.
        }
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

    func testEventRouterPrefersUSBButAcceptsBluetoothHIDWithoutConfigurationGATT() {
        XCTAssertEqual(
            EventChannelRouter.activeEventChannel(usbAvailable: true, bluetoothHIDAvailable: true),
            .usb
        )
        XCTAssertEqual(
            EventChannelRouter.activeEventChannel(usbAvailable: false, bluetoothHIDAvailable: true),
            .bluetooth
        )
        XCTAssertNil(EventChannelRouter.activeEventChannel(usbAvailable: false, bluetoothHIDAvailable: false))
    }

    func testBLEWriteGateAllowsRetryAfterTimeoutRelease() {
        var gate = BLEWriteGate()

        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin())

        // The transport invokes the same release method when its watchdog
        // expires without receiving a CoreBluetooth write callback.
        gate.finish()

        XCTAssertFalse(gate.isWriting)
        XCTAssertTrue(gate.begin())
    }

    func testConfigurationAcknowledgementMustMatchTheSendingChannel() {
        let expected = ConfigurationAcknowledgementExpectation(
            channel: .usb,
            bytes: 128,
            crc16: 0x12ab
        )
        let acknowledgement = DeviceProtocol.ConfigurationAcknowledgement(
            phase: 1,
            ok: true,
            bytes: 128,
            crc16: 0x12ab,
            saved: true
        )

        XCTAssertTrue(expected.matches(acknowledgement, from: .usb))
        XCTAssertFalse(expected.matches(acknowledgement, from: .bluetooth))
        XCTAssertEqual(
            expected.assess(acknowledgement, from: .bluetooth),
            .ignoredDifferentChannel
        )
    }

    func testConfigurationAcknowledgementRejectsMismatchedContentOnTheSendingChannel() {
        let expected = ConfigurationAcknowledgementExpectation(
            channel: .usb,
            bytes: 128,
            crc16: 0x12ab
        )
        let acknowledgement = DeviceProtocol.ConfigurationAcknowledgement(
            phase: 1,
            ok: true,
            bytes: 127,
            crc16: 0x12ab,
            saved: true
        )

        XCTAssertEqual(expected.assess(acknowledgement, from: .usb), .rejected)
    }

    func testBluetoothHIDRemainsVisibleAfterUSBConfigurationDisconnects() {
        let connection = DeviceConnection.current(
            name: "EasyInput AI",
            activeInputChannel: .bluetooth,
            configurationChannel: nil
        )

        XCTAssertEqual(connection.state, .connected(.bluetooth))
        XCTAssertEqual(connection.activeInputChannel, .bluetooth)
        XCTAssertNil(connection.configurationChannel)
    }
}

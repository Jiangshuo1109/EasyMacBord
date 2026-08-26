import XCTest
@testable import EasyMacBord

final class HIDTransportNameTests: XCTestCase {
    func testMapsSystemBluetoothLowEnergyNameToBluetoothChannel() {
        XCTAssertEqual(TransportChannel.fromHIDTransportName("Bluetooth Low Energy"), .bluetooth)
    }

    func testKeepsUSBAndClassicBluetoothMappings() {
        XCTAssertEqual(TransportChannel.fromHIDTransportName("USB"), .usb)
        XCTAssertEqual(TransportChannel.fromHIDTransportName("Bluetooth"), .bluetooth)
    }

    func testRejectsUnsupportedHIDTransportNames() {
        XCTAssertNil(TransportChannel.fromHIDTransportName("Wi-Fi"))
    }
}

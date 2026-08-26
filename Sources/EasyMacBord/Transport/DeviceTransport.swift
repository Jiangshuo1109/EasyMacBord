import Foundation

extension TransportChannel {
    /// Converts the transport values exposed by macOS IOKit into the two
    /// channels defined by the EasyInput V2 contract.
    static func fromHIDTransportName(_ name: String?) -> Self? {
        switch name {
        case "USB": .usb
        case "Bluetooth", "Bluetooth Low Energy": .bluetooth
        default: nil
        }
    }
}

@MainActor
protocol ConfigurationTransport: AnyObject {
    var channel: TransportChannel { get }
    var isAvailable: Bool { get }
    func send(_ frames: [DeviceProtocol.ConfigurationFrame]) async throws
}

enum TransportError: Swift.Error, Equatable {
    case unavailable(TransportChannel)
    case writeFailed(TransportChannel)
}

enum EventChannelRouter {
    static func activeEventChannel(
        usbAvailable: Bool,
        bluetoothHIDAvailable: Bool
    ) -> TransportChannel? {
        if usbAvailable { return .usb }
        return bluetoothHIDAvailable ? .bluetooth : nil
    }
}

@MainActor
final class TransportRouter {
    private let usb: ConfigurationTransport
    private let bluetooth: ConfigurationTransport

    init(usb: ConfigurationTransport, bluetooth: ConfigurationTransport) {
        self.usb = usb
        self.bluetooth = bluetooth
    }

    /// Mirrors the device contract: USB is selected when available; a failed USB
    /// write is reported and never retried through Bluetooth.
    func send(_ frames: [DeviceProtocol.ConfigurationFrame]) async throws -> TransportChannel {
        if usb.isAvailable {
            try await usb.send(frames)
            return .usb
        }
        guard bluetooth.isAvailable else { throw TransportError.unavailable(.bluetooth) }
        try await bluetooth.send(frames)
        return .bluetooth
    }

    var activeEventChannel: TransportChannel? {
        usb.isAvailable ? .usb : (bluetooth.isAvailable ? .bluetooth : nil)
    }
}

@MainActor
final class InMemoryTransport: ConfigurationTransport {
    let channel: TransportChannel
    var isAvailable: Bool
    var failWrites = false
    private(set) var frames: [DeviceProtocol.ConfigurationFrame] = []

    init(channel: TransportChannel, isAvailable: Bool = false) {
        self.channel = channel
        self.isAvailable = isAvailable
    }

    func send(_ frames: [DeviceProtocol.ConfigurationFrame]) async throws {
        guard isAvailable else { throw TransportError.unavailable(channel) }
        guard !failWrites else { throw TransportError.writeFailed(channel) }
        self.frames.append(contentsOf: frames)
    }
}

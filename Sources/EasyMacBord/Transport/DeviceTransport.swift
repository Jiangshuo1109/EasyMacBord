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
    case statusRequestFailed(TransportChannel, StatusRequestFailure)
}

/// Tracks whether one BLE write sequence owns the serialized CoreBluetooth
/// callback path. A timeout uses the same release path as a write callback,
/// so a later sync can retry instead of remaining permanently blocked.
struct BLEWriteGate: Equatable {
    private(set) var isWriting = false

    mutating func begin() -> Bool {
        guard !isWriting else { return false }
        isWriting = true
        return true
    }

    mutating func finish() {
        isWriting = false
    }
}

/// A privacy-preserving observation of an input report. It deliberately keeps
/// no report ID, key usage, payload, or timing information.
struct HIDInputObservation: Equatable {
    private(set) var totalReportCount = 0
    private(set) var usbReportCount = 0
    private(set) var bluetoothReportCount = 0
    private(set) var latestChannel: TransportChannel?

    mutating func record(from channel: TransportChannel) {
        totalReportCount += 1
        latestChannel = channel
        switch channel {
        case .usb:
            usbReportCount += 1
        case .bluetooth:
            bluetoothReportCount += 1
        }
    }
}

enum StatusRequestFailure: Equatable {
    case invalidReport
    case deviceNotOpen
    case unsupported
    case disconnected
    case inputMonitoringNotGranted
    case featureReportNotPermitted
    case other

    var displayMessage: String {
        switch self {
        case .invalidReport: "参数不匹配"
        case .deviceNotOpen: "HID 设备未打开"
        case .unsupported: "HID 接口不支持该请求"
        case .disconnected: "设备已断开"
        case .inputMonitoringNotGranted: "输入监控授权未对当前应用生效"
        case .featureReportNotPermitted: "输入监控已授权，但系统拒绝 HID Feature Report"
        case .other: "系统拒绝该请求"
        }
    }
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
        guard let channel = configurationChannel else {
            throw TransportError.unavailable(.bluetooth)
        }
        return try await send(frames, through: channel)
    }

    /// A sync commits to the channel that was available when it started.
    /// This prevents a connection change from silently switching a write or
    /// accepting a confirmation from a different transport.
    func send(
        _ frames: [DeviceProtocol.ConfigurationFrame],
        through channel: TransportChannel
    ) async throws -> TransportChannel {
        let transport = channel == .usb ? usb : bluetooth
        guard transport.isAvailable else { throw TransportError.unavailable(channel) }
        try await transport.send(frames)
        return channel
    }

    var configurationChannel: TransportChannel? {
        if usb.isAvailable { return .usb }
        return bluetooth.isAvailable ? .bluetooth : nil
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

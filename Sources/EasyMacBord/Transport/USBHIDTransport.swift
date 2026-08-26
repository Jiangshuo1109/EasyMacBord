import Foundation
@preconcurrency import IOKit.hid

/// Matches only the published EasyInput USB/BLE HID identity. The adapter has
/// no knowledge of user mappings or application paths.
@MainActor
final class USBHIDTransport: ConfigurationTransport {
    let channel: TransportChannel = .usb
    private(set) var isAvailable = false
    var appCommandHandler: ((TransportChannel, Data) -> Void)?
    var connectionHandler: ((Bool) -> Void)?

    private let manager: IOHIDManager
    private var activeDevice: IOHIDDevice?
    private var inputBuffers: [UnsafeMutablePointer<UInt8>] = []
    private var inputContexts: [InputContext] = []

    private final class InputContext {
        weak var transport: USBHIDTransport?
        let channel: TransportChannel

        init(transport: USBHIDTransport, channel: TransportChannel) {
            self.transport = transport
            self.channel = channel
        }
    }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x303A,
            kIOHIDProductIDKey as String: 0x1006
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let transport = Unmanaged<USBHIDTransport>.fromOpaque(context).takeUnretainedValue()
                    transport.attach(device)
                }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let transport = Unmanaged<USBHIDTransport>.fromOpaque(context).takeUnretainedValue()
                    transport.detach(device)
                }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    isolated deinit {
        inputBuffers.forEach { $0.deallocate() }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() {
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func stop() {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func send(_ frames: [DeviceProtocol.ConfigurationFrame]) async throws {
        guard let activeDevice, isAvailable else { throw TransportError.unavailable(.usb) }
        for frame in frames {
            let result = frame.payload.withUnsafeBytes { bytes in
                guard let address = bytes.baseAddress else { return kIOReturnBadArgument }
                return IOHIDDeviceSetReport(
                    activeDevice,
                    kIOHIDReportTypeFeature,
                    CFIndex(DeviceProtocol.configurationReportID),
                    address.assumingMemoryBound(to: UInt8.self),
                    frame.payload.count
                )
            }
            guard result == kIOReturnSuccess else { throw TransportError.writeFailed(.usb) }
        }
    }

    private func attach(_ device: IOHIDDevice) {
        guard let eventChannel = eventChannel(for: device) else { return }
        if eventChannel == .usb {
            activeDevice = device
            isAvailable = true
            connectionHandler?(true)
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: DeviceProtocol.appCommandPayloadLength)
        inputBuffers.append(buffer)
        let inputContext = InputContext(transport: self, channel: eventChannel)
        inputContexts.append(inputContext)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            DeviceProtocol.appCommandPayloadLength,
            { context, _, _, _, reportID, report, reportLength in
                guard let context, reportID == DeviceProtocol.appCommandReportID,
                      reportLength == DeviceProtocol.appCommandPayloadLength else { return }
                MainActor.assumeIsolated {
                    let inputContext = Unmanaged<InputContext>.fromOpaque(context).takeUnretainedValue()
                    inputContext.transport?.appCommandHandler?(inputContext.channel, Data(bytes: report, count: reportLength))
                }
            },
            Unmanaged.passUnretained(inputContext).toOpaque()
        )
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func detach(_ device: IOHIDDevice) {
        if let activeDevice, CFEqual(activeDevice, device) {
            self.activeDevice = nil
            isAvailable = false
            connectionHandler?(false)
        }
    }

    private func eventChannel(for device: IOHIDDevice) -> TransportChannel? {
        switch IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String {
        case "USB": .usb
        case "Bluetooth": .bluetooth
        default: nil
        }
    }
}

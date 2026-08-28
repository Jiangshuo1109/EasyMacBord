import Foundation
@preconcurrency import IOKit.hid

/// Matches only the published EasyInput transport identity. The adapter has
/// no knowledge of user mappings or application paths.
@MainActor
final class USBHIDTransport: ConfigurationTransport {
    let channel: TransportChannel = .usb
    private(set) var isAvailable = false
    private(set) var isBluetoothHIDAvailable = false
    var appCommandHandler: ((TransportChannel, Data) -> Void)?
    var standardHIDInputHandler: ((TransportChannel) -> Void)?
    var connectionHandler: ((Bool) -> Void)?
    var eventConnectionHandler: ((TransportChannel, Bool) -> Void)?

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

    /// Sends the 16-byte S3R v1 body using the firmware's status Feature
    /// Report. Status replies continue to arrive through the existing 0x11
    /// input-report callback.
    func requestStatus(requestID: UInt32, fresh: Bool) throws {
        guard let activeDevice, isAvailable else { throw TransportError.unavailable(.usb) }
        let listenEventAccessGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        let openResult = IOHIDDeviceOpen(activeDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            throw TransportError.statusRequestFailed(
                .usb,
                statusRequestFailure(for: openResult, listenEventAccessGranted: listenEventAccessGranted)
            )
        }
        let report = try DeviceProtocol.makeStatusFeatureReport(requestID: requestID, fresh: fresh)
        let result = report.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(
                activeDevice,
                kIOHIDReportTypeFeature,
                CFIndex(DeviceProtocol.statusRequestReportID),
                address.assumingMemoryBound(to: UInt8.self),
                report.count
            )
        }
        guard result == kIOReturnSuccess else {
            throw TransportError.statusRequestFailed(.usb, statusRequestFailure(for: result))
        }
    }

    var activeEventChannel: TransportChannel? {
        EventChannelRouter.activeEventChannel(
            usbAvailable: isAvailable,
            bluetoothHIDAvailable: isBluetoothHIDAvailable
        )
    }

    private func attach(_ device: IOHIDDevice) {
        guard let eventChannel = eventChannel(for: device) else { return }
        if eventChannel == .usb {
            activeDevice = device
            isAvailable = true
            connectionHandler?(true)
        } else {
            isBluetoothHIDAvailable = true
        }
        eventConnectionHandler?(eventChannel, true)

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: DeviceProtocol.appCommandPayloadLength + 1)
        inputBuffers.append(buffer)
        let inputContext = InputContext(transport: self, channel: eventChannel)
        inputContexts.append(inputContext)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            DeviceProtocol.appCommandPayloadLength + 1,
            { context, _, _, _, reportID, report, reportLength in
                guard let context, reportID <= UInt32(UInt8.max) else { return }
                let receivedReportID = UInt8(reportID)
                MainActor.assumeIsolated {
                    let inputContext = Unmanaged<InputContext>.fromOpaque(context).takeUnretainedValue()
                    guard let transport = inputContext.transport else { return }
                    guard receivedReportID == DeviceProtocol.appCommandReportID else {
                        transport.standardHIDInputHandler?(inputContext.channel)
                        return
                    }
                    guard let payload = DeviceProtocol.normalizeIOKitAppCommandReport(
                        reportID: receivedReportID,
                        report: Data(bytes: report, count: reportLength)
                    ) else { return }
                    transport.appCommandHandler?(inputContext.channel, payload)
                }
            },
            Unmanaged.passUnretained(inputContext).toOpaque()
        )
    }

    private func detach(_ device: IOHIDDevice) {
        guard let eventChannel = eventChannel(for: device) else { return }
        if eventChannel == .usb, let activeDevice, CFEqual(activeDevice, device) {
            self.activeDevice = nil
            isAvailable = false
            connectionHandler?(false)
            eventConnectionHandler?(.usb, false)
        } else if eventChannel == .bluetooth {
            isBluetoothHIDAvailable = false
            eventConnectionHandler?(.bluetooth, false)
        }
    }

    private func eventChannel(for device: IOHIDDevice) -> TransportChannel? {
        TransportChannel.fromHIDTransportName(
            IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
        )
    }

    private func statusRequestFailure(
        for result: IOReturn,
        listenEventAccessGranted: Bool = false
    ) -> StatusRequestFailure {
        switch result {
        case kIOReturnBadArgument: .invalidReport
        case kIOReturnNotOpen: .deviceNotOpen
        case kIOReturnUnsupported: .unsupported
        case kIOReturnNoDevice: .disconnected
        case kIOReturnNotPermitted:
            listenEventAccessGranted ? .featureReportNotPermitted : .inputMonitoringNotGranted
        default: .other
        }
    }
}

import Foundation

@MainActor
final class DeviceSession {
    enum AccessMode: Equatable {
        case standard
        case usbStatusOnly
        case inputObserveOnly

        init(arguments: [String]) {
            if arguments.contains("--input-observe-only") {
                self = .inputObserveOnly
            } else if arguments.contains("--status-only") {
                self = .usbStatusOnly
            } else {
                self = .standard
            }
        }

        var allowsConfigurationSync: Bool {
            self == .standard
        }

        var startsBluetoothConfiguration: Bool {
            self == .standard
        }

        var allowsStatusRead: Bool {
            self != .inputObserveOnly
        }

        var allowsHostActionExecution: Bool {
            self == .standard
        }

        var observesStandardHIDInput: Bool {
            self == .inputObserveOnly
        }
    }

    var appCommandHandler: ((Data) -> Void)?
    var observedStandardHIDInputHandler: ((TransportChannel) -> Void)?
    var confirmationHandler: ((TransportChannel, DeviceProtocol.ConfigurationAcknowledgement) -> Void)?
    var statusHandler: ((DeviceProtocol.DeviceStatus) -> Void)?
    var statusErrorHandler: ((DeviceProtocol.Error) -> Void)?
    var connectionHandler: ((DeviceConnection) -> Void)?

    private let usb = USBHIDTransport()
    private let bluetooth = BLEConfigurationTransport()
    private lazy var router = TransportRouter(usb: usb, bluetooth: bluetooth)
    private var statusReassembler = DeviceProtocol.StatusResponseReassembler()
    private var nextStatusRequestID: UInt32 = 1
    private var accessMode: AccessMode = .standard

    init() {
        usb.appCommandHandler = { [weak self] channel, payload in
            self?.receiveHID(channel: channel, payload: payload)
        }
        usb.standardHIDInputHandler = { [weak self] channel in
            self?.receiveStandardHIDInput(channel: channel)
        }
        usb.connectionHandler = { [weak self] connected in
            self?.publishConnection()
        }
        usb.eventConnectionHandler = { [weak self] channel, connected in
            self?.publishConnection()
        }
        bluetooth.connectionHandler = { [weak self] connected in
            self?.publishConnection()
        }
        bluetooth.statusHandler = { [weak self] data in
            guard let self else { return }
            if self.accessMode.allowsStatusRead,
               let status = DeviceProtocol.decodeBLEDeviceStatus(data) {
                self.statusHandler?(status)
            }
            if self.accessMode.allowsConfigurationSync,
               let acknowledgement = DeviceProtocol.decodeBLEConfirmationStatus(data) {
                self.confirmationHandler?(.bluetooth, acknowledgement)
            }
        }
    }

    func start(mode: AccessMode = .standard) {
        accessMode = mode
        connectionHandler?(DeviceConnection(state: .connecting, name: "EasyInput AI"))
        usb.start()
        if mode.startsBluetoothConfiguration {
            bluetooth.start()
        }
    }

    func stop() {
        usb.stop()
        bluetooth.stop()
        connectionHandler?(DeviceConnection(state: .disconnected, name: "EasyInput AI"))
    }

    var configurationChannel: TransportChannel? {
        router.configurationChannel
    }

    func sendConfiguration(
        _ frames: [DeviceProtocol.ConfigurationFrame],
        through channel: TransportChannel
    ) async throws -> TransportChannel {
        guard accessMode.allowsConfigurationSync else { throw TransportError.writeFailed(.usb) }
        return try await router.send(frames, through: channel)
    }

    /// USB is the sole active status-request transport. BLE status remains a
    /// notification-only source so dual connections cannot issue duplicate
    /// status reads.
    @discardableResult
    func requestStatus(fresh: Bool = true) throws -> UInt32 {
        guard accessMode.allowsStatusRead else {
            throw TransportError.statusRequestFailed(.usb, .unsupported)
        }
        let requestID = allocateStatusRequestID()
        try statusReassembler.begin(requestID: requestID)
        do {
            try usb.requestStatus(requestID: requestID, fresh: fresh)
            return requestID
        } catch {
            statusReassembler.reset()
            throw error
        }
    }

    private func receiveHID(channel: TransportChannel, payload: Data) {
        guard usb.activeEventChannel == channel else { return }
        if payload.first == DeviceProtocol.statusResponseKind {
            guard accessMode.allowsStatusRead else { return }
            do {
                if let status = try statusReassembler.receive(payload: payload) {
                    statusHandler?(status)
                }
            } catch let error as DeviceProtocol.Error {
                statusErrorHandler?(error)
            } catch {
                statusErrorHandler?(.malformedStatusResponse)
            }
            return
        }
        if accessMode.allowsConfigurationSync,
           let message = try? DeviceProtocol.decodeAppCommand(payload: payload),
           case let .configurationAcknowledgement(acknowledgement) = message {
            confirmationHandler?(channel, acknowledgement)
            return
        }
        guard accessMode.allowsHostActionExecution else { return }
        appCommandHandler?(payload)
    }

    private func receiveStandardHIDInput(channel: TransportChannel) {
        guard accessMode.observesStandardHIDInput,
              usb.activeEventChannel == channel else { return }
        observedStandardHIDInputHandler?(channel)
    }

    private func allocateStatusRequestID() -> UInt32 {
        if nextStatusRequestID == 0 {
            nextStatusRequestID = 1
        }
        let requestID = nextStatusRequestID
        nextStatusRequestID = requestID == .max ? 1 : requestID + 1
        return requestID
    }

    private func publishConnection() {
        let inputChannel = usb.activeEventChannel
        let configurationChannel = router.configurationChannel
        connectionHandler?(DeviceConnection.current(
            name: "EasyInput AI",
            activeInputChannel: inputChannel,
            configurationChannel: configurationChannel
        ))
    }
}

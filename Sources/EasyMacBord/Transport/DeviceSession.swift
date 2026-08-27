import Foundation

@MainActor
final class DeviceSession {
    var appCommandHandler: ((Data) -> Void)?
    var confirmationHandler: ((DeviceProtocol.ConfigurationAcknowledgement) -> Void)?
    var statusHandler: ((DeviceProtocol.DeviceStatus) -> Void)?
    var statusErrorHandler: ((DeviceProtocol.Error) -> Void)?
    var connectionHandler: ((DeviceConnection) -> Void)?

    private let usb = USBHIDTransport()
    private let bluetooth = BLEConfigurationTransport()
    private lazy var router = TransportRouter(usb: usb, bluetooth: bluetooth)
    private var statusReassembler = DeviceProtocol.StatusResponseReassembler()
    private var nextStatusRequestID: UInt32 = 1

    init() {
        usb.appCommandHandler = { [weak self] channel, payload in
            self?.receiveHID(channel: channel, payload: payload)
        }
        usb.connectionHandler = { [weak self] connected in
            self?.connectionHandler?(DeviceConnection(
                state: connected ? .connected(.usb) : self?.fallbackConnectionState() ?? .disconnected,
                name: "EasyInput AI"
            ))
        }
        usb.eventConnectionHandler = { [weak self] channel, connected in
            guard channel == .bluetooth, let self, !self.usb.isAvailable else { return }
            self.connectionHandler?(DeviceConnection(
                state: connected ? .connected(.bluetooth) : self.fallbackConnectionState(),
                name: "EasyInput AI"
            ))
        }
        bluetooth.connectionHandler = { [weak self] connected in
            guard let self, !self.usb.isAvailable else { return }
            self.connectionHandler?(DeviceConnection(
                state: connected ? .connected(.bluetooth) : .disconnected,
                name: "EasyInput AI"
            ))
        }
        bluetooth.statusHandler = { [weak self] data in
            guard let self else { return }
            if let status = DeviceProtocol.decodeBLEDeviceStatus(data) {
                self.statusHandler?(status)
            }
            if let acknowledgement = DeviceProtocol.decodeBLEConfirmationStatus(data) {
                self.confirmationHandler?(acknowledgement)
            }
        }
    }

    func start() {
        connectionHandler?(DeviceConnection(state: .connecting, name: "EasyInput AI"))
        usb.start()
        bluetooth.start()
    }

    func stop() {
        usb.stop()
        bluetooth.stop()
        connectionHandler?(DeviceConnection(state: .disconnected, name: "EasyInput AI"))
    }

    func sendConfiguration(_ frames: [DeviceProtocol.ConfigurationFrame]) async throws -> TransportChannel {
        try await router.send(frames)
    }

    /// USB is the sole active status-request transport. BLE status remains a
    /// notification-only source so dual connections cannot issue duplicate
    /// status reads.
    @discardableResult
    func requestStatus(fresh: Bool = true) throws -> UInt32 {
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
        appCommandHandler?(payload)
    }

    private func allocateStatusRequestID() -> UInt32 {
        if nextStatusRequestID == 0 {
            nextStatusRequestID = 1
        }
        let requestID = nextStatusRequestID
        nextStatusRequestID = requestID == .max ? 1 : requestID + 1
        return requestID
    }

    private func fallbackConnectionState() -> DeviceConnection.State {
        bluetooth.isAvailable ? .connected(.bluetooth) : .disconnected
    }
}

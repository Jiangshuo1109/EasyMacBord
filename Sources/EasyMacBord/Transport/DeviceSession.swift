import Foundation

@MainActor
final class DeviceSession {
    var appCommandHandler: ((Data) -> Void)?
    var confirmationHandler: ((DeviceProtocol.ConfigurationAcknowledgement) -> Void)?
    var connectionHandler: ((DeviceConnection) -> Void)?

    private let usb = USBHIDTransport()
    private let bluetooth = BLEConfigurationTransport()
    private lazy var router = TransportRouter(usb: usb, bluetooth: bluetooth)

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
        bluetooth.connectionHandler = { [weak self] connected in
            guard let self, !self.usb.isAvailable else { return }
            self.connectionHandler?(DeviceConnection(
                state: connected ? .connected(.bluetooth) : .disconnected,
                name: "EasyInput AI"
            ))
        }
        bluetooth.statusHandler = { [weak self] data in
            guard let acknowledgement = DeviceProtocol.decodeBLEConfirmationStatus(data) else { return }
            self?.confirmationHandler?(acknowledgement)
        }
    }

    func start() {
        usb.start()
        bluetooth.start()
        connectionHandler?(DeviceConnection(state: .connecting, name: "EasyInput AI"))
    }

    func stop() {
        usb.stop()
        bluetooth.stop()
        connectionHandler?(DeviceConnection(state: .disconnected, name: "EasyInput AI"))
    }

    func sendConfiguration(_ frames: [DeviceProtocol.ConfigurationFrame]) async throws -> TransportChannel {
        try await router.send(frames)
    }

    private func receiveHID(channel: TransportChannel, payload: Data) {
        guard router.activeEventChannel == channel else { return }
        appCommandHandler?(payload)
    }

    private func fallbackConnectionState() -> DeviceConnection.State {
        bluetooth.isAvailable ? .connected(.bluetooth) : .disconnected
    }
}

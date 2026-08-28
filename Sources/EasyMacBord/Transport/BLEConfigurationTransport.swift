@preconcurrency import CoreBluetooth
import Foundation

/// BLE configuration writes are serialized. A later chunk is never written
/// until CoreBluetooth confirms the previous `.withResponse` write.
@MainActor
final class BLEConfigurationTransport: NSObject, ConfigurationTransport {
    let channel: TransportChannel = .bluetooth
    private(set) var isAvailable = false
    var statusHandler: ((Data) -> Void)?
    var connectionHandler: ((Bool) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var statusNotificationsEnabled = false
    private var pendingFrames: [DeviceProtocol.ConfigurationFrame] = []
    private var writeContinuation: CheckedContinuation<Void, Swift.Error>?
    private var writeTimeoutTask: Task<Void, Never>?
    private var writeGate = BLEWriteGate()
    private let serviceUUID = CBUUID(string: "7D2F4D10-6F6B-4A2D-8B01-6D4653320001")
    private let writeUUID = CBUUID(string: "7D2F4D10-6F6B-4A2D-8B01-6D4653320002")
    private let statusUUID = CBUUID(string: "7D2F4D10-6F6B-4A2D-8B01-6D4653320003")

    func start() {
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func stop() {
        finishWrite(with: TransportError.unavailable(.bluetooth))
        if let peripheral, let central { central.cancelPeripheralConnection(peripheral) }
        resetConnection()
    }

    func send(_ frames: [DeviceProtocol.ConfigurationFrame]) async throws {
        guard let peripheral, let writeCharacteristic, isAvailable else {
            throw TransportError.unavailable(.bluetooth)
        }
        guard writeGate.begin() else { throw TransportError.writeFailed(.bluetooth) }
        let maximum = peripheral.maximumWriteValueLength(for: .withResponse)
        guard maximum >= DeviceProtocol.configurationHeaderLength,
              frames.allSatisfy({ $0.payload.count <= maximum }) else {
            writeGate.finish()
            throw TransportError.writeFailed(.bluetooth)
        }

        try await withCheckedThrowingContinuation { continuation in
            writeContinuation = continuation
            pendingFrames = frames
            writeTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                self?.finishWrite(with: TransportError.writeFailed(.bluetooth))
            }
            writeNext(peripheral: peripheral, characteristic: writeCharacteristic)
        }
    }

    private func writeNext(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard !pendingFrames.isEmpty else {
            finishWrite(with: nil)
            return
        }
        let frame = pendingFrames.removeFirst()
        peripheral.writeValue(frame.payload, for: characteristic, type: .withResponse)
    }

    private func finishWrite(with error: Swift.Error?) {
        let continuation = writeContinuation
        writeContinuation = nil
        pendingFrames = []
        writeTimeoutTask?.cancel()
        writeTimeoutTask = nil
        writeGate.finish()
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }

    private func resetConnection() {
        peripheral = nil
        writeCharacteristic = nil
        statusCharacteristic = nil
        statusNotificationsEnabled = false
        isAvailable = false
    }

    private func updateAvailability() {
        let isWritable = writeCharacteristic?.properties.contains(.write) == true
        let isNotifying = statusCharacteristic?.properties.contains(.notify) == true
            && statusNotificationsEnabled
        let nextAvailability = isWritable && isNotifying
        guard isAvailable != nextAvailability else { return }
        isAvailable = nextAvailability
        connectionHandler?(nextAvailability)
    }
}

extension BLEConfigurationTransport: @MainActor CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            resetConnection()
            finishWrite(with: TransportError.unavailable(.bluetooth))
            connectionHandler?(false)
            return
        }
        central.scanForPeripherals(withServices: [serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        resetConnection()
        finishWrite(with: TransportError.unavailable(.bluetooth))
        connectionHandler?(false)
        central.scanForPeripherals(withServices: [serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        resetConnection()
        finishWrite(with: TransportError.unavailable(.bluetooth))
        connectionHandler?(false)
        central.scanForPeripherals(withServices: [serviceUUID])
    }
}

extension BLEConfigurationTransport: @MainActor CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            resetConnection()
            connectionHandler?(false)
            return
        }
        peripheral.services?
            .filter { $0.uuid == serviceUUID }
            .forEach { peripheral.discoverCharacteristics([writeUUID, statusUUID], for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, service.uuid == serviceUUID else {
            resetConnection()
            connectionHandler?(false)
            return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == writeUUID, characteristic.properties.contains(.write) {
                writeCharacteristic = characteristic
            }
            if characteristic.uuid == statusUUID, characteristic.properties.contains(.notify) {
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        updateAvailability()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == writeUUID else { return }
        guard error == nil, let writeCharacteristic else {
            finishWrite(with: TransportError.writeFailed(.bluetooth))
            return
        }
        writeNext(peripheral: peripheral, characteristic: writeCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == statusUUID, let value = characteristic.value else { return }
        statusHandler?(value)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == statusUUID else { return }
        statusNotificationsEnabled = error == nil && characteristic.isNotifying
        updateAvailability()
    }
}

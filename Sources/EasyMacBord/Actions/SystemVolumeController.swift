import CoreAudio
import Foundation

struct SystemVolumeController {
    private let volumeStep: Float32 = 0.0625

    func increase() -> Bool {
        adjust(by: volumeStep)
    }

    func decrease() -> Bool {
        adjust(by: -volumeStep)
    }

    func toggleMute() -> Bool {
        guard let device = defaultOutputDevice(), let address = writableAddress(
            selector: kAudioDevicePropertyMute,
            device: device
        ) else {
            return false
        }
        var muted: UInt32 = 0
        guard readUInt32(device: device, address: address, value: &muted) else { return false }
        var nextValue: UInt32 = muted == 0 ? 1 : 0
        return writeUInt32(device: device, address: address, value: &nextValue)
    }

    private func adjust(by amount: Float32) -> Bool {
        guard let device = defaultOutputDevice(), let address = writableAddress(
            selector: kAudioDevicePropertyVolumeScalar,
            device: device
        ) else {
            return false
        }
        var current: Float32 = 0
        guard readFloat32(device: device, address: address, value: &current) else { return false }
        var nextValue = min(max(current + amount, 0), 1)
        return writeFloat32(device: device, address: address, value: &nextValue)
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return result == noErr && deviceID != AudioDeviceID(kAudioObjectUnknown) ? deviceID : nil
    }

    private func writableAddress(selector: AudioObjectPropertySelector, device: AudioDeviceID) -> AudioObjectPropertyAddress? {
        let elements: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            1,
            2
        ]
        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(device, &address) else { continue }
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
                continue
            }
            return address
        }
        return nil
    }

    private func readUInt32(device: AudioDeviceID, address: AudioObjectPropertyAddress, value: inout UInt32) -> Bool {
        var address = address
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
    }

    private func writeUInt32(device: AudioDeviceID, address: AudioObjectPropertyAddress, value: inout UInt32) -> Bool {
        var address = address
        return AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        ) == noErr
    }

    private func readFloat32(device: AudioDeviceID, address: AudioObjectPropertyAddress, value: inout Float32) -> Bool {
        var address = address
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
    }

    private func writeFloat32(device: AudioDeviceID, address: AudioObjectPropertyAddress, value: inout Float32) -> Bool {
        var address = address
        return AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &value
        ) == noErr
    }
}

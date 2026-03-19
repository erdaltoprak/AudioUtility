import CoreAudio
import Dispatch
import Foundation

enum AudioDeviceServiceError: LocalizedError {
    case coreAudioError(OSStatus)
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case .coreAudioError(let status):
            return "Core Audio returned error \(status)."
        case .deviceNotFound:
            return "The selected audio device is no longer available."
        }
    }
}

struct AudioDeviceSnapshot: Sendable {
    let inputDevices: [AudioDevice]
    let outputDevices: [AudioDevice]
}

struct AudioDeviceService: Sendable {
    func loadDevices() async throws -> AudioDeviceSnapshot {
        try await perform {
            let allDevices = try fetchAllDevices()
            let inputDevices = allDevices.filter { device in
                switch device.kind {
                case .input:
                    return true
                case .output:
                    return false
                }
            }
            let outputDevices = allDevices.filter { device in
                switch device.kind {
                case .input:
                    return false
                case .output:
                    return true
                }
            }
            return AudioDeviceSnapshot(inputDevices: inputDevices, outputDevices: outputDevices)
        }
    }

    func setDefaultInputDevice(id: AudioDevice.ID) async throws {
        try await perform {
            try setDefaultDevice(id: id, kind: .input)
        }
    }

    func setDefaultOutputDevice(id: AudioDevice.ID) async throws {
        try await perform {
            try setDefaultDevice(id: id, kind: .output)
        }
    }

    func makeObservation(
        onChange: @escaping @Sendable (AudioDeviceObservationEvent) -> Void
    ) throws -> AudioDeviceObservation {
        try AudioDeviceObservation(onChange: onChange)
    }

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated)
                .async {
                    do {
                        continuation.resume(returning: try operation())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
        }
    }
}

extension AudioDeviceService {
    fileprivate func fetchAllDevices() throws -> [AudioDevice] {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(systemObjectID, &devicesAddress, 0, nil, &dataSize)
        if status != noErr {
            throw AudioDeviceServiceError.coreAudioError(status)
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = Array(repeating: AudioObjectID(0), count: deviceCount)

        status = AudioObjectGetPropertyData(systemObjectID, &devicesAddress, 0, nil, &dataSize, &deviceIDs)
        if status != noErr {
            throw AudioDeviceServiceError.coreAudioError(status)
        }

        let defaultInputID = try defaultDeviceID(for: .input)
        let defaultOutputID = try defaultDeviceID(for: .output)

        var result: [AudioDevice] = []
        result.reserveCapacity(deviceIDs.count * 2)

        for deviceID in deviceIDs {
            let name = deviceName(for: deviceID) ?? "Device \(deviceID)"
            let uid = deviceUID(for: deviceID) ?? "audio-device-\(deviceID)"
            let isAlive = isDeviceAlive(deviceID: deviceID)

            if hasStreams(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput) {
                let idString = String(deviceID)
                let device = AudioDevice(
                    id: idString,
                    uid: uid,
                    name: name,
                    kind: .input,
                    isDefault: deviceID == defaultInputID,
                    isConnected: isAlive
                )
                result.append(device)
            }

            if hasStreams(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput) {
                let idString = String(deviceID)
                let device = AudioDevice(
                    id: idString,
                    uid: uid,
                    name: name,
                    kind: .output,
                    isDefault: deviceID == defaultOutputID,
                    isConnected: isAlive
                )
                result.append(device)
            }
        }

        return result
    }

    fileprivate func defaultDeviceID(for kind: AudioDeviceKind) throws -> AudioObjectID {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

        let selector: AudioObjectPropertySelector
        switch kind {
        case .input:
            selector = kAudioHardwarePropertyDefaultInputDevice
        case .output:
            selector = kAudioHardwarePropertyDefaultOutputDevice
        }

        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioObjectID(0)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceID)
        if status != noErr {
            throw AudioDeviceServiceError.coreAudioError(status)
        }

        return deviceID
    }

    fileprivate func setDefaultDevice(id: AudioDevice.ID, kind: AudioDeviceKind) throws {
        guard let numericID = UInt32(id) else {
            throw AudioDeviceServiceError.deviceNotFound
        }

        var deviceID = AudioObjectID(numericID)
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

        let selector: AudioObjectPropertySelector
        switch kind {
        case .input:
            selector = kAudioHardwarePropertyDefaultInputDevice
        case .output:
            selector = kAudioHardwarePropertyDefaultOutputDevice
        }

        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectSetPropertyData(systemObjectID, &address, 0, nil, dataSize, &deviceID)
        if status != noErr {
            throw AudioDeviceServiceError.coreAudioError(status)
        }
    }

    fileprivate func deviceName(for deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let namePointer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<CFString>.size,
            alignment: MemoryLayout<CFString>.alignment
        )
        defer {
            namePointer.deallocate()
        }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, namePointer)
        guard status == noErr else {
            return nil
        }

        let cfName = namePointer.load(as: CFString.self)
        return cfName as String
    }

    fileprivate func deviceUID(for deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let uidPointer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<CFString>.size,
            alignment: MemoryLayout<CFString>.alignment
        )
        defer {
            uidPointer.deallocate()
        }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, uidPointer)
        guard status == noErr else {
            return nil
        }

        let cfUID = uidPointer.load(as: CFString.self)
        return cfUID as String
    }

    fileprivate func isDeviceAlive(deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isAlive: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isAlive)
        guard status == noErr else {
            return false
        }

        return isAlive != 0
    }

    fileprivate func hasStreams(deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        if status != noErr || dataSize == 0 {
            return false
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            bufferListPointer.deallocate()
        }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer)
        if status != noErr {
            return false
        }

        let audioBufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        return withUnsafePointer(to: audioBufferList.pointee.mBuffers) { firstBuffer in
            let buffers = UnsafeBufferPointer(
                start: firstBuffer,
                count: Int(audioBufferList.pointee.mNumberBuffers)
            )
            return buffers.contains { buffer in
                buffer.mNumberChannels > 0
            }
        }
    }
}

import CoreAudio
import Dispatch
import Foundation

final class AudioDeviceObservation {
    private let queue = DispatchQueue(
        label: "com.erdaltoprak.AudioUtility.audio-device-observation",
        qos: .userInitiated
    )

    private var registrations: [Registration] = []

    init(onChange: @escaping @Sendable (AudioDeviceObservationEvent) -> Void) throws {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice,
        ]

        do {
            for selector in selectors {
                try addListener(
                    objectID: systemObjectID,
                    selector: selector,
                    onChange: onChange
                )
            }
        } catch {
            invalidate()
            throw error
        }
    }

    deinit {
        invalidate()
    }

    private func addListener(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        onChange: @escaping @Sendable (AudioDeviceObservationEvent) -> Void
    ) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { numberAddresses, addresses in
            onChange(
                AudioDeviceObservationEvent(
                    addresses: addresses,
                    count: numberAddresses
                )
            )
        }

        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block)
        guard status == noErr else {
            throw AudioDeviceServiceError.coreAudioError(status)
        }

        registrations.append(
            Registration(
                objectID: objectID,
                address: address,
                block: block
            )
        )
    }

    private func invalidate() {
        guard !registrations.isEmpty else {
            return
        }

        for registration in registrations {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(
                registration.objectID,
                &address,
                queue,
                registration.block
            )
        }

        registrations.removeAll()
    }
}

extension AudioDeviceObservation {
    fileprivate struct Registration {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
}

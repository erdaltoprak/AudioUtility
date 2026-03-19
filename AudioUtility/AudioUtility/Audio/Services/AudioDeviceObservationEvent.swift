import CoreAudio
import Foundation

struct AudioDeviceObservationEvent: Sendable {
    let hasDeviceListChange: Bool
    let hasDefaultInputChange: Bool
    let hasDefaultOutputChange: Bool

    init(
        hasDeviceListChange: Bool = false,
        hasDefaultInputChange: Bool = false,
        hasDefaultOutputChange: Bool = false
    ) {
        self.hasDeviceListChange = hasDeviceListChange
        self.hasDefaultInputChange = hasDefaultInputChange
        self.hasDefaultOutputChange = hasDefaultOutputChange
    }

    init(addresses: UnsafePointer<AudioObjectPropertyAddress>?, count: UInt32) {
        var hasDeviceListChange = false
        var hasDefaultInputChange = false
        var hasDefaultOutputChange = false

        if let addresses {
            for index in 0 ..< Int(count) {
                switch addresses[index].mSelector {
                case kAudioHardwarePropertyDevices:
                    hasDeviceListChange = true
                case kAudioHardwarePropertyDefaultInputDevice:
                    hasDefaultInputChange = true
                case kAudioHardwarePropertyDefaultOutputDevice:
                    hasDefaultOutputChange = true
                default:
                    break
                }
            }
        }

        self.init(
            hasDeviceListChange: hasDeviceListChange,
            hasDefaultInputChange: hasDefaultInputChange,
            hasDefaultOutputChange: hasDefaultOutputChange
        )
    }
}

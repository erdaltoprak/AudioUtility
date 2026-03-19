import Foundation

struct ManagedAudioDevice: Identifiable, Hashable, Sendable {
    let uid: String
    let name: String
    let kind: AudioDeviceKind
    let currentDevice: AudioDevice?

    var id: String {
        "\(kind.rawValue)-\(uid)"
    }

    var isAvailable: Bool {
        currentDevice != nil
    }

    var isDefault: Bool {
        currentDevice?.isDefault ?? false
    }
}

import Foundation

enum AudioDeviceKind: String, CaseIterable, Codable, Sendable {
    case input
    case output

    var title: String {
        switch self {
        case .input:
            "Input"
        case .output:
            "Output"
        }
    }
}

struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: String
    let uid: String
    let name: String
    let kind: AudioDeviceKind
    let isDefault: Bool
    let isConnected: Bool
}

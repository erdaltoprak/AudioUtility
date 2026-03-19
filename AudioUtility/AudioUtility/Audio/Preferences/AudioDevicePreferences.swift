import Foundation

struct AudioDevicePreferences: Codable, Sendable {
    var input = AudioDeviceKindPreferences()
    var output = AudioDeviceKindPreferences()

    mutating func registerAvailableDevices(_ devices: [AudioDevice], for kind: AudioDeviceKind) -> Bool {
        var preferences = preferences(for: kind)
        var hasChanges = false
        let knownUIDs = Set(preferences.orderedUIDs).union(preferences.excludedUIDs)
        let newUIDs = devices.map(\.uid).filter { !knownUIDs.contains($0) }

        if !newUIDs.isEmpty {
            preferences.orderedUIDs.append(contentsOf: newUIDs)
            hasChanges = true
        }

        for device in devices where preferences.knownDeviceNames[device.uid] != device.name {
            preferences.knownDeviceNames[device.uid] = device.name
            hasChanges = true
        }

        guard hasChanges else {
            return false
        }

        setPreferences(preferences, for: kind)
        return true
    }

    func orderedVisibleDevices(from devices: [AudioDevice], for kind: AudioDeviceKind) -> [AudioDevice] {
        let preferences = preferences(for: kind)
        let visibleUIDs = preferences.orderedUIDs.filter { !preferences.excludedUIDs.contains($0) }
        return orderedDevices(from: devices, using: visibleUIDs)
    }

    func excludedVisibleDevices(from devices: [AudioDevice], for kind: AudioDeviceKind) -> [AudioDevice] {
        orderedDevices(from: devices, using: preferences(for: kind).excludedUIDs)
    }

    func managedOrderedDevices(from devices: [AudioDevice], for kind: AudioDeviceKind) -> [ManagedAudioDevice] {
        managedDevices(from: devices, using: preferences(for: kind).orderedUIDs, for: kind)
    }

    func managedExcludedDevices(from devices: [AudioDevice], for kind: AudioDeviceKind) -> [ManagedAudioDevice] {
        managedDevices(from: devices, using: preferences(for: kind).excludedUIDs, for: kind)
    }

    func isExcluded(uid: String, for kind: AudioDeviceKind) -> Bool {
        preferences(for: kind).excludedUIDs.contains(uid)
    }

    func canMoveAllowedDevice(uid: String, by offset: Int, for kind: AudioDeviceKind) -> Bool {
        let orderedUIDs = preferences(for: kind).orderedUIDs
        guard let index = orderedUIDs.firstIndex(of: uid) else {
            return false
        }

        let destinationIndex = index + offset
        return orderedUIDs.indices.contains(destinationIndex)
    }

    mutating func moveAllowedDevice(uid: String, by offset: Int, for kind: AudioDeviceKind) -> Bool {
        var preferences = preferences(for: kind)

        guard let index = preferences.orderedUIDs.firstIndex(of: uid) else {
            return false
        }

        let destinationIndex = index + offset
        guard preferences.orderedUIDs.indices.contains(destinationIndex) else {
            return false
        }

        preferences.orderedUIDs.swapAt(index, destinationIndex)
        setPreferences(preferences, for: kind)
        return true
    }

    mutating func setExcluded(_ isExcluded: Bool, uid: String, for kind: AudioDeviceKind) -> Bool {
        var preferences = preferences(for: kind)

        if isExcluded {
            guard let index = preferences.orderedUIDs.firstIndex(of: uid) else {
                return false
            }

            preferences.orderedUIDs.remove(at: index)
            if !preferences.excludedUIDs.contains(uid) {
                preferences.excludedUIDs.append(uid)
            }
            setPreferences(preferences, for: kind)
            return true
        }

        guard let index = preferences.excludedUIDs.firstIndex(of: uid) else {
            return false
        }

        preferences.excludedUIDs.remove(at: index)
        if !preferences.orderedUIDs.contains(uid) {
            preferences.orderedUIDs.append(uid)
        }
        setPreferences(preferences, for: kind)
        return true
    }

    private func orderedDevices(from devices: [AudioDevice], using orderedUIDs: [String]) -> [AudioDevice] {
        let devicesByUID = Dictionary(uniqueKeysWithValues: devices.map { ($0.uid, $0) })
        return orderedUIDs.compactMap { devicesByUID[$0] }
    }

    private func managedDevices(
        from devices: [AudioDevice],
        using orderedUIDs: [String],
        for kind: AudioDeviceKind
    ) -> [ManagedAudioDevice] {
        let preferences = preferences(for: kind)
        let devicesByUID = Dictionary(uniqueKeysWithValues: devices.map { ($0.uid, $0) })

        return orderedUIDs.compactMap { uid in
            let currentDevice = devicesByUID[uid]
            let name = currentDevice?.name ?? preferences.knownDeviceNames[uid]

            guard let name else {
                return nil
            }

            return ManagedAudioDevice(
                uid: uid,
                name: name,
                kind: kind,
                currentDevice: currentDevice
            )
        }
    }

    private func preferences(for kind: AudioDeviceKind) -> AudioDeviceKindPreferences {
        switch kind {
        case .input:
            input
        case .output:
            output
        }
    }

    private mutating func setPreferences(_ preferences: AudioDeviceKindPreferences, for kind: AudioDeviceKind) {
        switch kind {
        case .input:
            input = preferences
        case .output:
            output = preferences
        }
    }
}

struct AudioDeviceKindPreferences: Codable, Sendable {
    var orderedUIDs: [String] = []
    var excludedUIDs: [String] = []
    var knownDeviceNames: [String: String] = [:]
}

struct AudioDevicePreferencesStore {
    private let defaults: UserDefaults
    private let key = "AudioUtility.AudioDevicePreferences"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AudioDevicePreferences {
        guard
            let data = defaults.data(forKey: key),
            let preferences = try? JSONDecoder().decode(AudioDevicePreferences.self, from: data)
        else {
            return AudioDevicePreferences()
        }

        return preferences
    }

    func save(_ preferences: AudioDevicePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}

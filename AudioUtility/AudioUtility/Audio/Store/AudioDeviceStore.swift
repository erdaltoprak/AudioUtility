import Foundation
import Observation

@MainActor
@Observable
final class AudioDeviceStore {
    @ObservationIgnored private let preferencesStore: AudioDevicePreferencesStore
    @ObservationIgnored private let service: AudioDeviceService
    @ObservationIgnored private var audioDeviceObservation: AudioDeviceObservation?
    @ObservationIgnored private var isPerformingDeviceUpdate = false
    @ObservationIgnored private var latestSnapshot: AudioDeviceSnapshot?
    @ObservationIgnored private var pendingRefreshPolicy: RefreshPolicy?
    @ObservationIgnored private var runtimeSelectedDeviceUIDs: [AudioDeviceKind: String] = [:]

    var inputDevices: [AudioDevice] = []
    var outputDevices: [AudioDevice] = []

    var devicePreferences: AudioDevicePreferences
    var selectedInput: AudioDevice?
    var selectedOutput: AudioDevice?

    var isLoading = false
    var errorMessage: String?

    init(
        service: AudioDeviceService,
        preferencesStore: AudioDevicePreferencesStore
    ) {
        self.preferencesStore = preferencesStore
        self.service = service
        devicePreferences = preferencesStore.load()
        startObservingAudioDevices()

        Task { @MainActor [weak self] in
            await self?.loadDevices()
        }
    }

    convenience init() {
        self.init(
            service: AudioDeviceService(),
            preferencesStore: AudioDevicePreferencesStore()
        )
    }

    func loadDevices() async {
        await loadDevices(using: .applyFallbackOrder)
    }

    func refreshDevices() async {
        await loadDevices(using: .preserveCurrentSelection)
    }

    func managedOrderedDevices(for kind: AudioDeviceKind) -> [ManagedAudioDevice] {
        guard let snapshot = latestSnapshot else {
            return []
        }

        switch kind {
        case .input:
            return devicePreferences.managedOrderedDevices(from: snapshot.inputDevices, for: .input)
        case .output:
            return devicePreferences.managedOrderedDevices(from: snapshot.outputDevices, for: .output)
        }
    }

    func managedExcludedDevices(for kind: AudioDeviceKind) -> [ManagedAudioDevice] {
        guard let snapshot = latestSnapshot else {
            return []
        }

        switch kind {
        case .input:
            return devicePreferences.managedExcludedDevices(from: snapshot.inputDevices, for: .input)
        case .output:
            return devicePreferences.managedExcludedDevices(from: snapshot.outputDevices, for: .output)
        }
    }

    func loadDevices(using refreshPolicy: RefreshPolicy) async {
        if isPerformingDeviceUpdate {
            queueRefresh(using: refreshPolicy)
            return
        }

        errorMessage = nil
        isLoading = true
        isPerformingDeviceUpdate = true

        await refreshDevicesUntilCurrent(using: refreshPolicy)
    }

    func changeInput(to device: AudioDevice) async {
        guard selectedInput?.id != device.id, !isLoading else {
            return
        }

        setRuntimeSelection(uid: device.uid, for: .input)
        await updateDefaultDevice(id: device.id, kind: .input, refreshPolicy: .preserveCurrentSelection)
    }

    func changeOutput(to device: AudioDevice) async {
        guard selectedOutput?.id != device.id, !isLoading else {
            return
        }

        setRuntimeSelection(uid: device.uid, for: .output)
        await updateDefaultDevice(id: device.id, kind: .output, refreshPolicy: .preserveCurrentSelection)
    }

    func orderedDevices(for kind: AudioDeviceKind) -> [AudioDevice] {
        guard let snapshot = latestSnapshot else {
            return []
        }

        switch kind {
        case .input:
            return devicePreferences.orderedVisibleDevices(from: snapshot.inputDevices, for: .input)
        case .output:
            return devicePreferences.orderedVisibleDevices(from: snapshot.outputDevices, for: .output)
        }
    }

    func excludedDevices(for kind: AudioDeviceKind) -> [AudioDevice] {
        guard let snapshot = latestSnapshot else {
            return []
        }

        switch kind {
        case .input:
            return devicePreferences.excludedVisibleDevices(from: snapshot.inputDevices, for: .input)
        case .output:
            return devicePreferences.excludedVisibleDevices(from: snapshot.outputDevices, for: .output)
        }
    }

    func selectedDevice(for kind: AudioDeviceKind) -> AudioDevice? {
        switch kind {
        case .input:
            selectedInput
        case .output:
            selectedOutput
        }
    }

    func isManualSelectionActive(for kind: AudioDeviceKind) -> Bool {
        runtimeSelectedDeviceUIDs[kind] != nil
    }

    func canMoveDevice(_ deviceUID: String, kind: AudioDeviceKind, offset: Int) -> Bool {
        devicePreferences.canMoveAllowedDevice(uid: deviceUID, by: offset, for: kind)
    }

    func moveDevice(_ deviceUID: String, kind: AudioDeviceKind, offset: Int) async {
        guard devicePreferences.moveAllowedDevice(uid: deviceUID, by: offset, for: kind) else {
            return
        }

        saveDevicePreferences()
        await loadDevices(using: .preserveCurrentSelection)
    }

    func setDeviceExcluded(
        _ isExcluded: Bool,
        for deviceUID: String,
        kind: AudioDeviceKind
    ) async {
        guard devicePreferences.setExcluded(isExcluded, uid: deviceUID, for: kind) else {
            return
        }

        saveDevicePreferences()
        await loadDevices(using: .preserveCurrentSelection)
    }

    private func startObservingAudioDevices() {
        do {
            audioDeviceObservation = try service.makeObservation { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    let refreshPolicy = self.refreshPolicy(for: event)
                    await self.loadDevices(using: refreshPolicy)
                }
            }
        } catch {
            assertionFailure("Failed to start Core Audio observation: \(error.localizedDescription)")
        }
    }

    private func updateDefaultDevice(
        id: AudioDevice.ID,
        kind: AudioDeviceKind,
        refreshPolicy: RefreshPolicy
    ) async {
        errorMessage = nil
        isLoading = true
        isPerformingDeviceUpdate = true

        do {
            switch kind {
            case .input:
                try await service.setDefaultInputDevice(id: id)
            case .output:
                try await service.setDefaultOutputDevice(id: id)
            }
        } catch {
            errorMessage = error.localizedDescription
            finishDeviceUpdate()
            return
        }

        await refreshDevicesUntilCurrent(using: refreshPolicy)
    }

    private func refreshDevicesUntilCurrent(using refreshPolicy: RefreshPolicy) async {
        var currentRefreshPolicy = refreshPolicy

        while true {
            pendingRefreshPolicy = nil

            do {
                let snapshot = try await loadSnapshot()
                latestSnapshot = snapshot
                registerAvailableDevices(in: snapshot)

                if let correction = preferredDefaultCorrection(in: snapshot, using: currentRefreshPolicy) {
                    try await applyPreferredDefaultCorrection(correction)
                    currentRefreshPolicy = currentRefreshPolicy.merged(with: pendingRefreshPolicy)
                    continue
                }

                apply(snapshot)
            } catch {
                errorMessage = error.localizedDescription
            }

            guard let nextRefreshPolicy = pendingRefreshPolicy else {
                break
            }

            currentRefreshPolicy = currentRefreshPolicy.merged(with: nextRefreshPolicy)
        }

        finishDeviceUpdate()
    }

    private func apply(_ snapshot: AudioDeviceSnapshot) {
        inputDevices = devicePreferences.orderedVisibleDevices(from: snapshot.inputDevices, for: .input)
        outputDevices = devicePreferences.orderedVisibleDevices(from: snapshot.outputDevices, for: .output)
        selectedInput = snapshot.inputDevices.first(where: \.isDefault)
        selectedOutput = snapshot.outputDevices.first(where: \.isDefault)
    }

    private func loadSnapshot() async throws -> AudioDeviceSnapshot {
        try await service.loadDevices()
    }

    private func finishDeviceUpdate() {
        isLoading = false
        isPerformingDeviceUpdate = false
    }

    private func applyPreferredDefaultCorrection(_ correction: (kind: AudioDeviceKind, id: AudioDevice.ID)) async throws
    {
        switch correction.kind {
        case .input:
            try await service.setDefaultInputDevice(id: correction.id)
        case .output:
            try await service.setDefaultOutputDevice(id: correction.id)
        }
    }

    private func preferredDefaultCorrection(
        in snapshot: AudioDeviceSnapshot,
        using refreshPolicy: RefreshPolicy
    ) -> (kind: AudioDeviceKind, id: AudioDevice.ID)? {
        if let preferredInput = preferredDefaultCorrection(
            in: snapshot.inputDevices,
            for: .input,
            using: refreshPolicy
        ) {
            return (.input, preferredInput.id)
        }

        if let preferredOutput = preferredDefaultCorrection(
            in: snapshot.outputDevices,
            for: .output,
            using: refreshPolicy
        ) {
            return (.output, preferredOutput.id)
        }

        return nil
    }

    private func preferredDefaultCorrection(
        in devices: [AudioDevice],
        for kind: AudioDeviceKind,
        using refreshPolicy: RefreshPolicy
    ) -> AudioDevice? {
        let hadRuntimeSelection = runtimeSelectedDeviceUIDs[kind] != nil

        if let runtimeSelection = runtimeSelectedDevice(for: kind, in: devices) {
            return runtimeSelection.isDefault ? nil : runtimeSelection
        }

        let invalidatedRuntimeSelection = hadRuntimeSelection && runtimeSelectedDeviceUIDs[kind] == nil
        let lostPreviousSelection = didLosePreviouslySelectedDevice(for: kind, in: devices)

        let orderedDevices = devicePreferences.orderedVisibleDevices(from: devices, for: kind)
        guard let fallbackDevice = orderedDevices.first else {
            return nil
        }

        guard let currentDefault = devices.first(where: \.isDefault) else {
            return fallbackDevice
        }

        if devicePreferences.isExcluded(uid: currentDefault.uid, for: kind) {
            return fallbackDevice
        }

        if invalidatedRuntimeSelection || lostPreviousSelection {
            return currentDefault.uid == fallbackDevice.uid ? nil : fallbackDevice
        }

        guard refreshPolicy.enforcement(for: kind) == .applyFallbackOrder else {
            return nil
        }

        return currentDefault.uid == fallbackDevice.uid ? nil : fallbackDevice
    }

    private func registerAvailableDevices(in snapshot: AudioDeviceSnapshot) {
        let inputChanged = devicePreferences.registerAvailableDevices(snapshot.inputDevices, for: .input)
        let outputChanged = devicePreferences.registerAvailableDevices(snapshot.outputDevices, for: .output)

        if inputChanged || outputChanged {
            saveDevicePreferences()
        }
    }

    private func saveDevicePreferences() {
        preferencesStore.save(devicePreferences)
    }

    private func queueRefresh(using refreshPolicy: RefreshPolicy) {
        pendingRefreshPolicy = refreshPolicy.merged(with: pendingRefreshPolicy)
    }

    private func refreshPolicy(for event: AudioDeviceObservationEvent) -> RefreshPolicy {
        var refreshPolicy: RefreshPolicy = .preserveCurrentSelection

        if event.hasDeviceListChange || event.hasDefaultInputChange {
            refreshPolicy.input = .preserveCurrentSelection
        }

        if event.hasDeviceListChange || event.hasDefaultOutputChange {
            refreshPolicy.output = .preserveCurrentSelection
        }

        return refreshPolicy
    }

    private func setRuntimeSelection(uid: String, for kind: AudioDeviceKind) {
        runtimeSelectedDeviceUIDs[kind] = uid
    }

    private func runtimeSelectedDevice(for kind: AudioDeviceKind, in devices: [AudioDevice]) -> AudioDevice? {
        guard let uid = runtimeSelectedDeviceUIDs[kind] else {
            return nil
        }

        if devicePreferences.isExcluded(uid: uid, for: kind) {
            runtimeSelectedDeviceUIDs.removeValue(forKey: kind)
            return nil
        }

        guard let device = devices.first(where: { $0.uid == uid }) else {
            runtimeSelectedDeviceUIDs.removeValue(forKey: kind)
            return nil
        }

        return device
    }

    private func didLosePreviouslySelectedDevice(for kind: AudioDeviceKind, in devices: [AudioDevice]) -> Bool {
        let previousSelectedUID: String?

        switch kind {
        case .input:
            previousSelectedUID = selectedInput?.uid
        case .output:
            previousSelectedUID = selectedOutput?.uid
        }

        guard let previousSelectedUID else {
            return false
        }

        return !devices.contains(where: { $0.uid == previousSelectedUID })
    }
}

extension AudioDeviceStore {
    struct RefreshPolicy {
        var input: DeviceResolution
        var output: DeviceResolution

        static let applyFallbackOrder = Self(input: .applyFallbackOrder, output: .applyFallbackOrder)
        static let preserveCurrentSelection = Self(
            input: .preserveCurrentSelection,
            output: .preserveCurrentSelection
        )

        func enforcement(for kind: AudioDeviceKind) -> DeviceResolution {
            switch kind {
            case .input:
                input
            case .output:
                output
            }
        }

        func merged(with other: Self?) -> Self {
            guard let other else {
                return self
            }

            return Self(
                input: input.merged(with: other.input),
                output: output.merged(with: other.output)
            )
        }
    }

    enum DeviceResolution {
        case applyFallbackOrder
        case preserveCurrentSelection

        func merged(with other: Self) -> Self {
            self == .applyFallbackOrder || other == .applyFallbackOrder
                ? .applyFallbackOrder
                : .preserveCurrentSelection
        }
    }
}

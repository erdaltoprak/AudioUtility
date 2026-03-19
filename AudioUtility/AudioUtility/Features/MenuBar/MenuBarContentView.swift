import AppKit
import Observation
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var audioDeviceStore: AudioDeviceStore
    let updater: any AppUpdaterProviding
    @Environment(\.openURL) private var openURL

    private let repositoryURL = URL(string: "https://github.com/erdaltoprak/AudioUtility")
    private let websiteURL = URL(string: "https://erdaltoprak.com")

    @State private var activePopover: FooterPopover?
    @State private var expandedExcludedKinds: Set<AudioDeviceKind> = []
    @State private var hoveredOrderedDeviceID: ManagedAudioDevice.ID?
    @State private var hoveredAction: MenuBarAction?
    @State private var hoveredPopoverContent: FooterPopover?
    @State private var hoveredPopoverRow: FooterPopover?
    @State private var isEditingOrder = false
    @State private var popoverDismissTask: Task<Void, Never>?

    private var hasAnyDeviceContent: Bool {
        AudioDeviceKind.allCases.contains { kind in
            !orderedDevices(for: kind).isEmpty || !excludedDevices(for: kind).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            deviceContent
            Divider()
            footerActions
        }
        .padding(12)
        .frame(minWidth: 388, idealWidth: 416)
        .task {
            if !audioDeviceStore.isLoading,
                audioDeviceStore.inputDevices.isEmpty,
                audioDeviceStore.outputDevices.isEmpty
            {
                await audioDeviceStore.refreshDevices()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("AudioUtility")
                .font(.headline)

            Spacer(minLength: 12)

            toolbarButton(
                systemImage: isEditingOrder ? "checkmark" : "square.and.pencil",
                help: isEditingOrder ? "Done editing order" : "Edit order",
                isActive: isEditingOrder
            ) {
                withAnimation(.snappy(duration: 0.16)) {
                    isEditingOrder.toggle()
                }
            }

            Button {
                Task {
                    await audioDeviceStore.refreshDevices()
                }
            } label: {
                Group {
                    if audioDeviceStore.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 14, height: 14)
                .padding(4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(audioDeviceStore.isLoading)
            .help("Refresh devices")
        }
    }

    private var deviceContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if audioDeviceStore.isLoading {
                ProgressView("Updating devices…")
                    .controlSize(.small)
            }

            if let errorMessage = audioDeviceStore.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)

                    Button("Retry loading devices") {
                        Task {
                            await audioDeviceStore.refreshDevices()
                        }
                    }
                    .disabled(audioDeviceStore.isLoading)
                }
            }

            if !hasAnyDeviceContent,
                !audioDeviceStore.isLoading,
                audioDeviceStore.errorMessage == nil
            {
                Text("No audio devices found.")
                    .foregroundStyle(.secondary)
            } else {
                if isEditingOrder {
                    Text(
                        "Edit the fallback order used after relaunch or disconnect. Excluded devices stay available below."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                deviceKindSection(.output)
                Divider()
                deviceKindSection(.input)
            }
        }
    }

    private func deviceKindSection(_ kind: AudioDeviceKind) -> some View {
        let ordered = orderedDevices(for: kind)
        let excluded = excludedDevices(for: kind)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(kind.title)
                    .font(.headline)

                if audioDeviceStore.isManualSelectionActive(for: kind) {
                    Text("This Run")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }

                Spacer(minLength: 8)
            }

            Text(currentDeviceName(for: kind))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(audioDeviceStore.selectedDevice(for: kind) == nil ? .secondary : .primary)
                .lineLimit(1)

            if let sectionStatus = sectionStatusText(for: kind) {
                Text(sectionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if ordered.isEmpty, excluded.isEmpty {
                Text("No \(kind.title.lowercased()) devices found.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, device in
                    preferredRow(device: device, index: index, kind: kind)
                }

                if !excluded.isEmpty {
                    excludedDisclosure(kind: kind, devices: excluded)
                }
            }
        }
    }

    private func preferredRow(
        device: ManagedAudioDevice,
        index: Int,
        kind: AudioDeviceKind
    ) -> some View {
        let isHovered = hoveredOrderedDeviceID == device.id
        let isSelected = device.isDefault
        let canMoveUp = audioDeviceStore.canMoveDevice(device.uid, kind: kind, offset: -1)
        let canMoveDown = audioDeviceStore.canMoveDevice(device.uid, kind: kind, offset: 1)

        return HStack(spacing: 10) {
            Button {
                guard let currentDevice = device.currentDevice else {
                    return
                }

                Task {
                    await changeSelection(to: currentDevice)
                }
            } label: {
                HStack(spacing: 10) {
                    rankBadge(index: index, isSelected: isSelected)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(device.isAvailable ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let subtitle = preferredRowSubtitle(for: device, index: index, kind: kind) {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)
            .disabled(audioDeviceStore.isLoading || !device.isAvailable)
            .help(device.isAvailable ? "Use \(device.name)" : "\(device.name) is unavailable")
            .contextMenu {
                preferredRowActions(device: device, kind: kind)
            }

            if isEditingOrder {
                if canMoveUp {
                    inlineSelectedActionButton(
                        systemImage: "chevron.up",
                        help: "Move up"
                    ) {
                        Task {
                            await audioDeviceStore.moveDevice(device.uid, kind: kind, offset: -1)
                        }
                    }
                }

                if canMoveDown {
                    inlineSelectedActionButton(
                        systemImage: "chevron.down",
                        help: "Move down"
                    ) {
                        Task {
                            await audioDeviceStore.moveDevice(device.uid, kind: kind, offset: 1)
                        }
                    }
                }

                inlineSelectedActionButton(
                    systemImage: "xmark",
                    help: "Exclude from AudioUtility"
                ) {
                    Task {
                        await audioDeviceStore.setDeviceExcluded(true, for: device.uid, kind: kind)
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(isHovered: isHovered, isSelected: isSelected))
        .onHover { isHovering in
            hoveredOrderedDeviceID = isHovering ? device.id : nil
        }
    }

    @ViewBuilder
    private func preferredRowActions(device: ManagedAudioDevice, kind: AudioDeviceKind) -> some View {
        let canMoveUp = audioDeviceStore.canMoveDevice(device.uid, kind: kind, offset: -1)
        let canMoveDown = audioDeviceStore.canMoveDevice(device.uid, kind: kind, offset: 1)

        Button("Move Up", systemImage: "chevron.up") {
            Task {
                await audioDeviceStore.moveDevice(device.uid, kind: kind, offset: -1)
            }
        }
        .disabled(!canMoveUp)

        Button("Move Down", systemImage: "chevron.down") {
            Task {
                await audioDeviceStore.moveDevice(device.uid, kind: kind, offset: 1)
            }
        }
        .disabled(!canMoveDown)

        Divider()

        Button("Exclude from AudioUtility", systemImage: "xmark.circle") {
            Task {
                await audioDeviceStore.setDeviceExcluded(true, for: device.uid, kind: kind)
            }
        }
    }

    private func excludedDisclosure(
        kind: AudioDeviceKind,
        devices: [ManagedAudioDevice]
    ) -> some View {
        let isExpanded = expandedExcludedKinds.contains(kind)

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                let binding = excludedDisclosureBinding(for: kind)
                binding.wrappedValue.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    Text("Excluded")

                    Spacer()

                    Text("\(devices.count)")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(devices, id: \.id) { device in
                        excludedRow(device: device, kind: kind)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func excludedRow(
        device: ManagedAudioDevice,
        kind: AudioDeviceKind
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(width: 16, alignment: .center)

            Text(device.name)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Include") {
                Task {
                    await audioDeviceStore.setDeviceExcluded(false, for: device.uid, kind: kind)
                }
            }
            .buttonStyle(.borderless)
            .disabled(audioDeviceStore.isLoading)
        }
        .font(.caption)
        .padding(.leading, 2)
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            popoverRow(
                title: "Settings",
                systemImage: "gearshape",
                action: .settings,
                popover: .settings
            ) {
                settingsPopover
            }

            popoverRow(
                title: "About",
                systemImage: "info.circle",
                action: .about,
                popover: .about
            ) {
                aboutPopover
            }

            actionRow(
                title: "Quit",
                systemImage: "power",
                action: .quit
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var settingsPopover: some View {
        AppSettingsPopoverView(updater: updater)
            .padding(.vertical, 2)
            .onHover { isHovering in
                handlePopoverContentHover(.settings, isHovering: isHovering)
            }
            .onDisappear {
                resetPopoverHoverState(for: .settings)
            }
    }

    private var aboutPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let repositoryURL {
                actionRow(
                    title: "View on GitHub",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    action: .github
                ) {
                    activePopover = nil
                    openURL(repositoryURL)
                }
            }

            if let websiteURL {
                actionRow(
                    title: "View developer website",
                    systemImage: "globe",
                    action: .website
                ) {
                    activePopover = nil
                    openURL(websiteURL)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 220)
        .onHover { isHovering in
            handlePopoverContentHover(.about, isHovering: isHovering)
        }
        .onDisappear {
            resetPopoverHoverState(for: .about)
        }
    }

    private func popoverRow<Content: View>(
        title: String,
        systemImage: String,
        action: MenuBarAction,
        popover: FooterPopover,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        actionRow(
            title: title,
            systemImage: systemImage,
            action: action,
            accessorySystemImage: "chevron.right",
            isActive: activePopover == popover
        ) {
            activePopover = activePopover == popover ? nil : popover
        }
        .onHover { isHovering in
            handlePopoverRowHover(popover, isHovering: isHovering)
        }
        .popover(isPresented: popoverBinding(for: popover), attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            content()
        }
    }

    private func actionRow(
        title: String,
        systemImage: String,
        action: MenuBarAction,
        accessorySystemImage: String? = nil,
        isActive: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredAction == action

        return Button {
            perform()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)

                Text(title)

                Spacer()

                if let accessorySystemImage {
                    Image(systemName: accessorySystemImage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isHovered || isActive {
                    Color.accentColor.opacity(0.12)
                        .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredAction = isHovering ? action : nil
        }
    }

    private func popoverBinding(for popover: FooterPopover) -> Binding<Bool> {
        Binding {
            activePopover == popover
        } set: { isPresented in
            if isPresented {
                activePopover = popover
            } else if activePopover == popover {
                activePopover = nil
            }
        }
    }

    private func showPopover(_ popover: FooterPopover) {
        popoverDismissTask?.cancel()
        popoverDismissTask = nil
        activePopover = popover
    }

    private func handlePopoverRowHover(_ popover: FooterPopover, isHovering: Bool) {
        popoverDismissTask?.cancel()
        popoverDismissTask = nil

        if isHovering {
            hoveredPopoverRow = popover
            if hoveredPopoverContent != popover {
                hoveredPopoverContent = nil
            }
            showPopover(popover)
            return
        }

        if hoveredPopoverRow == popover {
            hoveredPopoverRow = nil
        }
        updatePopoverHoverState(for: popover)
    }

    private func handlePopoverContentHover(_ popover: FooterPopover, isHovering: Bool) {
        popoverDismissTask?.cancel()
        popoverDismissTask = nil

        if isHovering {
            hoveredPopoverContent = popover
            showPopover(popover)
            return
        }

        if hoveredPopoverContent == popover {
            hoveredPopoverContent = nil
        }
        updatePopoverHoverState(for: popover)
    }

    private func resetPopoverHoverState(for popover: FooterPopover) {
        if hoveredPopoverContent == popover {
            hoveredPopoverContent = nil
        }
        if hoveredPopoverRow == popover {
            hoveredPopoverRow = nil
        }
        popoverDismissTask?.cancel()
        popoverDismissTask = nil
    }

    private func updatePopoverHoverState(for popover: FooterPopover) {
        let isHoveringPopover = hoveredPopoverRow == popover || hoveredPopoverContent == popover
        if isHoveringPopover {
            showPopover(popover)
            return
        }

        guard activePopover == popover else {
            return
        }

        popoverDismissTask?.cancel()
        popoverDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else {
                return
            }

            if hoveredPopoverRow != popover,
                hoveredPopoverContent != popover,
                activePopover == popover
            {
                activePopover = nil
            }
        }
    }

    private func currentDeviceName(for kind: AudioDeviceKind) -> String {
        if let selectedDevice = audioDeviceStore.selectedDevice(for: kind) {
            return selectedDevice.name
        }

        return "No active \(kind.title.lowercased()) device"
    }

    private func sectionStatusText(for kind: AudioDeviceKind) -> String? {
        if audioDeviceStore.isManualSelectionActive(for: kind) {
            return "Saved order resumes after relaunch or disconnect."
        }

        return nil
    }

    private func orderedDevices(for kind: AudioDeviceKind) -> [ManagedAudioDevice] {
        audioDeviceStore.managedOrderedDevices(for: kind)
    }

    private func excludedDevices(for kind: AudioDeviceKind) -> [ManagedAudioDevice] {
        audioDeviceStore.managedExcludedDevices(for: kind)
    }

    private func excludedDisclosureBinding(for kind: AudioDeviceKind) -> Binding<Bool> {
        Binding {
            expandedExcludedKinds.contains(kind)
        } set: { isExpanded in
            if isExpanded {
                expandedExcludedKinds.insert(kind)
            } else {
                expandedExcludedKinds.remove(kind)
            }
        }
    }

    private func rankBadge(index: Int, isSelected: Bool) -> some View {
        Text("\(index + 1)")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: 22, height: 22)
            .background(
                (isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06)),
                in: Circle()
            )
    }

    private func preferredRowSubtitle(
        for device: ManagedAudioDevice,
        index: Int,
        kind: AudioDeviceKind
    ) -> String? {
        if !device.isAvailable {
            return "Unavailable"
        }

        if device.isDefault, audioDeviceStore.isManualSelectionActive(for: kind) {
            return "Current for this run"
        }

        if device.isDefault {
            return "Current device"
        }

        if index == 0 {
            return "Top fallback"
        }

        return nil
    }

    private func rowBackground(isHovered: Bool, isSelected: Bool) -> some ShapeStyle {
        if isSelected {
            return Color.accentColor.opacity(0.14)
        }

        if isHovered {
            return Color.primary.opacity(0.07)
        }

        return Color.primary.opacity(0.04)
    }

    private func toolbarButton(
        systemImage: String,
        help: String,
        isActive: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        Button {
            perform()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 14, height: 14)
                .padding(4)
                .contentShape(.rect)
                .background {
                    if isActive {
                        Color.accentColor.opacity(0.14)
                            .clipShape(.rect(cornerRadius: 7))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func inlineSelectedActionButton(
        systemImage: String,
        help: String,
        perform: @escaping () -> Void
    ) -> some View {
        Button {
            perform()
        } label: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 20, height: 20)
                .background(
                    Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(audioDeviceStore.isLoading)
        .help(help)
    }

    private func changeSelection(to device: AudioDevice) async {
        switch device.kind {
        case .input:
            await audioDeviceStore.changeInput(to: device)
        case .output:
            await audioDeviceStore.changeOutput(to: device)
        }
    }
}

extension MenuBarContentView {
    fileprivate enum MenuBarAction {
        case settings
        case about
        case github
        case website
        case quit
    }

    fileprivate enum FooterPopover {
        case settings
        case about
    }
}

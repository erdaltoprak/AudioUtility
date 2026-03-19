import SwiftUI

@MainActor
struct AppSettingsPopoverView: View {
    let updater: any AppUpdaterProviding
    @State private var loginLaunchController = LoginLaunchController.shared
    @State private var openAtLogin = LoginLaunchController.shared.isOpenAtLoginEnabled
    @State private var isUpdatingOpenAtLogin = false
    @State private var loginLaunchErrorMessage: String?
    @AppStorage(.autoUpdateEnabledKey) private var autoUpdateEnabled = true
    @State private var hasSyncedUpdaterPreference = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Settings")
                .font(.headline)

            Toggle("Open at Login", isOn: openAtLoginBinding)
                .disabled(isUpdatingOpenAtLogin)

            Text(openAtLoginDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if loginLaunchController.needsApproval {
                Button("Open Login Items Settings") {
                    loginLaunchController.openLoginItemsSettings()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Updates")
                    .font(.headline)

                Toggle("Check for updates automatically", isOn: $autoUpdateEnabled)

                Button("Check for Updates…", action: checkForUpdates)
                    .disabled(!updater.isAvailable)

                if let availabilityDescription = updater.availabilityDescription {
                    Text(availabilityDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 260)
        .task {
            syncOpenAtLoginState()
        }
        .onAppear(perform: syncUpdaterPreferenceIfNeeded)
        .onChange(of: autoUpdateEnabled) { _, newValue in
            updater.automaticallyChecksForUpdates = newValue
        }
        .alert("Open at Login", isPresented: loginLaunchErrorIsPresented) {
            Button("OK", role: .cancel) {
                loginLaunchErrorMessage = nil
            }
        } message: {
            Text(loginLaunchErrorMessage ?? "AudioUtility could not update the login item setting.")
        }
    }

    private var openAtLoginBinding: Binding<Bool> {
        Binding(
            get: { openAtLogin },
            set: { newValue in
                let previousValue = openAtLogin
                openAtLogin = newValue
                isUpdatingOpenAtLogin = true

                Task { @MainActor in
                    defer { isUpdatingOpenAtLogin = false }

                    do {
                        try loginLaunchController.setOpenAtLoginEnabled(newValue)
                        syncOpenAtLoginState()
                    } catch {
                        openAtLogin = previousValue
                        loginLaunchErrorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    private var loginLaunchErrorIsPresented: Binding<Bool> {
        Binding(
            get: { loginLaunchErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    loginLaunchErrorMessage = nil
                }
            }
        )
    }

    private var openAtLoginDescription: String {
        if loginLaunchController.needsApproval {
            return "macOS needs your approval in System Settings before AudioUtility can launch automatically."
        }

        if openAtLogin {
            return "AudioUtility will launch automatically and stay available from the menu bar."
        }

        return "AudioUtility only launches when you open it yourself."
    }

    private func syncOpenAtLoginState() {
        loginLaunchController.refreshStatus()
        openAtLogin = loginLaunchController.isOpenAtLoginEnabled
    }

    private func syncUpdaterPreferenceIfNeeded() {
        guard !hasSyncedUpdaterPreference else { return }
        updater.automaticallyChecksForUpdates = autoUpdateEnabled
        hasSyncedUpdaterPreference = true
    }

    private func checkForUpdates() {
        updater.checkForUpdates()
    }
}

#Preview {
    AppSettingsPopoverView(updater: DisabledAppUpdater())
}

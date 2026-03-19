import SwiftUI

struct AudioUtilityOnboardingView: View {
    @AppStorage(.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var loginLaunchController = LoginLaunchController.shared
    @State private var openAtLogin = LoginLaunchController.shared.isOpenAtLoginEnabled
    @State private var isUpdatingOpenAtLogin = false
    @State private var loginLaunchErrorMessage: String?
    @State private var featureCardHeight: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.12),
                    Color.cyan.opacity(0.08),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroCard
                    featureRow
                    menuBarCard
                    launchCard
                    actionRow
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(.background)
        .task {
            syncOpenAtLoginState()
        }
        .alert("Open at Login", isPresented: loginLaunchErrorIsPresented) {
            Button("OK", role: .cancel) {
                loginLaunchErrorMessage = nil
            }
        } message: {
            Text(loginLaunchErrorMessage ?? "AudioUtility could not update the login item setting.")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.indigo.opacity(0.85),
                                    Color.cyan.opacity(0.75),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "poweroutlet.type.f")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 68, height: 68)
                .shadow(color: .indigo.opacity(0.18), radius: 18, y: 10)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to AudioUtility")
                        .font(.system(size: 28, weight: .bold))

                    Text(
                        "AudioUtility lets you switch input and output devices, keep a saved fallback order, and exclude devices you never want used automatically."
                    )
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(cardBorder(cornerRadius: 24))
    }

    private var featureRow: some View {
        HStack(alignment: .top, spacing: 14) {
            OnboardingFeatureCard(
                title: "Switch Defaults",
                detail: "Choose your current input or output device in one click.",
                systemImage: "arrow.left.arrow.right.circle",
                tint: .indigo,
                minHeight: featureCardHeight
            )
            .background(featureCardHeightReader)

            OnboardingFeatureCard(
                title: "Manage Priorities",
                detail:
                    "Set the fallback order and exclude devices you never want AudioUtility to choose after relaunch or disconnects.",
                systemImage: "slider.horizontal.3",
                tint: .green,
                minHeight: featureCardHeight
            )
            .background(featureCardHeightReader)
        }
        .onPreferenceChange(OnboardingFeatureCardHeightKey.self) { featureCardHeight = $0 }
    }

    private var menuBarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 32, height: 32)
                    .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Lives in your menu bar")
                        .font(.headline)

                    Text(
                        "After setup, click the AudioUtility icon in the menu bar to switch devices now or adjust the saved fallback order."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardBorder(cornerRadius: 22))
    }

    private var launchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Launch Behavior")
                .font(.title3.weight(.semibold))

            Text(
                "Open at Login is optional and stays off until you enable it. You can change this later from App Settings."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle("Open at Login", isOn: openAtLoginBinding)
                .disabled(isUpdatingOpenAtLogin)

            Text(openAtLoginDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if loginLaunchController.needsApproval {
                Button("Open Login Items Settings") {
                    loginLaunchController.openLoginItemsSettings()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardBorder(cornerRadius: 22))
    }

    private var actionRow: some View {
        HStack {
            Spacer(minLength: 0)

            Button("Continue in Menu Bar") {
                hasCompletedOnboarding = true
                dismissWindow(id: AppSceneID.onboarding)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
            return "AudioUtility will launch at login and stay available from the menu bar."
        }

        return "AudioUtility only launches when you open it yourself."
    }

    private var cardBackground: some ShapeStyle {
        Color.primary.opacity(0.035)
    }

    private var featureCardHeightReader: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: OnboardingFeatureCardHeightKey.self, value: geometry.size.height)
        }
    }

    private func cardBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.08))
    }

    private func syncOpenAtLoginState() {
        loginLaunchController.refreshStatus()
        openAtLogin = loginLaunchController.isOpenAtLoginEnabled
    }
}

private struct OnboardingFeatureCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct OnboardingFeatureCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(title)
                .font(.headline)

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }
}

#Preview {
    AudioUtilityOnboardingView()
}

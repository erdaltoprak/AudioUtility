import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appUpdater: any AppUpdaterProviding = makeAppUpdater()
    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !defaults.bool(forKey: .hasCompletedOnboardingKey) else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            activateIgnoringOtherApps()
        }
    }

    private func activateIgnoringOtherApps() {
        _ = NSApp.perform(NSSelectorFromString("activateIgnoringOtherApps:"), with: true as NSNumber)
    }
}

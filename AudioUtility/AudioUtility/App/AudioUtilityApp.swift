//
//  AudioUtilityApp.swift
//  AudioUtility
//
//  Created by Erdal Toprak on 08/12/2025.
//

import SwiftUI

@main
struct AudioUtilityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @State private var audioDeviceStore = AudioDeviceStore()

    var body: some Scene {
        Window("Welcome to AudioUtility", id: AppSceneID.onboarding) {
            AudioUtilityOnboardingView()
        }
        .defaultSize(width: 1400, height: 800)
        .defaultLaunchBehavior(hasCompletedOnboarding ? .suppressed : .presented)
        .restorationBehavior(.disabled)

        MenuBarExtra("AudioUtility", systemImage: "poweroutlet.type.f") {
            MenuBarContentView(
                audioDeviceStore: audioDeviceStore,
                updater: appDelegate.appUpdater
            )
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appDelegate.appUpdater.checkForUpdates()
                }
                .disabled(!appDelegate.appUpdater.isAvailable)
            }
            CommandGroup(replacing: .appSettings) {}
            CommandGroup(replacing: .newItem) {}
        }
    }
}

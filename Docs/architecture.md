# AudioUtility Architecture

AudioUtility is a small macOS menu bar app for switching the system’s default input and output audio devices. It wraps CoreAudio in a focused SwiftUI interface so common device changes do not require opening System Settings.

## High-Level Design

- **Platform:** native macOS app using the SwiftUI app lifecycle.
- **Primary UI:** `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
- **Launch flow:** a separate onboarding `Window` appears until first-run setup is complete, then the app lives in the menu bar.
- **Data flow:** a single shared `@MainActor @Observable` `AudioDeviceStore` drives the UI and talks to a CoreAudio-backed service.
- **Automatic observation:** CoreAudio listeners trigger refreshes when the device list or system defaults change.
- **Preference-aware switching:** the app persists fallback ordering and exclusions separately for input and output devices, while allowing runtime manual selection.
- **Distribution:** direct distribution with Sparkle for in-app updates.

## Project Structure

- `AudioUtility/App`
  - App entry point, onboarding, login item control, updater wiring.
- `AudioUtility/Audio/Models`
  - Lightweight models such as `AudioDevice` and `ManagedAudioDevice`.
- `AudioUtility/Audio/Preferences`
  - Persisted device ordering, exclusion, and known-device metadata.
- `AudioUtility/Audio/Services`
  - CoreAudio access, listeners, and observation events.
- `AudioUtility/Audio/Store`
  - Main-actor observable state used by SwiftUI.
- `AudioUtility/Features/MenuBar`
  - Menu bar content, device management, app settings, and about UI.

## Core Components

### App Shell

- `AudioUtilityApp`
  - Owns the shared `AudioDeviceStore`.
  - Declares the onboarding window and the menu bar scene.
  - Adds the app-menu `Check for Updates…` command.
- `AppDelegate`
  - Handles first-launch activation behavior.
  - Creates the Sparkle updater controller.
- `AppUpdater`
  - Wraps Sparkle behind a small app-facing protocol.
  - Disables update checks automatically for unsupported builds, missing config, or non-Developer-ID signing.

### Audio Layer

- `AudioDeviceService`
  - Reads available devices, current defaults, and applies default-device changes.
- `AudioDeviceObservation`
  - Owns CoreAudio listener registrations and emits device/default change events.
- `AudioDevicePreferences`
  - Persists preferred order, exclusions, and remembered device names.
- `AudioDeviceStore`
  - Holds menu bar state such as devices, selected defaults, loading state, and error state.
  - Applies refresh policy, runtime manual selection, and fallback-order enforcement.

## UI Layer

- `MenuBarContentView`
  - Shows stacked output and input device lists, refresh state, edit mode, and footer actions.
  - Lets the user switch devices immediately, edit fallback order inline, and expand excluded devices inline.
- `AppSettingsPopoverView`
  - Controls Open at Login and Sparkle update preferences.
- About popover
  - Provides repository and website links from the menu bar footer.
- `OnboardingView`
  - Introduces the app and optionally configures Open at Login before the app settles into the menu bar.

## Data Flow Summary

1. `AudioUtilityApp` creates `AudioDeviceStore` and injects it into the menu bar UI.
2. `MenuBarContentView` requests refreshes when needed and forwards selection, reordering, and exclusion actions to the store.
3. `AudioDeviceStore` uses `AudioDeviceService` to fetch devices, read defaults, and apply changes.
4. `AudioDevicePreferences` keeps fallback ordering and exclusion rules stable across relaunches and reconnects.
5. `AudioDeviceObservation` reports CoreAudio changes back to the store.
6. The store updates observable state on the main actor, and SwiftUI refreshes the menu bar UI automatically.

This keeps CoreAudio details isolated, centralizes selection policy in one store, and preserves the lightweight menu bar-first shape of the app while separating immediate user choice from saved fallback behavior.

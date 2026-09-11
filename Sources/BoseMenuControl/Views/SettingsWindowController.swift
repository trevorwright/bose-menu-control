import AppKit
import SwiftUI

/// Hosts the settings window.
///
/// The app is an accessory with no main scene, so the window is built in AppKit and created on
/// demand rather than declared as a SwiftUI `Settings`/`Window` scene, which would either be
/// unreachable without an app menu or open by itself at launch.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private let launchAtLogin = LaunchAtLogin()
    private var window: NSWindow?

    private init() {}

    func show() {
        // Picks up a change made in System Settings while the window was closed.
        launchAtLogin.refresh()

        let window = self.window ?? {
            let created = makeWindow()
            created.center()
            self.window = created
            return created
        }()

        // An accessory app is never the active app, so the window opens behind everything
        // else unless the app is activated first.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: SettingsView(launchAtLogin: launchAtLogin)
        ))
        window.title = "Bose Menu Control Settings"
        window.styleMask = [.titled, .closable]
        // The controller outlives the window, so keep the instance around for the next open.
        window.isReleasedWhenClosed = false
        return window
    }
}

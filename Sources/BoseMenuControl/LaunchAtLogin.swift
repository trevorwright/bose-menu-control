import Foundation
import ServiceManagement

/// Wraps the login-item registration for the app bundle itself.
///
/// `SMAppService` registers a bundle, so this only works for `BoseMenuControl.app`; the bare
/// executable that `make dev` builds has nothing to register and reports `isSupported == false`.
@MainActor
final class LaunchAtLogin: ObservableObject {
    enum State: Equatable {
        case on
        case off
        /// Registered, but the user has to allow it in System Settings > General > Login Items.
        case needsApproval
        /// Not running from an .app bundle, so there is nothing macOS can launch.
        case unsupported
    }

    @Published private(set) var state: State = .off
    @Published private(set) var lastError: String?

    private let isBundled = Bundle.main.bundleURL.pathExtension == "app"

    init() {
        refresh()
    }

    var isSupported: Bool { state != .unsupported }
    var isOn: Bool { state == .on || state == .needsApproval }

    /// Re-reads the live registration so a change made in System Settings shows up here.
    func refresh() {
        guard isBundled else {
            state = .unsupported
            return
        }
        switch SMAppService.mainApp.status {
        case .enabled: state = .on
        case .requiresApproval: state = .needsApproval
        default: state = .off
        }
    }

    func set(_ enabled: Bool) {
        guard isBundled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            // Registering reports success before the status flips, so an optimistic toggle would
            // snap back on the next refresh. Surface the failure instead.
            lastError = error.localizedDescription
            let action = enabled ? "register" : "unregister"
            Log.controller.error("launch at login \(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }
}

import SwiftUI

struct SettingsView: View {
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)

            Toggle("Start at login", isOn: Binding(
                get: { launchAtLogin.isOn },
                set: { launchAtLogin.set($0) }
            ))
            .disabled(!launchAtLogin.isSupported)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
        .frame(minHeight: 140, alignment: .top)
    }

    private var detail: String? {
        if let error = launchAtLogin.lastError { return error }
        switch launchAtLogin.state {
        case .on, .off:
            return "Opens Bose Menu Control in the menu bar when you log in to macOS."
        case .needsApproval:
            return "Allow Bose Menu Control in System Settings > General > Login Items to finish turning this on."
        case .unsupported:
            return "Only available when running the installed app. Run `make install` and launch it from Applications."
        }
    }
}

import SwiftUI

struct PopoverView: View {
    @ObservedObject var controller: HeadphoneController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if controller.isConnected, let headphones = controller.headphones {
                ConnectedView(controller: controller, headphones: headphones)
            } else {
                DisconnectedView(status: controller.status, nearbyUnwornName: controller.nearbyUnwornName)
            }

            Divider()
                .padding(.vertical, 6)

            HStack {
                if let error = controller.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Quit") { controller.quit() }
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 280)
        .onAppear {
            Task { await controller.refresh() }
        }
    }
}

private struct ConnectedView: View {
    @ObservedObject var controller: HeadphoneController
    let headphones: HeadphoneController.Headphones

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(headphones: headphones)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            SectionTitle("Listening mode")
            if headphones.availableModes.isEmpty {
                Text("Loading modes…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            } else {
                ForEach(headphones.availableModes) { mode in
                    OptionRow(
                        title: mode.displayName,
                        symbolName: mode.symbolName,
                        isSelected: headphones.currentMode?.index == mode.index,
                        isDisabled: controller.isBusy
                    ) {
                        Task { await controller.selectMode(mode) }
                    }
                }
                // The device reports mode 0xFF when the live settings no longer match any
                // stored mode, which happens as soon as immersive audio is changed on its
                // own. Show that as a checked "Custom" row so the list always marks what is
                // active. It is a state, not a preset, so it appears only while overridden
                // and never alongside an active mode.
                if headphones.isModeOverridden {
                    OptionRow(
                        title: "Custom",
                        symbolName: "slider.horizontal.3",
                        isSelected: true,
                        isDisabled: false
                    ) {}

                    Text("Settings adjusted; no stored mode is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                }
            }

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            SectionTitle("Immersive audio")
            ForEach(ImmersiveAudioMode.allCases) { option in
                OptionRow(
                    title: option.title,
                    symbolName: option.symbolName,
                    isSelected: headphones.immersiveAudio == option,
                    isDisabled: controller.isBusy || headphones.liveSettings == nil
                ) {
                    Task { await controller.setImmersiveAudio(option) }
                }
            }
        }
    }
}

private struct HeaderView: View {
    let headphones: HeadphoneController.Headphones

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "headphones")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(headphones.name)
                    .font(.headline)
                    .lineLimit(1)
                BatteryLine(battery: headphones.battery)
            }
            Spacer()
        }
    }
}

private struct BatteryLine: View {
    let battery: BatteryStatus?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var text: String {
        guard let battery else { return "Reading battery…" }
        var line = "\(battery.percent)%"
        if let minutes = battery.minutesRemaining {
            line += " · about \(minutes / 60)h \(minutes % 60)m left"
        }
        return line
    }

    private var symbolName: String {
        guard let percent = battery?.percent else { return "battery.0percent" }
        switch percent {
        case 87...: return "battery.100percent"
        case 62...: return "battery.75percent"
        case 37...: return "battery.50percent"
        case 12...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var tint: Color {
        guard let percent = battery?.percent else { return .secondary }
        return percent <= 20 ? .red : .secondary
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 2)
    }
}

private struct OptionRow: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 12)
                    .opacity(isSelected ? 1 : 0)
                Image(systemName: symbolName)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
            }
            .font(.body)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering && !isDisabled ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }
}

private struct DisconnectedView: View {
    let status: HeadphoneController.Status
    let nearbyUnwornName: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "headphones.slash")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
            Text("No headphones connected")
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var detail: String {
        if let nearbyUnwornName {
            return "\(nearbyUnwornName) is nearby but not being worn."
        }
        switch status {
        case .bluetoothUnavailable(let reason): return reason
        case .searching: return "Looking for Bose headphones nearby."
        case .connecting: return "Connecting…"
        case .connected: return "Reading headphone details…"
        }
    }
}

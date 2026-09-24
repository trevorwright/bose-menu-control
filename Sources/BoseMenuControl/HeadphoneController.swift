import AppKit
import Foundation

/// Owns the headphone connection and publishes a snapshot of device state for the UI.
@MainActor
final class HeadphoneController: ObservableObject {
    enum Status: Equatable {
        case bluetoothUnavailable(String)
        case searching
        case connecting
        case connected
    }

    struct Headphones: Equatable {
        var name: String
        var firmwareVersion: String?
        var battery: BatteryStatus?
        var modes: [ListeningMode] = []
        var currentModeIndex: UInt8?
        var liveSettings: LiveAudioSettings?

        /// Available modes with favourites first; slot order is preserved within each group.
        var availableModes: [ListeningMode] {
            let available = modes.filter(\.isAvailable)
            return available.filter(\.isFavorite) + available.filter { !$0.isFavorite }
        }
        var isModeOverridden: Bool { currentModeIndex == ListeningMode.overrideIndex }
        var currentMode: ListeningMode? {
            guard let currentModeIndex, !isModeOverridden else { return nil }
            return modes.first { $0.index == currentModeIndex }
        }
        var immersiveAudio: ImmersiveAudioMode? { liveSettings?.immersiveAudio }
    }

    @Published private(set) var status: Status = .searching
    @Published private(set) var headphones: Headphones?
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?
    /// True while the headphones are present as a macOS audio device, which only happens while worn.
    @Published private(set) var isWorn = false

    private let connection = BoseBLEConnection()
    private let audioMonitor = AudioDeviceMonitor()
    private var pollTask: Task<Void, Never>?
    private let pollInterval: Duration = .seconds(60)

    init() {
        connection.delegate = self
        connection.start()
        audioMonitor.onChange = { [weak self] in self?.updateWornState() }
        audioMonitor.start()
    }

    /// Connected for UI purposes means the control link is up and the headphones are being worn.
    var isConnected: Bool { status == .connected && headphones != nil && isWorn }

    /// The control link is up but the headphones are not being worn.
    var nearbyUnwornName: String? {
        guard status == .connected, let headphones, !isWorn else { return nil }
        return headphones.name
    }

    // MARK: Actions

    func refresh() async {
        guard status == .connected else { return }
        do {
            try await readBattery()
            // A mode load that failed during connect leaves `modes` empty, and the popover
            // shows "Loading modes…" for as long as it stays that way. Retry it here so a
            // transient failure heals on the next poll instead of needing a restart.
            if headphones?.modes.isEmpty ?? false {
                try await readModes()
            }
            try await readCurrentMode()
            try await readLiveSettings()
            lastError = nil
        } catch {
            report(error)
        }
    }

    func selectMode(_ mode: ListeningMode) async {
        guard status == .connected, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            // START with payload [slot, voicePrompt]; 0 keeps the headphones from announcing the change.
            let reply = try await connection.exchange(BMAPPacket(.currentMode, operation: .start, payload: [mode.index, 0]))
            apply(reply)
            try await readCurrentMode()
            try await readLiveSettings()
            lastError = nil
        } catch {
            report(error)
        }
    }

    func setImmersiveAudio(_ target: ImmersiveAudioMode) async {
        guard status == .connected, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            // Read the live register first so the other four fields are preserved exactly.
            var settings = try await readLiveSettings()
            settings.immersiveAudioRaw = target.rawValue
            let reply = try await connection.exchange(BMAPPacket(.liveAudioSettings, operation: .setGet, payload: settings.payload))
            apply(reply)
            try await readCurrentMode()
            lastError = nil
        } catch {
            report(error)
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Loading

    private func loadHeadphones(name: String?) async {
        headphones = Headphones(name: name ?? "Bose headphones")
        do {
            let deviceName = String(bmapDeviceName: try await connection.get(.deviceName))
            if !deviceName.isEmpty { headphones?.name = deviceName }
            updateWornState()
            headphones?.firmwareVersion = String(bmapPayload: try await connection.get(.firmwareVersion))
            try await readBattery()
            try await readModes()
            try await readCurrentMode()
            try await readLiveSettings()
            lastError = nil
            Log.controller.notice("Loaded \(self.headphones?.name ?? "?", privacy: .public): battery \(self.headphones?.battery?.percent ?? -1) mode \(self.headphones?.currentModeIndex ?? 0xFE) modes \(self.headphones?.availableModes.count ?? 0)")
        } catch {
            report(error)
        }
        startPolling()
    }

    private func readBattery() async throws {
        let payload = try await connection.get(.batteryStatus)
        guard let battery = BatteryStatus(payload: payload) else { throw BMAPError.malformedReply(.batteryStatus) }
        headphones?.battery = battery
    }

    /// Reads mode capabilities and every stored slot, with one retry.
    ///
    /// The exchanges immediately after `ready` can be slow enough to hit the request
    /// timeout while the link is still settling, and this is the one call whose failure
    /// is visible as a permanently stuck "Loading modes…".
    private func readModes() async throws {
        do {
            try await readModesOnce()
        } catch {
            Log.controller.notice("Retrying mode load after \(String(describing: error), privacy: .public)")
            try await readModesOnce()
        }
    }

    private func readModesOnce() async throws {
        let payload = try await connection.get(.modeCapabilities)
        guard let capabilities = ModeCapabilities(payload: payload), (1...32).contains(capabilities.totalSlots) else {
            throw BMAPError.malformedReply(.modeCapabilities)
        }
        var modes: [ListeningMode] = []
        for slot in 0..<capabilities.totalSlots {
            let slotPayload = try await connection.get(.modeConfig, payload: [UInt8(slot)])
            if let mode = ListeningMode(payload: slotPayload) {
                modes.append(mode)
            }
        }
        headphones?.modes = modes
    }

    private func readCurrentMode() async throws {
        let payload = try await connection.get(.currentMode)
        guard let index = payload.first else { throw BMAPError.malformedReply(.currentMode) }
        headphones?.currentModeIndex = index
    }

    @discardableResult
    private func readLiveSettings() async throws -> LiveAudioSettings {
        let payload = try await connection.get(.liveAudioSettings)
        guard let settings = LiveAudioSettings(payload: payload) else { throw BMAPError.malformedReply(.liveAudioSettings) }
        headphones?.liveSettings = settings
        return settings
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(60))
                guard !Task.isCancelled, let self else { return }
                await refresh()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Applies any STATUS or RESULT packet to the snapshot, including unsolicited updates such as a
    /// mode change made with the headphone buttons.
    private func apply(_ packet: BMAPPacket) {
        guard headphones != nil, let operation = packet.operation else { return }
        switch (packet.function, operation) {
        case (.batteryStatus, .status):
            if let battery = BatteryStatus(payload: packet.payload) { headphones?.battery = battery }
        case (.currentMode, .status), (.currentMode, .result):
            if let index = packet.payload.first { headphones?.currentModeIndex = index }
        case (.liveAudioSettings, .status):
            if let settings = LiveAudioSettings(payload: packet.payload) { headphones?.liveSettings = settings }
        case (.modeConfig, .status):
            if let mode = ListeningMode(payload: packet.payload),
               let slot = headphones?.modes.firstIndex(where: { $0.index == mode.index }) {
                headphones?.modes[slot] = mode
            }
        default:
            break
        }
    }

    private func updateWornState() {
        let name = headphones?.name ?? connection.peripheralName
        let worn = name.map { audioMonitor.hasDevice(named: $0) } ?? false
        guard worn != isWorn else { return }
        isWorn = worn
        Log.controller.notice("Worn: \(worn) (audio devices: \(self.audioMonitor.bluetoothDeviceNames.sorted().joined(separator: ", "), privacy: .public))")
    }

    private func report(_ error: Error) {
        Log.controller.error("\(String(describing: error), privacy: .public)")
        if case BMAPError.notConnected = error { return }
        lastError = error.localizedDescription
    }
}

extension HeadphoneController: BoseBLEConnectionDelegate {
    func connection(_ connection: BoseBLEConnection, didChangePhase phase: BoseBLEConnection.Phase) {
        switch phase {
        case .bluetoothUnavailable(let reason):
            stopPolling()
            headphones = nil
            status = .bluetoothUnavailable(reason)
        case .searching:
            stopPolling()
            headphones = nil
            status = .searching
        case .connecting:
            stopPolling()
            headphones = nil
            status = .connecting
        case .ready(let name):
            status = .connected
            lastError = nil
            updateWornState()
            Task { await loadHeadphones(name: name) }
        }
    }

    func connection(_ connection: BoseBLEConnection, didReceive packet: BMAPPacket) {
        apply(packet)
    }
}

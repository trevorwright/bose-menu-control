import CoreAudio
import Foundation

/// Watches CoreAudio for Bluetooth audio devices.
///
/// Bose headphones keep their low-energy control link up whenever they are nearby, but only bring up
/// the classic audio link while they are being worn. The headphones therefore appear as a macOS audio
/// device exactly while worn, which makes CoreAudio the wear signal the app uses.
@MainActor
final class AudioDeviceMonitor {
    private(set) var bluetoothDeviceNames: Set<String> = []
    var onChange: (() -> Void)?

    private var listener: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        listener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        refresh()
    }

    func refresh() {
        let names = Set(
            Self.currentDevices()
                .filter { $0.transport == kAudioDeviceTransportTypeBluetooth || $0.transport == kAudioDeviceTransportTypeBluetoothLE }
                .map(\.name)
        )
        guard names != bluetoothDeviceNames else { return }
        bluetoothDeviceNames = names
        onChange?()
    }

    func hasDevice(named name: String) -> Bool {
        Self.contains(bluetoothDeviceNames, name: name)
    }

    nonisolated static func contains(_ names: Set<String>, name: String) -> Bool {
        names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private nonisolated static func currentDevices() -> [(name: String, transport: UInt32)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr,
                  let name = name?.takeUnretainedValue() else { return nil }

            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var transport: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transport) == noErr else { return nil }
            return (name as String, transport)
        }
    }
}

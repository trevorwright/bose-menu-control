import Foundation

/// Immersive audio (spatial audio) setting, byte 2 of the live audio settings payload.
enum ImmersiveAudioMode: UInt8, CaseIterable, Identifiable, Sendable {
    case off = 0
    case still = 1
    case motion = 2

    var id: UInt8 { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .still: return "Still"
        case .motion: return "Motion"
        }
    }

    var symbolName: String {
        switch self {
        case .off: return "circle.slash"
        case .still: return "figure.stand"
        case .motion: return "figure.walk"
        }
    }
}

/// Live audio settings register, block 31 function 10. Five bytes: CNC level, auto CNC, immersive audio, wind block, ANC.
struct LiveAudioSettings: Equatable, Sendable {
    var cncLevel: UInt8
    var autoCNC: UInt8
    var immersiveAudioRaw: UInt8
    var windBlock: UInt8
    var anc: UInt8

    init?(payload: [UInt8]) {
        guard payload.count == 5 else { return nil }
        cncLevel = payload[0]
        autoCNC = payload[1]
        immersiveAudioRaw = payload[2]
        windBlock = payload[3]
        anc = payload[4]
    }

    var payload: [UInt8] { [cncLevel, autoCNC, immersiveAudioRaw, windBlock, anc] }

    var immersiveAudio: ImmersiveAudioMode? { ImmersiveAudioMode(rawValue: immersiveAudioRaw) }
}

/// Battery status, block 2 function 2. Four bytes per component: percent, minutes remaining (big endian, 0xFFFF unknown), component ID.
struct BatteryStatus: Equatable, Sendable {
    let percent: Int
    let minutesRemaining: Int?

    init?(payload: [UInt8]) {
        guard payload.count >= 1 else { return nil }
        percent = min(100, Int(payload[0]))
        if payload.count >= 3 {
            let minutes = Int(payload[1]) << 8 | Int(payload[2])
            minutesRemaining = minutes == 0xFFFF ? nil : minutes
        } else {
            minutesRemaining = nil
        }
    }
}

/// Mode capabilities, block 31 function 2: number of Bose built-in modes and number of user slots.
struct ModeCapabilities: Equatable, Sendable {
    let boseModeCount: Int
    let userModeCount: Int

    init?(payload: [UInt8]) {
        guard payload.count >= 2 else { return nil }
        boseModeCount = Int(payload[0])
        userModeCount = Int(payload[1])
    }

    var totalSlots: Int { boseModeCount + userModeCount }
}

/// A stored listening mode slot, block 31 function 6. 48-byte payload.
struct ListeningMode: Identifiable, Equatable, Sendable {
    /// The device reports this index when live settings no longer match any stored mode.
    static let overrideIndex: UInt8 = 0xFF

    let index: UInt8
    let promptID: UInt16
    let isUserConfigurable: Bool
    let isConfigured: Bool
    let isFavorite: Bool
    /// Name string as stored on the device. User slots report "None" when unnamed.
    let storedName: String
    let settings: LiveAudioSettings?

    var id: UInt8 { index }

    init?(payload: [UInt8]) {
        guard payload.count >= 38 else { return nil }
        index = payload[0]
        promptID = UInt16(payload[1]) << 8 | UInt16(payload[2])
        isUserConfigurable = payload[3] != 0
        isConfigured = payload[4] != 0
        isFavorite = payload[5] != 0
        storedName = String(decoding: payload[6..<38].prefix(while: { $0 != 0 }), as: UTF8.self)
        if payload.count >= 48 {
            settings = LiveAudioSettings(payload: [payload[42], payload[43], payload[44], payload[46], payload[47]])
        } else {
            settings = nil
        }
    }

    /// Built-in modes are always available. User slots only count once the user has configured them.
    var isAvailable: Bool { !isUserConfigurable || isConfigured }

    /// Prefers a real custom name, falls back to the Bose prompt name, then to the slot number.
    var displayName: String {
        let trimmed = storedName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed.caseInsensitiveCompare("None") != .orderedSame {
            return trimmed
        }
        if let promptName = BosePrompt.name(for: promptID) {
            return promptName
        }
        return "Mode \(index + 1)"
    }

    var symbolName: String {
        switch BosePrompt.name(for: promptID) ?? displayName {
        case "Quiet": return "moon.fill"
        case "Aware", "Transparent", "Transparency": return "ear.badge.waveform"
        case "Immersion": return "waveform"
        case "Cinema": return "film"
        case "Focus", "Work", "Learn": return "scope"
        case "Commute", "Airport", "Flight", "Driving": return "tram.fill"
        case "Workout", "Gym", "Run", "Training": return "figure.run"
        case "Walk", "Hike", "Outdoor": return "figure.walk"
        case "Sleep", "Relax", "Calm", "Meditate", "Yoga": return "bed.double.fill"
        case "Music", "Stereo": return "music.note"
        case "Podcast", "Audiobook": return "book.fill"
        case "Talk", "Call": return "phone.fill"
        default: return "slider.horizontal.3"
        }
    }
}

/// Bose voice prompt IDs reported in a mode slot. The device stores "None" as the name for user modes
/// that use a Bose preset name, so the prompt ID is the reliable label.
enum BosePrompt {
    private static let names: [UInt16: String] = [
        1: "Quiet", 2: "Aware", 3: "Transparent", 4: "Transparency", 5: "Masking", 6: "Comfort",
        7: "Commute", 8: "Outdoor", 9: "Workout", 10: "Home", 11: "Work", 12: "Music", 13: "Focus",
        14: "Relax", 15: "Flight", 16: "Airport", 17: "Driving", 18: "Training", 19: "Gym", 20: "Run",
        21: "Walk", 22: "Hike", 23: "Talk", 24: "Call", 25: "Whisper", 26: "Hearing", 27: "Learn",
        28: "Podcast", 29: "Audiobook", 30: "Calm", 31: "Sleep", 32: "Meditate", 33: "Yoga",
        34: "Immersion", 35: "Stereo", 36: "Cinema",
    ]

    static func name(for id: UInt16) -> String? { names[id] }
}

extension String {
    /// Device-name replies can prefix the text with 0x00 or 0x01; neither is part of the name.
    init(bmapDeviceName payload: [UInt8]) {
        let text = payload.first == 0 || payload.first == 1 ? Array(payload.dropFirst()) : payload
        self.init(bmapPayload: text)
    }

    /// Decodes a BMAP string payload. Some replies lead with a zero flag byte before the text.
    init(bmapPayload payload: [UInt8]) {
        self = String(decoding: payload.drop(while: { $0 == 0 }).prefix(while: { $0 != 0 }), as: UTF8.self)
    }
}

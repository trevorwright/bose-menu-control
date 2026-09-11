import Foundation
import Testing
@testable import BoseMenuControl

/// Byte sequences below are copied from the recorded BLE sessions with QuietComfort Ultra Headphones (2nd Gen).
struct BMAPTests {
    private func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    @Test func testGetFrameEncoding() {
        let packet = BMAPPacket(.modeConfig, operation: .get, payload: [4])
        #expect(packet.frame == bytes("1f 06 01 01 04"))
    }

    @Test func testStartFrameEncoding() {
        let packet = BMAPPacket(.currentMode, operation: .start, payload: [1, 0])
        #expect(packet.frame == bytes("1f 03 05 02 01 00"))
    }

    @Test func testFrameParsingRejectsBadLength() {
        #expect(BMAPPacket(frame: bytes("1f 03 03 02 04")) == nil)
        #expect(BMAPPacket(frame: bytes("1f 03 03 01 04")) != nil)
    }

    @Test func testReplyMatching() {
        let get = BMAPPacket(.currentMode, operation: .get)
        let status = BMAPPacket(frame: bytes("1f 03 03 01 04"))!
        let error = BMAPPacket(frame: bytes("01 04 04 01 04"))!
        #expect(status.isReply(to: get))
        #expect(!(error.isReply(to: get)))

        let start = BMAPPacket(.currentMode, operation: .start, payload: [1, 0])
        let result = BMAPPacket(frame: bytes("1f 03 06 01 01"))!
        #expect(result.isReply(to: start))
        #expect(result.operation == .result)
    }

    @Test func testSingleSegmentAssembly() {
        var assembler = BLESegmentAssembler()
        let frame = assembler.consume(Data([0x00] + bytes("02 02 03 04 28 ff ff 00")))
        #expect(frame == bytes("02 02 03 04 28 ff ff 00"))
    }

    @Test func testMultiSegmentAssembly() {
        var assembler = BLESegmentAssembler()
        #expect(assembler.consume(Data([0x10, 0x1f, 0x03])) == nil)
        #expect(assembler.consume(Data([0x11, 0x03, 0x01, 0x04])) == bytes("1f 03 03 01 04"))
    }

    @Test func testOutOfOrderSegmentIsDropped() {
        var assembler = BLESegmentAssembler()
        #expect(assembler.consume(Data([0x11, 0x03, 0x01, 0x04])) == nil)
        #expect(assembler.consume(Data([0x00] + bytes("1f 03 03 01 04"))) == bytes("1f 03 03 01 04"))
    }

    @Test func testBatteryDecoding() {
        let battery = BatteryStatus(payload: bytes("28 ff ff 00"))
        #expect(battery?.percent == 40)
        #expect(battery?.minutesRemaining == nil)

        let withTime = BatteryStatus(payload: bytes("50 00 f0 00"))
        #expect(withTime?.percent == 80)
        #expect(withTime?.minutesRemaining == 240)
    }

    @Test func testDeviceNameDecoding() {
        #expect(String(bmapPayload: bytes("00 55 6c 74 72 61 20 43 61 6e 73")) == "Ultra Cans")
        #expect(String(bmapPayload: bytes("38 2e 32 2e 32 30")) == "8.2.20")
    }

    @Test func testCapabilities() {
        let capabilities = ModeCapabilities(payload: bytes("04 07 00 00 00 7f 02"))
        #expect(capabilities?.boseModeCount == 4)
        #expect(capabilities?.userModeCount == 7)
        #expect(capabilities?.totalSlots == 11)
    }

    @Test func testLiveSettings() {
        var settings = LiveAudioSettings(payload: bytes("00 00 00 00 01"))!
        #expect(settings.immersiveAudio == .off)
        #expect(settings.anc == 1)
        settings.immersiveAudioRaw = ImmersiveAudioMode.motion.rawValue
        #expect(settings.payload == bytes("00 00 02 00 01"))
    }

    @Test func testBuiltInModeDecoding() {
        let aware = ListeningMode(payload: bytes("01 00 02 00 00 01 41 77 61 72 65 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 02 0a 00 00 00 00 01"))!
        #expect(aware.index == 1)
        #expect(aware.promptID == 2)
        #expect(!(aware.isUserConfigurable))
        #expect(aware.isFavorite)
        #expect(aware.isAvailable)
        #expect(aware.displayName == "Aware")
        #expect(aware.settings?.cncLevel == 10)
    }

    @Test func testUserModeUsesPromptNameWhenStoredNameIsNone() {
        let focus = ListeningMode(payload: bytes("04 00 0d 01 01 01 4e 6f 6e 65 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 1d 00 00 00 01 00 01"))!
        #expect(focus.storedName == "None")
        #expect(focus.displayName == "Focus")
        #expect(focus.isUserConfigurable)
        #expect(focus.isConfigured)
        #expect(focus.isAvailable)
    }

    @Test func testEmptyUserSlotIsUnavailable() {
        let empty = ListeningMode(payload: bytes("05 00 00 01 00 00 4e 6f 6e 65 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 1d 0a 00 00 01 00 01"))!
        #expect(!(empty.isAvailable))
        #expect(empty.displayName == "Mode 6")
    }

    @Test func testImmersionModeCarriesMotionSetting() {
        let immersion = ListeningMode(payload: bytes("02 00 22 00 00 00 49 6d 6d 65 72 73 69 6f 6e 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 02 00 00 01"))!
        #expect(immersion.displayName == "Immersion")
        #expect(immersion.settings?.immersiveAudio == .motion)
    }

    @Test func testAvailableModesListFavouritesFirst() {
        let quiet = ListeningMode(payload: bytes("00 00 01 00 00 00 51 75 69 65 74 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01"))!
        let aware = ListeningMode(payload: bytes("01 00 02 00 00 01 41 77 61 72 65 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 02 0a 00 00 00 00 01"))!
        let cinema = ListeningMode(payload: bytes("03 00 24 00 00 00 43 69 6e 65 6d 61 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 00 00 01"))!
        let focus = ListeningMode(payload: bytes("04 00 0d 01 01 01 4e 6f 6e 65 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 1d 00 00 00 01 00 01"))!
        let empty = ListeningMode(payload: bytes("05 00 00 01 00 00 4e 6f 6e 65 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 1d 0a 00 00 01 00 01"))!
        let headphones = HeadphoneController.Headphones(name: "Ultra Cans", modes: [quiet, aware, cinema, focus, empty])
        #expect(headphones.availableModes.map(\.displayName) == ["Aware", "Focus", "Quiet", "Cinema"])
    }

    @Test func testAudioDeviceNameMatchingIgnoresCase() {
        #expect(AudioDeviceMonitor.contains(["Ultra Cans", "AirPods"], name: "ultra cans"))
        #expect(!AudioDeviceMonitor.contains(["AirPods"], name: "Ultra Cans"))
    }
}

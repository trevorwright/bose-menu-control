# Bose Menu Control

A macOS menu bar app for Bose headphones. It shows a headphones icon with the current battery
percentage while headphones are connected, and a slashed headphones icon while they are not.
Clicking the icon opens a popover with the headphone name, battery level, the active listening
mode with the other stored modes, and the active immersive audio setting (Off, Still, Motion).

Verified against QuietComfort Ultra Headphones (2nd Gen), firmware 8.2.20. Requires macOS 13 or later.

## Install

Building from source needs Xcode or the command-line tools (`xcode-select --install`).

```sh
git clone https://github.com/trevorwright/bose-menu-control.git
cd bose-menu-control
make install
```

That builds the app and copies it to `/Applications`, or to `~/Applications` if `/Applications`
is not writable. To choose the location yourself:

```sh
make install APP_DIR=~/Applications
```

The app has no Dock icon and no main window; look for the headphones icon in the menu bar. macOS
asks for Bluetooth access on first launch. If you decline, enable it later in System Settings >
Privacy & Security > Bluetooth. Because you compile it yourself the app is never quarantined, so
there is no Gatekeeper warning and nothing needs to be notarized.

Update to a newer version, or remove it, with:

```sh
git pull && make install
make uninstall
```

Each install of an ad hoc signed build counts as a new app to macOS and asks for Bluetooth access
again; see below for how to sign with a real identity and keep the permission.

## Build and run

`make run` builds the bundle and launches it in place, without installing:

```sh
make run
```

That produces `.build/BoseMenuControl.app`, which is build output — `make clean` deletes it. Use
`make install` for a copy that stays put.

The bundle is ad hoc signed by default, so macOS treats each rebuild as a new app and asks for
Bluetooth access again. Sign with a real identity to keep the permission across rebuilds:

```sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make run
```

For quick iteration without a bundle, `make dev` runs the executable directly. The Info.plist is
embedded in the binary, so Bluetooth permission still works, but the permission is then attributed
to the terminal that launched it.

## Tests

```sh
make test
```

The tests exercise BMAP framing, BLE segment reassembly, and payload decoding using byte sequences
recorded from the real headphones. `swift test` on its own fails to find Swift Testing when only the
command-line tools are installed; the Makefile adds the framework search paths.

## How it works

The app talks to the headphones over Bluetooth Low Energy using Bose's BMAP protocol on GATT
service `FEBE`, characteristic `C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8`. Each BLE write is a
one-byte segment header followed by a BMAP frame of `[block, function, operator, length, payload]`.

| Source file | Role |
| --- | --- |
| `BMAP/BMAPPacket.swift` | Frame encoding and parsing, reply matching, BLE segment reassembly |
| `BMAP/BMAPModels.swift` | Battery, listening mode slot, live audio settings, and Bose prompt-ID decoding |
| `Bluetooth/BoseBLEConnection.swift` | CoreBluetooth discovery, connection, reconnection, and one-at-a-time request/response |
| `Bluetooth/AudioDeviceMonitor.swift` | CoreAudio listener that reports whether the headphones are present as an audio device |
| `HeadphoneController.swift` | Publishes device state to the UI, polls battery every minute, applies mode changes |
| `Views/` | Menu bar label and popover |

Functions used:

| Block.function | Purpose |
| --- | --- |
| 1.2 | Device name |
| 0.5 | Firmware version |
| 2.2 | Battery: percent, minutes remaining, component |
| 31.2 | Mode capabilities: count of built-in and user slots |
| 31.6 | Stored mode slot, 48 bytes |
| 31.3 | Current mode; `START [slot, 0]` switches modes silently |
| 31.10 | Live settings `[cnc, autoCNC, immersive, wind, anc]`; `SETGET` changes immersive audio |

### Wear detection

The headphones keep their low-energy control link up whenever they are nearby, but only bring up the
classic audio link while they are on your head. So the app treats them as connected only while a
Bluetooth audio device with the headphones' name is present in CoreAudio, watched live through
`AudioDeviceMonitor`. Taking them off switches the menu bar to the slashed icon within about 15
seconds; the popover then says the headphones are nearby but not being worn. The BMAP status
functions that were probed (2.0, 2.5, 2.16, 2.21, 1.24) did not change with wear state, and the
headphones sent no unsolicited frames, so there is no protocol-level wear signal on this firmware.

User mode slots store the name `None` when they use a Bose preset name, so the app labels those
slots from the prompt ID (for example ID 13 is Focus). When live settings no longer match a stored
mode the headphones report mode `0xFF`; the popover marks that with a checked `Custom` row, which
appears only in that state and never alongside an active mode.

Logs are available with:

```sh
/usr/bin/log stream --predicate 'subsystem == "local.bose.menucontrol"' --level debug
```

Protocol references:
- https://github.com/NerdySouth/bozo/blob/main/docs/BMAP.md
- https://github.com/aaronsb/bosectl/blob/main/NOTES.md

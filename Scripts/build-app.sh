#!/bin/zsh
# Builds BoseMenuControl and wraps it in a signed .app bundle at .build/BoseMenuControl.app.
# Usage: Scripts/build-app.sh [debug|release]
# Set CODESIGN_IDENTITY to a real signing identity to keep the Bluetooth permission across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP=".build/BoseMenuControl.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/BoseMenuControl"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN" "$APP/Contents/MacOS/BoseMenuControl"
codesign --force --sign "$IDENTITY" "$APP"

# macOS caches app icons per bundle; bumping mtime forces a reload.
touch "$APP"

echo "Built $APP"

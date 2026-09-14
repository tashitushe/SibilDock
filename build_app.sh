#!/bin/bash
# Builds FloatingDock and packages it into a proper FloatingDock.app bundle,
# then ad-hoc code-signs it. A real .app bundle (vs. a loose binary) is what
# lets macOS show the location-permission prompt reliably and gives the app
# a stable identity across launches.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/SibilDock"
APP="SibilDock.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_PATH" "$APP/Contents/MacOS/SibilDock"
cp "Sources/SibilDock/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "Sources/SibilDock/Resources/AppIcon.icns" ]; then
    cp "Sources/SibilDock/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP"

echo "Built $APP (config: $CONFIG)"

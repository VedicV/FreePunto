#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-FreePunto}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$ROOT_DIR/Resources/AppIcon.iconset"
ICNS_PATH="$ROOT_DIR/Resources/AppIcon.icns"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION" --scratch-path "$ROOT_DIR/.build"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path --scratch-path "$ROOT_DIR/.build")"

if [ ! -f "$ICNS_PATH" ] || [ "$ROOT_DIR/scripts/generate_icon.swift" -nt "$ICNS_PATH" ]; then
    swift "$ROOT_DIR/scripts/generate_icon.swift" "$ICONSET_DIR"
    iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ICNS_PATH" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>FreePunto</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>dev.freepunto.FreePunto</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>FreePunto</string>
    <key>CFBundleDisplayName</key>
    <string>FreePunto</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSInputMonitoringUsageDescription</key>
    <string>FreePunto uses keyboard events only for explicit hotkeys and the single Control trigger.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR"
echo "Built $APP_DIR"

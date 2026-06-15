#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-FreePunto}"
VERSION="${VERSION:-0.1.1}"
VOLUME_NAME="${VOLUME_NAME:-FreePunto}"
DMG_NAME="${DMG_NAME:-FreePunto-${VERSION}.dmg}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$DMG_NAME"

"$ROOT_DIR/scripts/build_app.sh"

rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT"
cp -R "$APP_DIR" "$DMG_ROOT/${APP_NAME}.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -fs HFS+ \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_ROOT"
echo "Built $DMG_PATH"

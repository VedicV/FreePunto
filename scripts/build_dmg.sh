#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-FreePunto}"
VERSION="${VERSION:-0.2.1}"
VOLUME_NAME="${VOLUME_NAME:-FreePunto}"
DMG_NAME="${DMG_NAME:-FreePunto-${VERSION}.dmg}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$DMG_NAME"

APP_NAME="$APP_NAME" VERSION="$VERSION" "$ROOT_DIR/scripts/build_app.sh"

rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT"
cp -R "$APP_DIR" "$DMG_ROOT/${APP_NAME}.app"
ln -s /Applications "$DMG_ROOT/Applications"

# Створюємо зручний скрипт встановлення в 1 клік всередині DMG
cat > "$DMG_ROOT/Install or Update FreePunto.command" << 'CMD'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="FreePunto"
BUNDLE_ID="dev.freepunto.FreePunto"
SOURCE_APP="$SCRIPT_DIR/${APP_NAME}.app"
TARGET_DIR="/Applications"
TARGET_APP="$TARGET_DIR/${APP_NAME}.app"

echo "========================================================"
echo "    Встановлення / Оновлення ${APP_NAME}"
echo "========================================================"
echo ""

if [ ! -d "$SOURCE_APP" ]; then
    echo "Помилка: ${APP_NAME}.app не знайдено поруч зі скриптом!" >&2
    exit 1
fi

echo "1. Завершуємо попередню версію..."
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true

for _ in {1..25}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    pkill -9 -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
fi
echo "   Попередню версію зупинено."

echo "2. Скидаємо старі системні дозволи (Accessibility, ListenEvent)..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null || true
tccutil reset PostEvent "$BUNDLE_ID" 2>/dev/null || true
echo "   Дозволи очищено."

echo "3. Встановлюємо ${APP_NAME} у ${TARGET_DIR}..."
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
echo "   Скопійовано."

echo "4. Знімаємо карантин macOS..."
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

echo "5. Запускаємо нову версію..."
open "$TARGET_APP"
sleep 0.5
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo ""
echo "========================================================"
echo " Готово! FreePunto встановлено та запущено."
echo " У вікні 'Доступність' увімкніть перемикач навпроти FreePunto."
echo "========================================================"
echo ""
read -n 1 -s -r -p "Натисніть будь-яку клавішу для закриття..." || true
exit 0
CMD
chmod +x "$DMG_ROOT/Install or Update FreePunto.command"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -fs HFS+ \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_ROOT"
echo "Built $DMG_PATH"

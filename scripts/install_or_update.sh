#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || echo "$SCRIPT_DIR")"
APP_NAME="FreePunto"
BUNDLE_ID="dev.freepunto.FreePunto"
TARGET_DIR="/Applications"
TARGET_APP="$TARGET_DIR/${APP_NAME}.app"

SOURCE_APP="${1:-}"

if [ -z "$SOURCE_APP" ]; then
    if [ -d "$SCRIPT_DIR/${APP_NAME}.app" ]; then
        SOURCE_APP="$SCRIPT_DIR/${APP_NAME}.app"
    elif [ -d "$ROOT_DIR/dist/${APP_NAME}.app" ]; then
        SOURCE_APP="$ROOT_DIR/dist/${APP_NAME}.app"
    elif [ -f "$ROOT_DIR/scripts/build_app.sh" ]; then
        echo "Збірка ${APP_NAME}.app не знайдена в dist/. Збираємо новий застосунок..."
        "$ROOT_DIR/scripts/build_app.sh"
        SOURCE_APP="$ROOT_DIR/dist/${APP_NAME}.app"
    fi
fi

if [ ! -d "$SOURCE_APP" ]; then
    echo "Помилка: файл застосунку не знайдено за шляхом: $SOURCE_APP" >&2
    exit 1
fi

SOURCE_REALPATH="$(cd "$SOURCE_APP" && pwd -P)"
TARGET_DIR_REALPATH="$(cd "$TARGET_DIR" 2>/dev/null && pwd -P || echo "$TARGET_DIR")"
if [ "$SOURCE_REALPATH" = "$TARGET_DIR_REALPATH/${APP_NAME}.app" ]; then
    echo "Помилка: джерело і ціль збігаються ($SOURCE_APP). Встановлення не потрібне." >&2
    exit 1
fi

echo "========================================================"
echo "    Встановлення / Оновлення ${APP_NAME}"
echo "========================================================"
echo "Джерело: $SOURCE_APP"
echo "Ціль:    $TARGET_APP"
echo ""

# 1. Завершення працюючого застосунку
echo "Крок 1/5: Завершуємо роботу попередньої версії..."
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true

# Чекаємо повного виходу процесу, щоб уникнути дедлоку WindowServer
for _ in {1..25}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "   Примусово зупиняємо процес $APP_NAME..."
    pkill -9 -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
fi

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Помилка: не вдалося зупинити старий процес $APP_NAME. Зупиніть його вручну і повторіть." >&2
    exit 1
fi
echo "   Попередню версію зупинено."

# 2. Очищення TCC-дозволів (тільки якщо вказано явно)
if [ "${RESET_TCC:-0}" = "1" ] || [ "${1:-}" = "--reset-tcc" ] || [ "${2:-}" = "--reset-tcc" ]; then
    echo "Крок 2/5: Скидаємо старі дозволи TCC (Accessibility, ListenEvent)..."
    tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset PostEvent "$BUNDLE_ID" 2>/dev/null || true
else
    echo "Крок 2/5: Зберігаємо існуючі системні дозволи TCC (для скидання запустіть з RESET_TCC=1)..."
fi

# 3. Атомарне встановлення нового бандла
echo "Крок 3/5: Встановлюємо новий $APP_NAME у $TARGET_DIR..."
SUDO=""
if [ ! -w "$TARGET_DIR" ] || ([ -e "$TARGET_APP" ] && [ ! -w "$TARGET_APP" ]); then
    echo "   Увага: для запису в $TARGET_DIR потрібні права суперкористувача (sudo)."
    SUDO="sudo"
fi

TMP_APP="${TARGET_DIR}/.${APP_NAME}.tmp.$$"
$SUDO rm -rf "$TMP_APP"
$SUDO cp -R "$SOURCE_APP" "$TMP_APP"

# Зняття карантину
$SUDO xattr -dr com.apple.quarantine "$TMP_APP" 2>/dev/null || true

# Атомарна заміна цілі
$SUDO rm -rf "$TARGET_APP"
$SUDO mv "$TMP_APP" "$TARGET_APP"
echo "   Атомарне копіювання успішно завершено."

# Перевірка наявності дубліката у ~/Applications
USER_APP="$HOME/Applications/${APP_NAME}.app"
if [ -d "$USER_APP" ] && [ "$TARGET_APP" != "$USER_APP" ]; then
    echo "   Попередження: виявлено копію у $USER_APP. Рекомендується видалити її, щоб уникнути конфліктів системних дозволів."
fi

# 4. Перевірка цілісності бандла
echo "Крок 4/5: Перевіряємо цілісність встановленого застосунку..."
if [ -f "$TARGET_APP/Contents/Info.plist" ]; then
    INSTALLED_VER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$TARGET_APP/Contents/Info.plist" 2>/dev/null || echo "unknown")"
    INSTALLED_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$TARGET_APP/Contents/Info.plist" 2>/dev/null || echo "unknown")"
    echo "   Встановлено FreePunto версії $INSTALLED_VER (збірка $INSTALLED_BUILD)"
fi
if codesign --verify --deep --strict "$TARGET_APP" 2>/dev/null; then
    echo "   Підпис коду валідний."
fi

# 5. Запуск та відкриття налаштувань
echo "Крок 5/5: Запускаємо нову версію та відкриваємо налаштування Доступності..."
open "$TARGET_APP"
sleep 0.5
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo ""
echo "========================================================"
echo " Встановлення успішно завершено!"
echo " У Системних параметрах (Доступність) увімкніть FreePunto."
echo " Якщо гарячі клавіші не реагують, перевірте також розділ"
echo " 'Моніторинг вводу' (Input Monitoring)."
echo "========================================================"
echo ""
if [ -t 0 ]; then
    read -n 1 -s -r -p "Натисніть будь-яку клавішу для закриття..." || true
    echo ""
fi

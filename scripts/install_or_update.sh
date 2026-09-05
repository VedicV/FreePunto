#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FreePunto"
BUNDLE_ID="dev.freepunto.FreePunto"
TARGET_DIR="/Applications"
TARGET_APP="$TARGET_DIR/${APP_NAME}.app"

SOURCE_APP="${1:-}"

if [ -z "$SOURCE_APP" ]; then
    if [ -d "$ROOT_DIR/dist/${APP_NAME}.app" ]; then
        SOURCE_APP="$ROOT_DIR/dist/${APP_NAME}.app"
    else
        echo "Збірка ${APP_NAME}.app не знайдена в dist/. Збираємо новий застосунок..."
        "$ROOT_DIR/scripts/build_app.sh"
        SOURCE_APP="$ROOT_DIR/dist/${APP_NAME}.app"
    fi
fi

if [ ! -d "$SOURCE_APP" ]; then
    echo "Помилка: файл застосунку не знайдено за шляхом: $SOURCE_APP" >&2
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
echo "   Попередню версію зупинено."

# 2. Безпечне очищення TCC-дозволів
echo "Крок 2/5: Скидаємо старі дозволи TCC (Accessibility, ListenEvent)..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null || true
tccutil reset PostEvent "$BUNDLE_ID" 2>/dev/null || true
echo "   Дозволи скинуто."

# 3. Встановлення нового бандла
echo "Крок 3/5: Встановлюємо новий $APP_NAME у $TARGET_DIR..."
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
echo "   Скопійовано."

# 4. Зняття карантину
echo "Крок 4/5: Знімаємо карантинну мітку macOS (quarantine)..."
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
echo "   Карантин знято."

# 5. Запуск та відкриття налаштувань
echo "Крок 5/5: Запускаємо нову версію та відкриваємо налаштування Доступності..."
open "$TARGET_APP"
sleep 0.5
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo ""
echo "========================================================"
echo " Встановлення успішно завершено!"
echo " У Системних параметрах (Доступність) увімкніть FreePunto."
echo "========================================================"

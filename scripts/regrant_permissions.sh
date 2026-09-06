#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="dev.freepunto.FreePunto"

echo "=== FreePunto Permissions Reset & Setup ==="
echo "1. Зупиняємо запущений FreePunto..."
osascript -e 'quit app "FreePunto"' 2>/dev/null || true
pkill -x FreePunto 2>/dev/null || true

# Обов'язково чекаємо, поки процес повністю завершиться, щоб уникнути дедлоку WindowServer
for _ in {1..20}; do
    if ! pgrep -x FreePunto >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done

if pgrep -x FreePunto >/dev/null 2>&1; then
    echo "   Примусово зупиняємо процес..."
    pkill -9 -x FreePunto 2>/dev/null || true
    sleep 0.5
fi

if pgrep -x FreePunto >/dev/null 2>&1; then
    echo "Помилка: не вдалося зупинити FreePunto. Завершіть його через Activity Monitor і спробуйте знову." >&2
    exit 1
fi

echo "2. Скидаємо старі TCC-дозволи для $BUNDLE_ID..."
if tccutil reset Accessibility "$BUNDLE_ID"; then
    echo "   Accessibility успішно скинуто через tccutil."
else
    echo "   Зауваження: tccutil не зміг скинути Accessibility (можливо, запис ще не існує в базі TCC)."
fi
tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null || true
tccutil reset PostEvent "$BUNDLE_ID" 2>/dev/null || true

echo "3. Відкриваємо Системні параметри -> Приватність і безпека -> Доступність..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo ""
echo "Інструкція:"
echo "1. Якщо FreePunto вже є у списку 'Доступність', видаліть його (кнопка '-') або вимкніть/увімкніть перемикач."
echo "2. Додайте dist/FreePunto.app або /Applications/FreePunto.app у список."
echo "3. Запустіть застосунок знову."

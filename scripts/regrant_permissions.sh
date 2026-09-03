#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="dev.freepunto.FreePunto"

echo "=== FreePunto Permissions Reset & Setup ==="
echo "1. Зупиняємо запущений FreePunto..."
pkill -x FreePunto 2>/dev/null || true

echo "2. Скидаємо старі TCC-дозволи для $BUNDLE_ID..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null || true
tccutil reset PostEvent "$BUNDLE_ID" 2>/dev/null || true

echo "3. Відкриваємо Системні параметри -> Приватність і безпека -> Доступність..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo ""
echo "Інструкція:"
echo "1. Якщо FreePunto вже є у списку 'Доступність', видаліть його (кнопка '-') або вимкніть/увімкніть перемикач."
echo "2. Додайте dist/FreePunto.app або /Applications/FreePunto.app у список."
echo "3. Запустіть застосунок знову."

# Диагностика и исправления FreePunto — отчёт

Дата: 2026-06-16

## Выявленные проблемы и их корневые причины

### 1. AX (Accessibility) недоступен для Chrome/Electron-приложений

**Симптом:** `AX error=-25212` (`kAXErrorAPIDisabled`) при любом AX-запросе к VS Code, Google Chrome.

**Причина:** Chromium/Electron-приложения отключают Accessibility API, если не обнаружен «настоящий» ассистивный инструмент (VoiceOver и т.п.). `AXIsProcessTrusted()` возвращает `true`, но целевое приложение блокирует AX-запросы на своей стороне.

**Следствие:** невозможно получить `focusedElement`, `AXRole`, `AXValue`, `AXEditable` для Chrome/VS Code. AX-путь (`readAXLastWord`, `waitForGridEditMode`) не работает.

**Решение:** реализован обходной путь через `Cmd+C` (line-copy → извлечение последнего слова) для VS Code редактора. Для Google Sheets — слепой F2-танец без AX-проверки.

**Статус:** фундаментальное ограничение. Без поддержки со стороны Chrome/Electron AX не заработает.

---

### 2. `focusedTextElement()` возвращал nil даже при `hasAX=true`

**Симптом:** `focusedEl=no` в логах, хотя `accessibility TRUSTED`.

**Причина:** `AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute)` вызывался через `DispatchQueue.main.sync` из фоновой очереди (`commandQueue`). AX-запросы через GCD main queue работают нестабильно для чужих процессов.

**Решение:** `focusedElement` захватывается на главном потоке в `performTextCommand` ДО dispatch на `commandQueue`. Вызов идёт напрямую (без `syncMain`). Для Terminal/Firefox — работает. Для Chrome/VS Code — см. п. 1.

**Статус:** исправлено.

---

### 3. NSPasteboard-операции с фонового потока

**Симптом:** потенциальная гонка данных в pasteboard.

**Причина:** `NSPasteboard.general` документирован как main-thread-only. Код вызывал `clearContents`, `setString`, `changeCount` из `commandQueue` (фон).

**Решение:** все операции с NSPasteboard обёрнуты в `syncMain { }`. Добавлен хелпер `@discardableResult syncMain<T>(_:)`.

**Статус:** исправлено.

---

### 4. Line-copy → удаление лишних пробелов

**Симптом:** в чате/редакторе при замене последнего слова «съедался» пробел перед ним.

**Причина:** при line-copy (Cmd+C без выделения в VS Code) копируется строка с `\n`. `TextScanner.lastWord` включает `\n` в `trailingSpacesCount`. Backspace-удаление пытается стереть `wordLength + trailingSpacesCount` символов, включая невидимый `\n` перед курсором.

**Решение:** для line-copy пути `trailingSpacesCount = 0`.

**Статус:** исправлено.

---

### 5. Блокировка главного потока при ожидании

**Симптом:** event tap отваливался по таймауту (`tapDisabledByTimeout`).

**Причина (исходная):** `RunLoop.current.run(until:)` в `waitForKeyboardSideEffects` блокировал главный run loop.

**Решение:** заменён на `Thread.sleep` + вынос тяжёлой работы на `commandQueue` (фоновая serial-очередь). Главный поток освобождается сразу после dispatch.

**Статус:** исправлено.

---

### 6. NSString.length вместо графемного count

**Симптом:** потенциально неправильное удаление эмодзи/составных символов.

**Причина:** `makeCopiedTarget` использовал `(text as NSString).length` (UTF-16 code units).

**Решение:** заменён на `text.count` (графемы).

**Статус:** исправлено.

---

### 7. Гонка восстановления pasteboard

**Симптом:** иногда вставлялось старое содержимое буфера обмена.

**Причина:** `snapshot.restore(to:)` вызывался через фиксированный таймаут после Cmd+V. Если целевое приложение читало буфер асинхронно, восстановление происходило раньше.

**Решение:** `settleTimeout` увеличен до 1.0 секунды в `pasteReplacement` и `replaceBrowserGridLike`.

**Статус:** частично исправлено (увеличенный таймаут). Полное решение требует подтверждения вставки.

---

### 8. Системный диалог Accessibility по кругу

**Симптом:** при каждом запуске появлялся системный диалог запроса Accessibility-разрешения.

**Причина:** `AXIsProcessTrustedWithOptions(prompt: true)` вызывался в `applicationDidFinishLaunching`.

**Решение:** заменён на `prompt: false`. Пользователь добавляет разрешение вручную через Системные настройки.

**Статус:** исправлено.

---

### 9. Ad-hoc подпись меняется при каждой сборке

**Симптом:** после каждой пересборки macOS требует заново авторизовать приложение в Accessibility.

**Причина:** `codesign --sign -` создаёт новую ad-hoc подпись при каждом билде. macOS привязывает разрешения к подписи.

**Решение:** не исправлено (требуется постоянный code signing identity). Для разработки — переавторизовывать после каждой сборки.

**Статус:** известное ограничение dev-сборок.

---

## Что сделано (итог изменений в коде)

### `AppDelegate.swift`
- `performTextCommand`: захват `bundleID`, `hasAX`, `focusedEl` на главном потоке до dispatch
- Убран `AXIsProcessTrustedWithOptions(prompt: true)` из `applicationDidFinishLaunching`
- Диагностический лог `rawLog` на всех этапах команды

### `TextIOController.swift`
- `readTarget(bundleIdentifier:hasAccessibility:focusedElement:)` — новый сигнатура
- `syncMain<T>(_:)` — хелпер для main-thread-only операций (NSPasteboard, AX)
- Все NSPasteboard-операции обёрнуты в `syncMain`
- `readCodeEditorTarget` / `readEditableTarget`: line-copy → извлечение последнего слова, `trailingSpacesCount=0`
- `replaceBrowserGridLike`: F2 отправляется всегда, при отсутствии AX — ожидание 0.8с вслепую
- `readBrowserNonEditable`: новый метод, Cmd+C без AXValue-фоллбека
- `focusedTextElement`, `stringAttribute`, `boolAttribute`: обёрнуты в `syncMain`, лог AX-ошибок
- `makeCopiedTarget`: `text.count` вместо `NSString.length`

### `HotKeyController.swift`
- `rawLog` при срабатывании `actions.main`

### `Diag.swift`
- `rawLog(_:)` — синхронная запись в `~/Desktop/freepunto.log`

---

## Оставшиеся проблемы (фундаментальные ограничения)

### А. Поля ввода в Chrome/Firefox — только через выделение

Без AX невозможно прочитать текст из `<input>`/`<textarea>` в Chrome без выделения. Cmd+C без выделения в браузере не копирует строку (в отличие от VS Code).

**Обходной путь:** выделить текст перед нажатием хоткея.

---

### Б. VS Code интегрированный терминал

Без AX терминал внутри VS Code неотличим от редактора (bundle ID один — `com.microsoft.VSCode`). Cmd+C в терминале копирует выделение, а не строку. Line-copy-путь не работает.

**Обходной путь:** использовать родной Terminal.app (работает через AX).

---

### В. Google Sheets — F2 через CGEvent может не входить в edit mode

Chrome может игнорировать синтетические нажатия F2. Реализован слепой F2-танец с ожиданием 0.8с. Если F2 не срабатывает в конкретной версии Chrome — ячейка не изменится.

**Обходной путь:** дважды кликнуть по ячейке (войти в edit mode), затем хоткей.

---

### Г. Ad-hoc подпись — переавторизация при каждой сборке

**Обходной путь:** не пересобирать без необходимости. Использовать один собранный `.app` для тестирования.

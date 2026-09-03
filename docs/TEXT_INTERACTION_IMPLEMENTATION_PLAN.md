# План реалізації нової логіки TextIOController

Мета: переписати читання і заміну тексту так, щоб FreePunto використовував тільки два способи отримання тексту: `Cmd+C -> NSPasteboard` і `AXValue`. Усі рішення про заміну мають залежати від фактичного origin читання, а не від спроби заздалегідь вгадати конкретний сайт за заголовком вікна.

## Контракт

1. Не використовувати `windowTitle` для визначення Google Sheets, CanvasTable або іншого grid/canvas.
2. Не використовувати для читання `AXSelectedText`, `AXSelectedTextRange`, `Option+Shift+Left`, `Cmd+Shift+Left`, double click, `Return`, `F2`, `Cmd+A`.
3. Дозволені способи читання: `Cmd+C -> NSPasteboard` і `AXValue`.
4. Terminal читає тільки через `AXValue` і працює тільки з останнім словом.
5. Browser non-editable/grid читає через `Cmd+C`, але не вставляє прямим `Cmd+V`; запис тільки через `F2 -> verify edit mode -> Cmd+A -> Cmd+V -> Cmd+A`.
6. `Return`, double click і `Escape` не використовувати в browser/grid сценарії.
7. Якщо `F2` не перевів browser/grid в edit mode, не вставляти в grid напряму; завершити команду помилкою/beep.
8. Якщо потрібно змінити середину тексту, користувач має сам виділити потрібний фрагмент.

## Крок 1. Ввести origin читання

У `Sources/PuntoApp/TextIOController.swift` замінити поточну модель `source/profile` на точнішу модель origin.

Приклад:

```swift
private enum ReadOrigin {
    case copiedEditableSelection
    case copiedCodeEditorSelection
    case copiedBrowserGridLike
    case editableAXLastWord
    case codeEditorAXLastWord
    case terminalAXLastWord
}
```

`TextTarget` має зберігати:

- `text`;
- `origin`;
- `wordLength`;
- `trailingSpacesCount`;
- дані, потрібні для заміни.

## Крок 2. Ввести простий контекст активного застосунку

Зібрати контекст один раз на початку `readTarget()`:

- `bundleIdentifier`;
- `appKind`: terminal, codeEditor, browser, other;
- focused AX element;
- `AXRole`;
- `AXEditable`;
- `isEditableContext`.

Прибрати залежність від `AppEnvironmentClassifier.isGoogleSheetsWindow(...)` і `isCanvasTableApp(...)` у виборі сценарію читання/запису.

## Крок 3. Переписати helper для `Cmd+C`

Helper має:

1. Зберегти snapshot pasteboard.
2. Очистити pasteboard.
3. Запам'ятати `changeCount`.
4. Надіслати `Cmd+C`.
5. Дочекатися нового string.
6. Відновити pasteboard.
7. Повернути string тільки якщо він реально з'явився і непорожній.

Для code editor додати перевірку line-copy: не приймати результат як виділення, якщо він схожий на рядок, який редактор скопіював без виділення. Для VS Code/Cursor/Antigravity line-copy fallback можна використовувати тільки як технічний спосіб отримати останнє слово.

## Крок 4. Переписати читання

Порядок:

1. Terminal:
   - тільки `AXValue`;
   - взяти останнє слово останнього релевантного рядка;
   - повернути `.terminalAXLastWord`;
   - якщо не вийшло, `nil`.

2. Editable context:
   - спробувати `Cmd+C`;
   - якщо вийшло, повернути `.copiedEditableSelection`;
   - якщо не вийшло, прочитати `AXValue`, взяти останнє слово, повернути `.editableAXLastWord`.

3. Code editor:
   - спробувати `Cmd+C`;
   - якщо це реальне виділення, повернути `.copiedCodeEditorSelection`;
   - якщо це line-copy, не вважати його виділенням, але можна витягнути останнє слово як `.codeEditorAXLastWord`;
   - якщо copy порожній або line-copy fallback не дав слова, прочитати `AXValue`, взяти останнє слово, повернути `.codeEditorAXLastWord`.

4. Browser non-editable:
   - спробувати `Cmd+C`;
   - якщо вийшло, повернути `.copiedBrowserGridLike`;
   - якщо не вийшло, `nil`.

5. Other non-editable:
   - спробувати `Cmd+C`;
   - якщо немає безпечної стратегії запису, краще повернути `nil`, ніж вставляти в невідомий non-editable контекст.

## Крок 5. Переписати заміну за origin

1. `.copiedEditableSelection` / `.copiedCodeEditorSelection`:
   - покласти replacement у pasteboard;
   - `Cmd+V`;
   - відновити pasteboard.

2. `.editableAXLastWord` / `.codeEditorAXLastWord`:
   - видалити `wordLength + trailingSpacesCount` символів Backspace;
   - вставити replacement через `Cmd+V`;
   - відновити pasteboard.

3. `.terminalAXLastWord`:
   - standalone terminal: terminal-safe delete word, потім `Cmd+V`;
   - integrated terminal: Backspace за довжиною прочитаного слова, потім `Cmd+V`;
   - не використовувати `Control+C`, `Return`, `F2`, `Cmd+A`, double click, `Cmd+Shift+Left`.

4. `.copiedBrowserGridLike`:
   - натиснути `F2`;
   - дочекатися стабілізації;
   - перевірити, що поточний focused AX context став editable;
   - якщо не став editable, повернути `false`;
   - `Cmd+A`;
   - `Cmd+V`;
   - `Cmd+A`, щоб результат залишився виділеним для повторного перетворення;
   - не натискати `Return`;
   - не робити прямий `Cmd+V` у grid.

## Крок 6. Оновити класифікатор

У `Sources/PuntoCore/AppEnvironmentClassifier.swift` залишити тільки стійкі класифікації:

- VS Code / Cursor / Antigravity family за `bundleIdentifier`;
- standalone terminals за `bundleIdentifier`;
- browser identifiers за `bundleIdentifier`, якщо їх зручно винести з `TextIOController`.

Видалити або перестати використовувати title-based Google Sheets / CanvasTable detection.

## Крок 7. Тести і перевірки

Мінімальні automated checks:

- `swift test`;
- тести класифікатора без window title Google Sheets/CanvasTable як обов'язкового сценарію;
- тести helper-логіки, яку можна винести в pure functions: last word extraction, line-copy detection, app kind classification.

Manual QA:

- Terminal: останнє слово замінюється, заборонені клавіші не надсилаються.
- VS Code/Cursor/Antigravity: виділений текст замінюється; без виділення line-copy не приймається як selection target, але може дати останнє слово.
- Chrome/Safari/Firefox editable field: виділення замінюється через copy/paste; без виділення замінюється останнє слово через `AXValue`.
- Google Sheets active cell: `Cmd+C` читає cell, `F2` входить в edit mode, `Cmd+A -> Cmd+V -> Cmd+A` замінює текст, прямого paste в grid немає.
- CanvasTable active cell: після реалізації `F2` у CanvasTable той самий сценарій працює.
- Browser/grid: якщо `F2` не дав edit mode, FreePunto не вставляє текст.

## Порядок роботи в новому чаті

1. Почати з читання `docs/TEXT_INTERACTION_SCENARIOS.md` і цього плану.
2. Потім відкрити `Sources/PuntoApp/TextIOController.swift`.
3. Спочатку впровадити `ReadOrigin` і новий `TextTarget`.
4. Потім переписати `readTarget()`.
5. Після цього переписати `replace(...)`.
6. Тільки після компіляції чистити старі helper-и і title-based grid detection.
7. Запустити `swift test`.
8. Звірити підсумок із manual QA списком.

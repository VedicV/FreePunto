# План реализации новой логики TextIOController

Цель: переписать чтение и замену текста так, чтобы FreePunto использовал только два способа получения текста: `Cmd+C -> NSPasteboard` и `AXValue`. Все решения о замене должны зависеть от фактического origin чтения, а не от попытки заранее угадать конкретный сайт по заголовку окна.

## Контракт

1. Не использовать `windowTitle` для определения Google Sheets, CanvasTable или другого grid/canvas.
2. Не использовать для чтения `AXSelectedText`, `AXSelectedTextRange`, `Option+Shift+Left`, `Cmd+Shift+Left`, double click, `Return`, `F2`, `Cmd+A`.
3. Разрешенные способы чтения: `Cmd+C -> NSPasteboard` и `AXValue`.
4. Terminal читает только через `AXValue` и работает только с последним словом.
5. Browser non-editable/grid читает через `Cmd+C`, но не вставляет прямым `Cmd+V`; запись только через `F2 -> verify edit mode -> Cmd+A -> Cmd+V -> Cmd+A`.
6. `Return`, double click и `Escape` не использовать в browser/grid сценарии.
7. Если `F2` не перевел browser/grid в edit mode, не вставлять в grid напрямую; завершить команду ошибкой/beep.
8. Если нужно изменить середину текста, пользователь должен сам выделить нужный фрагмент.

## Шаг 1. Ввести origin чтения

В `Sources/PuntoApp/TextIOController.swift` заменить текущую модель `source/profile` на более точную модель origin.

Пример:

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

`TextTarget` должен хранить:

- `text`;
- `origin`;
- `wordLength`;
- `trailingSpacesCount`;
- данные, нужные для замены.

## Шаг 2. Ввести простой контекст активного приложения

Собрать контекст один раз в начале `readTarget()`:

- `bundleIdentifier`;
- `appKind`: terminal, codeEditor, browser, other;
- focused AX element;
- `AXRole`;
- `AXEditable`;
- `isEditableContext`.

Удалить зависимость от `AppEnvironmentClassifier.isGoogleSheetsWindow(...)` и `isCanvasTableApp(...)` в выборе сценария чтения/записи.

## Шаг 3. Переписать helper для `Cmd+C`

Helper должен:

1. Сохранить snapshot pasteboard.
2. Очистить pasteboard.
3. Запомнить `changeCount`.
4. Отправить `Cmd+C`.
5. Дождаться нового string.
6. Восстановить pasteboard.
7. Вернуть string только если он реально появился и непустой.

Для code editor добавить проверку line-copy: не принимать результат как выделение, если он похож на строку, которую редактор скопировал без выделения.

## Шаг 4. Переписать чтение

Порядок:

1. Terminal:
   - только `AXValue`;
   - взять последнее слово последнего релевантного ряда;
   - вернуть `.terminalAXLastWord`;
   - если не получилось, `nil`.

2. Editable context:
   - попробовать `Cmd+C`;
   - если получилось, вернуть `.copiedEditableSelection`;
   - если не получилось, прочитать `AXValue`, взять последнее слово, вернуть `.editableAXLastWord`.

3. Code editor:
   - попробовать `Cmd+C`;
   - если это реальное выделение, вернуть `.copiedCodeEditorSelection`;
   - если это line-copy или пусто, прочитать `AXValue`, взять последнее слово, вернуть `.codeEditorAXLastWord`.

4. Browser non-editable:
   - попробовать `Cmd+C`;
   - если получилось, вернуть `.copiedBrowserGridLike`;
   - если не получилось, `nil`.

5. Other non-editable:
   - попробовать `Cmd+C`;
   - если нет безопасной стратегии записи, лучше вернуть `nil`, чем вставлять в неизвестный non-editable контекст.

## Шаг 5. Переписать замену по origin

1. `.copiedEditableSelection` / `.copiedCodeEditorSelection`:
   - положить replacement в pasteboard;
   - `Cmd+V`;
   - восстановить pasteboard.

2. `.editableAXLastWord` / `.codeEditorAXLastWord`:
   - удалить `wordLength + trailingSpacesCount` символов Backspace;
   - вставить replacement через `Cmd+V`;
   - восстановить pasteboard.

3. `.terminalAXLastWord`:
   - standalone terminal: terminal-safe delete word, затем `Cmd+V`;
   - integrated terminal: Backspace по длине прочитанного слова, затем `Cmd+V`;
   - не использовать `Control+C`, `Return`, `F2`, `Cmd+A`, double click, `Cmd+Shift+Left`.

4. `.copiedBrowserGridLike`:
   - нажать `F2`;
   - дождаться стабилизации;
   - проверить, что текущий focused AX context стал editable;
   - если не стал editable, вернуть `false`;
   - `Cmd+A`;
   - `Cmd+V`;
   - `Cmd+A`, чтобы результат остался выделенным для повторного преобразования;
   - не нажимать `Return`;
   - не делать прямой `Cmd+V` в grid.

## Шаг 6. Обновить классификатор

В `Sources/PuntoCore/AppEnvironmentClassifier.swift` оставить только устойчивые классификации:

- VS Code / Antigravity family по `bundleIdentifier`;
- standalone terminals по `bundleIdentifier`;
- browser identifiers по `bundleIdentifier`, если их удобно вынести из `TextIOController`.

Удалить или перестать использовать title-based Google Sheets / CanvasTable detection.

## Шаг 7. Тесты и проверки

Минимальные automated checks:

- `swift test`;
- тесты классификатора без window title Google Sheets/CanvasTable как обязательного сценария;
- тесты helper-логики, которую можно вынести в pure functions: last word extraction, line-copy rejection, app kind classification.

Manual QA:

- Terminal: последнее слово заменяется, запрещенные клавиши не отправляются.
- VS Code: выделенный текст заменяется; без выделения line-copy не принимается как target.
- Chrome/Safari/Firefox editable field: выделение заменяется через copy/paste; без выделения заменяется последнее слово через `AXValue`.
- Google Sheets active cell: `Cmd+C` читает cell, `F2` входит в edit mode, `Cmd+A -> Cmd+V -> Cmd+A` заменяет текст, прямого paste в grid нет.
- CanvasTable active cell: после реализации `F2` в CanvasTable тот же сценарий работает.
- Browser/grid: если `F2` не дал edit mode, FreePunto не вставляет текст.

## Порядок работы в новом чате

1. Начать с чтения `docs/TEXT_INTERACTION_SCENARIOS.md` и этого плана.
2. Затем открыть `Sources/PuntoApp/TextIOController.swift`.
3. Сначала внедрить `ReadOrigin` и новый `TextTarget`.
4. Затем переписать `readTarget()`.
5. После этого переписать `replace(...)`.
6. Только после компиляции чистить старые helper-и и title-based grid detection.
7. Запустить `swift test`.
8. Сверить итог с manual QA списком.

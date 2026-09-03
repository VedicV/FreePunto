# Діагностика та виправлення FreePunto - звіт

Дата: 2026-06-16

## Виявлені проблеми та їхні кореневі причини

### 1. AX (Accessibility) недоступний для Chrome/Electron-застосунків

**Симптом:** `AX error=-25212` (`kAXErrorAPIDisabled`) при будь-якому AX-запиті до VS Code, Google Chrome.

**Причина:** Chromium/Electron-застосунки вимикають Accessibility API, якщо не виявлено "справжній" асистивний інструмент (VoiceOver тощо). `AXIsProcessTrusted()` повертає `true`, але цільовий застосунок блокує AX-запити на своєму боці.

**Наслідок:** неможливо отримати `focusedElement`, `AXRole`, `AXValue`, `AXEditable` для Chrome/VS Code. AX-шлях (`readAXLastWord`, `waitForGridEditMode`) не працює.

**Рішення:** реалізовано обхідний шлях через `Cmd+C` (line-copy -> витягування останнього слова) для VS Code редактора. Для Google Sheets - сліпий F2-танець без AX-перевірки.

**Статус:** фундаментальне обмеження. Без підтримки з боку Chrome/Electron AX не запрацює.

---

### 2. `focusedTextElement()` повертав nil навіть при `hasAX=true`

**Симптом:** `focusedEl=no` у логах, хоча `accessibility TRUSTED`.

**Причина:** `AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute)` викликався через `DispatchQueue.main.sync` із фонової черги (`commandQueue`). AX-запити через GCD main queue працюють нестабільно для чужих процесів.

**Рішення:** `focusedElement` захоплюється на головному потоці в `performTextCommand` ДО dispatch на `commandQueue`. Виклик іде напряму (без `syncMain`). Для Terminal/Firefox - працює. Для Chrome/VS Code - див. п. 1.

**Статус:** виправлено.

---

### 3. NSPasteboard-операції з фонового потоку

**Симптом:** потенційна гонка даних у pasteboard.

**Причина:** `NSPasteboard.general` документований як main-thread-only. Код викликав `clearContents`, `setString`, `changeCount` із `commandQueue` (фон).

**Рішення:** усі операції з NSPasteboard обгорнуті в `syncMain { }`. Додано helper `@discardableResult syncMain<T>(_:)`.

**Статус:** виправлено.

---

### 4. Line-copy -> видалення зайвих пробілів

**Симптом:** у чаті/редакторі при заміні останнього слова "з'їдався" пробіл перед ним.

**Причина:** при line-copy (Cmd+C без виділення у VS Code) копіюється рядок із `\n`. `TextScanner.lastWord` включає `\n` у `trailingSpacesCount`. Backspace-видалення намагається стерти `wordLength + trailingSpacesCount` символів, включно з невидимим `\n` перед курсором.

**Рішення:** для line-copy шляху `trailingSpacesCount = 0`.

**Статус:** виправлено.

---

### 5. Блокування головного потоку під час очікування

**Симптом:** event tap відвалювався за таймаутом (`tapDisabledByTimeout`).

**Причина (початкова):** `RunLoop.current.run(until:)` у `waitForKeyboardSideEffects` блокував головний run loop.

**Рішення:** замінено на `Thread.sleep` + винесення важкої роботи на `commandQueue` (фонова serial-черга). Головний потік звільняється одразу після dispatch.

**Статус:** виправлено.

---

### 6. NSString.length замість графемного count

**Симптом:** потенційно неправильне видалення емодзі/складених символів.

**Причина:** `makeCopiedTarget` використовував `(text as NSString).length` (UTF-16 code units).

**Рішення:** замінено на `text.count` (графеми).

**Статус:** виправлено.

---

### 7. Гонка відновлення pasteboard

**Симптом:** іноді вставлявся старий вміст буфера обміну.

**Причина:** `snapshot.restore(to:)` викликався через фіксований таймаут після Cmd+V. Якщо цільовий застосунок читав буфер асинхронно, відновлення відбувалося раніше.

**Рішення:** `settleTimeout` збільшено до 1.0 секунди в `pasteReplacement` і `replaceBrowserGridLike`.

**Статус:** частково виправлено (збільшений таймаут). Повне рішення потребує підтвердження вставки.

---

### 8. Системний діалог Accessibility по колу

**Симптом:** під час кожного запуску з'являвся системний діалог запиту Accessibility-дозволу.

**Причина:** `AXIsProcessTrustedWithOptions(prompt: true)` викликався в `applicationDidFinishLaunching`.

**Рішення:** замінено на `prompt: false`. Користувач додає дозвіл вручну через Системні налаштування.

**Статус:** виправлено.

---

### 9. Ad-hoc підпис змінюється під час кожної збірки

**Симптом:** після кожної пересбірки macOS вимагає заново авторизувати застосунок в Accessibility.

**Причина:** `codesign --sign -` створює новий ad-hoc підпис під час кожного build. macOS прив'язує дозволи до підпису.

**Рішення:** не виправлено (потрібен постійний code signing identity). Для розробки - переавторизовувати після кожної збірки.

**Статус:** відоме обмеження dev-збірок.

---

## Що зроблено (підсумок змін у коді)

### `AppDelegate.swift`

- `performTextCommand`: захоплення `bundleID`, `hasAX`, `focusedEl` на головному потоці до dispatch.
- Прибрано `AXIsProcessTrustedWithOptions(prompt: true)` з `applicationDidFinishLaunching`.
- Діагностичний лог `rawLog` на всіх етапах команди.

### `TextIOController.swift`

- `readTarget(bundleIdentifier:hasAccessibility:focusedElement:)` - нова сигнатура.
- `syncMain<T>(_:)` - helper для main-thread-only операцій (NSPasteboard, AX).
- Усі NSPasteboard-операції обгорнуті в `syncMain`.
- `readCodeEditorTarget` / `readEditableTarget`: line-copy -> витягування останнього слова, `trailingSpacesCount=0`.
- `replaceBrowserGridLike`: F2 надсилається завжди, за відсутності AX - очікування 0.8с наосліп.
- `readBrowserNonEditable`: новий метод, Cmd+C без AXValue-fallback.
- `focusedTextElement`, `stringAttribute`, `boolAttribute`: обгорнуті в `syncMain`, лог AX-помилок.
- `makeCopiedTarget`: `text.count` замість `NSString.length`.

### `HotKeyController.swift`

- `rawLog` при спрацюванні `actions.main`.

### `Diag.swift`

- `rawLog(_:)` - синхронний запис у `~/Desktop/freepunto.log`.

---

## Залишкові проблеми (фундаментальні обмеження)

### А. Поля введення в Chrome/Firefox - тільки через виділення

Без AX неможливо прочитати текст із `<input>`/`<textarea>` у Chrome без виділення. Cmd+C без виділення в браузері не копіює рядок (на відміну від VS Code).

**Обхідний шлях:** виділити текст перед натисканням хоткея.

---

### Б. VS Code інтегрований термінал

Без AX термінал усередині VS Code невідрізний від редактора (bundle ID один - `com.microsoft.VSCode`). Cmd+C у терміналі копіює виділення, а не рядок. Line-copy-шлях не працює.

**Обхідний шлях:** використовувати рідний Terminal.app (працює через AX).

---

### В. Google Sheets - F2 через CGEvent може не входити в edit mode

Chrome може ігнорувати синтетичні натискання F2. Реалізовано сліпий F2-танець з очікуванням 0.8с. Якщо F2 не спрацьовує в конкретній версії Chrome - комірка не зміниться.

**Обхідний шлях:** двічі клікнути по комірці (увійти в edit mode), потім хоткей.

---

### Г. Ad-hoc підпис - переавторизація під час кожної збірки

**Обхідний шлях:** не пересобирати без потреби. Використовувати один зібраний `.app` для тестування.

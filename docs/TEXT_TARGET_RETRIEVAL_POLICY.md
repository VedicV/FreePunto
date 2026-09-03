# Рекомендована політика отримання тексту для заміни

Дата: 2026-06-18.

Цей документ описує, як FreePunto має безпечно зрозуміти, який текст потрібно перетворити. Це політика для `TextIOController`: спочатку визначити контекст, потім вибрати спосіб читання, потім повернути `TextTarget` або відмовитися від дії.

Головне правило:

```text
Якщо текстову ціль не визначено впевнено, повернути nil і нічого не змінювати.
Краще пропустити заміну, ніж видалити або вставити текст не туди.
```

## Базовий контракт

FreePunto працює тільки після явної команди користувача. Він не має фоново читати потік введення, будувати історію набору або агресивно вгадувати.

Дозволені тільки дві користувацькі цілі:

1. Реально виділений текст.
2. Останнє слово перед курсором.

Окремої цілі "весь рядок" немає. Рядок може бути тільки технічним джерелом, з якого витягується останнє слово, якщо це безпечно для конкретного типу застосунку.

## Спочатку зібрати контекст

Перед читанням тексту потрібно отримати:

- `bundleIdentifier` активного застосунку;
- focused Accessibility element;
- `AXRole`;
- `AXEditable`;
- `AXSelectedText`, тільки як діагностичний сигнал;
- `AXValue`;
- `AXTitle`;
- `AXDescription`;
- `AXIdentifier`;
- поточний системний input source.

## Класифікація застосунку

Класифікувати контекст так:

```text
якщо bundle id у списку standalone terminals:
    appKind = standaloneTerminal

інакше якщо bundle id у списку VS Code / Cursor / Antigravity / схожих редакторів:
    якщо AX role/title/description/identifier/value схожі на terminal/shell/pty:
        appKind = integratedTerminal
    інакше:
        appKind = codeEditor

інакше якщо bundle id у списку браузерів:
    appKind = browser

інакше:
    appKind = other
```

`bundleIdentifier` дає тільки грубий профіль. Остаточне рішення про читання має враховувати focused AX element і фактичний результат `Cmd+C`.

## Обов'язкові профілі застосунків

Політика має явно враховувати всі застосунки й поверхні, які вже фігурували в сценаріях FreePunto. Вони не мають губитися в загальному `other`.

| Застосунок / поверхня | Як класифікувати | Як отримувати текст |
| --- | --- | --- |
| Terminal.app | `standaloneTerminal` за `com.apple.Terminal` | тільки `AXValue` -> останнє слово останнього релевантного рядка |
| iTerm2 | `standaloneTerminal` за `com.googlecode.iterm2` | тільки `AXValue` -> останнє слово |
| Warp | `standaloneTerminal` за `dev.warp.Warp-Stable` | тільки `AXValue` -> останнє слово, якщо AX реально віддає terminal buffer |
| Ghostty | `standaloneTerminal` за `com.mitchellh.ghostty` | тільки `AXValue` -> останнє слово |
| Alacritty | `standaloneTerminal` за `io.alacritty` | тільки `AXValue` -> останнє слово |
| kitty | `standaloneTerminal` за `net.kovidgoyal.kitty` | тільки `AXValue` -> останнє слово |
| WezTerm | `standaloneTerminal` за `com.github.wez.wezterm` | тільки `AXValue` -> останнє слово |
| Hyper | `standaloneTerminal` за `co.zeit.hyper` | тільки `AXValue` -> останнє слово |
| VS Code editor | `codeEditor` за `com.microsoft.VSCode`, якщо focused element не схожий на terminal | спочатку реальне `Cmd+C` виділення; automatic line-copy не вважати виділенням; fallback - останнє слово через `AXValue` або line-copy fallback |
| VS Code integrated terminal | `integratedTerminal`, якщо AX role/title/description/identifier/value схожі на terminal/shell/pty | не використовувати generic selection flow; тільки `AXValue` terminal element -> останнє слово |
| VS Code Insiders / Exploration | як VS Code family | ті самі правила, що для VS Code |
| VSCodium | як VS Code family | ті самі правила, що для VS Code |
| Cursor | як VS Code family; локально підтверджений bundle id: `com.todesktop.230313mzl4w4u92` | ті самі правила, що для VS Code; integrated terminal визначати через AX terminal signals, а не через назву вікна |
| Antigravity / Antigravity IDE | як VS Code family | ті самі правила, що для VS Code; інтегрований термінал перевіряти окремо |
| Google Chrome | `browser` за `com.google.Chrome` | editable: `Cmd+C`, потім `AXValue` last word; non-editable/grid: тільки `Cmd+C` |
| Chrome Canary | `browser` за `com.google.Chrome.canary` | ті самі правила, що для Chrome |
| Safari | `browser` за `com.apple.Safari` | editable: `Cmd+C`, потім `AXValue` last word; non-editable/grid: тільки `Cmd+C` |
| Firefox | `browser` за `org.mozilla.firefox` | pasteboard-first; не покладатися на нестабільні browser AX ranges; editable last-word тільки якщо AXValue реально доступний |
| Brave | `browser` за `com.brave.Browser` | ті самі правила, що для Chrome |
| Microsoft Edge | `browser` за `com.microsoft.edgemac` | ті самі правила, що для Chrome |
| Google Sheets у браузері | `browser` + non-editable/grid-like behavior | тільки `Cmd+C`; не брати останнє слово; заміна потім тільки через grid edit-mode path |
| CanvasTable у браузері | `browser` + non-editable/grid-like behavior | тільки `Cmd+C`; `F2` використовується не для читання, а тільки для входу в edit mode під час запису |
| Звичайне browser textarea/input/contenteditable | `browser editable` | `Cmd+C` для виділення; якщо виділення немає - `AXValue` -> останнє слово, якщо доступно |
| Notes / Pages / інші native text apps | `other editable`, якщо `AXEditable == true` або роль явно текстова | `Cmd+C` для виділення; fallback - `AXValue` -> останнє слово |
| Slack / Discord / Claude-like Electron редактори | не вгадувати за назвою; класифікувати через bundle id + AX role/editable | якщо editable - як editable/code editor; якщо AX недоступний або target не підтверджений - `nil` |

Для Google Sheets і CanvasTable не використовувати заголовок вкладки або `windowTitle` як джерело рішення. Їх потрібно розпізнавати за фактичною поведінкою: браузерний non-editable/grid контекст, який віддає текст через `Cmd+C` і потребує окремого edit-mode path для запису.

## Універсальна спроба `Cmd+C`

Для copy-спроби завжди використовувати безпечний протокол:

```text
1. Зберегти повний snapshot pasteboard.
2. Очистити pasteboard.
3. Запам'ятати pasteboard.changeCount.
4. Надіслати Cmd+C.
5. Почекати короткий timeout.
6. Якщо changeCount змінився і з'явився непорожній string:
       copiedText = string
   інакше:
       copiedText = nil
7. Відновити старий pasteboard.
8. Повернути copiedText.
```

`Cmd+C` доводить тільки те, що текст вдалося прочитати. Він не доводить, що назад можна безпечно вставляти прямим `Cmd+V`.

У code editor потрібно відрізняти реальне виділення від автоматичної копії всього рядка. Якщо редактор без виділення скопіював рядок із переносом рядка в кінці, такий результат не можна вважати виділеним текстом.

## Browser

```text
якщо appKind == browser:

    якщо focused element editable:
        1. спробувати Cmd+C;
        2. якщо отримано реальний текст виділення:
               повернути target origin = copiedEditableSelection;
        3. якщо виділення немає:
               спробувати AXValue;
        4. якщо AXValue дав останнє слово:
               повернути target origin = editableAXLastWord;
        5. інакше повернути nil.

    якщо focused element не editable:
        1. спробувати Cmd+C;
        2. якщо отримано непорожній текст:
               повернути target origin = copiedBrowserGridLike;
        3. інакше повернути nil.
```

Для Google Sheets, CanvasTable та інших web-grid поверхонь не брати останнє слово. Там безпечний target - тільки те, що grid реально віддав через `Cmd+C`.

## Code editor

```text
якщо appKind == codeEditor:

    1. спробувати Cmd+C;

    2. якщо отримано текст і він не схожий на automatic line-copy:
           повернути target origin = copiedCodeEditorSelection;

    3. якщо скопіювався весь рядок:
           не вважати це виділенням;
           витягнути останнє слово з рядка тільки як fallback;
           повернути target origin = codeEditorAXLastWord;

    4. якщо Cmd+C нічого не дав:
           спробувати AXValue;

    5. якщо AXValue дав останнє слово:
           повернути target origin = codeEditorAXLastWord;

    6. інакше повернути nil.
```

Реальне виділення завжди важливіше за останнє слово.

## Integrated terminal

```text
якщо appKind == integratedTerminal:

    1. не використовувати звичайний selection flow;
    2. спробувати AXValue активного terminal element;
    3. взяти останній непорожній рядок;
    4. із нього взяти останнє слово;
    5. якщо слово знайдено:
           повернути target origin = integratedTerminalAXLastWord;
       інакше:
           повернути nil.
```

## Standalone terminal

```text
якщо appKind == standaloneTerminal:

    1. спробувати AXValue;
    2. взяти останній непорожній рядок terminal buffer;
    3. із нього взяти останнє слово;
    4. якщо слово знайдено:
           повернути target origin = standaloneTerminalAXLastWord;
       інакше:
           повернути nil.
```

Для терміналів політика проста: без користувацького виділення працюємо тільки з останнім словом поточної команди. Не використовувати `Control+C`, `Return`, `F2`, `Cmd+A`, double click або `Cmd+Shift+Left` для отримання тексту.

## Other app

```text
якщо appKind == other:

    якщо focused element editable:
        1. спробувати Cmd+C;
        2. якщо отримано реальний текст виділення:
               повернути target origin = copiedEditableSelection;
        3. інакше спробувати AXValue;
        4. якщо AXValue дав останнє слово:
               повернути target origin = editableAXLastWord;
        5. інакше повернути nil.

    якщо focused element не editable:
        повернути nil.
```

Для невідомого non-editable контексту не читати і не замінювати текст. Винятки потрібно додавати тільки як окремі підтверджені профілі.

## Що має містити `TextTarget`

```text
TextTarget:
    text
    origin
    wordLength
    trailingSpacesCount
    appKind
    replaceStrategyHint
```

`origin` має описувати фактичний спосіб читання, а не припущення:

```text
copiedEditableSelection
copiedCodeEditorSelection
copiedBrowserGridLike
editableAXLastWord
codeEditorAXLastWord
integratedTerminalAXLastWord
standaloneTerminalAXLastWord
```

Заміна має вибирати стратегію тільки за `origin`.

## Safety policy

Команда має повернути `nil`, якщо:

- немає Accessibility і немає безпечного fallback;
- `Cmd+C` не дав непорожній текст;
- `AXValue` недоступний або з нього не можна отримати останнє слово;
- застосунок non-editable і не є відомим browser/grid профілем;
- browser/grid не віддав текст через `Cmd+C`;
- сигнали суперечать один одному;
- стратегія запису для знайденого target не підтверджена.

## Короткий prompt для реалізації

```text
Отримати текстову ціль для FreePunto.

1. Збери bundle id, focused AX element, AXRole, AXEditable, AXValue,
   AXTitle, AXDescription, AXIdentifier і поточний input source.

2. Класифікуй застосунок:
   standaloneTerminal, integratedTerminal, codeEditor, browser або other.

3. Для всіх editable/codeEditor/browser сценаріїв спочатку пробуй Cmd+C
   через безпечний pasteboard snapshot protocol.

4. Не приймай automatic line-copy у code editor як користувацьке виділення.

5. Якщо реального виділення немає, бери останнє слово тільки там, де це
   дозволено політикою:
   editable AXValue, codeEditor AXValue/line-copy fallback, terminal AXValue.

6. Для browser non-editable/grid бери тільки те, що повернув Cmd+C.
   Не намагайся брати останнє слово.

7. Поверни TextTarget із точним origin читання.

8. Якщо є сумнів, поверни nil.
```

## Пов'язані документи

- `docs/TEXT_INTERACTION_SCENARIOS.md`
- `docs/TEXT_INTERACTION_IMPLEMENTATION_PLAN.md`
- `docs/EXTERNAL_PROJECTS_PROPOSALS.md`

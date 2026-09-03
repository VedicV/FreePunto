# Пропозиції після аналізу зовнішніх перемикачів розкладки

Дата аналізу: 2026-06-18.

## Контекст FreePunto

FreePunto потрібно тримати в поточному продуктовому контракті:

- тільки macOS;
- ручні команди, без фонової автокорекції;
- основна команда за замовчуванням через одиночний `Control`;
- виділений текст або останнє слово;
- після успішного перетворення - системне перемикання розкладки на мову результату;
- без історії набору, телеметрії, мережі та власного undo.

Тому нижче відібрані не всі можливості зовнішніх проєктів, а тільки те, що можна взяти без перетворення FreePunto на фоновий автокоректор.

## Вивчені задані проєкти

### OleksandrCEO/MagShift

Джерело: https://github.com/OleksandrCEO/MagShift

Що робить:

- Linux-інструмент на Python/evdev/uinput.
- Слухає фізичну клавіатуру, тримає короткий буфер keycode+Shift, за подвійним Right Shift видаляє набране, перемикає системну розкладку через налаштований хоткей і програє ті самі keycode назад.
- Не конвертує текст таблицями; використовує факт, що повтор тих самих фізичних клавіш після перемикання розкладки дасть потрібний текст.
- Має явні таймінги для стабільності: тривалість хоткея, settle після перемикання, затримка між backspace/replay.
- Скидає буфер за таймаутом, Enter/Tab/Esc, Backspace, Meta/CapsLock і модифікаторними комбінаціями.
- Для Linux акуратно вирішує доступ до `/dev/input` і `uinput` через udev `uaccess`/`seat`, без додавання користувача до груп `input`/`uinput`.
- Дає корисні dev-команди: `--list`, `--verbose`, вибір стилю хоткея.

Що корисно для FreePunto:

- Ввести явну модель "транзакції заміни": reset modifier state -> видалити старе -> дочекатися settle -> вставити/надрукувати нове -> відновити стан. Зараз це є частинами в `TextIOController`, але параметри варто централізовано описати й логувати.
- Додати діагностичний режим, схожий на `--list/--verbose`: список input sources, frontmost bundle id, focused AX role, вибрана стратегія читання/заміни, остання причина відмови.
- Залишити ідею короткого keycode-buffer як опційний дослідницький шлях тільки для майбутньої ручної команди "останнє набране", не для фонового режиму.
- Не переносити Linux-специфіку, uinput і сервісну модель: це не підходить macOS-застосунку.

### rundax/SwitchFix

Джерело: https://github.com/rundax/SwitchFix

Що робить:

- Нативний macOS Swift-застосунок, близький за платформою до FreePunto.
- Має два режими: автоматична корекція на межах слів і hotkey-only.
- `KeyboardMonitor` ставить listen-only `CGEventTap`, пробує `.cgSessionEventTap`, потім `.cghidEventTap`.
- Для символів використовує `keyboardGetUnicodeString`, а за потреби перекладає keyCode через поточну TIS-розкладку з `UCKeyTranslate`.
- `LayoutDetector` веде state machine, буфер слова, low-confidence логіку, приглушення коротких сумнівних слів і контекстне підтвердження.
- `WordValidator` фільтрує URL/email/числа/camelCase, перевіряє очікуваний script і словники EN/RU/UA.
- Словники винесені в окремий модуль, є `.bin` формат, `mmap` fallback/fast path і performance test runner.
- `TextCorrector` видаляє неправильний текст backspace-подіями, друкує Unicode через `keyboardSetUnicodeString`, окремо підтримує undo/revert window.
- Є app blacklist за замовчуванням для терміналів, IDE і редакторів.
- Є TCC/dev UX: попередження про ad-hoc signing, `SWITCHFIX_CODESIGN_IDENTITY`, `scripts/regrant-permissions.sh`.
- Є GitHub release workflow, який збирає arm64 та Intel артефакти окремо.

Що корисно для FreePunto:

- Забрати TCC/dev tooling: скрипт regrant-permissions, документований stable signing identity, installed-app audit.
- Не додавати окремий secure/password guard у поточну ручну команду; це не входить у нинішній scope.
- Винести "останню причину відмови" в діагностику: немає AX, target не editable, Cmd+C порожній, F2 не дав edit mode, TIS source не знайдено.
- Розглянути `keyboardSetUnicodeString` як експериментальний fallback для last-word replacement, де pasteboard дає поганий результат. Вмикати тільки після ручних тестів, бо pasteboard краще зберігає звичайний undo цільового застосунку.
- Не переносити auto-correction, словники, history і власний undo в основний продуктовий контракт.

## Додатково знайдені схожі проєкти

| Проєкт | Релевантність | Що можна взяти |
| --- | --- | --- |
| https://github.com/rashn/RuSwitcher | Висока: macOS Swift, manual Alt, selection/last word | Dynamic layout mapping через `UCKeyTranslate`, робота з будь-якою парою встановлених розкладок, permission wizard, Homebrew cask |
| https://github.com/reg2005/langSwitcher | Висока за UX, але ширше нашого scope | Режим manual "greedy line" як окрема команда, універсальні DMG, GitHub Pages docs; conversion log не брати за замовчуванням |
| https://github.com/abaskalov/perekluk | Висока: мінімальний macOS switcher | Підтримка dead keys, configurable trigger, кілька розкладок, menu-bar current layout indicator |
| https://github.com/bobjer/retype | Середня: selection-first macOS converter | Homebrew cask, double-press timeout setting, зрозуміла TCC troubleshooting секція |
| https://github.com/gjoob/lapsusfix | Дуже висока за філософією privacy/manual | Не слухати потік введення, читати текст тільки за hotkey, детальна матриця відомих обмежень за застосунками, verbose logging off by default |
| https://github.com/spendolas/traple | Висока як інженерний reference | Stable self-signed dev signing, per-app strategy, input-source picker, raw keycode buffer translated at terminator time, Secure Keyboard Entry/Accessibility polling |
| https://github.com/rshagiev/punto-switcher | Висока за сумісністю | Safe no-op when target cannot be verified, deploy script that preserves Accessibility permission, installed bundle audit, focused regression scripts |
| https://github.com/weird-mirror/keyflow | Середня: automatic-first | Secure Keyboard Entry warning, password-field guard, in-memory current-word buffer boundaries; auto-mode і dictionaries не брати |
| https://github.com/dslabakov/layout-switcher | Низька-середня: Python/macOS auto-corrector | Ідея onboarding/status indicator для missing permissions; Python/runtime dependency path нам не підходить |

## Пріоритетні пропозиції

### P0 - TCC і dev/release стійкість

Зробити:

- `scripts/regrant_permissions.sh` для FreePunto: зупинити застосунок, скинути Accessibility/Input Monitoring для bundle id, відкрити потрібні System Settings panes, запустити `.app`.
- Підтримати `FREEPUNTO_CODESIGN_IDENTITY` у `scripts/build_app.sh` і `scripts/build_dmg.sh`, з ad-hoc fallback і явним попередженням, що TCC може скидатися.
- Додати `scripts/audit_installed_app.sh`: bundle id, підпис, шлях `/Applications/FreePunto.app`, версія, наявність Accessibility/Input Monitoring.
- Документувати стабільний dev-підпис у `docs/INSTALL_USAGE.md` або окремому dev-розділі.

Чому:

- Це напряму зменшує клас багів "зібралося, але hotkey/replacement не працює".
- SwitchFix, Traple, Retype і rshagiev/punto-switcher усі впираються в один і той самий macOS TCC факт: дозвіл прив'язаний до identity/signature/path.

### P0 - Діагностичний звіт усередині застосунку

Зробити menu item "Diagnostics..." або "Copy Diagnostics Report":

- версія FreePunto і bundle path;
- Accessibility/Input Monitoring status;
- frontmost app bundle id/name;
- focused AX role/title/identifier/value availability, без тексту за замовчуванням;
- detected app kind: browser/codeEditor/terminal/other;
- active input sources і вибрані source ids для EN/RU/UA;
- event tap status;
- остання команда: read origin, replace strategy, success/failure reason.

Чому:

- Зараз runtime path складний: browsers, code editors, terminals і grid-like surfaces мають різні стратегії.
- Це дасть швидкий root-cause без повторного додавання raw logging у код.

### P0 - Приватність логів

Зробити:

- За замовчуванням не писати в release-лог самі слова або фрагменти користувацького тексту.
- Залишити метадані: довжина, origin, app kind, bundle id, role, стратегія, код помилки.
- Текстові snippets дозволяти тільки за явним `FREEPUNTO_TRACE_TEXT=1` або ручним verbose toggle з попередженням.
- Переглянути поточні `trace(...)` у `TextIOController`: там є повідомлення зі словом/value prefix, а `trace` завжди пише в `rawLog`.

Чому:

- FreePunto обіцяє privacy-first і відсутність історії введення.
- LapsusFix добре формулює межу: verbose off by default, у звичайних логах немає вмісту полів.

### P1 - Dynamic layout mapping через `UCKeyTranslate`

Зробити:

- Додати новий mapper, який будує відповідність символів із встановлених TIS input sources через `UCKeyTranslate`.
- Зберегти поточні EN/RU/UA таблиці як стабільний fallback і regression baseline.
- Покрити тестами punctuation, Shift, Ukrainian Legacy/PC, Russian PC, dead keys.

Чому:

- RuSwitcher, Perekluk, Retype, SwitchFix і Traple всі сходяться на системних layout data замість ручних таблиць.
- Це вирішить частину українських варіантів і майбутню підтримку користувацьких розкладок без розростання словників.

### P1 - Вибір конкретних input sources користувачем

Зробити:

- У налаштуваннях показувати встановлені macOS input sources.
- Для кожної підтриманої мови/цілі дати вибрати конкретний source id.
- Якщо не вибрано - використовувати поточний scoring в `InputSourceController`.

Чому:

- У нас уже був клас бага "перемикає спочатку не туди", і root cause був у виборі input source.
- Traple/RuSwitcher/Perekluk показують, що users with non-canonical layouts потребують явного source picker.

### P1 - Матриця сумісності застосунків

Зробити:

- Оновити `docs/TEXT_INTERACTION_SCENARIOS.md` як живу таблицю: Safari, Chrome, Firefox, Google Sheets, VS Code editor, VS Code terminal, Cursor editor, Cursor terminal, Antigravity editor, Antigravity terminal, Terminal.app, iTerm2, Pages, Notes, Slack/Discord/Claude-like Electron.
- Для кожного: selection read, last word read, replacement, known caveat, expected fallback.
- У коді тримати відмову від дії, якщо target не підтверджено безпечно.

Чому:

- LapsusFix і rshagiev/punto-switcher явно виграють завдяки чесним known limitations.
- Для FreePunto краще missed conversion, ніж видалення/вставка в неправильне поле.

### P1 - App-specific strategy overrides, але не blacklist-first

Зробити:

- Не вводити default blacklist як у SwitchFix: FreePunto ручний, тому IDE/термінали є важливими цільовими застосунками.
- Замість blacklist завести internal strategy table: terminal -> terminal strategy, browser grid -> F2 strategy, editor -> copy/line-copy strategy.
- У налаштуваннях можна додати "Disable in current app" пізніше, якщо з'являться реальні скарги.

Чому:

- SwitchFix blacklist потрібен автоматичному режиму. Для ручної утиліти він може неочікувано прибрати корисний сценарій.

### P2 - Експериментальний replacement fallback через Unicode events

Зробити:

- Прототипувати `keyboardSetUnicodeString` для controlled cases.
- Порівняти з поточним pasteboard path за: undo у target app, браузери, Electron, Terminal, Google Sheets.
- Не вмикати за замовчуванням без матриці тестів.

Чому:

- SwitchFix показує, що Unicode events можуть друкувати незалежно від поточної розкладки.
- Але для FreePunto зараз важливіші predictability і native undo target app, тому потрібен експеримент, не пряме перенесення.

### P2 - Ручна команда "виправити фразу до початку рядка"

Зробити:

- Розглянути окрему команду, яка не замінює основну: вибрати від cursor до початку рядка, знайти початок wrong-layout segment, перетворити тільки цей segment.
- Не вмикати автодетект/словник/логування історії.

Чому:

- LangSwitcher Greedy Line вирішує частий випадок "уся фраза не в тій розкладці".
- Це все ще manual-only, якщо команда викликається явно.

### P2 - Публічне пакування

Зробити:

- GitHub Actions release workflow для tag `v*`.
- Збирати arm64 і Intel/Universal DMG.
- Після стабілізації - Homebrew cask.
- У release notes явно писати Gatekeeper/TCC нюанси.

Чому:

- SwitchFix, RuSwitcher, Retype і langSwitcher знижують friction встановлення через Releases/Homebrew.

## Що не варто переносити

- Фонову автокорекцію за кожним словом.
- Словники і language guessing як основний шлях.
- Історію виправлень/conversion log за замовчуванням.
- Власний undo/revert window.
- Linux/uinput/Nix/systemd scope із MagShift.
- `Option` як default trigger: для FreePunto вже вибрано `Control`.
- Default blacklist для IDE/терміналів.

## Рекомендований порядок робіт

1. P0: TCC scripts, stable signing env var, installed-app audit.
2. P0: diagnostics report і redacted logging.
3. P1: input-source picker + діагностика вибраних source ids.
4. P1: `UCKeyTranslate` mapper prototype за feature flag/fallback.
5. P1: compatibility matrix і ручна перевірка ключових застосунків.
6. P2: Unicode event replacement experiment.
7. P2: release workflow/Homebrew cask.

## Джерела

- MagShift: https://github.com/OleksandrCEO/MagShift
- SwitchFix: https://github.com/rundax/SwitchFix
- RuSwitcher: https://github.com/rashn/RuSwitcher
- LangSwitcher: https://github.com/reg2005/langSwitcher
- Perekluk: https://github.com/abaskalov/perekluk
- Retype: https://github.com/bobjer/retype
- LapsusFix: https://github.com/gjoob/lapsusfix
- Traple: https://github.com/spendolas/traple
- rshagiev/punto-switcher: https://github.com/rshagiev/punto-switcher
- KeyFlow: https://github.com/weird-mirror/keyflow
- dslabakov/layout-switcher: https://github.com/dslabakov/layout-switcher

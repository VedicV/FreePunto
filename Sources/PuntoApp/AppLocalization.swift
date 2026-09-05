import Foundation
import PuntoCore

// * -- Локалізація меню і налаштувань --
enum AppText {
    enum Key: String {
        case pause
        case resume
        case convertLayout
        case changeCase
        case transliterate
        case switchingMode
        case fixedTarget
        case transliterationTarget
        case caseMode
        case interfaceLanguage
        case settings
        case launchAtLogin
        case disableLaunchAtLogin
        case permissions
        case quit
        case version
        case enabled
        case mainHotkey
        case restoreControl
        case useSingleControl
        case caseHotkey
        case transliterationHotkey
        case pauseHotkey
        case openPermissions
        case record
        case pressKeys
        case settingsTitle
        case globalHotkeysUnavailable
        case globalHotkeysUnavailableDetail
        case couldNotReplaceText
        case inputSourceUnavailable
        case addInputSourceDetail
        case launchAtLoginUnavailable
        case permissionsTitle
        case permissionsEnabledDetail
        case permissionsMissingDetail
        case openAccessibility
        case openInputMonitoring
        case close
        case lowercase
        case sentenceCase
        case titleCase
        case normalizeCapsLock
        case sequentialMode
        case fixedTargetMode
    }

    // * -- Текст за ключем --
    static func get(_ key: Key, _ language: InterfaceLanguage) -> String {
        switch language {
        case .russian:
            return russian[key] ?? english[key]!
        case .ukrainian:
            return ukrainian[key] ?? english[key]!
        case .english:
            return english[key]!
        }
    }

    // * -- Отримання локалізованої назви для режиму перемикання --
    static func switchingModeTitle(_ mode: SwitchingMode, _ language: InterfaceLanguage) -> String {
        switch mode {
        case .sequential:
            return get(.sequentialMode, language)
        case .fixedTarget:
            return get(.fixedTargetMode, language)
        }
    }

    // * -- Отримання локалізованої назви для режиму зміни регістру --
    static func caseModeTitle(_ mode: CaseMode, _ language: InterfaceLanguage) -> String {
        switch mode {
        case .lower:
            return get(.lowercase, language)
        case .sentence:
            return get(.sentenceCase, language)
        case .title:
            return get(.titleCase, language)
        case .normalizeCapsLock:
            return get(.normalizeCapsLock, language)
        }
    }

// * -- Локалізовані словники для кожної мови --
    private static let russian: [Key: String] = [
        .pause: "Пауза",
        .resume: "Продолжить",
        .convertLayout: "Сменить раскладку",
        .changeCase: "Изменить регистр",
        .transliterate: "Транслитерация",
        .switchingMode: "Режим переключения",
        .fixedTarget: "Цель раскладки",
        .transliterationTarget: "Цель транслитерации",
        .caseMode: "Регистр",
        .interfaceLanguage: "Язык меню",
        .settings: "Горячие клавиши и настройки...",
        .launchAtLogin: "Запускать при входе",
        .disableLaunchAtLogin: "Не запускать при входе",
        .permissions: "Разрешения...",
        .quit: "Выйти из FreePunto",
        .version: "Версия",
        .enabled: "Включено",
        .mainHotkey: "Смена раскладки",
        .restoreControl: "Вернуть Control",
        .useSingleControl: "Использовать Control для смены раскладки",
        .caseHotkey: "Клавиша регистра",
        .transliterationHotkey: "Клавиша транслитерации",
        .pauseHotkey: "Клавиша паузы",
        .openPermissions: "Открыть запрос разрешений",
        .record: "Записать",
        .pressKeys: "Нажмите клавиши...",
        .settingsTitle: "Настройки FreePunto",
        .globalHotkeysUnavailable: "Горячие клавиши недоступны",
        .globalHotkeysUnavailableDetail:
            "Разрешите Accessibility и Input Monitoring для FreePunto, затем перезапустите приложение. Если разрешения уже включены, удалите FreePunto из списка (кнопкой «-»), добавьте заново, полностью выйдите из приложения и запустите его еще раз.",
        .couldNotReplaceText: "Не удалось заменить текст",
        .inputSourceUnavailable: "Раскладка недоступна",
        .addInputSourceDetail: "Добавьте раскладку %@ в настройках клавиатуры macOS.",
        .launchAtLoginUnavailable: "Не удалось включить запуск при входе",
        .permissionsTitle: "Разрешения FreePunto",
        .permissionsEnabledDetail:
            "Доступность (Accessibility) включена.\n\nЧтобы удалить FreePunto перед установкой новой версии или сбросить доступ, откройте Системные настройки и удалите приложение из списка (кнопкой «-»).\n\nДля глобальных клавиш также может потребоваться Мониторинг ввода.",
        .permissionsMissingDetail:
            "Включите доступность для FreePunto в Системных настройках (Конфиденциальность и безопасность -> Универсальный доступ).\n\nДля глобальных клавиш также может потребоваться Мониторинг ввода.",
        .openAccessibility: "Открыть «Универсальный доступ»",
        .openInputMonitoring: "Открыть «Мониторинг ввода»",
        .close: "Закрыть",
        .lowercase: "Нижний регистр",
        .sentenceCase: "Регистр предложения",
        .titleCase: "Первые буквы слов",
        .normalizeCapsLock: "Исправить Caps Lock",
        .sequentialMode: "По кругу",
        .fixedTargetMode: "Фиксированная цель",
    ]

    // * -- Локалізований словник для української мови -- 
    private static let ukrainian: [Key: String] = [
        .pause: "Пауза",
        .resume: "Продовжити",
        .convertLayout: "Змінити розкладку",
        .changeCase: "Змінити регістр",
        .transliterate: "Транслітерація",
        .switchingMode: "Режим перемикання",
        .fixedTarget: "Ціль розкладки",
        .transliterationTarget: "Ціль транслітерації",
        .caseMode: "Регістр",
        .interfaceLanguage: "Мова меню",
        .settings: "Гарячі клавіші й налаштування...",
        .launchAtLogin: "Запускати при вході",
        .disableLaunchAtLogin: "Не запускати при вході",
        .permissions: "Дозволи...",
        .quit: "Вийти з FreePunto",
        .version: "Версія",
        .enabled: "Увімкнено",
        .mainHotkey: "Зміна розкладки",
        .restoreControl: "Повернути Control",
        .useSingleControl: "Використовувати Control для зміни розкладки",
        .caseHotkey: "Клавіша регістру",
        .transliterationHotkey: "Клавіша транслітерації",
        .pauseHotkey: "Клавіша паузи",
        .openPermissions: "Відкрити запит дозволів",
        .record: "Записати",
        .pressKeys: "Натисніть клавіші...",
        .settingsTitle: "Налаштування FreePunto",
        .globalHotkeysUnavailable: "Гарячі клавіші недоступні",
        .globalHotkeysUnavailableDetail:
            "Дозвольте Accessibility та Input Monitoring для FreePunto, потім перезапустіть застосунок. Якщо дозволи вже надано, видаліть FreePunto зі списку (кнопкою «-»), додайте знову, повністю вийдіть із застосунку та запустіть його ще раз.",
        .couldNotReplaceText: "Не вдалося замінити текст",
        .inputSourceUnavailable: "Розкладка недоступна",
        .addInputSourceDetail: "Додайте розкладку %@ у налаштуваннях клавіатури macOS.",
        .launchAtLoginUnavailable: "Не вдалося ввімкнути запуск при вході",
        .permissionsTitle: "Дозволи FreePunto",
        .permissionsEnabledDetail:
            "Доступність (Accessibility) увімкнено.\n\nЩоб видалити FreePunto перед встановленням нової версії або скинути доступ, відкрийте Системні параметри та видаліть застосунок зі списку (кнопкою «-»).\n\nДля глобальних клавіш також може знадобитися Моніторинг вводу.",
        .permissionsMissingDetail:
            "Увімкніть доступність для FreePunto у Системних параметрах (Приватність і безпека -> Доступність).\n\nДля глобальних клавіш також може знадобитися Моніторинг вводу.",
        .openAccessibility: "Відкрити «Доступність»",
        .openInputMonitoring: "Відкрити «Моніторинг вводу»",
        .close: "Закрити",
        .lowercase: "Нижній регістр",
        .sentenceCase: "Регістр речення",
        .titleCase: "Перші літери слів",
        .normalizeCapsLock: "Виправити Caps Lock",
        .sequentialMode: "По колу",
        .fixedTargetMode: "Фіксована ціль",
    ]

    // * -- Локалізований словник для англійської мови -- 
    private static let english: [Key: String] = [
        .pause: "Pause",
        .resume: "Resume",
        .convertLayout: "Convert layout",
        .changeCase: "Change case",
        .transliterate: "Transliterate",
        .switchingMode: "Switching mode",
        .fixedTarget: "Fixed target",
        .transliterationTarget: "Transliteration target",
        .caseMode: "Case mode",
        .interfaceLanguage: "Menu language",
        .settings: "Hotkeys and settings...",
        .launchAtLogin: "Launch at login",
        .disableLaunchAtLogin: "Disable launch at login",
        .permissions: "Permissions...",
        .quit: "Quit FreePunto",
        .version: "Version",
        .enabled: "Enabled",
        .mainHotkey: "Keyboard layout switch",
        .restoreControl: "Restore Control",
        .useSingleControl: "Use Control for layout switching",
        .caseHotkey: "Case hotkey",
        .transliterationHotkey: "Transliteration hotkey",
        .pauseHotkey: "Pause hotkey",
        .openPermissions: "Open permissions prompt",
        .record: "Record",
        .pressKeys: "Press keys...",
        .settingsTitle: "FreePunto Settings",
        .globalHotkeysUnavailable: "Global hotkeys are unavailable",
        .globalHotkeysUnavailableDetail:
            "Enable Accessibility and Input Monitoring for FreePunto, then restart the app. If permissions are already enabled, remove FreePunto from the list (using the '-' button), add it again, fully quit the app, and launch it one more time.",
        .couldNotReplaceText: "Could not replace text",
        .inputSourceUnavailable: "Input source is not available",
        .addInputSourceDetail: "Add %@ keyboard layout in macOS System Settings.",
        .launchAtLoginUnavailable: "Launch at login is unavailable",
        .permissionsTitle: "FreePunto permissions",
        .permissionsEnabledDetail:
            "Accessibility permission is enabled.\n\nTo remove FreePunto before installing a new version or reset permissions, open System Settings and remove the app from the list (using the '-' button).\n\nInput Monitoring may also be required for global hotkeys.",
        .permissionsMissingDetail:
            "Enable Accessibility for FreePunto in System Settings (Privacy & Security -> Accessibility).\n\nInput Monitoring may also be required for global hotkeys.",
        .openAccessibility: "Open Accessibility",
        .openInputMonitoring: "Open Input Monitoring",
        .close: "Close",
        .lowercase: "Lowercase",
        .sentenceCase: "Sentence case",
        .titleCase: "Title Case",
        .normalizeCapsLock: "Normalize Caps Lock",
        .sequentialMode: "Sequential",
        .fixedTargetMode: "Fixed target",
    ]
}

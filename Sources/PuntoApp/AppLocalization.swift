import Foundation
import PuntoCore

// * -- Локализация меню и настроек --
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
        case lowercase
        case sentenceCase
        case titleCase
        case normalizeCapsLock
        case sequentialMode
        case fixedTargetMode
    }

    // * -- Текст по ключу --
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

    static func switchingModeTitle(_ mode: SwitchingMode, _ language: InterfaceLanguage) -> String {
        switch mode {
        case .sequential:
            return get(.sequentialMode, language)
        case .fixedTarget:
            return get(.fixedTargetMode, language)
        }
    }

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
            "Разрешите Accessibility и Input Monitoring для FreePunto, затем перезапустите приложение. Если разрешения уже включены, удалите приложение из списка (кнопкой «-») и добавьте заново.",
        .couldNotReplaceText: "Не удалось заменить текст",
        .inputSourceUnavailable: "Раскладка недоступна",
        .addInputSourceDetail: "Добавьте раскладку %@ в настройках клавиатуры macOS.",
        .launchAtLoginUnavailable: "Не удалось включить запуск при входе",
        .permissionsTitle: "Разрешения FreePunto",
        .permissionsEnabledDetail:
            "Accessibility включен. Для глобальных клавиш и одиночного Control может также понадобиться Input Monitoring.",
        .permissionsMissingDetail:
            "Включите Accessibility для FreePunto в System Settings -> Privacy & Security -> Accessibility. Для глобальных клавиш и одиночного Control может также понадобиться Input Monitoring.",
        .lowercase: "Нижний регистр",
        .sentenceCase: "Регистр предложения",
        .titleCase: "Первые буквы слов",
        .normalizeCapsLock: "Исправить Caps Lock",
        .sequentialMode: "По кругу",
        .fixedTargetMode: "Фиксированная цель",
    ]

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
            "Дозвольте Accessibility та Input Monitoring для FreePunto, потім перезапустіть застосунок. Якщо дозволи вже надано, видаліть FreePunto зі списку (кнопкою «-») та додайте знову.",
        .couldNotReplaceText: "Не вдалося замінити текст",
        .inputSourceUnavailable: "Розкладка недоступна",
        .addInputSourceDetail: "Додайте розкладку %@ у налаштуваннях клавіатури macOS.",
        .launchAtLoginUnavailable: "Не вдалося ввімкнути запуск при вході",
        .permissionsTitle: "Дозволи FreePunto",
        .permissionsEnabledDetail:
            "Accessibility увімкнено. Для глобальних клавіш і одиночного Control також може знадобитися Input Monitoring.",
        .permissionsMissingDetail:
            "Увімкніть Accessibility для FreePunto в System Settings -> Privacy & Security -> Accessibility. Для глобальних клавіш і одиночного Control також може знадобитися Input Monitoring.",
        .lowercase: "Нижній регістр",
        .sentenceCase: "Регістр речення",
        .titleCase: "Перші літери слів",
        .normalizeCapsLock: "Виправити Caps Lock",
        .sequentialMode: "По колу",
        .fixedTargetMode: "Фіксована ціль",
    ]

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
            "Enable Accessibility and Input Monitoring for FreePunto, then restart the app. If permissions are already enabled, remove FreePunto from the list (using the '-' button) and add it again.",
        .couldNotReplaceText: "Could not replace text",
        .inputSourceUnavailable: "Input source is not available",
        .addInputSourceDetail: "Add %@ keyboard layout in macOS System Settings.",
        .launchAtLoginUnavailable: "Launch at login is unavailable",
        .permissionsTitle: "FreePunto permissions",
        .permissionsEnabledDetail:
            "Accessibility permission is enabled. Input Monitoring may still be required for global hotkeys and single Control.",
        .permissionsMissingDetail:
            "Enable Accessibility for FreePunto in System Settings -> Privacy & Security -> Accessibility. Input Monitoring may also be required for global hotkeys and single Control.",
        .lowercase: "Lowercase",
        .sentenceCase: "Sentence case",
        .titleCase: "Title Case",
        .normalizeCapsLock: "Normalize Caps Lock",
        .sequentialMode: "Sequential",
        .fixedTargetMode: "Fixed target",
    ]
}

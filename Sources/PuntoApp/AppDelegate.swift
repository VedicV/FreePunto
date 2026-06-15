import AppKit
import PuntoCore

// * -- Главный контроллер menu bar приложения --
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private let textIO = TextIOController()
    private let inputSources = InputSourceController()
    private var statusItem: NSStatusItem?
    private var hotKeys: HotKeyController?
    private var settingsWindowController: SettingsWindowController?

    // * -- Запуск приложения и подключение системных обработчиков --
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        state.onSettingsChanged = { [weak self] in
            self?.refreshAfterSettingsChange()
        }

        hotKeys = HotKeyController(
            settingsProvider: { [weak state] in state?.settings ?? .default },
            actions: HotKeyController.Actions(
                main: { [weak self] in self?.performLayoutConversion() },
                letterCase: { [weak self] in self?.performCaseConversion() },
                transliteration: { [weak self] in self?.performTransliteration() },
                pause: { [weak self] in self?.toggleEnabled() }
            )
        )

        rebuildMenu()

        if Diagnostics.accessibilityTrusted(prompt: false) {
            hotKeys?.start()
        } else {
            _ = Diagnostics.accessibilityTrusted(prompt: true)
            Diagnostics.showPermissionsWindow(language: state.settings.interfaceLanguage)
        }
    }

    // * -- Остановка глобальных обработчиков --
    func applicationWillTerminate(_ notification: Notification) {
        hotKeys?.stop()
    }

    // * -- Применение измененных настроек --
    private func refreshAfterSettingsChange() {
        if Diagnostics.accessibilityTrusted(prompt: false) {
            hotKeys?.start()
        }
        rebuildMenu()
    }

    // * -- Сборка меню status bar --
    private func rebuildMenu() {
        guard let statusItem else {
            return
        }

        statusItem.button?.title = ""
        statusItem.button?.image = statusIcon()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = statusTooltip()

        let menu = NSMenu()
        menu.addItem(makeItem(title: t(state.settings.isEnabled ? .pause : .resume), action: #selector(toggleEnabled)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: commandTitle(.convertLayout, hotKey: state.settings.mainHotKey), action: #selector(convertLayoutFromMenu)))
        menu.addItem(makeItem(title: commandTitle(.changeCase, hotKey: state.settings.caseHotKey), action: #selector(changeCaseFromMenu)))
        menu.addItem(makeItem(title: commandTitle(.transliterate, hotKey: state.settings.transliterationHotKey), action: #selector(transliterateFromMenu)))
        menu.addItem(.separator())
        menu.addItem(modeMenuItem())
        menu.addItem(fixedTargetMenuItem())
        menu.addItem(transliterationTargetMenuItem())
        menu.addItem(caseModeMenuItem())
        menu.addItem(interfaceLanguageMenuItem())
        menu.addItem(.separator())
        menu.addItem(makeItem(title: t(.settings), action: #selector(openSettings)))

        let launchTitle = state.settings.launchAtLogin ? t(.disableLaunchAtLogin) : t(.launchAtLogin)
        menu.addItem(makeItem(title: launchTitle, action: #selector(toggleLaunchAtLogin)))
        menu.addItem(makeItem(title: t(.permissions), action: #selector(openPermissions)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: t(.quit), action: #selector(quit)))

        statusItem.menu = menu
    }

    // * -- Иконка status bar --
    private func statusIcon() -> NSImage {
        guard state.settings.isEnabled else {
            return StatusIconFactory.make(.paused)
        }

        return StatusIconFactory.make(.language(
            state.engine.nextLayoutLanguageHint(settings: state.settings),
            fixedMode: state.settings.switchingMode == .fixedTarget
        ))
    }

    // Tooltip оставляем текстовым, чтобы по hover было понятно текущее состояние.
    private func statusTooltip() -> String {
        guard state.settings.isEnabled else {
            return "FreePunto: PAUSE"
        }

        let hint = state.engine.nextLayoutLanguageHint(settings: state.settings).statusTitle
        return state.settings.switchingMode == .fixedTarget ? "FreePunto: \(hint)*" : "FreePunto: \(hint)"
    }

    private func t(_ key: AppText.Key) -> String {
        AppText.get(key, state.settings.interfaceLanguage)
    }

    private func commandTitle(_ key: AppText.Key, hotKey: HotKey) -> String {
        "\(t(key)) (\(hotKey.displayTitle))"
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // Меню режима переключения.
    private func modeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: t(.switchingMode), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for mode in SwitchingMode.allCases {
            let child = NSMenuItem(title: AppText.switchingModeTitle(mode, state.settings.interfaceLanguage), action: #selector(setSwitchingMode(_:)), keyEquivalent: "")
            child.target = self
            child.representedObject = mode.rawValue
            child.state = state.settings.switchingMode == mode ? .on : .off
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    // Меню фиксированной цели.
    private func fixedTargetMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: t(.fixedTarget), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for language in [PuntoLanguage.russian, .ukrainian] {
            let child = NSMenuItem(title: language.statusTitle, action: #selector(setFixedTarget(_:)), keyEquivalent: "")
            child.target = self
            child.representedObject = language.rawValue
            child.state = state.settings.fixedTargetLanguage == language ? .on : .off
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    // Меню цели транслитерации.
    private func transliterationTargetMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: t(.transliterationTarget), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for language in [PuntoLanguage.russian, .ukrainian] {
            let child = NSMenuItem(title: language.statusTitle, action: #selector(setTransliterationTarget(_:)), keyEquivalent: "")
            child.target = self
            child.representedObject = language.rawValue
            child.state = state.settings.transliterationTargetLanguage == language ? .on : .off
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    // Меню режима регистра.
    private func caseModeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: t(.caseMode), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for mode in CaseMode.allCases {
            let child = NSMenuItem(title: AppText.caseModeTitle(mode, state.settings.interfaceLanguage), action: #selector(setCaseMode(_:)), keyEquivalent: "")
            child.target = self
            child.representedObject = mode.rawValue
            child.state = state.settings.caseMode == mode ? .on : .off
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    private func interfaceLanguageMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: t(.interfaceLanguage), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for language in InterfaceLanguage.allCases {
            let child = NSMenuItem(title: language.title, action: #selector(setInterfaceLanguage(_:)), keyEquivalent: "")
            child.target = self
            child.representedObject = language.rawValue
            child.state = state.settings.interfaceLanguage == language ? .on : .off
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    // * -- Общий сценарий текстовой команды --
    private func performTextCommand(_ command: (String) -> TransformationResult) {
        guard state.settings.isEnabled else {
            return
        }

        // Читаем выделение или предыдущее слово.
        guard let target = textIO.readTarget() else {
            NSSound.beep()
            return
        }

        // Выполняем преобразование и пропускаем результат без изменений.
        let result = command(target.text)
        guard result.didChange else {
            NSSound.beep()
            return
        }

        // Заменяем текущий выбор через системный ввод.
        guard textIO.replace(target, with: result.replacementText) else {
            Diagnostics.showError(t(.couldNotReplaceText), language: state.settings.interfaceLanguage)
            return
        }

        // Синхронизируем macOS input source с языком результата.
        if let targetLanguage = result.targetLanguage,
           !inputSources.selectInputSource(for: targetLanguage) {
            Diagnostics.showError(
                t(.inputSourceUnavailable),
                detail: String(format: t(.addInputSourceDetail), targetLanguage.title),
                language: state.settings.interfaceLanguage
            )
        }

        rebuildMenu()
    }

    // * -- Команда смены раскладки --
    @objc private func convertLayoutFromMenu() {
        performLayoutConversion()
    }

    private func performLayoutConversion() {
        performTextCommand { [state] text in
            state.engine.convertLayout(text, settings: state.settings)
        }
    }

    // * -- Команда смены регистра --
    @objc private func changeCaseFromMenu() {
        performCaseConversion()
    }

    private func performCaseConversion() {
        performTextCommand { [state] text in
            state.engine.convertCase(text, mode: state.settings.caseMode)
        }
    }

    // * -- Команда транслитерации --
    @objc private func transliterateFromMenu() {
        performTransliteration()
    }

    private func performTransliteration() {
        performTextCommand { [state] text in
            state.engine.transliterate(text, targetLanguage: state.settings.transliterationTargetLanguage)
        }
    }

    @objc private func toggleEnabled() {
        state.toggleEnabled()
    }

    // * -- Настройки режима переключения --
    @objc private func setSwitchingMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = SwitchingMode(rawValue: rawValue) else {
            return
        }
        state.settings.switchingMode = mode
        state.engine.resetContext()
    }

    // * -- Настройка фиксированной цели --
    @objc private func setFixedTarget(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = PuntoLanguage(rawValue: rawValue) else {
            return
        }
        state.settings.fixedTargetLanguage = language
        state.engine.resetContext()
    }

    // * -- Настройка цели транслитерации --
    @objc private func setTransliterationTarget(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = PuntoLanguage(rawValue: rawValue) else {
            return
        }
        state.settings.transliterationTargetLanguage = language
    }

    // * -- Настройка режима регистра --
    @objc private func setCaseMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = CaseMode(rawValue: rawValue) else {
            return
        }
        state.settings.caseMode = mode
    }

    @objc private func setInterfaceLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = InterfaceLanguage(rawValue: rawValue) else {
            return
        }
        state.settings.interfaceLanguage = language
        settingsWindowController?.refreshContent()
    }

    // * -- Окно настроек --
    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(state: state)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // * -- Переключение запуска при входе --
    @objc private func toggleLaunchAtLogin() {
        let requestedValue = !state.settings.launchAtLogin

        do {
            try LaunchAtLoginController.setEnabled(requestedValue)
            state.settings.launchAtLogin = requestedValue
        } catch {
            state.settings.launchAtLogin = false
            Diagnostics.showError(t(.launchAtLoginUnavailable), detail: error.localizedDescription, language: state.settings.interfaceLanguage)
        }
    }

    @objc private func openPermissions() {
        Diagnostics.showPermissionsWindow(language: state.settings.interfaceLanguage)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

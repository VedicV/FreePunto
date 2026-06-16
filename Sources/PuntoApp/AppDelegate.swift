import AppKit
import PuntoCore

// * -- Головний контролер menu bar застосунку --
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private let textIO = TextIOController()
    private let inputSources = InputSourceController()
    private var statusItem: NSStatusItem?
    private var hotKeys: HotKeyController?
    private var settingsWindowController: SettingsWindowController?
    // * -- Послідовна черга для тяжкої частини команд (читання/заміна тексту) --
    private let commandQueue = DispatchQueue(label: "com.freepunto.command")
    // * -- Захист від перекрытих команд: якщо команда вже виконується, нову ігноруємо --
    private var isRunningCommand = false

    // * -- Запуск застосунку і підключення системних обробників --
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Маркер на робочий стіл — 100% надійний шлях.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let marker = home.appendingPathComponent("Desktop/freepunto_test.txt")
        try? "launched at \(Date())\n".write(to: marker, atomically: true, encoding: .utf8)

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

        // Перевіряємо Accessibility без системного діалогу (prompt: false).
        // Користувач додає дозвіл вручну через Системні налаштування.
        if Diagnostics.accessibilityTrusted(prompt: false) {
            rawLog("accessibility TRUSTED — hotKeys starting")
            hotKeys?.start()
        } else {
            rawLog("accessibility NOT TRUSTED — відкрийте Системні налаштування → Універсальний доступ → додайте FreePunto")
            Diagnostics.showPermissionsWindow(language: state.settings.interfaceLanguage)
        }
    }

    // * -- Зупинка глобальних обробників --
    func applicationWillTerminate(_ notification: Notification) {
        hotKeys?.stop()
    }

    // * -- Застосування змінених налаштувань --
    private func refreshAfterSettingsChange() {
        if Diagnostics.accessibilityTrusted(prompt: false) {
            hotKeys?.start()
        }
        rebuildMenu()
    }

    // * -- Збирання меню status bar --
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
        menu.addItem(versionAndBuildMenuItem())
        menu.addItem(makeItem(title: t(.quit), action: #selector(quit)))

        statusItem.menu = menu
    }

    // * -- Іконка status bar --
    private func statusIcon() -> NSImage {
        guard state.settings.isEnabled else {
            return StatusIconFactory.make(.paused)
        }

        return StatusIconFactory.make(.language(
            state.engine.nextLayoutLanguageHint(settings: state.settings),
            fixedMode: state.settings.switchingMode == .fixedTarget
        ))
    }

    // Tooltip залишаємо текстовим, щоб на hover був зрозумілий поточний стан.
    private func statusTooltip() -> String {
        guard state.settings.isEnabled else {
            return "FreePunto: PAUSE"
        }

        let hint = state.engine.nextLayoutLanguageHint(settings: state.settings).statusTitle
        return state.settings.switchingMode == .fixedTarget ? "FreePunto: \(hint)*" : "FreePunto: \(hint)"
    }

// * -- Допоміжні методи для створення меню і обробки команд --

// Метод для отримання локалізованого рядка з ключа.
    private func t(_ key: AppText.Key) -> String {
        AppText.get(key, state.settings.interfaceLanguage)
    }

// Формування заголовка команди з урахуванням гарячої клавіші.
    private func commandTitle(_ key: AppText.Key, hotKey: HotKey) -> String {
        "\(t(key)) (\(hotKey.displayTitle))"
    }

// Універсальний метод для створення пункту меню з заданою дією.
    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // Меню режиму перемикання.
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

    // Меню фіксованої цілі.
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

    // Меню цілі транслітерації.
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

    // Меню режиму регістру.
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

    // Меню вибору мови інтерфейсу.
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

// * -- Пункт меню з версією і часом збірки --
    private func versionAndBuildMenuItem() -> NSMenuItem {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let buildTimeStr: String
        if let path = Bundle.main.executablePath,
           let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let modificationDate = attributes[.modificationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            buildTimeStr = formatter.string(from: modificationDate)
        } else {
            buildTimeStr = "--:--"
        }
        let item = NSMenuItem(title: "\(t(.version)) \(version) (\(buildTimeStr))", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // * -- Загальний сценарій текстової команди --
    // * -- Тяжка частина (читання/заміна тексту) виконується на фоновій черзі commandQueue,
    // * -- щоб не блокувати головний RunLoop і не вимикати CGEventTap по таймауту. --
    private func performTextCommand(_ command: @escaping (String) -> TransformationResult) {
        // (a) Перевірки та захоплення контексту на головному потоці.
        guard state.settings.isEnabled else {
            return
        }
        guard !isRunningCommand else {
            return
        }
        isRunningCommand = true

        rawLog("[AppDelegate] performTextCommand ENTRY, enabled=\(state.settings.isEnabled)")

        // Захоплюємо bundleIdentifier, accessibility і фокусований елемент на головному потоці.
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let hasAX = Diagnostics.accessibilityTrusted(prompt: false)
        let focusedEl: AXUIElement? = {
            guard hasAX else { return nil }
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var focusedValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)
            if result == .success, let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
                return (focusedValue as! AXUIElement)
            }
            // Chrome/Electron блокують AX — це нормально, працюємо через Cmd+C.
            rawLog("performTextCommand: focusedEl=no, AX error=\(result.rawValue) (ок для Chrome/Electron)")
            return nil
        }()
        rawLog("performTextCommand: focusedEl=\(focusedEl != nil ? "yes" : "no")")

        commandQueue.async { [weak self] in
            guard let self else { return }

            rawLog("[AppDelegate] commandQueue block START, bundle=\(bundleID ?? "nil") hasAX=\(hasAX)")

            // (b) Читаємо виділення або попереднє слово на фоні.
            let target = self.textIO.readTarget(bundleIdentifier: bundleID, hasAccessibility: hasAX, focusedElement: focusedEl)
            guard let target else {
                rawLog("[AppDelegate] readTarget повернув nil → beep")
                DispatchQueue.main.async {
                    NSSound.beep()
                    self.isRunningCommand = false
                }
                return
            }

            rawLog("[AppDelegate] readTarget ok: text='\(target.text.prefix(50))'")

            // (c) Виконуємо перетворення і пропускаємо результат без змін.
            let result = command(target.text)
            guard result.didChange else {
                rawLog("[AppDelegate] transform didChange=false → beep")
                DispatchQueue.main.async {
                    NSSound.beep()
                    self.isRunningCommand = false
                }
                return
            }

            // (d) Замінюємо поточний вибір через системне введення, якщо текст змінився.
            if result.originalText != result.replacementText {
                let ok = self.textIO.replace(target, with: result.replacementText)
                guard ok else {
                    rawLog("[AppDelegate] replace повернув false → showError")
                    DispatchQueue.main.async {
                        Diagnostics.showError(self.t(.couldNotReplaceText), language: self.state.settings.interfaceLanguage)
                        self.isRunningCommand = false
                    }
                    return
                }
            }

            // (e) Синхронізуємо macOS input source і оновлюємо меню на головному потоці.
            // Синхронізуємо macOS input source з мовою результату після заміни,
            // щоб перемикання розкладки не скидало активне виділення у браузерах.
            DispatchQueue.main.async {
                if let targetLanguage = result.targetLanguage,
                   !self.inputSources.selectInputSource(for: targetLanguage) {
                    Diagnostics.showError(
                        self.t(.inputSourceUnavailable),
                        detail: String(format: self.t(.addInputSourceDetail), targetLanguage.title),
                        language: self.state.settings.interfaceLanguage
                    )
                }

                self.rebuildMenu()
                self.isRunningCommand = false
            }
        }
    }

    // * -- Команда зміни розкладки --
    @objc private func convertLayoutFromMenu() {
        performLayoutConversion()
    }

// * -- Загальний сценарій текстової команди --
    private func performLayoutConversion() {
        rawLog("[AppDelegate] performLayoutConversion")
        performTextCommand { [state] text in
            state.engine.convertLayout(text, settings: state.settings)
        }
    }

    // * -- Команда зміни регістру --
    @objc private func changeCaseFromMenu() {
        performCaseConversion()
    }

    private func performCaseConversion() {
        performTextCommand { [state] text in
            state.engine.convertCase(text, mode: state.settings.caseMode)
        }
    }

    // * -- Команда транслітерації --
    @objc private func transliterateFromMenu() {
        performTransliteration()
    }

// * -- Команда транслітерації --
     // Використовуємо налаштування цілі транслітерації для визначення мови результату.
    private func performTransliteration() {
        performTextCommand { [state] text in
            state.engine.transliterate(text, targetLanguage: state.settings.transliterationTargetLanguage)
        }
    }

    // * -- Перемикання увімкнення --
    @objc private func toggleEnabled() {
        state.toggleEnabled()
    }

    // * -- Налаштування режиму перемикання --
    @objc private func setSwitchingMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = SwitchingMode(rawValue: rawValue) else {
            return
        }
        state.settings.switchingMode = mode
        state.engine.resetContext()
    }

    // * -- Налаштування фіксованої цілі --
    @objc private func setFixedTarget(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = PuntoLanguage(rawValue: rawValue) else {
            return
        }
        state.settings.fixedTargetLanguage = language
        state.engine.resetContext()
    }

    // * -- Налаштування цілі транслітерації --
    @objc private func setTransliterationTarget(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = PuntoLanguage(rawValue: rawValue) else {
            return
        }
        state.settings.transliterationTargetLanguage = language
    }

    // * -- Налаштування режиму регістру --
    @objc private func setCaseMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = CaseMode(rawValue: rawValue) else {
            return
        }
        state.settings.caseMode = mode
    }

// * -- Налаштування мови інтерфейсу --
    @objc private func setInterfaceLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = InterfaceLanguage(rawValue: rawValue) else {
            return
        }
        state.settings.interfaceLanguage = language
        settingsWindowController?.refreshContent()
    }

    // * -- Вікно налаштувань --
    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(state: state)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // * -- Перемикання запуску при вході --
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

// * -- Відкриття вікна дозволів --
    @objc private func openPermissions() {
        Diagnostics.showPermissionsWindow(language: state.settings.interfaceLanguage)
    }

// * -- Вихід із застосунку --
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

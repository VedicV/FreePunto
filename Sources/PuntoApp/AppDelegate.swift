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
    // * -- Захист від перекритих команд: якщо команда вже виконується, нову ігноруємо --
    private var isRunningCommand = false
    private var isProgrammaticLayoutChange = false
    private var layoutChangeGeneration: UInt64 = 0
    private var statusGeneration: UInt64 = 0
    private var interactionGeneration: UInt64 = 0
    private var permissionTimer: Timer?

    private func resetConversionContext() {
        interactionGeneration &+= 1
        textIO.cancelCurrentCommand()
        state.engine.resetContext()
    }

    // * -- Запуск застосунку і підключення системних обробників --
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
                pause: { [weak self] in self?.toggleEnabled() },
                interaction: { [weak self] in self?.resetConversionContext() }
            )
        )

        rebuildMenu()

        checkAndStartHotKeysIfNeeded()

        // Постійний моніторинг стану Доступності (Accessibility):
        // Коли користувач вмикає тумблер у Системних параметрах, FreePunto
        // підхоплює дозвіл та запускає глобальні гарячі клавіші без перезапуску!
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAndStartHotKeysIfNeeded()
        }

        if !Diagnostics.accessibilityTrusted(prompt: true) {
            rawLog("accessibility NOT TRUSTED — очікуємо надання дозволу в Системних параметрах")
            Diagnostics.openAccessibilitySettings()
        }

        // Спостереження за зміною активної системної розкладки в macOS
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardLayoutDidChange),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil
        )

        // Спостереження за перемиканням активного застосунку для скидання застарілого контексту перетворення
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    // * -- Зупинка глобальних обробників --
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        permissionTimer?.invalidate()
        hotKeys?.stop()
    }

    @objc private func keyboardLayoutDidChange() {
        rawLog("[AppDelegate] keyboardLayoutDidChange (programmatic=\(isProgrammaticLayoutChange))")
        DynamicLayoutMapper.shared.refreshTables()
        if !isProgrammaticLayoutChange {
            resetConversionContext()
        }
        rebuildMenu()
    }

    @objc private func activeApplicationDidChange() {
        rawLog("[AppDelegate] activeApplicationDidChange -> resetContext")
        resetConversionContext()
    }

    // * -- Перевірка та автоматичний запуск гарячих клавіш --
    private func checkAndStartHotKeysIfNeeded() {
        let isTrusted = Diagnostics.accessibilityTrusted(prompt: false)
        let isRunning = hotKeys?.isRunning == true

        if isTrusted && !isRunning {
            rawLog("accessibility TRUSTED — hotKeys starting")
            hotKeys?.start()
            rebuildMenu()
        } else if !isTrusted && isRunning {
            rawLog("accessibility LOST — hotKeys stopping")
            hotKeys?.stop()
            rebuildMenu()
        }
    }

    // * -- Застосування змінених налаштувань --
    private func refreshAfterSettingsChange() {
        resetConversionContext()
        checkAndStartHotKeysIfNeeded()
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

        let activeLangs = inputSources.activeLanguages()
        return StatusIconFactory.make(.language(
            state.engine.nextLayoutLanguageHint(settings: state.settings, enabledLanguages: activeLangs),
            fixedMode: state.settings.switchingMode == .fixedTarget
        ))
    }

    // Tooltip залишаємо текстовим, щоб на hover був зрозумілий поточний стан.
    private func statusTooltip() -> String {
        let isTest = isTestBuild()
        let prefix = isTest ? "FreePunto [TEST]: " : "FreePunto: "
        guard state.settings.isEnabled else {
            return "\(prefix)PAUSE"
        }

        let activeLangs = inputSources.activeLanguages()
        let hint = state.engine.nextLayoutLanguageHint(settings: state.settings, enabledLanguages: activeLangs).statusTitle
        return state.settings.switchingMode == .fixedTarget ? "\(prefix)\(hint)*" : "\(prefix)\(hint)"
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

    // * -- Ознака тестової збірки --
    private func isTestBuild() -> Bool {
        if let explicit = Bundle.main.infoDictionary?["FreePuntoIsTestBuild"] as? Bool {
            return explicit
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let lower = version.lowercased()
        return lower.contains("-") || lower.contains("test") || lower.contains("beta") || lower.contains("dev") || lower.contains("alpha") || lower.contains("rc")
    }

    // * -- Пункт меню з версією і часом збірки --
    private func versionAndBuildMenuItem() -> NSMenuItem {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let isTest = isTestBuild()

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
        let title: String
        if isTest {
            title = "\(t(.version)) \(version) (\(t(.testVersion)), \(buildTimeStr))"
        } else {
            title = "\(t(.version)) \(version) (\(buildTimeStr))"
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // * -- Загальний сценарій текстової команди --
    // * -- Тяжка частина (читання/заміна тексту) виконується на фоновій черзі commandQueue,
    // * -- щоб не блокувати головний RunLoop і не вимикати CGEventTap по таймауту. --
    private struct TextCommandResult {
        let result: TransformationResult
        let token: ConversionToken?
    }

    // Коротке повідомлення про стан не забирає фокус у цільового застосунку.
    private func reportCommandStatus(_ key: AppText.Key) {
        statusGeneration &+= 1
        let receipt = statusGeneration
        statusItem?.button?.toolTip = t(key)
        NSSound.beep()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.statusGeneration == receipt else { return }
            self.statusItem?.button?.toolTip = nil
        }
    }

    private func performTextCommand(_ command: @escaping (String, String) -> TextCommandResult?) {
        // (a) Перевірки та захоплення контексту на головному потоці.
        guard state.settings.isEnabled else {
            return
        }
        guard !isRunningCommand else {
            reportCommandStatus(.commandBusy)
            return
        }
        isRunningCommand = true
        let capturedInteraction = interactionGeneration

        rawLog("[AppDelegate] performTextCommand ENTRY, enabled=\(state.settings.isEnabled)")

        // Захоплюємо bundleIdentifier, accessibility і фокусований елемент на головному потоці.
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let hasAX = Diagnostics.accessibilityTrusted(prompt: false)
        let focusedEl: AXUIElement? = {
            guard hasAX else { return nil }
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)

            // Вмикаємо доступність для Chromium/Electron (VS Code, Antigravity, Chrome)
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

            var focusedValue: CFTypeRef?
            var result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)

            // Fallback 1: фокусований елемент активного вікна (обхід -25211 у Chromium/Electron)
            if result != .success {
                var windowValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
                   let win = windowValue as! AXUIElement? {
                    result = AXUIElementCopyAttributeValue(win, kAXFocusedUIElementAttribute as CFString, &focusedValue)
                }
            }

            // Fallback 2: глобальний systemWide елемент
            if result != .success {
                let sys = AXUIElementCreateSystemWide()
                result = AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focusedValue)
            }

            if result == .success, let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
                let el = (focusedValue as! AXUIElement)
                var roleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
                let roleStr = roleRef as? String ?? "nil"
                rawLog("performTextCommand: focusedEl=yes role=\(roleStr)")
                return el
            }

            rawLog("performTextCommand: focusedEl=no, AX error=\(result.rawValue)")
            return nil
        }()
        rawLog("performTextCommand: focusedEl=\(focusedEl != nil ? "yes" : "no")")

        commandQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.textIO.endCommand()
                DispatchQueue.main.async {
                    self.isRunningCommand = false
                    self.rebuildMenu()
                }
            }
            guard DispatchQueue.main.sync(execute: {
                guard self.interactionGeneration == capturedInteraction && self.state.settings.isEnabled else { return false }
                return self.textIO.beginCommand(bundleIdentifier: bundleID, focusedElement: focusedEl)
            }),
                  let target = self.textIO.readTarget(bundleIdentifier: bundleID, hasAccessibility: hasAX, focusedElement: focusedEl),
                  let identity = self.textIO.currentTargetIdentity,
                  self.textIO.isTargetCurrent(target) else {
                DispatchQueue.main.async { self.reportCommandStatus(.noReliableTarget) }
                return
            }
            // Невдала підготовка навмисно зберігає невизначений receipt: його очищення
            // дозволило б застарілому AX-знімку повторити попередній запис.
            guard let prepared = command(target.text, identity) else {
                DispatchQueue.main.async { self.reportCommandStatus(.replacementUnconfirmed) }
                return
            }
            let result = prepared.result
            guard result.didChange, self.textIO.isTargetCurrent(target) else {
                if let token = prepared.token { self.state.engine.discardPendingConversion(token) }
                DispatchQueue.main.async { self.reportCommandStatus(.noReliableTarget) }
                return
            }
            let outcome = result.requiresTextReplacement
                ? self.textIO.replace(target, with: result.replacementText)
                : ReplaceOutcome.successVerified
            switch outcome {
            case .successVerified:
                // Commit і зміна джерела вводу мають бачити ту саму актуальну ціль.
                DispatchQueue.main.sync {
                    guard self.textIO.isTargetCurrent(target), self.state.settings.isEnabled else {
                        if let token = prepared.token { self.state.engine.discardPendingConversion(token) }
                        return
                    }
                    if let token = prepared.token,
                       !self.state.engine.commitPendingConversion(token) { return }
                    if let language = result.targetLanguage {
                        self.layoutChangeGeneration &+= 1
                        let layoutReceipt = self.layoutChangeGeneration
                        self.isProgrammaticLayoutChange = true
                        if !self.inputSources.selectInputSource(for: language) {
                            self.isProgrammaticLayoutChange = false
                            self.reportCommandStatus(.inputSourceUnavailable)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            guard self.layoutChangeGeneration == layoutReceipt else { return }
                            self.isProgrammaticLayoutChange = false
                        }
                    }
                }
            case .deliveredUnconfirmedAX:
                if let token = prepared.token { self.state.engine.recordUnknownConversion(token) }
                DispatchQueue.main.async { self.reportCommandStatus(.replacementUnconfirmed) }
            case .failed:
                if let token = prepared.token { self.state.engine.discardPendingConversion(token) }
                DispatchQueue.main.async { self.reportCommandStatus(.couldNotReplaceText) }
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
        let activeLangs = inputSources.activeLanguages()
        let currentLang = inputSources.currentLanguage()
        let settingsSnapshot = state.settings
        performTextCommand { [state] text, identity in
            guard let prepared = state.engine.prepareLayoutConversion(
                text,
                settings: settingsSnapshot,
                enabledLanguages: activeLangs,
                currentLanguage: currentLang,
                targetIdentity: identity
            ) else { return nil }
            return TextCommandResult(result: prepared.result, token: prepared.token)
        }
    }

    // * -- Команда зміни регістру --
    @objc private func changeCaseFromMenu() {
        performCaseConversion()
    }

    private func performCaseConversion() {
        let mode = state.settings.caseMode
        performTextCommand { [state] text, _ in
            TextCommandResult(result: state.engine.convertCase(text, mode: mode), token: nil)
        }
    }

    // * -- Команда транслітерації --
    @objc private func transliterateFromMenu() {
        performTransliteration()
    }

     // Використовуємо налаштування цілі транслітерації для визначення мови результату.
    private func performTransliteration() {
        let targetLanguage = state.settings.transliterationTargetLanguage
        performTextCommand { [state] text, _ in
            TextCommandResult(result: state.engine.transliterate(text, targetLanguage: targetLanguage), token: nil)
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
        resetConversionContext()
    }

    // * -- Налаштування фіксованої цілі --
    @objc private func setFixedTarget(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = PuntoLanguage(rawValue: rawValue) else {
            return
        }
        state.settings.fixedTargetLanguage = language
        resetConversionContext()
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

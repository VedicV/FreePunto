import AppKit
import PuntoCore

// * -- Вікно налаштувань --
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let state: AppState
    private var recordingMonitor: Any?
    private weak var activeRecordingButton: NSButton?
    private var sleeves: [ClosureSleeve] = []

    // * -- Створення вікна --
    init(state: AppState) {
        self.state = state
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 710, height: 530),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = AppText.get(.settingsTitle, state.settings.interfaceLanguage)
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshContent() {
        buildContent()
    }

    // * -- Збирання вікна налаштувань --
    private func buildContent() {
        stopRecording()
        sleeves = []
        window?.title = t(.settingsTitle)
        window?.setContentSize(NSSize(width: 710, height: 530))

        // Створюємо стек для розміщення елементів налаштувань.
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Основні налаштування застосунку.
        stack.addArrangedSubview(makeCheckbox(
            title: t(.enabled),
            isOn: state.settings.isEnabled,
            action: { [weak self] isOn in self?.state.settings.isEnabled = isOn }
        ))

        stack.addArrangedSubview(makeLaunchAtLoginCheckbox())

        // Налаштування режимів роботи.
        stack.addArrangedSubview(makePopupRow(
            title: t(.switchingMode),
            values: SwitchingMode.allCases,
            selected: state.settings.switchingMode,
            titleProvider: { [weak self] mode in
                AppText.switchingModeTitle(mode, self?.state.settings.interfaceLanguage ?? .systemDefault)
            },
            action: { [weak self] mode in
                self?.state.settings.switchingMode = mode
                self?.state.engine.resetContext()
            }
        ))

        // Налаштування фіксованої цільової мови.
        stack.addArrangedSubview(makePopupRow(
            title: t(.fixedTarget),
            values: [.russian, .ukrainian],
            selected: state.settings.fixedTargetLanguage,
            titleProvider: { $0.statusTitle },
            action: { [weak self] language in
                self?.state.settings.fixedTargetLanguage = language
                self?.state.engine.resetContext()
            }
        ))

    // Налаштування мови для транслітерації.
        stack.addArrangedSubview(makePopupRow(
            title: t(.transliterationTarget),
            values: [.russian, .ukrainian],
            selected: state.settings.transliterationTargetLanguage,
            titleProvider: { $0.statusTitle },
            action: { [weak self] language in
                self?.state.settings.transliterationTargetLanguage = language
            }
        ))
    // Налаштування режиму зміни регістру.
        stack.addArrangedSubview(makePopupRow(
            title: t(.caseMode),
            values: CaseMode.allCases,
            selected: state.settings.caseMode,
            titleProvider: { [weak self] mode in
                AppText.caseModeTitle(mode, self?.state.settings.interfaceLanguage ?? .systemDefault)
            },
            action: { [weak self] mode in self?.state.settings.caseMode = mode }
        ))

    // Налаштування мови інтерфейсу застосунку.
        stack.addArrangedSubview(makePopupRow(
            title: t(.interfaceLanguage),
            values: InterfaceLanguage.allCases,
            selected: state.settings.interfaceLanguage,
            titleProvider: { $0.title },
            action: { [weak self] language in
                self?.state.settings.interfaceLanguage = language
                self?.buildContent()
            }
        ))

        addSeparator(to: stack)
       
        // Налаштування гарячих клавіш.
        stack.addArrangedSubview(makeMainHotKeyRow())
        stack.addArrangedSubview(makeHotKeyRow(
            title: t(.caseHotkey),
            hotKey: state.settings.caseHotKey,
            update: { [weak self] hotKey in self?.state.settings.caseHotKey = hotKey }
        ))
        stack.addArrangedSubview(makeHotKeyRow(
            title: t(.transliterationHotkey),
            hotKey: state.settings.transliterationHotKey,
            update: { [weak self] hotKey in self?.state.settings.transliterationHotKey = hotKey }
        ))
        stack.addArrangedSubview(makeHotKeyRow(
            title: t(.pauseHotkey),
            hotKey: state.settings.pauseHotKey,
            update: { [weak self] hotKey in self?.state.settings.pauseHotKey = hotKey }
        ))

        // Налаштування доступів macOS.
        addSeparator(to: stack)
        // Доступи macOS.
        let permissions = NSButton(title: t(.openPermissions), target: self, action: #selector(openPermissions))
        stack.addArrangedSubview(permissions)

        let contentView = NSView()
        contentView.addSubview(stack)
        window?.contentView = contentView
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    // Базовий checkbox із closure-обробником.
    private func makeCheckbox(title: String, isOn: Bool, action: @escaping (Bool) -> Void) -> NSView {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = isOn ? .on : .off
        let sleeve = retainSleeve {
            action(button.state == .on)
        }
        button.target = sleeve
        button.action = #selector(ClosureSleeve.invoke)
        return button
    }

    // Checkbox запуску при вході з обробкою помилки ServiceManagement.
    private func makeLaunchAtLoginCheckbox() -> NSView {
        let button = NSButton(checkboxWithTitle: t(.launchAtLogin), target: nil, action: nil)
        button.state = state.settings.launchAtLogin ? .on : .off
        let sleeve = retainSleeve { [weak self, weak button] in
            guard let self, let button else { return }
            let requestedValue = button.state == .on
            do {
                try LaunchAtLoginController.setEnabled(requestedValue)
                self.state.settings.launchAtLogin = requestedValue
            } catch {
                self.state.settings.launchAtLogin = false
                button.state = .off
                Diagnostics.showError(self.t(.launchAtLoginUnavailable), detail: error.localizedDescription, language: self.state.settings.interfaceLanguage)
            }
        }
        button.target = sleeve
        button.action = #selector(ClosureSleeve.invoke)
        return button
    }

    // Універсальний рядок popup-вибору.
    private func makePopupRow<Value: Equatable>(
        title: String,
        values: [Value],
        selected: Value,
        titleProvider: @escaping (Value) -> String,
        action: @escaping (Value) -> Void
    ) -> NSView {
        let row = rowStack()
        row.addArrangedSubview(label(title))

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for (index, value) in values.enumerated() {
            popup.addItem(withTitle: titleProvider(value))
            popup.item(at: index)?.representedObject = Box(value)
            if value == selected {
                popup.selectItem(at: index)
            }
        }
        let sleeve = retainSleeve {
            guard let box = popup.selectedItem?.representedObject as? Box<Value> else {
                return
            }
            action(box.value)
        }
        popup.target = sleeve
        popup.action = #selector(ClosureSleeve.invoke)
        row.addArrangedSubview(popup)
        return row
    }

    // Налаштування основної команди: за замовчуванням Control, але можна записати явну комбінацію.
    private func makeMainHotKeyRow() -> NSView {
        let row = rowStack()
        row.addArrangedSubview(label(t(.mainHotkey)))

        let valueLabel = NSTextField(labelWithString: state.settings.mainHotKey.displayTitle)
        valueLabel.widthAnchor.constraint(equalToConstant: 140).isActive = true
        row.addArrangedSubview(valueLabel)

        let restore = NSButton(title: t(.restoreControl), target: nil, action: nil)
        restore.widthAnchor.constraint(equalToConstant: 150).isActive = true
        restore.isEnabled = state.settings.mainHotKey != .singleControl

        let record = NSButton(title: t(.record), target: nil, action: nil)
        record.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let recordSleeve = retainSleeve { [weak self, weak record, weak valueLabel, weak restore] in
            guard let self, let record, let valueLabel else { return }
            self.startRecording(button: record) { hotKey in
                valueLabel.stringValue = hotKey.displayTitle
                self.state.settings.mainHotKey = hotKey
                restore?.isEnabled = (hotKey != .singleControl)
            }
        }
        record.target = recordSleeve
        record.action = #selector(ClosureSleeve.invoke)
        row.addArrangedSubview(record)

        let restoreSleeve = retainSleeve { [weak self, weak valueLabel, weak restore] in
            guard let self else { return }
            self.state.settings.mainHotKey = .singleControl
            valueLabel?.stringValue = self.state.settings.mainHotKey.displayTitle
            restore?.isEnabled = false
        }
        restore.target = restoreSleeve
        restore.action = #selector(ClosureSleeve.invoke)
        row.addArrangedSubview(restore)

        return row
    }

    // Рядок запису гарячої клавіші.
    private func makeHotKeyRow(title: String, hotKey: HotKey, update: @escaping (HotKey) -> Void) -> NSView {
        let row = rowStack()
        row.addArrangedSubview(label(title))

        let valueLabel = NSTextField(labelWithString: hotKey.displayTitle)
        valueLabel.widthAnchor.constraint(equalToConstant: 140).isActive = true
        row.addArrangedSubview(valueLabel)

        let record = NSButton(title: t(.record), target: nil, action: nil)
        record.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let sleeve = retainSleeve { [weak self, weak record, weak valueLabel] in
            guard let self, let record, let valueLabel else { return }
            self.startRecording(button: record) { hotKey in
                valueLabel.stringValue = hotKey.displayTitle
                update(hotKey)
            }
        }
        record.target = sleeve
        record.action = #selector(ClosureSleeve.invoke)
        row.addArrangedSubview(record)
        return row
    }

    // Локальний запис наступного keyDown для налаштування hotkey.
    private func startRecording(button: NSButton, update: @escaping (HotKey) -> Void) {
        stopRecording()
        activeRecordingButton = button
        button.title = t(.pressKeys)
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak button] event in
            guard let self else { return nil }
            let modifiers = HotKeyModifiers(modifierFlags: event.modifierFlags)
            let keyCode = Int(event.keyCode)

            // Якщо натиснуто Esc без модифікаторів — скасовуємо запис
            if keyCode == 53 && modifiers.isEmpty {
                button?.title = self.t(.record)
                self.activeRecordingButton = nil
                self.stopRecording()
                return nil
            }

            // Валідація: гаряча клавіша повинна містити хоча б один модифікатор (Cmd/Opt/Ctrl/Shift)
            // або бути F-клавішею (F1–F12). Одиночні літери заборонені, щоб не блокувати звичайний ввід!
            let isFunctionKey = (keyCode >= 120 && keyCode <= 122) || (keyCode >= 96 && keyCode <= 101) || (keyCode >= 109 && keyCode <= 111) || keyCode == 103 || keyCode == 118
            let hasModifiers = !modifiers.isEmpty

            if !hasModifiers && !isFunctionKey {
                NSSound.beep()
                rawLog("startRecording: відхилено клавішу без модифікаторів (keyCode=\(keyCode))")
                return nil
            }

            let hotKey = HotKey.combination(keyCode: keyCode, modifiers: modifiers)

            // Перевірка конфлікту з іншими гарячими клавішами
            if self.hasConflict(with: hotKey) {
                NSSound.beep()
                rawLog("startRecording: виявлено конфлікт гарячих клавіш з \(hotKey.displayTitle)")
                Diagnostics.showError("Ця комбінація вже використовується для іншої дії!", language: self.state.settings.interfaceLanguage)
                button?.title = self.t(.record)
                self.activeRecordingButton = nil
                self.stopRecording()
                return nil
            }

            update(hotKey)
            button?.title = self.t(.record)
            self.activeRecordingButton = nil
            self.stopRecording()
            return nil
        }
    }

    private func hasConflict(with hotKey: HotKey) -> Bool {
        let existing = [
            state.settings.mainHotKey,
            state.settings.caseHotKey,
            state.settings.transliterationHotKey,
            state.settings.pauseHotKey
        ]
        return existing.contains(hotKey)
    }

    private func stopRecording() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
        }
        recordingMonitor = nil
        activeRecordingButton?.title = t(.record)
        activeRecordingButton = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    // Утримуємо target-об'єкти AppKit, щоб closure не звільнялися.
    private func retainSleeve(_ closure: @escaping () -> Void) -> ClosureSleeve {
        let sleeve = ClosureSleeve(closure)
        sleeves.append(sleeve)
        return sleeve
    }

    @objc private func openPermissions() {
        Diagnostics.showPermissionsWindow(language: state.settings.interfaceLanguage)
    }

    private func rowStack() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    // Допоміжні методи для створення елементів інтерфейсу.
    private func label(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 185).isActive = true
        return label
    }

    private func addSeparator(to stack: NSStackView) {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
    }

    private func t(_ key: AppText.Key) -> String {
        AppText.get(key, state.settings.interfaceLanguage)
    }
}

// * -- Допоміжний клас-контейнер для передачі об'єктів у представлені значення NSPopUpButton --
private final class Box<Value> {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

// * -- Спеціальний sleeve-клас для утримання closure-обробників подій AppKit контролерів --
private final class ClosureSleeve: NSObject {
    private let closure: () -> Void

    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }

    @objc func invoke() {
        closure()
    }
}

// * -- Допоміжне розширення для перенесення модифікаторів із системного NSEvent --
private extension HotKeyModifiers {
    init(modifierFlags: NSEvent.ModifierFlags) {
        var modifiers: HotKeyModifiers = []
        if modifierFlags.contains(.control) { modifiers.insert(.control) }
        if modifierFlags.contains(.option) { modifiers.insert(.option) }
        if modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if modifierFlags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}

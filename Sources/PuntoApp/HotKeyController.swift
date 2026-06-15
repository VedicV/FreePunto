import AppKit
import PuntoCore

// * -- Глобальные горячие клавиши --
final class HotKeyController {
    struct Actions {
        var main: () -> Void
        var letterCase: () -> Void
        var transliteration: () -> Void
        var pause: () -> Void
    }

    private let settingsProvider: () -> PuntoSettings
    private let actions: Actions
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var singleControlCandidate = false

    init(settingsProvider: @escaping () -> PuntoSettings, actions: Actions) {
        self.settingsProvider = settingsProvider
        self.actions = actions
    }

    // * -- Подключение глобального перехватчика клавиш --
    func start() {
        stop()

        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let controller = Unmanaged<HotKeyController>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handle(type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            let language = settingsProvider().interfaceLanguage
            Diagnostics.showError(
                AppText.get(.globalHotkeysUnavailable, language),
                detail: AppText.get(.globalHotkeysUnavailableDetail, language),
                language: language
            )
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    // * -- Отключение глобального перехватчика клавиш --
    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        singleControlCandidate = false
    }

    // * -- Обработка события клавиатуры --
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Восстанавливаем tap после системного отключения.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let settings = settingsProvider()

        // Любой клик мыши отменяет кандидата на одиночное нажатие Control
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            singleControlCandidate = false
            return Unmanaged.passUnretained(event)
        }

        // Одиночный Control отслеживается через flagsChanged, а не через keyDown.
        if type == .flagsChanged {
            handleFlagsChanged(event: event, settings: settings)
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        singleControlCandidate = false

        // Pause работает даже при выключенном FreePunto.
        if matches(settings.pauseHotKey, event: event) {
            DispatchQueue.main.async(execute: actions.pause)
            return nil
        }

        // Остальные команды доступны только во включенном состоянии.
        guard settings.isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        if matches(settings.mainHotKey, event: event) {
            DispatchQueue.main.async(execute: actions.main)
            return nil
        }

        if matches(settings.caseHotKey, event: event) {
            DispatchQueue.main.async(execute: actions.letterCase)
            return nil
        }

        if matches(settings.transliterationHotKey, event: event) {
            DispatchQueue.main.async(execute: actions.transliteration)
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // Отслеживаем нажатие и отпускание одиночного Control.
    private func handleFlagsChanged(event: CGEvent, settings: PuntoSettings) {
        guard settings.mainHotKey.kind == .singleControl else {
            singleControlCandidate = false
            return
        }

        let flags = normalizedFlags(event.flags)
        let controlOnly = flags == .maskControl
        let noModifiers = flags.isEmpty
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isControlKey = keyCode == 59 || keyCode == 62

        if controlOnly && isControlKey {
            singleControlCandidate = true
        } else if noModifiers && singleControlCandidate && settings.isEnabled {
            singleControlCandidate = false
            DispatchQueue.main.async(execute: actions.main)
        } else if !controlOnly {
            singleControlCandidate = false
        }
    }

    // Сравниваем keyCode и нормализованные модификаторы.
    private func matches(_ hotKey: HotKey, event: CGEvent) -> Bool {
        guard hotKey.kind == .keyCombination,
              let keyCode = hotKey.keyCode,
              Int(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode else {
            return false
        }

        return HotKeyModifiers(eventFlags: normalizedFlags(event.flags)) == hotKey.modifiers
    }

    private func normalizedFlags(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
    }
}

private extension HotKeyModifiers {
    init(eventFlags: CGEventFlags) {
        var modifiers: HotKeyModifiers = []
        if eventFlags.contains(.maskControl) { modifiers.insert(.control) }
        if eventFlags.contains(.maskAlternate) { modifiers.insert(.option) }
        if eventFlags.contains(.maskShift) { modifiers.insert(.shift) }
        if eventFlags.contains(.maskCommand) { modifiers.insert(.command) }
        self = modifiers
    }
}

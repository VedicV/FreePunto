import AppKit
import ApplicationServices
import PuntoCore

// * -- Текстова ціль команди --
struct TextTarget {
    let text: String
    let trailingSpacesCount: Int
    let wordLength: Int
    fileprivate let origin: ReadOrigin
}

// * -- Фактичний спосіб, яким текст був прочитаний --
private enum ReadOrigin {
    case copiedEditableSelection
    case copiedCodeEditorSelection
    case copiedBrowserGridLike
    case editableAXLastWord
    case codeEditorAXLastWord
    case integratedTerminalAXLastWord
    case standaloneTerminalAXLastWord
}

// * -- Тип активного застосунку --
private enum AppKind {
    case standaloneTerminal
    case integratedTerminal
    case codeEditor
    case browser
    case other
}

// * -- Контекст активного застосунку і focused Accessibility element --
private struct InteractionContext {
    let appKind: AppKind
    let focusedElement: AXUIElement?
    let role: String?
    let isEditable: Bool
}

private let axEditableAttributeName: CFString = "AXEditable" as CFString

// * -- Ідентифікатори браузерів --
private let browserBundleIdentifiers: Set<String> = [
    "com.google.Chrome",
    "com.google.Chrome.canary",
    "com.apple.Safari",
    "org.mozilla.firefox",
    "com.brave.Browser",
    "com.microsoft.edgemac",
]

// * -- Контролер для читання тексту з активного застосунку і заміни його на результат трансформації --
final class TextIOController {
    private let pasteboard = NSPasteboard.general
    private let commandTimeout: TimeInterval = 0.5
    private let pollStep: TimeInterval = 0.01

    // * -- Виконати блок на головному потоці, якщо ми не на ньому.
    // * -- NSPasteboard вимагає головного потоку; цей хелпер гарантує безпеку. --
    @discardableResult
    private func syncMain<T>(_ block: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try block() }
        return try DispatchQueue.main.sync(execute: block)
    }

    // Прапорець діагностичного логування.
    // * -- Увімкнено в DEBUG або якщо виставлена змінна середовища FREEPUNTO_TRACE --
    private static let traceEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.environment["FREEPUNTO_TRACE"] != nil
        #endif
    }()

    // MARK: - Діагностичний трейс

    private func trace(_ message: @autoclosure () -> String) {
        let msg = message()
        // Завжди пишемо у файл для налагодження в release.
        rawLog(msg)
        guard Self.traceEnabled else { return }
        NSLog("[TextIO] %@", msg)
    }

    // MARK: - Читання тексту

    // * -- Читання тексту для перетворення.
    // * -- bundleIdentifier і hasAccessibility мають бути захоплені на головному потоці викликачем,
    // * -- щоб не звертатись до NSWorkspace з фонової черги. --
    func readTarget(bundleIdentifier: String?, hasAccessibility: Bool, focusedElement: AXUIElement?) -> TextTarget? {
        trace("readTarget entry: bundle=\(bundleIdentifier ?? "nil") hasAX=\(hasAccessibility)")

        let context = makeInteractionContext(
            bundleIdentifier: bundleIdentifier,
            focusedElement: focusedElement)

        trace("readTarget context: appKind=\(context.appKind) role=\(context.role ?? "nil") editable=\(context.isEditable) focusedEl=\(context.focusedElement != nil ? "yes" : "no")")

        trace(
            "context=\(context.appKind) bundle=\(bundleIdentifier ?? "nil") role=\(context.role ?? "nil") editable=\(context.isEditable)"
        )

        switch context.appKind {
        case .standaloneTerminal:
            return readTerminalLastWord(
                focusedElement: context.focusedElement,
                origin: .standaloneTerminalAXLastWord)
        case .integratedTerminal:
            return readTerminalLastWord(
                focusedElement: context.focusedElement,
                origin: .integratedTerminalAXLastWord)
        case .codeEditor:
            return readCodeEditorTarget(context)
        case .browser:
            return context.isEditable
                ? readEditableTarget(
                    context,
                    copiedOrigin: .copiedEditableSelection,
                    axOrigin: .editableAXLastWord,
                    tracePrefix: "browserEditable")
                : readBrowserNonEditable(context)
        case .other:
            guard context.isEditable else {
                trace("other: non-editable context без безпечної стратегії запису")
                return nil
            }
            return readEditableTarget(
                context,
                copiedOrigin: .copiedEditableSelection,
                axOrigin: .editableAXLastWord,
                tracePrefix: "editable")
        }
    }

    private func readCodeEditorTarget(_ context: InteractionContext) -> TextTarget? {
        if let copiedText = copyTextThroughPasteboard(timeout: 0.18) {
            if TextScanner.looksLikeAutomaticLineCopy(copiedText) {
                // Замість відкидати line-copy, виймаємо останнє слово.
                // trailingSpaces=0: при line-copy ми не знаємо позиції курсора,
                // тому не видаляємо пробіли після слова (уникнення випадкового
                // з'їдання пробілу між передостаннім і останнім словом).
                if let wordResult = TextScanner.lastWord(in: copiedText) {
                    let target = TextTarget(
                        text: wordResult.word,
                        trailingSpacesCount: 0,
                        wordLength: wordResult.word.count,
                        origin: .codeEditorAXLastWord)
                    trace("codeEditor: line-copy → останнє слово '\(wordResult.word)'")
                    return target
                }
                trace("codeEditor: відкинуто автоматичний line-copy (немає слова)")
            } else {
                trace("codeEditor: читання через Cmd+C")
                return makeCopiedTarget(copiedText, origin: .copiedCodeEditorSelection)
            }
        }

        return readAXLastWord(
            focusedElement: context.focusedElement,
            origin: .codeEditorAXLastWord,
            tracePrefix: "codeEditor")
    }

    private func readEditableTarget(
        _ context: InteractionContext,
        copiedOrigin: ReadOrigin,
        axOrigin: ReadOrigin,
        tracePrefix: String
    ) -> TextTarget? {
        if let copiedText = copyTextThroughPasteboard(timeout: 0.18) {
            if TextScanner.looksLikeAutomaticLineCopy(copiedText) {
                if let wordResult = TextScanner.lastWord(in: copiedText) {
                    let target = TextTarget(
                        text: wordResult.word,
                        trailingSpacesCount: 0,
                        wordLength: wordResult.word.count,
                        origin: axOrigin)
                    trace("\(tracePrefix): line-copy → останнє слово '\(wordResult.word)'")
                    return target
                }
                trace("\(tracePrefix): відкинуто автоматичний line-copy (немає слова)")
            } else {
                trace("\(tracePrefix): читання через Cmd+C")
                return makeCopiedTarget(copiedText, origin: copiedOrigin)
            }
        }

        return readAXLastWord(
            focusedElement: context.focusedElement,
            origin: axOrigin,
            tracePrefix: tracePrefix)
    }

    // * -- Браузер, не-editable: Cmd+C (grid/виділення). Без AX неможливо
    // * -- отримати текст без виділення в полях вводу Chrome/Electron. --
    private func readBrowserNonEditable(_ context: InteractionContext) -> TextTarget? {
        if let copiedText = copyTextThroughPasteboard(timeout: 0.18) {
            trace("browserNonEditable: читання через Cmd+C")
            return makeCopiedTarget(copiedText, origin: .copiedBrowserGridLike)
        }
        trace("browserNonEditable: Cmd+C не дав текст")
        return nil
    }

    private func readBrowserGridLikeTarget() -> TextTarget? {
        guard let copiedText = copyTextThroughPasteboard(timeout: 0.18) else {
            trace("browserGrid: Cmd+C не дав текст")
            return nil
        }

        trace("browserGrid: читання через Cmd+C")
        return makeCopiedTarget(copiedText, origin: .copiedBrowserGridLike)
    }

    private func readTerminalLastWord(focusedElement: AXUIElement?, origin: ReadOrigin) -> TextTarget? {
        guard let focusedElement else { return nil }

        var value: String? = nil
        for _ in 0..<3 {
            value = stringAttribute(kAXValueAttribute as CFString, from: focusedElement)
            if value != nil { break }
            waitForKeyboardSideEffects(timeout: 0.05)
        }

        guard let value else {
            trace("terminal: AXValue недоступний після повторних спроб")
            return nil
        }

        let lines = value.components(separatedBy: .newlines)
        guard
            let currentLine = lines.last(where: {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }),
            let wordResult = TextScanner.lastWord(in: currentLine)
        else {
            trace("terminal: не вдалося знайти останнє слово")
            return nil
        }

        trace("terminal: AXValue слово='\(wordResult.word)' trailing=\(wordResult.trailingSpacesCount)")
        return makeLastWordTarget(wordResult, origin: origin)
    }

    private func readAXLastWord(
        focusedElement: AXUIElement?,
        origin: ReadOrigin,
        tracePrefix: String
    ) -> TextTarget? {
        guard let focusedElement else {
            trace("\(tracePrefix): focusedElement == nil")
            return nil
        }

        var value: String? = nil
        for attempt in 0..<3 {
            value = stringAttribute(kAXValueAttribute as CFString, from: focusedElement)
            if value != nil { break }
            trace("\(tracePrefix): AXValue спроба \(attempt + 1) — nil")
            waitForKeyboardSideEffects(timeout: 0.05)
        }

        guard let value else {
            trace("\(tracePrefix): AXValue == nil після 3 спроб")
            return nil
        }

        guard let wordResult = TextScanner.lastWord(in: value) else {
            trace("\(tracePrefix): lastWord не знайдено у value='\(value.prefix(80))'")
            return nil
        }

        trace("\(tracePrefix): AXValue слово='\(wordResult.word)' trailing=\(wordResult.trailingSpacesCount)")
        return makeLastWordTarget(wordResult, origin: origin)
    }

    private func makeCopiedTarget(_ text: String, origin: ReadOrigin) -> TextTarget {
        TextTarget(
            text: text,
            trailingSpacesCount: 0,
            wordLength: text.count,
            origin: origin)
    }

    private func makeLastWordTarget(
        _ wordResult: (word: String, trailingSpacesCount: Int),
        origin: ReadOrigin
    ) -> TextTarget {
        TextTarget(
            text: wordResult.word,
            trailingSpacesCount: wordResult.trailingSpacesCount,
            wordLength: wordResult.word.count,
            origin: origin)
    }

    // MARK: - Заміна тексту

    // * -- Заміна поточної цілі за фактичним origin читання --
    func replace(_ target: TextTarget, with replacement: String) -> Bool {
        trace("replace: origin=\(target.origin) wordLen=\(target.wordLength)")

        switch target.origin {
        case .copiedEditableSelection, .copiedCodeEditorSelection:
            return pasteReplacement(replacement, settleTimeout: commandTimeout)
        case .editableAXLastWord, .codeEditorAXLastWord, .integratedTerminalAXLastWord:
            return replaceLastWordByBackspace(target, with: replacement, settleTimeout: 0.55)
        case .standaloneTerminalAXLastWord:
            return replaceStandaloneTerminalLastWord(target, with: replacement)
        case .copiedBrowserGridLike:
            return replaceBrowserGridLike(with: replacement)
        }
    }

    private func replaceLastWordByBackspace(
        _ target: TextTarget,
        with replacement: String,
        settleTimeout: TimeInterval
    ) -> Bool {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }
        syncMain { pasteboard.clearContents() }

        let replacementWithSpaces = replacement + String(repeating: " ", count: target.trailingSpacesCount)
        guard syncMain({ pasteboard.setString(replacementWithSpaces, forType: .string) }) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        let totalDeleteLength = target.wordLength + target.trailingSpacesCount
        for i in 0..<totalDeleteLength {
            guard sendKeyboardShortcut(keyCode: KeyCode.delete, flags: []) else {
                trace("replaceLastWord: Backspace \(i) не вдався")
                syncMain { snapshot.restore(to: pasteboard) }
                return false
            }
            waitForKeyboardSideEffects(timeout: pollStep)
        }

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }
        waitForKeyboardSideEffects(timeout: settleTimeout)

        syncMain { snapshot.restore(to: pasteboard) }
        return true
    }

    private func replaceStandaloneTerminalLastWord(_ target: TextTarget, with replacement: String) -> Bool {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }
        syncMain { pasteboard.clearContents() }

        let replacementWithSpaces = replacement + String(repeating: " ", count: target.trailingSpacesCount)
        guard syncMain({ pasteboard.setString(replacementWithSpaces, forType: .string) }) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        guard sendKeyboardShortcut(keyCode: KeyCode.w, flags: .maskControl) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.05)

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.55)

        trace("standaloneTerminal: Ctrl+W + Cmd+V")
        syncMain { snapshot.restore(to: pasteboard) }
        return true
    }

    private func replaceBrowserGridLike(with replacement: String) -> Bool {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }
        syncMain { pasteboard.clearContents() }

        guard syncMain({ pasteboard.setString(replacement, forType: .string) }) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        // F2 завжди — CGEvent працює навіть без AX.
        guard sendKeyboardShortcut(keyCode: KeyCode.f2, flags: []) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        // Якщо AX є — перевіряємо edit mode. Якщо немає — чекаємо наосліп.
        if focusedTextElement() != nil {
            guard waitForGridEditMode(previousRole: nil, timeout: 0.6) else {
                trace("browserGrid: F2 не дав edit-mode сигналу")
                syncMain { snapshot.restore(to: pasteboard) }
                return false
            }
        } else {
            trace("browserGrid: AX недоступний, F2 наосліп, чекаємо 0.8с")
            waitForKeyboardSideEffects(timeout: 0.8)
        }

        guard sendKeyboardShortcut(keyCode: KeyCode.a, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.08)

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }
        waitForKeyboardSideEffects(timeout: 1.0)

        guard sendKeyboardShortcut(keyCode: KeyCode.a, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.08)

        trace("browserGrid: F2 → Cmd+A → Cmd+V → Cmd+A")
        syncMain { snapshot.restore(to: pasteboard) }
        return true
    }

    private func pasteReplacement(_ replacement: String, settleTimeout: TimeInterval) -> Bool {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }
        syncMain { pasteboard.clearContents() }

        guard syncMain({ pasteboard.setString(replacement, forType: .string) }) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        // * -- C3: збільшений settleTimeout (1.0 с), щоб цільовий застосунок
        // * -- встиг прочитати pasteboard до відновлення попереднього вмісту. --
        waitForKeyboardSideEffects(timeout: max(settleTimeout, 1.0))

        syncMain { snapshot.restore(to: pasteboard) }
        return true
    }

    // MARK: - Контекст застосунку

    private func makeInteractionContext(
        bundleIdentifier: String?,
        focusedElement: AXUIElement?
    ) -> InteractionContext {
        let role = focusedElement.flatMap {
            stringAttribute(kAXRoleAttribute as CFString, from: $0)
        }
        let appKind = appKind(bundleIdentifier: bundleIdentifier, focusedElement: focusedElement)
        let isEditable = focusedElement.map {
            isEditableContext($0, role: role)
        } ?? false

        return InteractionContext(
            appKind: appKind,
            focusedElement: focusedElement,
            role: role,
            isEditable: isEditable)
    }

    private func appKind(bundleIdentifier: String?, focusedElement: AXUIElement?) -> AppKind {
        if AppEnvironmentClassifier.isStandaloneTerminal(bundleIdentifier: bundleIdentifier) {
            return .standaloneTerminal
        }

        if AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: bundleIdentifier) {
            return isIntegratedTerminalElement(focusedElement) ? .integratedTerminal : .codeEditor
        }

        if let bundleIdentifier, browserBundleIdentifiers.contains(bundleIdentifier) {
            return .browser
        }

        return .other
    }

    private func isIntegratedTerminalElement(_ focusedElement: AXUIElement?) -> Bool {
        guard let focusedElement else { return false }

        return AppEnvironmentClassifier.isIntegratedTerminal(
            role: stringAttribute(kAXRoleAttribute as CFString, from: focusedElement),
            title: stringAttribute(kAXTitleAttribute as CFString, from: focusedElement),
            description: stringAttribute(kAXDescriptionAttribute as CFString, from: focusedElement),
            identifier: stringAttribute(kAXIdentifierAttribute as CFString, from: focusedElement),
            value: stringAttribute(kAXValueAttribute as CFString, from: focusedElement))
    }

    // * -- Чекаємо, поки F2 переведе активну комірку в режим редагування.
    // * -- Canvas-таблиці не завжди виставляють AXEditable, тому приймаємо кілька сигналів. --
    private func waitForGridEditMode(previousRole: String?, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastRole: String? = previousRole
        repeat {
            if let element = focusedTextElement() {
                let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
                lastRole = role
                // Сигнал 1: контекст став явно редагованим.
                if isEditableContext(element, role: role) {
                    trace("browserGrid: edit mode сигнал=editable role=\(role ?? "nil")")
                    return true
                }
                // Сигнал 2: роль фокуса змінилася після F2 (фокус перейшов у редактор комірки).
                if role != previousRole {
                    trace("browserGrid: edit mode сигнал=roleChanged \(previousRole ?? "nil")->\(role ?? "nil")")
                    return true
                }
                // Сигнал 3: фокус віддає AXSelectedText (текстовий редактор комірки активний).
                if stringAttribute(kAXSelectedTextAttribute as CFString, from: element) != nil {
                    trace("browserGrid: edit mode сигнал=selectedTextReadable role=\(role ?? "nil")")
                    return true
                }
            } else {
                trace("browserGrid: focusedTextElement == nil у циклі очікування")
            }
            waitForKeyboardSideEffects(timeout: pollStep)
        } while Date() < deadline
        trace("browserGrid: waitForGridEditMode FAILED, lastRole=\(lastRole ?? "nil")")
        return false
    }

    private func isEditableContext(_ element: AXUIElement, role: String?) -> Bool {
        if boolAttribute(axEditableAttributeName, from: element) == true {
            return true
        }

        return ["AXTextArea", "AXTextField", "AXSearchField", "AXComboBox"].contains(role)
    }

    // MARK: - Низькорівневі допоміжні методи

    // * -- Копіювання поточної цілі через pasteboard --
    private func copyTextThroughPasteboard(timeout: TimeInterval = 0.5) -> String? {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }
        syncMain { pasteboard.clearContents() }
        let clearChangeCount = syncMain { pasteboard.changeCount }

        guard sendKeyboardShortcut(keyCode: KeyCode.c, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return nil
        }

        let copied = waitForCopiedString(after: clearChangeCount, timeout: timeout)
        syncMain { snapshot.restore(to: pasteboard) }

        guard let copied,
            !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return copied
    }

    // * -- Фокусований AX елемент.
    // * -- AXUIElementCopyAttributeValue вимагає головного потоку (XPC до цільового застосунку).
    // * -- Використовуємо прямий запит до frontmost app замість systemWide:
    // * -- Chrome/VS Code блокують kAXFocusedUIElementAttribute через systemWide. --
    private func focusedTextElement() -> AXUIElement? {
        syncMain {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var focusedValue: CFTypeRef?
            let focusedResult = AXUIElementCopyAttributeValue(
                appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)

            guard focusedResult == .success else {
                rawLog("focusedTextElement: AX error \(focusedResult.rawValue)")
                return nil
            }
            guard let focusedValue else {
                rawLog("focusedTextElement: focusedValue is nil")
                return nil
            }
            guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
                rawLog("focusedTextElement: wrong typeID")
                return nil
            }

            return unsafeBitCast(focusedValue, to: AXUIElement.self)
        }
    }

    // * -- Рядковий атрибут AX.
    // * -- Обгорнуто в syncMain: AX-запити потребують головного потоку. --
    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        syncMain {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            guard result == .success else {
                rawLog("AX stringAttribute error: \(result.rawValue) for attr=\(attribute)")
                return nil
            }
            return value as? String
        }
    }

    // * -- Булевий атрибут AX.
    // * -- Обгорнуто в syncMain: AX-запити потребують головного потоку. --
    private func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        syncMain {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            guard result == .success, let value else {
                if result != .success {
                    rawLog("AX boolAttribute error: \(result.rawValue) for attr=\(attribute)")
                }
                return nil
            }
            guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
            let booleanValue = unsafeBitCast(value, to: CFBoolean.self)
            return CFBooleanGetValue(booleanValue)
        }
    }

    // * -- Надсилання системного key down/up --
    private func sendKeyboardShortcut(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = flags
        keyDown.setIntegerValueField(.eventSourceUserData, value: freePuntoSyntheticEventMarker)
        keyUp.flags = flags
        keyUp.setIntegerValueField(.eventSourceUserData, value: freePuntoSyntheticEventMarker)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    // * -- Очікування обробки клавіатурної команди --
    // * -- Thread.sleep не блокує RunLoop головного потоку, тому CGEventTap не вимикається по таймауту --
    private func waitForKeyboardSideEffects(timeout: TimeInterval) {
        Thread.sleep(forTimeInterval: timeout)
    }

    // * -- Очікування оновлення pasteboard --
    private func waitForCopiedString(after changeCount: Int, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if syncMain({ pasteboard.changeCount }) > changeCount,
                let copied = syncMain({ pasteboard.string(forType: .string) })
            {
                return copied
            }
            waitForKeyboardSideEffects(timeout: pollStep)
        }
        return nil
    }
}

// * -- Маркер власних синтетичних подій, щоб HotKeyController їх ігнорував --
let freePuntoSyntheticEventMarker: Int64 = 0x4652_5045

// * -- Коди клавіш для симуляції клавіатурних шорткатів --
private enum KeyCode {
    static let a: CGKeyCode = 0
    static let c: CGKeyCode = 8
    static let v: CGKeyCode = 9
    static let w: CGKeyCode = 13
    static let delete: CGKeyCode = 51
    static let f2: CGKeyCode = 120
}

// * -- Знімок pasteboard для відновлення після copy/paste --
private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    // Зберігаємо всі типи даних, а не тільки plain text.
    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items =
            pasteboard.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
                var result: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) {
                        result[type] = data
                    }
                }
                return result
            } ?? []

        return PasteboardSnapshot(items: items)
    }

    // Відновлюємо всі типи даних у pasteboard.
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { itemData -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}

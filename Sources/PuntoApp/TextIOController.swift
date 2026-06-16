import AppKit
import ApplicationServices
import PuntoCore

// * -- Текстова ціль команди --
struct TextTarget {
    let text: String
    let source: Source
    let trailingSpacesCount: Int
    let wordLength: Int
    fileprivate let profile: AppProfile
    fileprivate let accessibilitySelection: AccessibilitySelection?

    enum Source {
        case selectedText
        case previousWord
        case gridCell
    }
}

// * -- Профіль взаємодії з текстом --
private enum AppProfile {
    case standardText
    case vscodeEditor
    case integratedTerminal
    case standaloneTerminal
    case googleSheetsGrid
    case canvasGrid
}

// * -- Допоміжні типи --
private struct AccessibilitySelection {
    let element: AXUIElement
    let text: String
    let selectedRange: CFRange?
    let currentValue: String?
    let trailingSpacesCount: Int
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

    // Прапорець діагностичного логування.
    private static let traceEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    // MARK: - Діагностичний трейс

    // Логування подій для діагностики (профіль, метод читання/заміни, ключові події).
    private func trace(_ message: @autoclosure () -> String) {
        guard Self.traceEnabled else { return }
        NSLog("[TextIO] %@", message())
    }

    // MARK: - Визначення профілю

    // * -- Визначення профілю за пріоритетом --
    private func detectProfile(
        bundleIdentifier: String?,
        focusedElement: AXUIElement?,
        windowTitle: String?
    ) -> AppProfile {
        guard let bundleIdentifier else {
            return .standardText
        }

        // 1. Автономний термінал (iTerm, Terminal.app, Warp тощо).
        if AppEnvironmentClassifier.isStandaloneTerminal(bundleIdentifier: bundleIdentifier) {
            return .standaloneTerminal
        }

        // 2. Інтегрований термінал VS Code / Antigravity.
        if AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: bundleIdentifier) {
            if isIntegratedTerminalElement(focusedElement, windowTitle: windowTitle) {
                return .integratedTerminal
            }
            // 3. Редакторна панель VS Code.
            return .vscodeEditor
        }

        // 4. Google Sheets (незалежно від браузера чи PWA).
        if AppEnvironmentClassifier.isGoogleSheetsWindow(windowTitle: windowTitle) {
            if isEditableTextField(focusedElement) {
                return .standardText
            }
            return .googleSheetsGrid
        }

        // 5. CanvasTable (наш застосунок, може бути Electron чи веб-версія).
        if AppEnvironmentClassifier.isCanvasTableApp(windowTitle: windowTitle) {
            if isEditableTextField(focusedElement) {
                return .standardText
            }
            return .canvasGrid
        }

        // 6. Браузер (загальний).
        if browserBundleIdentifiers.contains(bundleIdentifier) {
            return .standardText
        }

        // 7. Все інше.
        return .standardText
    }

    // Перевірка, чи елемент є інтегрованим терміналом VS Code.
    private func isIntegratedTerminalElement(
        _ focusedElement: AXUIElement?,
        windowTitle: String?
    ) -> Bool {
        let effectiveWindowTitle = windowTitle
            ?? frontmostWindowTitle(
                processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier)

        guard let focusedElement else {
            return AppEnvironmentClassifier.isIntegratedTerminal(
                role: nil, title: nil, description: nil,
                identifier: nil, windowTitle: effectiveWindowTitle, value: nil)
        }

        return AppEnvironmentClassifier.isIntegratedTerminal(
            role: stringAttribute(kAXRoleAttribute as CFString, from: focusedElement),
            title: stringAttribute(kAXTitleAttribute as CFString, from: focusedElement),
            description: stringAttribute(kAXDescriptionAttribute as CFString, from: focusedElement),
            identifier: stringAttribute(kAXIdentifierAttribute as CFString, from: focusedElement),
            windowTitle: effectiveWindowTitle,
            value: stringAttribute(kAXValueAttribute as CFString, from: focusedElement))
    }

    // Перевірка, чи фокус на редагованому текстовому полі (для браузерів).
    private func isEditableTextField(_ element: AXUIElement?) -> Bool {
        guard let element else { return false }

        if boolAttribute(axEditableAttributeName, from: element) == true {
            return true
        }
        if selectedTextRange(from: element) != nil,
            stringAttribute(kAXValueAttribute as CFString, from: element) != nil
        {
            return true
        }
        guard let role = stringAttribute(kAXRoleAttribute as CFString, from: element) else {
            return false
        }
        return ["AXTextArea", "AXTextField", "AXSearchField", "AXComboBox"].contains(role)
    }

    // MARK: - Читання тексту

    // * -- Читання тексту для перетворення --
    func readTarget() -> TextTarget? {
        let hasAccessibility = Diagnostics.accessibilityTrusted(prompt: false)
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let focusedElement = hasAccessibility ? focusedTextElement() : nil
        let windowTitle =
            hasAccessibility
            ? frontmostWindowTitle(processIdentifier: frontmostApp?.processIdentifier)
            : nil

        let profile = detectProfile(
            bundleIdentifier: frontmostApp?.bundleIdentifier,
            focusedElement: focusedElement,
            windowTitle: windowTitle)

        trace("profile=\(profile) bundle=\(frontmostApp?.bundleIdentifier ?? "nil") window=\(windowTitle ?? "nil")")

        switch profile {
        case .standardText:
            return readStandardText(focusedElement: focusedElement, profile: profile)
        case .vscodeEditor:
            return readVSCodeEditor(focusedElement: focusedElement, profile: profile)
        case .integratedTerminal:
            return readTerminal(focusedElement: focusedElement, profile: profile)
        case .standaloneTerminal:
            return readTerminal(focusedElement: focusedElement, profile: profile)
        case .googleSheetsGrid:
            return readGridCell(focusedElement: focusedElement, profile: profile)
        case .canvasGrid:
            return readGridCell(focusedElement: focusedElement, profile: profile)
        }
    }

    // * -- standardText: AX selectedText → AX previousWord → pasteboard Cmd+C → клавіатурний fallback --
    private func readStandardText(focusedElement: AXUIElement?, profile: AppProfile) -> TextTarget? {
        // 1. AX виділення.
        if let focused = focusedElement,
            let selection = readSelectedTextWithAccessibility(focused: focused)
        {
            trace("standardText: читання через AX selectedText")
            return TextTarget(
                text: selection.text, source: .selectedText,
                trailingSpacesCount: 0, wordLength: (selection.text as NSString).length,
                profile: profile, accessibilitySelection: selection)
        }

        // 2. AX попереднє слово.
        if let focused = focusedElement,
            let selection = readPreviousWordWithAccessibility(focused: focused)
        {
            trace("standardText: читання через AX previousWord")
            return TextTarget(
                text: selection.text, source: .previousWord,
                trailingSpacesCount: selection.trailingSpacesCount,
                wordLength: (selection.text as NSString).length,
                profile: profile, accessibilitySelection: selection)
        }

        // 3. Pasteboard Cmd+C.
        if let copiedSelection = copySelectedTextThroughPasteboard(timeout: 0.08),
            !copiedSelection.isEmpty
        {
            trace("standardText: читання через pasteboard Cmd+C")
            let axSel = focusedElement.flatMap {
                readSelectedTextWithAccessibility(focused: $0, copiedText: copiedSelection)
            }
            return TextTarget(
                text: copiedSelection, source: .selectedText,
                trailingSpacesCount: 0, wordLength: (copiedSelection as NSString).length,
                profile: profile, accessibilitySelection: axSel)
        }

        // 4. Клавіатурний fallback (Cmd+Shift+Left).
        if let fallback = selectAndCopyPreviousWordByLineSelection(copyTimeout: 0.08) {
            trace("standardText: клавіатурний fallback")
            return TextTarget(
                text: fallback.word, source: .previousWord,
                trailingSpacesCount: fallback.trailingSpacesCount,
                wordLength: (fallback.word as NSString).length,
                profile: profile, accessibilitySelection: nil)
        }

        return nil
    }

    // * -- vscodeEditor: Pasteboard Cmd+C (з AX підтвердженням) → AX selectedText → Option+Shift+Left fallback --
    private func readVSCodeEditor(focusedElement: AXUIElement?, profile: AppProfile) -> TextTarget? {
        // 1. Pasteboard Cmd+C — основний метод для VS Code.
        if let copiedText = copySelectedTextThroughPasteboard(timeout: 0.18),
            !copiedText.isEmpty
        {
            // VS Code копіює рядок, якщо немає виділення — перевіряємо через AX або евристику.
            let axSel = focusedElement.flatMap {
                readSelectedTextWithAccessibility(focused: $0, copiedText: copiedText)
            }
            let normalized = copiedText.replacingOccurrences(of: "\r\n", with: "\n")
            if axSel != nil || !normalized.hasSuffix("\n") {
                trace("vscodeEditor: pasteboard Cmd+C")
                return TextTarget(
                    text: copiedText, source: .selectedText,
                    trailingSpacesCount: 0, wordLength: (copiedText as NSString).length,
                    profile: profile, accessibilitySelection: axSel)
            }
        }

        // 2. AX selectedText.
        if let focused = focusedElement,
            let selection = readSelectedTextWithAccessibility(focused: focused)
        {
            trace("vscodeEditor: AX selectedText")
            return TextTarget(
                text: selection.text, source: .selectedText,
                trailingSpacesCount: 0, wordLength: (selection.text as NSString).length,
                profile: profile, accessibilitySelection: selection)
        }

        // 3. AX попереднє слово.
        if let focused = focusedElement,
            let selection = readPreviousWordWithAccessibility(focused: focused)
        {
            trace("vscodeEditor: AX previousWord")
            return TextTarget(
                text: selection.text, source: .previousWord,
                trailingSpacesCount: selection.trailingSpacesCount,
                wordLength: (selection.text as NSString).length,
                profile: profile, accessibilitySelection: selection)
        }

        // 4. Fallback через Option+Shift+Left (word navigation).
        if let wordNav = selectAndCopyPreviousWordWithWordNavigation(copyTimeout: 0.18) {
            trace("vscodeEditor: word navigation fallback")
            return TextTarget(
                text: wordNav.word, source: .previousWord,
                trailingSpacesCount: wordNav.trailingSpacesCount,
                wordLength: (wordNav.word as NSString).length,
                profile: profile, accessibilitySelection: nil)
        }

        return nil
    }

    // * -- Terminal (інтегрований і автономний): AX value → lastWord. Інше → nil (beep). --
    private func readTerminal(focusedElement: AXUIElement?, profile: AppProfile) -> TextTarget? {
        guard let focused = focusedElement,
            let value = stringAttribute(kAXValueAttribute as CFString, from: focused)
        else {
            trace("terminal: AX value недоступний")
            return nil
        }

        // Знаходимо останній непорожній рядок і останнє слово з нього.
        let lines = value.components(separatedBy: .newlines)
        guard
            let currentLine = lines.last(where: {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }),
            let wordResult = lastWord(in: currentLine)
        else {
            trace("terminal: не вдалося знайти останнє слово")
            return nil
        }

        trace("terminal: слово='\(wordResult.word)' trailing=\(wordResult.trailingSpacesCount)")
        return TextTarget(
            text: wordResult.word, source: .previousWord,
            trailingSpacesCount: wordResult.trailingSpacesCount,
            wordLength: (wordResult.word as NSString).length,
            profile: profile, accessibilitySelection: nil)
    }

    // * -- Grid (Google Sheets / CanvasTable): AX cell value. Уникаємо Cmd+C. --
    private func readGridCell(focusedElement: AXUIElement?, profile: AppProfile) -> TextTarget? {
        guard let focused = focusedElement else {
            trace("grid: немає focused element")
            return nil
        }

        let role = stringAttribute(kAXRoleAttribute as CFString, from: focused)
        let selectedText = stringAttribute(kAXSelectedTextAttribute as CFString, from: focused)
        let valueText = stringAttribute(kAXValueAttribute as CFString, from: focused)

        guard
            let cellText = AccessibilityTextSelection.preferredText(
                selectedText: selectedText, valueText: valueText, role: role),
            !cellText.isEmpty
        else {
            trace("grid: AX cell value порожній")
            return nil
        }

        trace("grid: cellText='\(cellText)'")
        return TextTarget(
            text: cellText, source: .gridCell,
            trailingSpacesCount: 0, wordLength: (cellText as NSString).length,
            profile: profile, accessibilitySelection: nil)
    }

    // MARK: - Заміна тексту

    // * -- Заміна поточного виділення --
    func replace(_ target: TextTarget, with replacement: String) -> Bool {
        trace("replace: profile=\(target.profile) source=\(target.source) wordLen=\(target.wordLength)")

        switch target.profile {
        case .standardText:
            return replaceStandardText(target, with: replacement)
        case .vscodeEditor:
            return replaceVSCodeEditor(target, with: replacement)
        case .integratedTerminal:
            return replaceIntegratedTerminal(target, with: replacement)
        case .standaloneTerminal:
            return replaceStandaloneTerminal(target, with: replacement)
        case .googleSheetsGrid, .canvasGrid:
            return replaceGridCell(with: replacement)
        }
    }

    // * -- standardText: AX setSelectedText → якщо не вдалося → Cmd+V --
    private func replaceStandardText(_ target: TextTarget, with replacement: String) -> Bool {
        if let selection = target.accessibilitySelection {
            if replaceWithAccessibility(selection, replacement: replacement,
                trailingSpacesCount: target.trailingSpacesCount)
            {
                trace("standardText: замінено через AX")
                return true
            }
        }

        // Fallback: Cmd+V через pasteboard.
        let ok = pasteReplacement(
            replacement, settleTimeout: commandTimeout,
            deleteBeforePaste: false,
            verificationSelection: target.accessibilitySelection)
        if ok { trace("standardText: замінено через Cmd+V") }
        return ok
    }

    // * -- vscodeEditor: Delete + Cmd+V → якщо не вдалося → AX --
    private func replaceVSCodeEditor(_ target: TextTarget, with replacement: String) -> Bool {
        // Якщо у нас є Accessibility-виділення, спочатку пробуємо AX.
        if let selection = target.accessibilitySelection {
            if replaceWithAccessibility(selection, replacement: replacement,
                trailingSpacesCount: target.trailingSpacesCount)
            {
                trace("vscodeEditor: замінено через AX")
                return true
            }
        }

        // Основний метод: Delete + Cmd+V.
        if pasteReplacement(
            replacement, settleTimeout: 0.55,
            deleteBeforePaste: true,
            verificationSelection: nil)
        {
            trace("vscodeEditor: замінено через Delete+Cmd+V")
            return true
        }

        return false
    }

    // * -- integratedTerminal: Backspace×N + Cmd+V (НІКОЛИ Ctrl+W і escape-послідовності!) --
    private func replaceIntegratedTerminal(_ target: TextTarget, with replacement: String) -> Bool {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()

        // Додаємо хвостові пробіли до заміни, щоб відновити їх після вставки.
        let replacementWithSpaces = replacement + String(repeating: " ", count: target.trailingSpacesCount)
        guard pasteboard.setString(replacementWithSpaces, forType: .string) else {
            snapshot.restore(to: pasteboard)
            return false
        }

        // Видаляємо слово та хвостові пробіли посимвольно через Backspace.
        let totalDeleteLength = target.wordLength + target.trailingSpacesCount
        for i in 0..<totalDeleteLength {
            guard sendKeyboardShortcut(keyCode: KeyCode.delete, flags: []) else {
                trace("integratedTerminal: Backspace \(i) не вдався")
                snapshot.restore(to: pasteboard)
                return false
            }
        }
        if totalDeleteLength > 0 {
            waitForKeyboardSideEffects(timeout: 0.05)
        }

        // Вставляємо заміну через Cmd+V.
        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            snapshot.restore(to: pasteboard)
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.55)

        trace("integratedTerminal: Backspace×\(totalDeleteLength) + Cmd+V")
        snapshot.restore(to: pasteboard)
        return true
    }

    // * -- standaloneTerminal: Ctrl+W + Cmd+V --
    private func replaceStandaloneTerminal(_ target: TextTarget, with replacement: String) -> Bool {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()

        // Додаємо хвостові пробіли до заміни, щоб відновити їх після вставки.
        let replacementWithSpaces = replacement + String(repeating: " ", count: target.trailingSpacesCount)
        guard pasteboard.setString(replacementWithSpaces, forType: .string) else {
            snapshot.restore(to: pasteboard)
            return false
        }

        // Ctrl+W видаляє попереднє слово та хвостові пробіли в bash/zsh.
        guard sendKeyboardShortcut(keyCode: KeyCode.w, flags: .maskControl) else {
            snapshot.restore(to: pasteboard)
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.05)

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            snapshot.restore(to: pasteboard)
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.55)

        trace("standaloneTerminal: Ctrl+W + Cmd+V")
        snapshot.restore(to: pasteboard)
        return true
    }

    // * -- Grid (Google Sheets / CanvasTable): Escape×2 → Enter → Cmd+A → Cmd+V --
    private func replaceGridCell(with replacement: String) -> Bool {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()

        guard pasteboard.setString(replacement, forType: .string) else {
            snapshot.restore(to: pasteboard)
            return false
        }

        // Подвійний Escape — гарантовано виходимо з copy-mode.
        _ = sendKeyboardShortcut(keyCode: KeyCode.escape, flags: [])
        waitForKeyboardSideEffects(timeout: 0.20)
        _ = sendKeyboardShortcut(keyCode: KeyCode.escape, flags: [])
        waitForKeyboardSideEffects(timeout: 0.15)

        // Enter — активуємо режим редагування комірки (НЕ F2).
        guard sendKeyboardShortcut(keyCode: KeyCode.returnKey, flags: []) else {
            snapshot.restore(to: pasteboard)
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.45)

        // Cmd+A — виділяємо весь вміст комірки.
        guard sendKeyboardShortcut(keyCode: KeyCode.a, flags: .maskCommand) else {
            snapshot.restore(to: pasteboard)
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.08)

        // Cmd+V — вставляємо заміну.
        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            snapshot.restore(to: pasteboard)
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.75)

        trace("grid: Esc×2 → Enter → Cmd+A → Cmd+V")
        snapshot.restore(to: pasteboard)
        return true
    }

    // MARK: - Допоміжні методи заміни

    // Заміна через AX setSelectedText з верифікацією.
    private func replaceWithAccessibility(
        _ selection: AccessibilitySelection,
        replacement: String,
        trailingSpacesCount: Int
    ) -> Bool {
        // Відновлюємо діапазон виділення, якщо він відомий.
        if let selectedRange = selection.selectedRange {
            _ = setSelectedTextRange(selectedRange, for: selection.element)
        }

        let result = AXUIElementSetAttributeValue(
            selection.element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFString)

        guard result == .success else {
            return false
        }

        // Верифікація: порівнюємо очікуване значення з поточним.
        if let selectedRange = selection.selectedRange,
            selectedRange.location >= 0, selectedRange.length >= 0,
            let previousValue = selection.currentValue,
            let currentValue = stringAttribute(kAXValueAttribute as CFString, from: selection.element)
        {
            let prev = previousValue as NSString
            let start = selectedRange.location
            let end = selectedRange.location + selectedRange.length
            if start <= prev.length, end <= prev.length {
                let expected = prev.substring(to: start) + replacement + prev.substring(from: end)
                if currentValue != expected {
                    return false
                }
            }
        }

        // Переміщуємо курсор після trailing пробілів.
        if trailingSpacesCount > 0, let selectedRange = selection.selectedRange {
            let newCaret =
                selectedRange.location + (replacement as NSString).length + trailingSpacesCount
            _ = setSelectedTextRange(
                CFRange(location: newCaret, length: 0), for: selection.element)
        }

        return true
    }

    // Вставка заміни через pasteboard (Cmd+V), опціонально з попереднім Delete.
    private func pasteReplacement(
        _ replacement: String,
        settleTimeout: TimeInterval,
        deleteBeforePaste: Bool,
        verificationSelection: AccessibilitySelection?
    ) -> Bool {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()

        guard pasteboard.setString(replacement, forType: .string) else {
            snapshot.restore(to: pasteboard)
            return false
        }

        if deleteBeforePaste {
            guard sendKeyboardShortcut(keyCode: KeyCode.delete, flags: []) else {
                snapshot.restore(to: pasteboard)
                return false
            }
            waitForKeyboardSideEffects(timeout: pollStep)
        }

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            snapshot.restore(to: pasteboard)
            return false
        }
        waitForKeyboardSideEffects(timeout: settleTimeout)

        snapshot.restore(to: pasteboard)
        return true
    }

    // MARK: - Низькорівневі допоміжні методи

    // * -- Читання виділеного тексту через AX --
    private func readSelectedTextWithAccessibility(
        focused: AXUIElement,
        copiedText: String? = nil
    ) -> AccessibilitySelection? {
        let selectedText = stringAttribute(kAXSelectedTextAttribute as CFString, from: focused)
        let range = selectedTextRange(from: focused)
        let text: String?

        if let selectedText, !selectedText.isEmpty {
            text = selectedText
        } else if let copiedText, !copiedText.isEmpty, let range, range.length > 0 {
            text = copiedText
        } else {
            text = nil
        }

        guard let text else { return nil }

        return AccessibilitySelection(
            element: focused, text: text, selectedRange: range,
            currentValue: stringAttribute(kAXValueAttribute as CFString, from: focused),
            trailingSpacesCount: 0)
    }

    // * -- Читання попереднього слова через AX (курсор без виділення) --
    private func readPreviousWordWithAccessibility(focused: AXUIElement) -> AccessibilitySelection? {
        guard let range = selectedTextRange(from: focused),
            range.length == 0,
            let value = stringAttribute(kAXValueAttribute as CFString, from: focused)
        else {
            return nil
        }

        let leftString = value as String
        guard range.location > 0, range.location <= (leftString as NSString).length else {
            return nil
        }

        let leftStringCut = (leftString as NSString).substring(to: range.location)
        guard let wordResult = lastWord(in: leftStringCut) else {
            return nil
        }

        let wordLength = (wordResult.word as NSString).length
        let wordStartIndex =
            (leftStringCut as NSString).length - wordResult.trailingSpacesCount - wordLength

        return AccessibilitySelection(
            element: focused, text: wordResult.word,
            selectedRange: CFRange(location: wordStartIndex, length: wordLength),
            currentValue: value, trailingSpacesCount: wordResult.trailingSpacesCount)
    }

    // * -- Останнє слово в рядку --
    private func lastWord(in text: String) -> (word: String, trailingSpacesCount: Int)? {
        // Пропускаємо хвостові пробіли.
        var endIndex = text.endIndex
        while endIndex > text.startIndex {
            let prevIndex = text.index(before: endIndex)
            if text[prevIndex].isWhitespace || text[prevIndex].isNewline {
                endIndex = prevIndex
            } else {
                break
            }
        }

        let wordText = text[..<endIndex]
        let word: String
        if let lastWhitespaceRange = wordText.rangeOfCharacter(
            from: .whitespacesAndNewlines, options: .backwards)
        {
            word = String(wordText.suffix(from: lastWhitespaceRange.upperBound))
        } else {
            word = String(wordText)
        }

        let wordLength = (word as NSString).length
        guard wordLength > 0, wordLength <= 40 else {
            return nil
        }

        return (
            word: word,
            trailingSpacesCount: text.distance(from: endIndex, to: text.endIndex)
        )
    }

    // * -- Виділення слова через Option+Shift+Left --
    private func selectAndCopyPreviousWordWithWordNavigation(copyTimeout: TimeInterval) -> (
        word: String, trailingSpacesCount: Int
    )? {
        guard sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: [.maskAlternate, .maskShift])
        else {
            return nil
        }
        waitForKeyboardSideEffects(timeout: pollStep)

        guard let selectedText = copySelectedTextThroughPasteboard(timeout: copyTimeout) else {
            _ = sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: [])
            return nil
        }

        let word = selectedText.trimmingCharacters(in: .newlines)
        let wordLength = (word as NSString).length
        guard wordLength > 0, wordLength <= 40 else {
            _ = sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: [])
            return nil
        }

        return (word: word, trailingSpacesCount: 0)
    }

    // * -- Виділення попереднього слова через Cmd+Shift+Left (лінійний fallback) --
    private func selectAndCopyPreviousWordByLineSelection(copyTimeout: TimeInterval) -> (
        word: String, trailingSpacesCount: Int
    )? {
        // 1. Виділяємо текст від курсора до початку рядка.
        guard sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: [.maskCommand, .maskShift])
        else {
            return nil
        }
        waitForKeyboardSideEffects(timeout: pollStep)

        // 2. Копіюємо виділений текст.
        guard let lineText = copySelectedTextThroughPasteboard(timeout: copyTimeout) else {
            _ = sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: [])
            return nil
        }

        // 3. Знімаємо виділення.
        guard sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: []) else {
            return nil
        }
        waitForKeyboardSideEffects(timeout: pollStep)

        // 4. Знаходимо останнє слово.
        let trimmedLine = lineText.trimmingCharacters(in: .newlines)
        guard let wordResult = lastWord(in: trimmedLine) else {
            return nil
        }

        // 5. Переміщуємо курсор ліворуч повз trailing пробіли.
        for _ in 0..<wordResult.trailingSpacesCount {
            guard sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: []) else {
                return nil
            }
        }
        if wordResult.trailingSpacesCount > 0 {
            waitForKeyboardSideEffects(timeout: pollStep)
        }

        // 6. Виділяємо слово: Shift+Left × wordLength.
        let wordLength = (wordResult.word as NSString).length
        for _ in 0..<wordLength {
            guard sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: .maskShift) else {
                return nil
            }
        }
        waitForKeyboardSideEffects(timeout: pollStep)

        return (word: wordResult.word, trailingSpacesCount: wordResult.trailingSpacesCount)
    }

    // * -- Фокусований AX елемент --
    private func focusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue)

        guard focusedResult == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return unsafeBitCast(focusedValue, to: AXUIElement.self)
    }

    // * -- Рядковий атрибут AX --
    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    // * -- Булевий атрибут AX --
    private func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        let booleanValue = unsafeBitCast(value, to: CFBoolean.self)
        return CFBooleanGetValue(booleanValue)
    }

    // * -- Діапазон виділеного тексту --
    private func selectedTextRange(from element: AXUIElement) -> CFRange? {
        var selectedValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &selectedValue)
        guard selectedResult == .success,
            let selectedValue,
            CFGetTypeID(selectedValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let axValue = unsafeBitCast(selectedValue, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    // * -- Встановлення діапазону виділення --
    private func setSelectedTextRange(_ range: CFRange, for element: AXUIElement) -> Bool {
        var mutableRange = range
        guard let value = AXValueCreate(.cfRange, &mutableRange) else { return false }
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    // * -- Копіювання виділення через pasteboard --
    private func copySelectedTextThroughPasteboard(timeout: TimeInterval = 0.5) -> String? {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        let clearChangeCount = pasteboard.changeCount

        guard sendKeyboardShortcut(keyCode: KeyCode.c, flags: .maskCommand) else {
            snapshot.restore(to: pasteboard)
            return nil
        }

        let copied = waitForCopiedString(after: clearChangeCount, timeout: timeout)
        snapshot.restore(to: pasteboard)
        return copied
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
        keyDown.post(tap: .cghidEventTap)
        keyUp.flags = flags
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    // * -- Очікування обробки клавіатурної команди --
    private func waitForKeyboardSideEffects(timeout: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(timeout))
    }

    // * -- Очікування оновлення pasteboard --
    private func waitForCopiedString(after changeCount: Int, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount > changeCount,
                let copied = pasteboard.string(forType: .string)
            {
                return copied
            }
            waitForKeyboardSideEffects(timeout: pollStep)
        }
        return nil
    }

    // * -- Заголовок активного вікна --
    private func frontmostWindowTitle(processIdentifier: pid_t?) -> String? {
        guard let processIdentifier else { return nil }

        // 1. CGWindowList — швидко і надійно для Chrome/Safari.
        let options = CGWindowListOption(
            arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        if let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? {
            for info in windowListInfo {
                guard let dict = info as? NSDictionary else { continue }
                let windowOwnerPID = dict[kCGWindowOwnerPID as String] as? pid_t
                if windowOwnerPID == processIdentifier {
                    let layer = dict[kCGWindowLayer as String] as? Int ?? 0
                    if layer == 0 {
                        if let name = dict[kCGWindowName as String] as? String, !name.isEmpty {
                            return name
                        }
                    }
                }
            }
        }

        // 2. Резервний варіант через Accessibility.
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)

        guard focusedWindowResult == .success,
            let focusedWindowValue,
            CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedWindow = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        return stringAttribute(kAXTitleAttribute as CFString, from: focusedWindow)
    }
}

// * -- Коди клавіш для симуляції клавіатурних шорткатів --
private enum KeyCode {
    static let a: CGKeyCode = 0
    static let c: CGKeyCode = 8
    static let v: CGKeyCode = 9
    static let w: CGKeyCode = 13
    static let returnKey: CGKeyCode = 36
    static let delete: CGKeyCode = 51
    static let escape: CGKeyCode = 53
    static let f2: CGKeyCode = 120
    static let leftArrow: CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
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

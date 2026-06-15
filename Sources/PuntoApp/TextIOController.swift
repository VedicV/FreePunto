import AppKit
import ApplicationServices

// * -- Текстова ціль команди --
struct TextTarget {
    let text: String
    let source: Source
    let trailingSpacesCount: Int
    fileprivate let accessibilitySelection: AccessibilitySelection?

    enum Source {
        case selectedText
        case previousWord
    }
}

private struct AccessibilitySelection {
    let element: AXUIElement
    let text: String
    let selectedRange: CFRange?
    let currentValue: String?
    let trailingSpacesCount: Int
}

private enum ReplacementMethod {
    case accessibility
    case pasteboard
}

private enum AccessibilityReplaceOutcome {
    case replacedVerified
    case replacedUnverified
    case failed
}

private enum AccessibilityVerificationState {
    case verified
    case unknown
    case failed
}

private enum TextInteractionProfile {
    case standard
    case vscode
    case browser
    case googleSheets
    case terminal
}

private struct TextInteractionContext {
    let profile: TextInteractionProfile
    let focusedElement: AXUIElement?
    let selectionCopyTimeout: TimeInterval
    let preferPasteboardSelectionRead: Bool
    let requiresEditableFocusedElementForSelectionRead: Bool
    let replacementOrder: [ReplacementMethod]
    let requiresVerifiedAccessibilityWrite: Bool
    let verifyPasteboardReplaceWhenPossible: Bool
    let deleteSelectionBeforePaste: Bool
    let prefersWordNavigationFallback: Bool
    let pasteReplaceTimeout: TimeInterval
}

private let axEditableAttributeName: CFString = "AXEditable" as CFString

// * -- Читання і заміна тексту в активному застосунку --
final class TextIOController {
    private let pasteboard = NSPasteboard.general
    private let commandTimeout: TimeInterval = 0.5
    private let pollStep: TimeInterval = 0.01

    private static let vscodeBundleIdentifiers: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.microsoft.VSCodeExploration",
        "com.vscodium",
    ]

    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "io.alacritty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
    ]

    private static let browserBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.microsoft.edgemac",
    ]

    private static let googleSheetsTitleHints = [
        "google sheets",
        "google таблицы",
        "google таблиці",
        "таблицы google",
        "таблиці google",
    ]

    // * -- Читання тексту для перетворення --
    func readTarget() -> TextTarget? {
        let hasAccessibility = Diagnostics.accessibilityTrusted(prompt: false)
        let context = resolveInteractionContext(hasAccessibility: hasAccessibility)
        let focusedElement = context.focusedElement
        let shouldReadSelection = shouldReadSelectionText(from: focusedElement, context: context)

        // 1. Для стандартних застосунків спочатку пробуємо поточне виділення через Accessibility.
        if shouldReadSelection,
            !context.preferPasteboardSelectionRead,
            let focused = focusedElement,
            let selection = readSelectedTextWithAccessibility(focused: focused)
        {
            return TextTarget(
                text: selection.text,
                source: .selectedText,
                trailingSpacesCount: 0,
                accessibilitySelection: selection
            )
        }

        // 2. Читаємо виділення через буфер обміну з адаптивним таймаутом.
        if shouldReadSelection,
            let copiedSelection = copySelectedTextThroughPasteboard(
                timeout: context.selectionCopyTimeout),
            !copiedSelection.isEmpty
        {
            let accessibilitySelection = focusedElement.flatMap {
                readSelectedTextWithAccessibility(focused: $0)
            }

            // Для редакторів із нестандартним Cmd+C (наприклад, VS Code копіює рядок
            // за відсутності виділення) довіряємо pasteboard тільки якщо AX підтвердив
            // наявність виділення або якщо профіль не потребує додаткової верифікації.
            if !context.preferPasteboardSelectionRead || accessibilitySelection != nil {
                return TextTarget(
                    text: copiedSelection,
                    source: .selectedText,
                    trailingSpacesCount: 0,
                    accessibilitySelection: accessibilitySelection
                )
            }
        }

        // 3. Для VS Code і web-редакторів після pasteboard додатково перевіряємо AX-виділення.
        if shouldReadSelection,
            context.preferPasteboardSelectionRead,
            let focused = focusedElement,
            let selection = readSelectedTextWithAccessibility(focused: focused)
        {
            return TextTarget(
                text: selection.text,
                source: .selectedText,
                trailingSpacesCount: 0,
                accessibilitySelection: selection
            )
        }

        // 4. Якщо виділення немає і доступний Accessibility, беремо слово перед курсором через Accessibility.
        if let focused = focusedElement,
            let selection = readPreviousWordWithAccessibility(focused: focused)
        {
            return TextTarget(
                text: selection.text,
                source: .previousWord,
                trailingSpacesCount: selection.trailingSpacesCount,
                accessibilitySelection: selection
            )
        }

        // 5. Якщо Accessibility недоступний або не повернув слово перед курсором, використовуємо клавіатурний fallback.
        if context.profile != .terminal,
            let fallbackResult = selectAndCopyPreviousWordThroughKeyboard(
                focusedElement: focusedElement,
                preferWordNavigation: context.prefersWordNavigationFallback,
                copyTimeout: context.selectionCopyTimeout
            )
        {
            return TextTarget(
                text: fallbackResult.word,
                source: .previousWord,
                trailingSpacesCount: fallbackResult.trailingSpacesCount,
                accessibilitySelection: nil
            )
        }

        return nil
    }

    // * -- Заміна поточного виділення --
    func replace(_ target: TextTarget, with replacement: String) -> Bool {
        let hasAccessibility = Diagnostics.accessibilityTrusted(prompt: false)
        let context = resolveInteractionContext(hasAccessibility: hasAccessibility)
        let verificationSelection = target.accessibilitySelection

        // Коли текст отримано через AX (слово перед курсором без візуального виділення),
        // спочатку пробуємо .accessibility, який викличе setSelectedTextRange,
        // потім .pasteboard. Навіть якщо AX-запис не вдасться, слово буде виділено для pasteboard.
        var effectiveOrder = context.replacementOrder
        if target.source == .previousWord, target.accessibilitySelection != nil {
            effectiveOrder = [.accessibility, .pasteboard]
        }

        var appliedMethod: ReplacementMethod?
        for method in effectiveOrder {
            let didReplace: Bool

            switch method {
            case .accessibility:
                guard let selection = target.accessibilitySelection else {
                    continue
                }

                let outcome = replaceWithAccessibility(
                    selection,
                    replacement: replacement,
                    trailingSpacesCount: target.trailingSpacesCount
                )

                switch outcome {
                case .replacedVerified:
                    didReplace = true
                case .replacedUnverified:
                    didReplace = !context.requiresVerifiedAccessibilityWrite
                case .failed:
                    didReplace = false
                }
            case .pasteboard:
                didReplace = replaceCurrentSelectionThroughPasteboard(
                    with: replacement,
                    settleTimeout: context.pasteReplaceTimeout,
                    deleteSelectionBeforePaste: context.deleteSelectionBeforePaste,
                    verificationSelection: verificationSelection,
                    verifyWhenPossible: context.verifyPasteboardReplaceWhenPossible
                )
            }

            if didReplace {
                appliedMethod = method
                break
            }
        }

        guard let appliedMethod else {
            return false
        }

        if appliedMethod == .pasteboard, target.trailingSpacesCount > 0 {
            for _ in 0..<target.trailingSpacesCount {
                _ = sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: [])
            }
            waitForKeyboardSideEffects(timeout: pollStep)
        }

        return true
    }

    // Пряма заміна через AX стабільніша для команд із меню: фокус міг тимчасово піти в меню.
    private func replaceWithAccessibility(
        _ selection: AccessibilitySelection, replacement: String, trailingSpacesCount: Int
    ) -> AccessibilityReplaceOutcome {
        if let selectedRange = selection.selectedRange {
            _ = setSelectedTextRange(selectedRange, for: selection.element)
        }

        let selectedTextResult = AXUIElementSetAttributeValue(
            selection.element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFString
        )
        guard selectedTextResult == .success else {
            return .failed
        }

        let verificationState = verifyAccessibilityReplacement(selection, replacement: replacement)
        guard verificationState != .failed else {
            return .failed
        }

        if trailingSpacesCount > 0, let selectedRange = selection.selectedRange {
            let newCaretLocation =
                selectedRange.location + (replacement as NSString).length + trailingSpacesCount
            _ = setSelectedTextRange(
                CFRange(location: newCaretLocation, length: 0), for: selection.element)
        }

        if verificationState == .verified {
            return .replacedVerified
        }

        return .replacedUnverified
    }

    private func verifyAccessibilityReplacement(
        _ selection: AccessibilitySelection,
        replacement: String
    ) -> AccessibilityVerificationState {
        guard let selectedRange = selection.selectedRange,
            selectedRange.location >= 0,
            selectedRange.length >= 0,
            let previousValue = selection.currentValue,
            let currentValue = stringAttribute(
                kAXValueAttribute as CFString, from: selection.element)
        else {
            return .unknown
        }

        let previousNSString = previousValue as NSString
        let replaceStart = selectedRange.location
        let replaceEnd = selectedRange.location + selectedRange.length

        guard replaceStart <= previousNSString.length,
            replaceEnd <= previousNSString.length
        else {
            return .unknown
        }

        let prefix = previousNSString.substring(to: replaceStart)
        let suffix = previousNSString.substring(from: replaceEnd)
        let expectedValue = prefix + replacement + suffix

        return currentValue == expectedValue ? .verified : .failed
    }

    // Fallback для редакторів, які не дозволяють змінювати значення через Accessibility.
    private func replaceCurrentSelectionThroughPasteboard(
        with replacement: String,
        settleTimeout: TimeInterval,
        deleteSelectionBeforePaste: Bool,
        verificationSelection: AccessibilitySelection?,
        verifyWhenPossible: Bool
    ) -> Bool {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()

        let didSetReplacement = pasteboard.setString(replacement, forType: .string)
        guard didSetReplacement else {
            snapshot.restore(to: pasteboard)
            return false
        }

        if deleteSelectionBeforePaste,
            !sendKeyboardShortcut(keyCode: KeyCode.delete, flags: [])
        {
            snapshot.restore(to: pasteboard)
            return false
        }

        if deleteSelectionBeforePaste {
            waitForKeyboardSideEffects(timeout: pollStep)
        }

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            snapshot.restore(to: pasteboard)
            return false
        }

        waitForKeyboardSideEffects(timeout: settleTimeout)

        if verifyWhenPossible,
            let verificationSelection,
            verifyAccessibilityReplacement(verificationSelection, replacement: replacement)
                == .failed
        {
            snapshot.restore(to: pasteboard)
            return false
        }

        snapshot.restore(to: pasteboard)
        return true
    }

    // Читаємо виділений текст із focused AX element.
    private func readSelectedTextWithAccessibility(focused: AXUIElement) -> AccessibilitySelection?
    {
        guard let selected = stringAttribute(kAXSelectedTextAttribute as CFString, from: focused),
            !selected.isEmpty
        else {
            return nil
        }

        return AccessibilitySelection(
            element: focused,
            text: selected,
            selectedRange: selectedTextRange(from: focused),
            currentValue: stringAttribute(kAXValueAttribute as CFString, from: focused),
            trailingSpacesCount: 0
        )
    }

    // Читаємо слово перед курсором через Accessibility, якщо виділення немає.
    private func readPreviousWordWithAccessibility(focused: AXUIElement) -> AccessibilitySelection?
    {
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

        // Пропускаємо хвостові пробіли.
        var endIndex = leftStringCut.endIndex
        while endIndex > leftStringCut.startIndex {
            let prevIndex = leftStringCut.index(before: endIndex)
            if leftStringCut[prevIndex].isWhitespace || leftStringCut[prevIndex].isNewline {
                endIndex = prevIndex
            } else {
                break
            }
        }

        let wordText = leftStringCut[..<endIndex]
        let wordStartIndex: Int
        let word: String
        if let lastWhitespaceRange = wordText.rangeOfCharacter(
            from: .whitespacesAndNewlines, options: .backwards)
        {
            wordStartIndex = leftStringCut.distance(
                from: leftStringCut.startIndex, to: lastWhitespaceRange.upperBound)
            word = String(wordText.suffix(from: lastWhitespaceRange.upperBound))
        } else {
            wordStartIndex = 0
            word = String(wordText)
        }

        let wordLength = (word as NSString).length
        guard wordLength > 0, wordLength <= 40 else {
            return nil
        }

        let trailingSpacesCount = leftStringCut.distance(from: endIndex, to: leftStringCut.endIndex)

        return AccessibilitySelection(
            element: focused,
            text: word,
            selectedRange: CFRange(location: wordStartIndex, length: wordLength),
            currentValue: value,
            trailingSpacesCount: trailingSpacesCount
        )
    }

    // Клавіатурний fallback для виділення слова до курсора через виділення до початку рядка.
    private func selectAndCopyPreviousWordThroughKeyboard(
        focusedElement: AXUIElement?,
        preferWordNavigation: Bool,
        copyTimeout: TimeInterval
    ) -> (
        word: String, trailingSpacesCount: Int
    )? {
        if let focused = focusedElement {
            if let role = stringAttribute(kAXRoleAttribute as CFString, from: focused) {
                let allowedRoles: Set<String> = ["AXTextArea", "AXTextField", "AXSearchField", "AXWebArea"]
                if !allowedRoles.contains(role) {
                    return nil
                }
            }
        }

        if preferWordNavigation,
            let directWordSelection = selectAndCopyPreviousWordWithWordNavigation(
                copyTimeout: copyTimeout)
        {
            return directWordSelection
        }

        return selectAndCopyPreviousWordByLineSelection(copyTimeout: copyTimeout)
    }

    // Пробуємо вибрати попереднє слово напряму: Option+Shift+Left.
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

    // Стратегія за замовчуванням: виділяємо до початку рядка і обчислюємо останнє слово.
    private func selectAndCopyPreviousWordByLineSelection(copyTimeout: TimeInterval) -> (
        word: String, trailingSpacesCount: Int
    )? {
        // 1. Виділяємо текст від курсора до початку рядка: Cmd+Shift+Left.
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

        // 3. Знімаємо виділення, повертаючи курсор у початкове положення: стрілка вправо.
        guard sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: []) else {
            return nil
        }
        waitForKeyboardSideEffects(timeout: pollStep)

        // 4. Знаходимо останнє слово: розділювачі тільки пробіли й нові рядки.
        let trimmedLine = lineText.trimmingCharacters(in: .newlines)

        // Пропускаємо хвостові пробіли.
        var endIndex = trimmedLine.endIndex
        while endIndex > trimmedLine.startIndex {
            let prevIndex = trimmedLine.index(before: endIndex)
            if trimmedLine[prevIndex].isWhitespace || trimmedLine[prevIndex].isNewline {
                endIndex = prevIndex
            } else {
                break
            }
        }

        let wordText = trimmedLine[..<endIndex]
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

        let trailingSpacesCount = trimmedLine.distance(from: endIndex, to: trimmedLine.endIndex)

        // 5. Рухаємо курсор ліворуч повз хвостові пробіли без Shift.
        for _ in 0..<trailingSpacesCount {
            guard sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: []) else {
                return nil
            }
        }
        if trailingSpacesCount > 0 {
            waitForKeyboardSideEffects(timeout: pollStep)
        }

        // 6. Виділяємо слово перед курсором: Shift+LeftArrow N разів.
        for _ in 0..<wordLength {
            guard sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: .maskShift) else {
                return nil
            }
        }
        waitForKeyboardSideEffects(timeout: pollStep)

        return (word: word, trailingSpacesCount: trailingSpacesCount)
    }

    private func resolveInteractionContext(hasAccessibility: Bool) -> TextInteractionContext {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let focusedElement = hasAccessibility ? focusedTextElement() : nil
        let windowTitle =
            hasAccessibility
            ? frontmostWindowTitle(processIdentifier: frontmostApplication?.processIdentifier)
            : nil

        let profile = interactionProfile(
            bundleIdentifier: frontmostApplication?.bundleIdentifier,
            windowTitle: windowTitle
        )

        switch profile {
        case .vscode:
            return TextInteractionContext(
                profile: profile,
                focusedElement: focusedElement,
                selectionCopyTimeout: 0.18,
                preferPasteboardSelectionRead: true,
                requiresEditableFocusedElementForSelectionRead: true,
                replacementOrder: [.pasteboard, .accessibility],
                requiresVerifiedAccessibilityWrite: true,
                verifyPasteboardReplaceWhenPossible: false,
                deleteSelectionBeforePaste: true,
                prefersWordNavigationFallback: true,
                pasteReplaceTimeout: 0.55
            )
        case .googleSheets:
            return TextInteractionContext(
                profile: profile,
                focusedElement: focusedElement,
                selectionCopyTimeout: 0.24,
                preferPasteboardSelectionRead: true,
                requiresEditableFocusedElementForSelectionRead: false,
                replacementOrder: [.pasteboard, .accessibility],
                requiresVerifiedAccessibilityWrite: true,
                verifyPasteboardReplaceWhenPossible: false,
                deleteSelectionBeforePaste: true,
                prefersWordNavigationFallback: true,
                pasteReplaceTimeout: 0.75
            )
        case .browser:
            return TextInteractionContext(
                profile: profile,
                focusedElement: focusedElement,
                selectionCopyTimeout: 0.18,
                preferPasteboardSelectionRead: true,
                requiresEditableFocusedElementForSelectionRead: false,
                replacementOrder: [.pasteboard, .accessibility],
                requiresVerifiedAccessibilityWrite: true,
                verifyPasteboardReplaceWhenPossible: false,
                deleteSelectionBeforePaste: true,
                prefersWordNavigationFallback: true,
                pasteReplaceTimeout: 0.65
            )
        case .terminal:
            return TextInteractionContext(
                profile: profile,
                focusedElement: focusedElement,
                selectionCopyTimeout: 0.18,
                preferPasteboardSelectionRead: true,
                requiresEditableFocusedElementForSelectionRead: false,
                replacementOrder: [.pasteboard],
                requiresVerifiedAccessibilityWrite: false,
                verifyPasteboardReplaceWhenPossible: false,
                deleteSelectionBeforePaste: false,
                prefersWordNavigationFallback: false,
                pasteReplaceTimeout: 0.55
            )
        case .standard:
            return TextInteractionContext(
                profile: profile,
                focusedElement: focusedElement,
                selectionCopyTimeout: 0.08,
                preferPasteboardSelectionRead: false,
                requiresEditableFocusedElementForSelectionRead: false,
                replacementOrder: [.accessibility, .pasteboard],
                requiresVerifiedAccessibilityWrite: false,
                verifyPasteboardReplaceWhenPossible: false,
                deleteSelectionBeforePaste: false,
                prefersWordNavigationFallback: false,
                pasteReplaceTimeout: commandTimeout
            )
        }
    }

    private func shouldReadSelectionText(
        from focusedElement: AXUIElement?,
        context: TextInteractionContext
    ) -> Bool {
        guard context.requiresEditableFocusedElementForSelectionRead else {
            return true
        }

        guard let focusedElement else {
            return true
        }

        guard let editable = boolAttribute(axEditableAttributeName, from: focusedElement)
        else {
            return true
        }

        return editable
    }

    private func interactionProfile(bundleIdentifier: String?, windowTitle: String?)
        -> TextInteractionProfile
    {
        guard let bundleIdentifier else {
            return .standard
        }

        if Self.terminalBundleIdentifiers.contains(bundleIdentifier) {
            return .terminal
        }

        if Self.vscodeBundleIdentifiers.contains(bundleIdentifier) {
            return .vscode
        }

        if Self.browserBundleIdentifiers.contains(bundleIdentifier) {
            if isGoogleSheetsWindow(windowTitle: windowTitle) {
                return .googleSheets
            }
            return .browser
        }

        return .standard
    }

    private func isGoogleSheetsWindow(windowTitle: String?) -> Bool {
        guard let loweredTitle = windowTitle?.lowercased() else {
            return false
        }

        return Self.googleSheetsTitleHints.contains(where: { loweredTitle.contains($0) })
    }

    private func frontmostWindowTitle(processIdentifier: pid_t?) -> String? {
        guard let processIdentifier else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        guard focusedWindowResult == .success,
            let focusedWindowValue,
            CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedWindow = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        return stringAttribute(kAXTitleAttribute as CFString, from: focusedWindow)
    }

    private func focusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusedResult == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return unsafeBitCast(focusedValue, to: AXUIElement.self)
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }

        return value as? String
    }

    private func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
            let value
        else {
            return nil
        }

        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return nil
        }

        let booleanValue = unsafeBitCast(value, to: CFBoolean.self)
        return CFBooleanGetValue(booleanValue)
    }

    private func selectedTextRange(from element: AXUIElement) -> CFRange? {
        var selectedValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedValue
        )

        guard selectedResult == .success,
            let selectedValue,
            CFGetTypeID(selectedValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = unsafeBitCast(selectedValue, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func setSelectedTextRange(_ range: CFRange, for element: AXUIElement) -> Bool {
        var mutableRange = range
        guard let value = AXValueCreate(.cfRange, &mutableRange) else {
            return false
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        ) == .success
    }

    // Копіюємо виділення, зберігаючи початковий pasteboard.
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

    // Надсилаємо системний key down/up.
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

    // Чекаємо, поки система обробить синтетичну клавіатурну команду.
    private func waitForKeyboardSideEffects(timeout: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(timeout))
    }

    // Очікуємо оновлення pasteboard після Cmd+C.
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
}

private enum KeyCode {
    static let c: CGKeyCode = 8
    static let v: CGKeyCode = 9
    static let delete: CGKeyCode = 51
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

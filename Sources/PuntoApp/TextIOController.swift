import AppKit
import ApplicationServices

// * -- Текстовая цель команды --
struct TextTarget {
    let text: String
    let source: Source
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
}

// * -- Чтение и замена текста в активном приложении --
final class TextIOController {
    private let pasteboard = NSPasteboard.general
    private let commandTimeout: TimeInterval = 0.5
    private let pollStep: TimeInterval = 0.01

    // * -- Чтение текста для преобразования --
    func readTarget() -> TextTarget? {
        // Сначала пробуем текущее выделение через Accessibility.
        if let selection = readSelectedTextWithAccessibility(), !selection.text.isEmpty {
            return TextTarget(
                text: selection.text,
                source: .selectedText,
                accessibilitySelection: selection
            )
        }

        // Если выделения нет, пробуем получить слово перед курсором через Accessibility.
        if let selection = readPreviousWordWithAccessibility() {
            return TextTarget(
                text: selection.text,
                source: .previousWord,
                accessibilitySelection: selection
            )
        }

        // Если Accessibility не вернул слово, пробуем клавиатурный fallback.
        if let word = selectAndCopyPreviousWordThroughKeyboard() {
            return TextTarget(
                text: word,
                source: .previousWord,
                accessibilitySelection: nil
            )
        }

        return nil
    }

    // * -- Замена текущего выделения --
    func replace(_ target: TextTarget, with replacement: String) -> Bool {
        if let selection = target.accessibilitySelection,
           replaceWithAccessibility(selection, replacement: replacement) {
            return true
        }

        return replaceCurrentSelectionThroughPasteboard(with: replacement)
    }

    // Прямая замена через AX стабильнее для команд из меню: фокус мог временно уйти в меню.
    private func replaceWithAccessibility(_ selection: AccessibilitySelection, replacement: String) -> Bool {
        if let selectedRange = selection.selectedRange {
            _ = setSelectedTextRange(selectedRange, for: selection.element)
        }

        let selectedTextResult = AXUIElementSetAttributeValue(
            selection.element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFString
        )
        if selectedTextResult == .success {
            return true
        }

        guard let selectedRange = selection.selectedRange,
              let currentValue = selection.currentValue,
              selectedRange.location >= 0,
              selectedRange.length >= 0
        else {
            return false
        }

        let original = currentValue as NSString
        guard selectedRange.location + selectedRange.length <= original.length else {
            return false
        }

        let newValue = original.replacingCharacters(
            in: NSRange(location: selectedRange.location, length: selectedRange.length),
            with: replacement
        )
        let valueResult = AXUIElementSetAttributeValue(
            selection.element,
            kAXValueAttribute as CFString,
            newValue as CFString
        )
        guard valueResult == .success else {
            return false
        }

        let caret = CFRange(location: selectedRange.location + (replacement as NSString).length, length: 0)
        _ = setSelectedTextRange(caret, for: selection.element)
        return true
    }

    // Fallback для редакторов, которые не позволяют менять значение через Accessibility.
    private func replaceCurrentSelectionThroughPasteboard(with replacement: String) -> Bool {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(replacement, forType: .string),
            sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand)
        else {
            snapshot.restore(to: pasteboard)
            return false
        }

        waitForKeyboardSideEffects(timeout: commandTimeout)
        snapshot.restore(to: pasteboard)
        return true
    }

    // Читаем выделенный текст из focused AX element.
    private func readSelectedTextWithAccessibility() -> AccessibilitySelection? {
        guard Diagnostics.accessibilityTrusted(prompt: false) else {
            return nil
        }

        guard let focused = focusedTextElement() else {
            return nil
        }

        guard let selected = stringAttribute(kAXSelectedTextAttribute as CFString, from: focused) else {
            return nil
        }

        return AccessibilitySelection(
            element: focused,
            text: selected,
            selectedRange: selectedTextRange(from: focused),
            currentValue: stringAttribute(kAXValueAttribute as CFString, from: focused)
        )
    }

    // Читаем слово перед курсором через Accessibility, если выделения нет.
    private func readPreviousWordWithAccessibility() -> AccessibilitySelection? {
        guard Diagnostics.accessibilityTrusted(prompt: false) else {
            return nil
        }

        guard let focused = focusedTextElement() else {
            return nil
        }

        guard let range = selectedTextRange(from: focused),
              range.length == 0,
              let value = stringAttribute(kAXValueAttribute as CFString, from: focused)
        else {
            return nil
        }

        let nsValue = value as NSString
        guard range.location > 0, range.location <= nsValue.length else {
            return nil
        }

        let leftText = nsValue.substring(to: range.location)
        
        // Находим слово перед курсором, используя только пробелы и переводы строк как разделители.
        let wordStartIndex: Int
        if let lastWhitespaceRange = leftText.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards) {
            wordStartIndex = leftText.distance(from: leftText.startIndex, to: lastWhitespaceRange.upperBound)
        } else {
            wordStartIndex = 0
        }

        let wordLength = range.location - wordStartIndex
        guard wordLength > 0, wordLength <= 40 else {
            return nil
        }

        let word = (leftText as NSString).substring(from: wordStartIndex)

        return AccessibilitySelection(
            element: focused,
            text: word,
            selectedRange: CFRange(location: wordStartIndex, length: wordLength),
            currentValue: value
        )
    }

    // Клавиатурный fallback для выделения слова до курсора (через выделение до начала строки).
    private func selectAndCopyPreviousWordThroughKeyboard() -> String? {
        // 1. Выделяем текст от курсора до начала строки: Cmd+Shift+Left
        guard sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: [.maskCommand, .maskShift]) else {
            return nil
        }
        waitForKeyboardSideEffects(timeout: pollStep)

        // 2. Копируем выделенный текст
        guard let lineText = copySelectedTextThroughPasteboard() else {
            // Восстанавливаем курсор на случай неудачи
            _ = sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: [])
            return nil
        }

        // 3. Снимаем выделение, возвращая курсор в исходное положение (стрелка вправо)
        guard sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: []) else {
            return nil
        }
        waitForKeyboardSideEffects(timeout: pollStep)

        // 4. Находим последнее слово (разделители — только пробелы и новые строки)
        let trimmedLine = lineText.trimmingCharacters(in: .newlines)
        let word: String
        if let lastWhitespaceRange = trimmedLine.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards) {
            let startIndex = trimmedLine.distance(from: trimmedLine.startIndex, to: lastWhitespaceRange.upperBound)
            word = String(trimmedLine.suffix(from: trimmedLine.index(trimmedLine.startIndex, offsetBy: startIndex)))
        } else {
            word = trimmedLine
        }

        let wordLength = (word as NSString).length
        // Защита от слишком длинных последовательностей без пробелов
        guard wordLength > 0, wordLength <= 40 else {
            return nil
        }

        // 5. Выделяем это слово: Shift+LeftArrow N раз
        for _ in 0..<wordLength {
            guard sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: .maskShift) else {
                return nil
            }
        }
        waitForKeyboardSideEffects(timeout: pollStep)

        return word
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

    // Копируем выделение, сохраняя исходный pasteboard.
    private func copySelectedTextThroughPasteboard() -> String? {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        let clearChangeCount = pasteboard.changeCount

        guard sendKeyboardShortcut(keyCode: KeyCode.c, flags: .maskCommand) else {
            snapshot.restore(to: pasteboard)
            return nil
        }

        let copied = waitForCopiedString(after: clearChangeCount, timeout: commandTimeout)
        snapshot.restore(to: pasteboard)
        return copied
    }



    // Отправляем системный key down/up.
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

    // Ждем, пока система обработает синтетическую клавиатурную команду.
    private func waitForKeyboardSideEffects(timeout: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(timeout))
    }

    // Ожидаем обновление pasteboard после Cmd+C.
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
    static let leftArrow: CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
}

// * -- Снимок pasteboard для восстановления после copy/paste --
private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    // Сохраняем все типы данных, а не только plain text.
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

import AppKit
import ApplicationServices

// * -- Текстовая цель команды --
struct TextTarget {
    let text: String
    let source: Source

    enum Source {
        case selectedText
        case previousWord
    }
}

// * -- Чтение и замена текста в активном приложении --
final class TextIOController {
    private let pasteboard = NSPasteboard.general

    // * -- Чтение текста для преобразования --
    func readTarget() -> TextTarget? {
        // Сначала пробуем текущее выделение через Accessibility.
        if let selected = readSelectedTextWithAccessibility(), !selected.isEmpty {
            return TextTarget(text: selected, source: .selectedText)
        }

        // Если выделения нет, выбираем предыдущее слово и копируем его.
        guard selectPreviousWord(),
              let word = copySelectedTextThroughPasteboard(),
              !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return TextTarget(text: word, source: .previousWord)
    }

    // * -- Замена текущего выделения --
    func replaceCurrentSelection(with replacement: String) -> Bool {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(replacement, forType: .string)
        sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand)
        Thread.sleep(forTimeInterval: 0.08)
        snapshot.restore(to: pasteboard)
        return true
    }

    // Читаем выделенный текст из focused AX element.
    private func readSelectedTextWithAccessibility() -> String? {
        guard Diagnostics.accessibilityTrusted(prompt: false) else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusedResult == .success,
              let focused = focusedValue else {
            return nil
        }

        var selectedValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(
            focused as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )

        guard selectedResult == .success else {
            return nil
        }

        return selectedValue as? String
    }

    // Копируем выделение, сохраняя исходный pasteboard.
    private func copySelectedTextThroughPasteboard() -> String? {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        sendKeyboardShortcut(keyCode: KeyCode.c, flags: .maskCommand)
        Thread.sleep(forTimeInterval: 0.08)
        let copied = pasteboard.string(forType: .string)
        snapshot.restore(to: pasteboard)
        return copied
    }

    // Выделяем слово слева от курсора.
    private func selectPreviousWord() -> Bool {
        sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: [.maskAlternate, .maskShift])
        Thread.sleep(forTimeInterval: 0.05)
        return true
    }

    // Отправляем системный key down/up.
    private func sendKeyboardShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)
    }
}

private enum KeyCode {
    static let c: CGKeyCode = 8
    static let v: CGKeyCode = 9
    static let leftArrow: CGKeyCode = 123
}

// * -- Снимок pasteboard для восстановления после copy/paste --
private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    // Сохраняем все типы данных, а не только plain text.
    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = pasteboard.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
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

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

// * -- Фактичний спосіб, яким текст був прочитаний та як його замінювати --
private enum ReadOrigin {
    case directAXSelection(AXUIElement)
    case directAXLastWord(AXUIElement, range: CFRange, wordLength: Int, trailingSpacesCount: Int)
    case copiedSelection
    case backspaceAXLastWord(wordLength: Int, trailingSpacesCount: Int)
    case standaloneTerminalAXLastWord(wordLength: Int, trailingSpacesCount: Int)
    case integratedTerminalAXLastWord(wordLength: Int, trailingSpacesCount: Int)
    case copiedBrowserGridLike
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
    // * -- NSPasteboard та AX вимагають головного потоку; цей хелпер гарантує безпеку. --
    @discardableResult
    private func syncMain<T>(_ block: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try block() }
        return try DispatchQueue.main.sync(execute: block)
    }

    // MARK: - Діагностичний трейс

    private func trace(_ message: @autoclosure () -> String) {
        let msg = message()
        rawLog("[TextIO] \(msg)")
    }

    // MARK: - Читання тексту

    // * -- Читання тексту для перетворення. Accessibility First -> Clipboard Fallback --
    func readTarget(bundleIdentifier: String?, hasAccessibility: Bool, focusedElement: AXUIElement?) -> TextTarget? {
        trace("readTarget entry: bundle=\(bundleIdentifier ?? "nil") hasAX=\(hasAccessibility)")

        let context = makeInteractionContext(
            bundleIdentifier: bundleIdentifier,
            focusedElement: focusedElement)

        trace("readTarget context: appKind=\(context.appKind) role=\(context.role ?? "nil") editable=\(context.isEditable) focusedEl=\(context.focusedElement != nil ? "yes" : "no")")

        // 1. Термінали мають специфічний буфер введення
        if context.appKind == .standaloneTerminal {
            return readTerminalLastWord(
                focusedElement: context.focusedElement,
                origin: { len, spaces in .standaloneTerminalAXLastWord(wordLength: len, trailingSpacesCount: spaces) })
        }
        if context.appKind == .integratedTerminal {
            return readTerminalLastWord(
                focusedElement: context.focusedElement,
                origin: { len, spaces in .integratedTerminalAXLastWord(wordLength: len, trailingSpacesCount: spaces) })
        }

        // 2. ACCESSIBILITY FIRST:
        // Якщо focusedElement доступний, спочатку читаємо напряму без зміни буфера обміну!
        if let focusedElement = context.focusedElement {
            if let directTarget = readDirectAXTarget(focusedElement: focusedElement) {
                trace("readTarget: взято через прямий доступ AX")
                return directTarget
            }
        }

        // 3. CLIPBOARD FALLBACK (коли AX недоступний або не дав результату):
        // Спробуємо скопіювати виділений текст через Cmd+C:
        if let copiedText = copyTextThroughPasteboard(timeout: 0.35), !copiedText.isEmpty {
            if context.appKind == .codeEditor && TextScanner.looksLikeAutomaticLineCopy(copiedText) {
                // У VS Code / Antigravity натискання Cmd+C без виділення копіює весь рядок
                if let wordResult = TextScanner.lastWord(in: copiedText) {
                    trace("readTarget: codeEditor line-copy fallback -> '\(wordResult.word)'")
                    return TextTarget(
                        text: wordResult.word,
                        trailingSpacesCount: 0,
                        wordLength: wordResult.word.count,
                        origin: .backspaceAXLastWord(wordLength: wordResult.word.count, trailingSpacesCount: 0)
                    )
                }
            } else {
                trace("readTarget: взято виділений текст через Cmd+C (довжина=\(copiedText.count))")
                return TextTarget(
                    text: copiedText,
                    trailingSpacesCount: 0,
                    wordLength: copiedText.count,
                    origin: .copiedSelection
                )
            }
        }

        // 4. Якщо нічого не виділено і є AX елемент — спробуємо витягнути останнє слово через AXValue
        if let focusedElement = context.focusedElement {
            if let target = readAXLastWordFallback(focusedElement: focusedElement, tracePrefix: "axLastWord") {
                return target
            }
        }

        // 5. Останнє слово перед курсором без виділення через Shift + Option + LeftArrow:
        // Універсальний спосіб, що працює у всіх браузерах (Chrome, Firefox, Safari), VS Code, Sheets, Slack тощо!
        if let target = selectAndCopyWordBeforeCursor() {
            return target
        }

        return nil
    }

    // * -- Виділення та копіювання слова перед курсором до найближчого ПРОБІЛУ --
    // * -- Крапки, коми, дефіси та інші символи вважаються частиною слова (ключа/ідентифікатора) --
    private func selectAndCopyWordBeforeCursor() -> TextTarget? {
        // 1. Спочатку пробуємо виділити префікс рядка ліворуч від курсора через Shift + Cmd + LeftArrow
        trace("selectAndCopyWordBeforeCursor: надсилаємо Shift+Cmd+LeftArrow")
        if sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: [.maskShift, .maskCommand]) {
            waitForKeyboardSideEffects(timeout: 0.06)
            if let copied = copyTextThroughPasteboard(timeout: 0.35), !copied.isEmpty {
                // Повертаємо курсор на місце стрілкою праворуч
                _ = sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: [])
                waitForKeyboardSideEffects(timeout: 0.05)

                if let wordResult = TextScanner.lastWord(in: copied) {
                    trace("selectAndCopyWordBeforeCursor: знайдено слово до пробілу '\(wordResult.word)' trailing=\(wordResult.trailingSpacesCount)")
                    return TextTarget(
                        text: wordResult.word,
                        trailingSpacesCount: wordResult.trailingSpacesCount,
                        wordLength: wordResult.word.count,
                        origin: .backspaceAXLastWord(wordLength: wordResult.word.count, trailingSpacesCount: wordResult.trailingSpacesCount)
                    )
                }
            } else {
                _ = sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: [])
                waitForKeyboardSideEffects(timeout: 0.05)
            }
        }

        // 2. Fallback через Shift + Option + LeftArrow (виділення слова ліворуч від курсора)
        trace("selectAndCopyWordBeforeCursor: fallback Shift+Option+LeftArrow")
        guard sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: [.maskShift, .maskAlternate]) else {
            return nil
        }
        waitForKeyboardSideEffects(timeout: 0.06)

        if let copied = copyTextThroughPasteboard(timeout: 0.35), !copied.isEmpty {
            let trimmed = copied.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                trace("selectAndCopyWordBeforeCursor: успішно виділено і скопійовано '\(copied)'")
                return TextTarget(
                    text: copied,
                    trailingSpacesCount: 0,
                    wordLength: copied.count,
                    origin: .copiedSelection
                )
            }
        }

        trace("selectAndCopyWordBeforeCursor: скасовуємо виділення стрілкою RightArrow")
        _ = sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: [])
        return nil
    }

    // * -- Пряме читання тексту через Accessibility API без взаємодії з Pasteboard --
    private func readDirectAXTarget(focusedElement: AXUIElement) -> TextTarget? {
        // (a) Перевірка чи є реальне виділення через kAXSelectedTextAttribute
        if let selectedText = stringAttribute(kAXSelectedTextAttribute as CFString, from: focusedElement),
           !selectedText.isEmpty {
            trace("directAX: знайдено виділення AXSelectedText (довжина=\(selectedText.count))")
            return TextTarget(
                text: selectedText,
                trailingSpacesCount: 0,
                wordLength: selectedText.count,
                origin: .directAXSelection(focusedElement)
            )
        }

        // (b) Перевірка позиції курсора через kAXSelectedTextRangeAttribute
        var rangeVal: CFTypeRef?
        let rangeResult = syncMain {
            AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeVal)
        }
        if rangeResult == .success, let rangeVal, CFGetTypeID(rangeVal) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rangeVal as! AXValue, .cfRange, &range) {
                if range.length > 0 {
                    // Якщо range вказує на виділення, але AXSelectedText був порожній: читаємо з AXValue
                    if let fullText = stringAttribute(kAXValueAttribute as CFString, from: focusedElement) {
                        let utf16 = fullText.utf16
                        let startOffset = max(0, min(utf16.count, range.location))
                        let endOffset = max(0, min(utf16.count, range.location + range.length))
                        let start = String.Index(utf16Offset: startOffset, in: fullText)
                        let end = String.Index(utf16Offset: endOffset, in: fullText)
                        let sel = String(fullText[start..<end])
                        if !sel.isEmpty {
                            trace("directAX: витягнуто виділення за range (довжина=\(sel.count))")
                            return TextTarget(
                                text: sel,
                                trailingSpacesCount: 0,
                                wordLength: sel.count,
                                origin: .directAXSelection(focusedElement)
                            )
                        }
                    }
                } else if range.location > 0 {
                    // Курсор стоїть у тексті: читаємо текст до курсора і беремо останнє слово
                    if let fullText = stringAttribute(kAXValueAttribute as CFString, from: focusedElement) {
                        let utf16 = fullText.utf16
                        let cursorOffset = max(0, min(utf16.count, range.location))
                        let cursorIndex = String.Index(utf16Offset: cursorOffset, in: fullText)
                        let textBeforeCursor = fullText[..<cursorIndex]
                        if let scanned = TextScanner.scanLastWord(in: textBeforeCursor) {
                            let wordStartLoc = fullText.utf16.distance(from: fullText.startIndex, to: scanned.wordRange.lowerBound)
                            let wordLengthUtf16 = fullText.utf16.distance(from: scanned.wordRange.lowerBound, to: scanned.fullRange.upperBound)
                            let wordRange = CFRange(location: wordStartLoc, length: wordLengthUtf16)
                            trace("directAX: знайдено слово перед курсором '\(scanned.word)' trailing=\(scanned.trailingSpacesCount) range=\(wordRange.location),\(wordRange.length)")
                            return TextTarget(
                                text: scanned.word,
                                trailingSpacesCount: scanned.trailingSpacesCount,
                                wordLength: scanned.word.count,
                                origin: .directAXLastWord(focusedElement, range: wordRange, wordLength: scanned.word.count, trailingSpacesCount: scanned.trailingSpacesCount)
                            )
                        }
                    }
                }
            }
        }

        return nil
    }


    private func readTerminalLastWord(
        focusedElement: AXUIElement?,
        origin: (Int, Int) -> ReadOrigin
    ) -> TextTarget? {
        // 1. Спочатку перевіряємо виділений текст (AXSelectedText або Cmd+C)
        if let focusedElement,
           let selText = stringAttribute(kAXSelectedTextAttribute as CFString, from: focusedElement),
           !selText.isEmpty {
            trace("terminal: знайдено AXSelectedText '\(selText)'")
            return TextTarget(
                text: selText,
                trailingSpacesCount: 0,
                wordLength: selText.count,
                origin: origin(selText.count, 0)
            )
        }

        if let copied = copyTextThroughPasteboard(timeout: 0.15), !copied.isEmpty, !TextScanner.looksLikeAutomaticLineCopy(copied) {
            trace("terminal: скопійовано виділення через Cmd+C '\(copied)'")
            return TextTarget(
                text: copied,
                trailingSpacesCount: 0,
                wordLength: copied.count,
                origin: origin(copied.count, 0)
            )
        }

        // 2. Якщо виділення немає, шукаємо останнє слово в AXValue елемента або батька
        guard let focusedElement else { return nil }

        var value: String? = nil
        for _ in 0..<3 {
            value = stringAttribute(kAXValueAttribute as CFString, from: focusedElement)
            if let val = value, !val.isEmpty { break }
            waitForKeyboardSideEffects(timeout: 0.05)
        }

        // Якщо елемент не має AXValue (як xterm textarea у VS Code/Antigravity), перевіряємо батьківський елемент
        if value == nil || value!.isEmpty {
            var parentRef: CFTypeRef?
            if syncMain({ AXUIElementCopyAttributeValue(focusedElement, kAXParentAttribute as CFString, &parentRef) }) == .success,
               let parent = parentRef as! AXUIElement? {
                value = stringAttribute(kAXValueAttribute as CFString, from: parent)
                if value == nil || value!.isEmpty {
                    value = stringAttribute(kAXDescriptionAttribute as CFString, from: parent)
                }
            }
        }

        guard let value, !value.isEmpty else {
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
        return TextTarget(
            text: wordResult.word,
            trailingSpacesCount: wordResult.trailingSpacesCount,
            wordLength: wordResult.word.count,
            origin: origin(wordResult.word.count, wordResult.trailingSpacesCount)
        )
    }

    private func readAXLastWordFallback(
        focusedElement: AXUIElement?,
        tracePrefix: String
    ) -> TextTarget? {
        guard let focusedElement else { return nil }

        var value: String? = nil
        for _ in 0..<3 {
            value = stringAttribute(kAXValueAttribute as CFString, from: focusedElement)
            if value != nil { break }
            waitForKeyboardSideEffects(timeout: 0.05)
        }

        guard let value else {
            trace("\(tracePrefix): AXValue == nil після 3 спроб")
            return nil
        }

        // Беремо останній непорожній рядок, щоб уникнути кінцевих \n у value
        let lines = value.components(separatedBy: .newlines)
        guard
            let currentLine = lines.last(where: {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }),
            let wordResult = TextScanner.lastWord(in: currentLine)
        else {
            trace("\(tracePrefix): lastWord не знайдено")
            return nil
        }

        trace("\(tracePrefix): AXValue слово='\(wordResult.word)' trailing=\(wordResult.trailingSpacesCount)")
        return TextTarget(
            text: wordResult.word,
            trailingSpacesCount: wordResult.trailingSpacesCount,
            wordLength: wordResult.word.count,
            origin: .backspaceAXLastWord(wordLength: wordResult.word.count, trailingSpacesCount: wordResult.trailingSpacesCount)
        )
    }

    // MARK: - Заміна тексту

    // * -- Заміна поточної цілі за фактичним origin читання --
    func replace(_ target: TextTarget, with replacement: String) -> Bool {
        trace("replace: origin=\(target.origin) wordLen=\(target.wordLength)")

        switch target.origin {
        case .directAXSelection(let element):
            // Спочатку пробуємо прямий запис через AX
            var setSuccess = false
            syncMain {
                let res = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFTypeRef)
                if res == .success {
                    // Перевіряємо, чи текст дійсно змінився (Qt у Telegram/Viber повертає success, але не змінює текст!)
                    if let current = stringAttribute(kAXSelectedTextAttribute as CFString, from: element) {
                        setSuccess = (current == replacement || current.isEmpty)
                    } else {
                        setSuccess = true
                    }
                }
            }
            if setSuccess {
                trace("replace: прямий AXSelectedText запис УСПІШНИЙ (0 мс, без буфера)")
                return true
            }
            trace("replace: прямий AX запис не змінив текст -> швидкий Cmd+V")
            return pasteReplacement(replacement, settleTimeout: 0.45)

        case .directAXLastWord(let element, var range, let wordLength, let trailingSpacesCount):
            // Спочатку пробуємо виділити діапазон слова і записати заміну через AX
            var setSuccess = false
            var rangeSelected = false
            let replacementWithSpaces = replacement + String(repeating: " ", count: trailingSpacesCount)

            syncMain {
                if let axRange = AXValueCreate(.cfRange, &range),
                   AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange) == .success {
                    rangeSelected = true
                    let res = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacementWithSpaces as CFTypeRef)
                    if res == .success {
                        if let current = stringAttribute(kAXSelectedTextAttribute as CFString, from: element) {
                            setSuccess = (current == replacementWithSpaces)
                        }
                    }
                    if setSuccess {
                        // Знімаємо виділення, переміщуючи курсор у кінець вставленого слова
                        var endRange = CFRange(location: range.location + (replacementWithSpaces as NSString).length, length: 0)
                        if let endVal = AXValueCreate(.cfRange, &endRange) {
                            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, endVal)
                        }
                    }
                }
            }
            if setSuccess {
                trace("replace: прямий AXLastWord запис УСПІШНИЙ")
                return true
            }

            if rangeSelected {
                // Діапазон слова вже виділено в UI (Qt у Telegram/Viber або Chromium у Chrome/VS Code)!
                // Cmd+V миттєво замінить виділене слово новим текстом!
                trace("replace: слово виділено в UI через AXRange, але AXSet не змінив текст -> заміна виділення через Cmd+V")
                return pasteReplacement(replacementWithSpaces, settleTimeout: 0.45)
            }

            trace("replace: directAXLastWord set не підтримується -> видалення Backspace + Cmd+V")
            return replaceLastWordByBackspace(wordLength: wordLength, trailingSpacesCount: trailingSpacesCount, with: replacement, settleTimeout: 0.45)

        case .copiedSelection:
            return pasteReplacement(replacement, settleTimeout: 0.45)

        case .backspaceAXLastWord(let wordLength, let trailingSpacesCount):
            return replaceLastWordByBackspace(wordLength: wordLength, trailingSpacesCount: trailingSpacesCount, with: replacement, settleTimeout: 0.45)

        case .integratedTerminalAXLastWord(let wordLength, let trailingSpacesCount):
            return replaceLastWordByBackspace(wordLength: wordLength, trailingSpacesCount: trailingSpacesCount, with: replacement, settleTimeout: 0.45)

        case .standaloneTerminalAXLastWord(let wordLength, let trailingSpacesCount):
            return replaceStandaloneTerminalLastWord(wordLength: wordLength, trailingSpacesCount: trailingSpacesCount, with: replacement)

        case .copiedBrowserGridLike:
            return replaceBrowserGridLike(with: replacement)
        }
    }

    private func replaceLastWordByBackspace(
        wordLength: Int,
        trailingSpacesCount: Int,
        with replacement: String,
        settleTimeout: TimeInterval
    ) -> Bool {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }

        let replacementWithSpaces = replacement + String(repeating: " ", count: trailingSpacesCount)
        guard setTransientPasteboardString(replacementWithSpaces) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        let totalDeleteLength = wordLength + trailingSpacesCount
        for i in 0..<totalDeleteLength {
            guard sendKeyboardShortcut(keyCode: KeyCode.delete, flags: []) else {
                trace("replaceLastWord: Backspace \(i) не вдався")
                syncMain { snapshot.restore(to: pasteboard) }
                return false
            }
            waitForKeyboardSideEffects(timeout: pollStep)
        }
        waitForKeyboardSideEffects(timeout: 0.03)

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }
        waitForKeyboardSideEffects(timeout: settleTimeout)

        syncMain { snapshot.restore(to: pasteboard) }
        return true
    }

    private func replaceStandaloneTerminalLastWord(
        wordLength: Int,
        trailingSpacesCount: Int,
        with replacement: String
    ) -> Bool {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }

        let replacementWithSpaces = replacement + String(repeating: " ", count: trailingSpacesCount)
        guard setTransientPasteboardString(replacementWithSpaces) else {
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
        waitForKeyboardSideEffects(timeout: 0.1)

        trace("standaloneTerminal: Ctrl+W + Cmd+V")
        syncMain { snapshot.restore(to: pasteboard) }
        return true
    }

    private func replaceBrowserGridLike(with replacement: String) -> Bool {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }

        guard setTransientPasteboardString(replacement) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        // F2 завжди — перехід у режим редагування комірки (Google Sheets)
        guard sendKeyboardShortcut(keyCode: KeyCode.f2, flags: []) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        if focusedTextElement() != nil {
            guard waitForGridEditMode(previousRole: nil, timeout: 0.6) else {
                trace("browserGrid: F2 не дав edit-mode сигналу")
                syncMain { snapshot.restore(to: pasteboard) }
                return false
            }
        } else {
            trace("browserGrid: AX недоступний, F2 наосліп, очікування")
            waitForKeyboardSideEffects(timeout: 0.2)
        }

        guard sendKeyboardShortcut(keyCode: KeyCode.a, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.05)

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.15)

        guard sendKeyboardShortcut(keyCode: KeyCode.a, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.05)

        trace("browserGrid: F2 → Cmd+A → Cmd+V → Cmd+A виконано")
        syncMain { snapshot.restore(to: pasteboard) }
        return true
    }

    private func pasteReplacement(_ replacement: String, settleTimeout: TimeInterval) -> Bool {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }

        guard setTransientPasteboardString(replacement) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        waitForKeyboardSideEffects(timeout: max(settleTimeout, 0.45))

        syncMain { snapshot.restore(to: pasteboard) }
        return true
    }

    // * -- Встановлення тексту з маркерами TransientType для уникнення запису в історію clipboard-менеджерів --
    private func setTransientPasteboardString(_ string: String) -> Bool {
        syncMain {
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setString(string, forType: .string)
            item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            let ok = pasteboard.writeObjects([item])
            // Прямий запис рядка для максимальної сумісності з Qt (Telegram, Viber) та старішими застосунками
            pasteboard.setString(string, forType: .string)
            return ok
        }
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

        if AppEnvironmentClassifier.isIntegratedTerminal(
            role: stringAttribute(kAXRoleAttribute as CFString, from: focusedElement),
            title: stringAttribute(kAXTitleAttribute as CFString, from: focusedElement),
            description: stringAttribute(kAXDescriptionAttribute as CFString, from: focusedElement),
            identifier: stringAttribute(kAXIdentifierAttribute as CFString, from: focusedElement),
            value: stringAttribute(kAXValueAttribute as CFString, from: focusedElement)) {
            return true
        }

        // Перевіряємо батьківський елемент (container xterm у VS Code / Antigravity)
        var parentRef: CFTypeRef?
        if syncMain({ AXUIElementCopyAttributeValue(focusedElement, kAXParentAttribute as CFString, &parentRef) }) == .success,
           let parent = parentRef as! AXUIElement? {
            if AppEnvironmentClassifier.isIntegratedTerminal(
                role: stringAttribute(kAXRoleAttribute as CFString, from: parent),
                title: stringAttribute(kAXTitleAttribute as CFString, from: parent),
                description: stringAttribute(kAXDescriptionAttribute as CFString, from: parent),
                identifier: stringAttribute(kAXIdentifierAttribute as CFString, from: parent),
                value: stringAttribute(kAXValueAttribute as CFString, from: parent)) {
                return true
            }
        }

        return false
    }

    private func waitForGridEditMode(previousRole: String?, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = focusedTextElement() {
                let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
                if isEditableContext(element, role: role) {
                    return true
                }
                if role != previousRole {
                    return true
                }
                if stringAttribute(kAXSelectedTextAttribute as CFString, from: element) != nil {
                    return true
                }
            }
            waitForKeyboardSideEffects(timeout: pollStep)
        } while Date() < deadline
        return false
    }

    private func isEditableContext(_ element: AXUIElement, role: String?) -> Bool {
        if let editable = boolAttribute(axEditableAttributeName, from: element), editable {
            return true
        }

        guard let role else { return false }
        return role == (kAXTextAreaRole as String)
            || role == (kAXTextFieldRole as String)
            || role == "AXWebArea"
    }

    // MARK: - Pasteboard Copy Helper

    private func copyTextThroughPasteboard(timeout: TimeInterval = 0.45) -> String? {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }
        syncMain { pasteboard.clearContents() }
        let clearChangeCount = syncMain { pasteboard.changeCount }

        guard sendKeyboardShortcut(keyCode: KeyCode.c, flags: .maskCommand) else {
            trace("copyText: помилка надсилання Cmd+C")
            syncMain { snapshot.restore(to: pasteboard) }
            return nil
        }

        let copied = waitForCopiedString(after: clearChangeCount, timeout: timeout)
        syncMain { snapshot.restore(to: pasteboard) }

        if let copied, !copied.isEmpty {
            trace("copyText: отримано текст довжиною \(copied.count)")
            return copied
        }

        return nil
    }

    // MARK: - AX Helpers

    private func focusedTextElement() -> AXUIElement? {
        syncMain {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)

            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

            var focusedValue: CFTypeRef?
            var result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)

            if result != .success {
                var windowValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
                   let win = windowValue as! AXUIElement? {
                    result = AXUIElementCopyAttributeValue(win, kAXFocusedUIElementAttribute as CFString, &focusedValue)
                }
            }

            if result != .success {
                let sys = AXUIElementCreateSystemWide()
                result = AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focusedValue)
            }

            guard result == .success, let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
                return nil
            }
            return (focusedValue as! AXUIElement)
        }
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        syncMain {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            guard result == .success, let value else {
                return nil
            }
            return value as? String
        }
    }

    private func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        syncMain {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            guard result == .success, let value else {
                return nil
            }
            guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
            let booleanValue = unsafeBitCast(value, to: CFBoolean.self)
            return CFBooleanGetValue(booleanValue)
        }
    }

    // MARK: - Keyboard Events & Shortcuts

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

    private func waitForKeyboardSideEffects(timeout: TimeInterval) {
        Thread.sleep(forTimeInterval: timeout)
    }

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
    static let leftArrow: CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
}

// * -- Знімок pasteboard для відновлення після copy/paste --
private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

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

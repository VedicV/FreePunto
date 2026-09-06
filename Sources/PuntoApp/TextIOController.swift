import AppKit
import ApplicationServices
import PuntoCore

// * -- Текстова ціль команди --
struct TextTarget {
    let text: String
    let trailingSpacesCount: Int
    let wordLength: Int
    let bundleIdentifier: String?
    fileprivate let origin: ReadOrigin
}

// * -- Фактичний спосіб, яким текст був прочитаний та як його замінювати --
private enum ReadOrigin {
    case directAXSelection(AXUIElement)
    case directAXWord(element: AXUIElement, range: CFRange, wordLength: Int, trailingSpacesCount: Int)
    case copiedSelection(element: AXUIElement?)
    case backspaceAXLastWord(element: AXUIElement?, wordLength: Int, trailingSpacesCount: Int)
    case standaloneTerminalAXLastWord(wordLength: Int, trailingSpacesCount: Int)
    case integratedTerminalAXLastWord(element: AXUIElement?, wordLength: Int, trailingSpacesCount: Int)
    case copiedBrowserGridLike(element: AXUIElement?)
}

private typealias AppKind = AppEnvironmentClassifier.AppKind
private typealias ReadStrategy = AppEnvironmentClassifier.ReadStrategy

// * -- Контекст активного застосунку і focused Accessibility element --
private struct InteractionContext {
    let appKind: AppKind
    let focusedElement: AXUIElement?
    let role: String?
    let isEditable: Bool
}

private let axEditableAttributeName: CFString = "AXEditable" as CFString

// * -- Ідентифікатори браузерів --
private let browserBundleIdentifiers = AppEnvironmentClassifier.browserBundleIdentifiers

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

    // * -- Читання тексту для перетворення. Строга маршрутизація відповідно до типу контексту --
    func readTarget(bundleIdentifier: String?, hasAccessibility: Bool, focusedElement: AXUIElement?) -> TextTarget? {
        trace("readTarget entry: bundle=\(bundleIdentifier ?? "nil") hasAX=\(hasAccessibility)")

        // 0. Без Accessibility повертаємо nil. Жодних синтетичних клавіш.
        guard hasAccessibility else {
            trace("readTarget: no accessibility -> nil")
            return nil
        }

        let context = makeInteractionContext(
            bundleIdentifier: bundleIdentifier,
            focusedElement: focusedElement)

        let isGrid = isConfirmedBrowserGridContext(context.focusedElement)
        let strategy = AppEnvironmentClassifier.determineReadStrategy(
            appKind: context.appKind,
            hasAccessibility: hasAccessibility,
            isEditable: context.isEditable,
            isConfirmedGrid: isGrid
        )

        trace("readTarget context: appKind=\(context.appKind) role=\(context.role ?? "nil") editable=\(context.isEditable) isGrid=\(isGrid) strategy=\(strategy)")

        switch strategy {
        case .none:
            trace("readTarget: strategy is none -> nil")
            return nil

        case .terminalActiveLineAXValue:
            let originBuilder: (Int, Int) -> ReadOrigin = { len, spaces in
                if context.appKind == .standaloneTerminal {
                    return .standaloneTerminalAXLastWord(wordLength: len, trailingSpacesCount: spaces)
                } else {
                    return .integratedTerminalAXLastWord(element: context.focusedElement, wordLength: len, trailingSpacesCount: spaces)
                }
            }
            return readTerminalLastWord(focusedElement: context.focusedElement, bundleIdentifier: bundleIdentifier, origin: originBuilder)

        case .browserEditableCmdCFirst:
            trace("readTarget: browser editable strategy")
            let isFirefox = (bundleIdentifier == "org.mozilla.firefox")

            // 1. browserEditableCmdCFirst повинен буквально починатися з Cmd+C для копіювання виділення
            if let copiedText = copyTextThroughPasteboard(timeout: 0.35), !copiedText.isEmpty {
                trace("readTarget: browser editable взято виділення через Cmd+C (довжина=\(copiedText.count))")
                return TextTarget(
                    text: copiedText,
                    trailingSpacesCount: 0,
                    wordLength: copiedText.count,
                    bundleIdentifier: bundleIdentifier,
                    origin: .copiedSelection(element: context.focusedElement)
                )
            }

            // 2. Якщо виділення немає:
            if isFirefox {
                // Для org.mozilla.firefox не використовувати AXSelectedTextRange ні для читання попереднього слова,
                // ні для виділення/заміни. Використовувати тільки підтверджений AXValue fallback
                // або існуючий keyboard fallback в активному полі. Якщо жоден шлях не доведений — nil.
                if context.isEditable, let focusedElement = context.focusedElement {
                    if let target = readAXLastWordFallback(focusedElement: focusedElement, tracePrefix: "firefoxAX", bundleIdentifier: bundleIdentifier) {
                        return target
                    }
                }
                if context.isEditable {
                    if let target = selectAndCopyWordBeforeCursor(bundleIdentifier: bundleIdentifier) {
                        return target
                    }
                }
                trace("readTarget: firefox без виділення і без підтвердженого фоллбеку -> nil")
                return nil
            } else {
                // Для інших браузерів (Chrome, Safari):
                if let focusedElement = context.focusedElement {
                    if let directTarget = readDirectAXTarget(focusedElement: focusedElement, isEditable: context.isEditable, bundleIdentifier: bundleIdentifier) {
                        return directTarget
                    }
                    if let target = readAXLastWordFallback(focusedElement: focusedElement, tracePrefix: "browserAX", bundleIdentifier: bundleIdentifier) {
                        return target
                    }
                }
                if context.isEditable {
                    if let target = selectAndCopyWordBeforeCursor(bundleIdentifier: bundleIdentifier) {
                        return target
                    }
                }
                return nil
            }

        case .browserConfirmedGrid:
            trace("readTarget: browser confirmed grid context")
            if let copiedText = copyTextThroughPasteboard(timeout: 0.45), !copiedText.isEmpty {
                trace("readTarget: взято browser grid через Cmd+C -> copiedBrowserGridLike (len=\(copiedText.count))")
                return TextTarget(
                    text: copiedText,
                    trailingSpacesCount: 0,
                    wordLength: copiedText.count,
                    bundleIdentifier: bundleIdentifier,
                    origin: .copiedBrowserGridLike(element: context.focusedElement)
                )
            }
            return nil

        case .codeEditorDirectAXFirst:
            trace("readTarget: code editor strategy")
            if let focusedElement = context.focusedElement {
                if let directTarget = readDirectAXTarget(focusedElement: focusedElement, isEditable: context.isEditable, bundleIdentifier: bundleIdentifier) {
                    trace("readTarget: codeEditor взято через прямий доступ AX")
                    return directTarget
                }
            }
            if let copiedText = copyTextThroughPasteboard(timeout: 0.45), !copiedText.isEmpty {
                if TextScanner.looksLikeAutomaticLineCopy(copiedText) {
                    if let wordResult = TextScanner.lastWord(in: copiedText) {
                        trace("readTarget: codeEditor line-copy fallback -> len=\(wordResult.word.count)")
                        return TextTarget(
                            text: wordResult.word,
                            trailingSpacesCount: 0,
                            wordLength: wordResult.word.count,
                            bundleIdentifier: bundleIdentifier,
                            origin: .backspaceAXLastWord(element: context.focusedElement, wordLength: wordResult.word.count, trailingSpacesCount: 0)
                        )
                    }
                } else {
                    trace("readTarget: codeEditor взято виділений текст через Cmd+C (довжина=\(copiedText.count))")
                    return TextTarget(
                        text: copiedText,
                        trailingSpacesCount: 0,
                        wordLength: copiedText.count,
                        bundleIdentifier: bundleIdentifier,
                        origin: .copiedSelection(element: context.focusedElement)
                    )
                }
            }
            if context.isEditable {
                if let focusedElement = context.focusedElement {
                    if let target = readAXLastWordFallback(focusedElement: focusedElement, tracePrefix: "codeEditorAX", bundleIdentifier: bundleIdentifier) {
                        return target
                    }
                }
                if let target = selectAndCopyWordBeforeCursor(bundleIdentifier: bundleIdentifier) {
                    return target
                }
            }
            return nil

        case .otherApp:
            trace("readTarget: other app strategy")
            if let focusedElement = context.focusedElement {
                if let directTarget = readDirectAXTarget(focusedElement: focusedElement, isEditable: context.isEditable, bundleIdentifier: bundleIdentifier) {
                    trace("readTarget: other взято через прямий доступ AX")
                    return directTarget
                }
            }
            if let copiedText = copyTextThroughPasteboard(timeout: 0.45), !copiedText.isEmpty {
                trace("readTarget: other взято виділений текст через Cmd+C (довжина=\(copiedText.count))")
                return TextTarget(
                    text: copiedText,
                    trailingSpacesCount: 0,
                    wordLength: copiedText.count,
                    bundleIdentifier: bundleIdentifier,
                    origin: .copiedSelection(element: context.focusedElement)
                )
            }
            if context.isEditable {
                if let focusedElement = context.focusedElement {
                    if let target = readAXLastWordFallback(focusedElement: focusedElement, tracePrefix: "otherAX", bundleIdentifier: bundleIdentifier) {
                        return target
                    }
                }
                if let target = selectAndCopyWordBeforeCursor(bundleIdentifier: bundleIdentifier) {
                    return target
                }
            }
            trace("readTarget: other non-editable with no selection -> nil")
            return nil
        }
    }

    // * -- Виділення та копіювання слова перед курсором до найближчого ПРОБІЛУ --
    // * -- Крапки, коми, дефіси та інші символи вважаються частиною слова (ключа/ідентифікатора) --
    private func selectAndCopyWordBeforeCursor(bundleIdentifier: String? = nil) -> TextTarget? {
        // 1. Спочатку пробуємо виділити префікс рядка ліворуч від курсора через Shift + Cmd + LeftArrow
        trace("selectAndCopyWordBeforeCursor: надсилаємо Shift+Cmd+LeftArrow")
        if sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: [.maskShift, .maskCommand]) {
            waitForKeyboardSideEffects(timeout: 0.06)
            if let copied = copyTextThroughPasteboard(timeout: 0.45), !copied.isEmpty {
                // Повертаємо курсор на місце стрілкою праворуч
                _ = sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: [])
                waitForKeyboardSideEffects(timeout: 0.05)

                if let wordResult = TextScanner.lastWord(in: copied) {
                    trace("selectAndCopyWordBeforeCursor: знайдено слово до пробілу len=\(wordResult.word.count) trailing=\(wordResult.trailingSpacesCount)")
                    return TextTarget(
                        text: wordResult.word,
                        trailingSpacesCount: wordResult.trailingSpacesCount,
                        wordLength: wordResult.word.count,
                        bundleIdentifier: bundleIdentifier,
                        origin: .backspaceAXLastWord(element: nil, wordLength: wordResult.word.count, trailingSpacesCount: wordResult.trailingSpacesCount)
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

        if let copied = copyTextThroughPasteboard(timeout: 0.45), !copied.isEmpty {
            // Повертаємо курсор на місце стрілкою праворуч
            _ = sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: [])
            waitForKeyboardSideEffects(timeout: 0.05)

            if let wordResult = TextScanner.lastWord(in: copied) {
                trace("selectAndCopyWordBeforeCursor: fallback знайдено слово len=\(wordResult.word.count) trailing=\(wordResult.trailingSpacesCount)")
                return TextTarget(
                    text: wordResult.word,
                    trailingSpacesCount: wordResult.trailingSpacesCount,
                    wordLength: wordResult.word.count,
                    bundleIdentifier: bundleIdentifier,
                    origin: .backspaceAXLastWord(element: nil, wordLength: wordResult.word.count, trailingSpacesCount: wordResult.trailingSpacesCount)
                )
            }
        }

        trace("selectAndCopyWordBeforeCursor: скасовуємо виділення стрілкою RightArrow")
        _ = sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: [])
        return nil
    }

    // * -- Пряме читання тексту через Accessibility API без взаємодії з Pasteboard --
    private func readDirectAXTarget(focusedElement: AXUIElement, isEditable: Bool, bundleIdentifier: String? = nil) -> TextTarget? {
        // Для org.mozilla.firefox не використовувати AXSelectedTextRange
        guard AppEnvironmentClassifier.supportsAXSelectedTextRange(bundleIdentifier: bundleIdentifier) else {
            trace("directAX: bundleIdentifier \(bundleIdentifier ?? "nil") не підтримує AXSelectedTextRange -> nil")
            return nil
        }

        // (a) Перевірка чи є реальне виділення через kAXSelectedTextAttribute
        // Реальне виділення завжди має найвищий пріоритет над курсором
        if let selectedText = stringAttribute(kAXSelectedTextAttribute as CFString, from: focusedElement),
           !selectedText.isEmpty {
            trace("directAX: знайдено виділення AXSelectedText (довжина=\(selectedText.count))")
            return TextTarget(
                text: selectedText,
                trailingSpacesCount: 0,
                wordLength: selectedText.count,
                bundleIdentifier: bundleIdentifier,
                origin: .directAXSelection(focusedElement)
            )
        }

        // (b) Тільки якщо реального виділення немає, аналізуємо AXSelectedTextRange та AXValue
        var rangeVal: CFTypeRef?
        let rangeResult = syncMain {
            AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeVal)
        }
        if rangeResult == .success, let rangeVal, CFGetTypeID(rangeVal) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rangeVal as! AXValue, .cfRange, &range) {
                if range.length > 0 {
                    // Якщо range вказує на виділення, але AXSelectedText був порожній: читаємо з AXValue за range
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
                                bundleIdentifier: bundleIdentifier,
                                origin: .directAXSelection(focusedElement)
                            )
                        }
                    }
                } else if range.location > 0 && isEditable {
                    // range.length == 0 -> ТІЛЬКИ якщо контекст редагований:
                    // читаємо текст до курсора і беремо останнє слово.
                    // Устарілий range з length == 0 НЕ знищує виділення, оскільки крок (a) вже перевірив AXSelectedText!
                    if let fullText = stringAttribute(kAXValueAttribute as CFString, from: focusedElement) {
                        let utf16 = fullText.utf16
                        let cursorOffset = max(0, min(utf16.count, range.location))
                        let cursorIndex = String.Index(utf16Offset: cursorOffset, in: fullText)

                        let textBeforeCursor = fullText[..<cursorIndex]
                        if let scanned = TextScanner.scanLastWord(in: textBeforeCursor) {
                            trace("directAX: знайдено слово перед курсором len=\(scanned.word.count) trailing=\(scanned.trailingSpacesCount)")
                            let startUtf16 = fullText.utf16.distance(from: fullText.utf16.startIndex, to: scanned.fullRange.lowerBound.samePosition(in: fullText.utf16) ?? fullText.utf16.startIndex)
                            let lenUtf16 = fullText.utf16.distance(from: scanned.fullRange.lowerBound.samePosition(in: fullText.utf16) ?? fullText.utf16.startIndex, to: scanned.fullRange.upperBound.samePosition(in: fullText.utf16) ?? fullText.utf16.endIndex)
                            let wordRange = CFRange(location: startUtf16, length: lenUtf16)
                            return TextTarget(
                                text: scanned.word,
                                trailingSpacesCount: scanned.trailingSpacesCount,
                                wordLength: scanned.word.count,
                                bundleIdentifier: bundleIdentifier,
                                origin: .directAXWord(element: focusedElement, range: wordRange, wordLength: scanned.word.count, trailingSpacesCount: scanned.trailingSpacesCount)
                            )
                        }
                    }
                }
            }
        }

        return nil
    }

    // * -- Перевірка, чи є елемент або його батько підтвердженим контекстом таблиці/сітки в браузері --
    private func isConfirmedBrowserGridContext(_ element: AXUIElement?) -> Bool {
        guard let element else { return false }
        let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element)
        let desc = stringAttribute(kAXRoleDescriptionAttribute as CFString, from: element)
        let ident = stringAttribute(kAXIdentifierAttribute as CFString, from: element)

        var parentRole: String? = nil
        var parentDesc: String? = nil
        var parentRef: CFTypeRef?
        if syncMain({ AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) }) == .success,
           let parent = parentRef as! AXUIElement? {
            parentRole = stringAttribute(kAXRoleAttribute as CFString, from: parent)
            parentDesc = stringAttribute(kAXRoleDescriptionAttribute as CFString, from: parent)
        }

        return AppEnvironmentClassifier.isConfirmedGridContext(
            role: role,
            subrole: subrole,
            roleDescription: desc,
            identifier: ident,
            parentRole: parentRole,
            parentDescription: parentDesc
        )
    }


    private func readTerminalLastWord(
        focusedElement: AXUIElement?,
        bundleIdentifier: String?,
        origin: (Int, Int) -> ReadOrigin
    ) -> TextTarget? {
        // У терміналах довільне виділення мишкою/Cmd+C зазвичай виділяє read-only вивід (output)
        // у скролі термінала. Спроба замінити його через Ctrl+W / Backspace стирає команду в активному промпті!
        // Тому в терміналах ми працюємо ТІЛЬКИ з останнім словом активного рядка вводу через AXValue.
        guard let focusedElement else { return nil }

        // Діагностичний трейс усіх підтримуваних атрибутів елемента терміналу
        var attrNamesRef: CFArray?
        if syncMain({ AXUIElementCopyAttributeNames(focusedElement, &attrNamesRef) }) == .success,
           let names = attrNamesRef as? [String] {
            trace("terminal element supported attributes: \(names)")
            for name in names {
                if let val = stringAttribute(name as CFString, from: focusedElement), !val.isEmpty {
                    let preview = val.count > 60 ? String(val.prefix(60)) + "..." : val
                    trace("  attribute \(name) = '\(preview)'")
                }
            }
        }

        var value: String? = nil
        for _ in 0..<3 {
            value = stringAttribute(kAXValueAttribute as CFString, from: focusedElement)
            if let val = value, !val.isEmpty, !val.contains("Screen Reader Accessibility") { break }
            waitForKeyboardSideEffects(timeout: 0.05)
        }

        // Читати тільки AXValue підтвердженого terminal prompt.
        // Не використовувати Cmd+C fallback і не брати довільний перший AXValue з дерева нащадків.
        // Якщо не можна довести, що це активна строка prompt, безпечно відмовитися.
        guard let promptWord = AppEnvironmentClassifier.terminalPromptLastWord(from: value) else {
            trace("terminal: AXValue не містить валідного активного рядка промпту -> nil")
            return nil
        }

        trace("terminal: валідне слово з промпту: '\(promptWord)'")
        return TextTarget(
            text: promptWord,
            trailingSpacesCount: 0,
            wordLength: promptWord.count,
            bundleIdentifier: bundleIdentifier,
            origin: origin(promptWord.count, 0)
        )
    }

    private func readAXLastWordFallback(
        focusedElement: AXUIElement?,
        tracePrefix: String,
        bundleIdentifier: String? = nil
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

        trace("\(tracePrefix): AXValue len=\(wordResult.word.count) trailing=\(wordResult.trailingSpacesCount)")
        return TextTarget(
            text: wordResult.word,
            trailingSpacesCount: wordResult.trailingSpacesCount,
            wordLength: wordResult.word.count,
            bundleIdentifier: bundleIdentifier,
            origin: .backspaceAXLastWord(element: focusedElement, wordLength: wordResult.word.count, trailingSpacesCount: wordResult.trailingSpacesCount)
        )
    }

    // MARK: - Заміна тексту

    // * -- Заміна поточної цілі за фактичним origin читання --
    func replace(_ target: TextTarget, with replacement: String) -> ReplaceOutcome {
        trace("replace: origin=\(target.origin) wordLen=\(target.wordLength)")

        switch target.origin {
        case .directAXSelection(let element):
            let isFirefox = (target.bundleIdentifier == "org.mozilla.firefox")
            if !isFirefox {
                // Спочатку пробуємо прямий запис через AX (якщо це не Firefox content)
                var setSuccess = false
                syncMain {
                    let res = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFTypeRef)
                    if res == .success {
                        // Перевіряємо, чи текст дійсно змінився (Qt у Telegram/Viber повертає success, але не змінює текст!)
                        if let current = stringAttribute(kAXSelectedTextAttribute as CFString, from: element) {
                            if current == replacement {
                                setSuccess = true
                            } else if current.isEmpty {
                                if let val = stringAttribute(kAXValueAttribute as CFString, from: element), val.contains(replacement) {
                                    setSuccess = true
                                }
                            }
                        } else if let val = stringAttribute(kAXValueAttribute as CFString, from: element), val.contains(replacement) {
                            setSuccess = true
                        }
                    }
                }
                if setSuccess {
                    trace("replace: прямий AXSelectedText запис УСПІШНИЙ (0 мс, без буфера)")
                    return .successVerified
                }
            }
            trace("replace: прямий AX запис не підтримується/не змінив текст -> перевірений Cmd+V")
            return pasteReplacement(replacement, settleTimeout: 0.45, targetElement: element, bundleIdentifier: target.bundleIdentifier)

        case .directAXWord(let element, let wordRange, let wordLength, let trailingSpacesCount):
            let isFirefox = (target.bundleIdentifier == "org.mozilla.firefox")
            let bundleId = target.bundleIdentifier ?? syncMain { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
            let isTerminal = AppEnvironmentClassifier.isStandaloneTerminal(bundleIdentifier: bundleId) || isIntegratedTerminal(element)

            // Якщо це термінал, який потрапив сюди через прямий AX фоллбек,
            // замінюємо його через Backspace ровно wordLength символів, потім Cmd+V (без Ctrl+W)
            if isTerminal {
                trace("directAXWord: виявлено термінал -> заміна через replaceIntegratedTerminalLastWord")
                return replaceIntegratedTerminalLastWord(element: element, wordLength: wordLength, with: replacement)
            }

            // Для Firefox не виконуємо direct AX write/range write для content field
            if isFirefox {
                trace("directAXWord: Firefox -> заміна через Backspace + Cmd+V без direct AX write")
                return replaceLastWordByBackspace(element: element, wordLength: wordLength, trailingSpacesCount: trailingSpacesCount, with: replacement, settleTimeout: 0.45, bundleIdentifier: target.bundleIdentifier)
            }

            let replacementWithSpaces = replacement + String(repeating: " ", count: trailingSpacesCount)

            // 1. Пробуємо прямий AX запис ТІЛЬКИ якщо kAXSelectedTextAttribute є дійсно settable (AppKit застосунки)
            var isSettable: DarwinBoolean = false
            let canSetDirect = syncMain {
                AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &isSettable) == .success && isSettable.boolValue
            }

            if canSetDirect {
                var targetRange = wordRange
                if let axRange = AXValueCreate(.cfRange, &targetRange) {
                    let setRangeRes = syncMain {
                        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
                    }
                    if setRangeRes == .success {
                        let setRes = syncMain {
                            AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacementWithSpaces as CFTypeRef)
                        }
                        if setRes == .success {
                            if let current = stringAttribute(kAXSelectedTextAttribute as CFString, from: element),
                               current == replacementWithSpaces {
                                // Переміщуємо курсор у кінець вставленого слова
                                var endRange = CFRange(location: wordRange.location + (replacementWithSpaces as NSString).length, length: 0)
                                if let endVal = AXValueCreate(.cfRange, &endRange) {
                                    _ = syncMain { AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, endVal) }
                                }
                                trace("directAXWord: прямий AXSelectedText запис УСПІШНИЙ (0 мс)")
                                return .successVerified
                            }
                        }
                    }
                }
            }

            // 2. Пробуємо прямий запис у kAXValueAttribute, якщо воно settable (форми, пошукові поля)
            var isValSettable: DarwinBoolean = false
            let canSetVal = syncMain {
                AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isValSettable) == .success && isValSettable.boolValue
            }

            if canSetVal, let currentVal = stringAttribute(kAXValueAttribute as CFString, from: element), currentVal.count <= 2000 {
                let utf16 = currentVal.utf16
                if wordRange.location >= 0,
                   wordRange.location + wordRange.length <= utf16.count {
                    let start = String.Index(utf16Offset: wordRange.location, in: currentVal)
                    let end = String.Index(utf16Offset: wordRange.location + wordRange.length, in: currentVal)
                    var newText = currentVal
                    newText.replaceSubrange(start..<end, with: replacementWithSpaces)
                    let setValRes = syncMain {
                        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newText as CFTypeRef)
                    }
                    if setValRes == .success {
                        // Перевіряємо, чи нове значення застосувалося
                        if let updated = stringAttribute(kAXValueAttribute as CFString, from: element),
                           updated == newText {
                            var endRange = CFRange(location: wordRange.location + (replacementWithSpaces as NSString).length, length: 0)
                            if let endVal = AXValueCreate(.cfRange, &endRange) {
                                _ = syncMain { AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, endVal) }
                            }
                            trace("directAXWord: прямий kAXValueAttribute запис УСПІШНИЙ (0 мс, без буфера)")
                            return .successVerified
                        }
                    }
                }
            }

            // 3. Якщо kAXSelectedTextRangeAttribute є settable (Chromium, Electron, webviews):
            var isRangeSettable: DarwinBoolean = false
            let canSetRange = syncMain {
                AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &isRangeSettable) == .success && isRangeSettable.boolValue
            }

            if canSetRange {
                var targetRange = wordRange
                if let axRange = AXValueCreate(.cfRange, &targetRange) {
                    let setRangeRes = syncMain {
                        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
                    }
                    if setRangeRes == .success {
                        waitForKeyboardSideEffects(timeout: 0.02)
                        // Перевіряємо, чи застосунок дійсно встановив виділення на цільовому слові
                        let currentlySelected = stringAttribute(kAXSelectedTextAttribute as CFString, from: element)
                        let isSelectionVerified = currentlySelected != nil && !currentlySelected!.isEmpty
                        if isSelectionVerified {
                            trace("directAXWord: виділено слово через AXSelectedTextRange підтверджено ('\(currentlySelected!)'), вставляємо Cmd+V")
                            return pasteReplacement(replacementWithSpaces, settleTimeout: 0.45, targetElement: element, bundleIdentifier: target.bundleIdentifier)
                        } else {
                            trace("directAXWord: AXSelectedTextRange не встановив виділення в елементі -> відновлюємо курсор у кінець слова перед Backspace")
                            var endCaretRange = CFRange(location: wordRange.location + wordRange.length, length: 0)
                            if let endVal = AXValueCreate(.cfRange, &endCaretRange) {
                                _ = syncMain { AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, endVal) }
                            }
                        }
                    }
                }
            }

            // 4. Якщо виділення недоступне або не підтвердилося: надійне покрокове видалення Backspace і вставка Cmd+V
            trace("directAXWord: заміна через Backspace + Cmd+V (wordLen=\(wordLength), trailing=\(trailingSpacesCount))")
            return replaceLastWordByBackspace(element: element, wordLength: wordLength, trailingSpacesCount: trailingSpacesCount, with: replacement, settleTimeout: 0.45, bundleIdentifier: target.bundleIdentifier)

        case .copiedSelection(let element):
            return pasteReplacement(replacement, settleTimeout: 0.45, targetElement: element, bundleIdentifier: target.bundleIdentifier)

        case .backspaceAXLastWord(let element, let wordLength, let trailingSpacesCount):
            return replaceLastWordByBackspace(element: element, wordLength: wordLength, trailingSpacesCount: trailingSpacesCount, with: replacement, settleTimeout: 0.45, bundleIdentifier: target.bundleIdentifier)

        case .integratedTerminalAXLastWord(let element, let wordLength, _):
            return replaceIntegratedTerminalLastWord(element: element, wordLength: wordLength, with: replacement)

        case .standaloneTerminalAXLastWord(let wordLength, let trailingSpacesCount):
            return replaceStandaloneTerminalLastWord(element: nil, wordLength: wordLength, trailingSpacesCount: trailingSpacesCount, with: replacement)

        case .copiedBrowserGridLike(let element):
            return replaceBrowserGridLike(element: element, with: replacement) ? .successVerified : .failed
        }
    }

    private func replaceLastWordByBackspace(
        element: AXUIElement?,
        wordLength: Int,
        trailingSpacesCount: Int,
        with replacement: String,
        settleTimeout: TimeInterval,
        bundleIdentifier: String? = nil
    ) -> ReplaceOutcome {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }

        let replacementWithSpaces = replacement + String(repeating: " ", count: trailingSpacesCount)
        guard setTransientPasteboardString(replacementWithSpaces) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return .failed
        }

        let initialValue = element.flatMap { stringAttribute(kAXValueAttribute as CFString, from: $0) }
        let initialSelected = element.flatMap { stringAttribute(kAXSelectedTextAttribute as CFString, from: $0) }

        let totalDeleteLength = wordLength + trailingSpacesCount
        trace("replaceLastWordByBackspace: видаляємо \(totalDeleteLength) символів (слово=\(wordLength), пробіли=\(trailingSpacesCount))")
        for i in 0..<totalDeleteLength {
            guard sendKeyboardShortcut(keyCode: KeyCode.delete, flags: []) else {
                trace("replaceLastWord: Backspace \(i) не вдався")
                syncMain { snapshot.restore(to: pasteboard) }
                return .failed
            }
            waitForKeyboardSideEffects(timeout: 0.025)
        }
        waitForKeyboardSideEffects(timeout: 0.06)

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return .failed
        }
        waitForKeyboardSideEffects(timeout: 0.08)

        let isFirefox = (bundleIdentifier == "org.mozilla.firefox")
        let isVSCode = syncMain {
            AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: bundleIdentifier ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        }
        let outcome = verifyElementChanged(
            element: element,
            initialValue: initialValue,
            initialSelectedText: initialSelected,
            expectedSubstring: replacement,
            timeout: 0.45,
            isVSCode: isVSCode,
            isFirefox: isFirefox
        )

        // Даємо безпечний час перед відновленням буфера обміну,
        // щоб браузери (Firefox) встигли прочитати NSPasteboard
        waitForKeyboardSideEffects(timeout: isFirefox ? 0.15 : 0.06)
        syncMain { snapshot.restore(to: pasteboard) }
        return outcome
    }

    private func replaceIntegratedTerminalLastWord(
        element: AXUIElement?,
        wordLength: Int,
        with replacement: String
    ) -> ReplaceOutcome {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }

        guard setTransientPasteboardString(replacement) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return .failed
        }

        // Для integrated terminal замінювати рівно wordLength символів через Backspace, потім Cmd+V.
        // Не використовувати Ctrl+W.
        trace("replaceIntegratedTerminalLastWord: видаляємо Backspace \(wordLength) разів (без Ctrl+W)")
        for i in 0..<wordLength {
            guard sendKeyboardShortcut(keyCode: KeyCode.delete, flags: []) else {
                trace("replaceIntegratedTerminalLastWord: Backspace \(i) не вдався")
                syncMain { snapshot.restore(to: pasteboard) }
                return .failed
            }
            waitForKeyboardSideEffects(timeout: 0.02)
        }
        waitForKeyboardSideEffects(timeout: 0.04)

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            trace("replaceIntegratedTerminalLastWord: Cmd+V не вдався")
            syncMain { snapshot.restore(to: pasteboard) }
            return .failed
        }
        waitForKeyboardSideEffects(timeout: 0.08)

        syncMain { snapshot.restore(to: pasteboard) }

        // У терміналах xterm canvas буфер не оновлює AXValue синхронно.
        // Заміна успішно доставлена синтетичними подіями клавіш -> deliveredUnconfirmedAX
        trace("replaceIntegratedTerminalLastWord: доставлено -> deliveredUnconfirmedAX")
        return .deliveredUnconfirmedAX
    }

    private func replaceStandaloneTerminalLastWord(
        element: AXUIElement? = nil,
        wordLength: Int,
        trailingSpacesCount: Int,
        with replacement: String
    ) -> ReplaceOutcome {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }

        // У терміналах (Terminal.app, iTerm2, xterm) ніколи не додаємо штучні кінцеві пробіли від колонок термінала
        let replacementWithSpaces = replacement
        guard setTransientPasteboardString(replacementWithSpaces) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return .failed
        }

        guard sendKeyboardShortcut(keyCode: KeyCode.w, flags: .maskControl) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return .failed
        }
        waitForKeyboardSideEffects(timeout: 0.05)

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return .failed
        }
        waitForKeyboardSideEffects(timeout: 0.08)

        trace("standaloneTerminal: Ctrl+W + Cmd+V доставлено -> deliveredUnconfirmedAX")
        syncMain { snapshot.restore(to: pasteboard) }
        return .deliveredUnconfirmedAX
    }

    private struct ElementStateSnapshot {
        let role: String?
        let roleDescription: String?
        let identifier: String?
        let isEditable: Bool
        let selectedText: String?
    }

    private func captureElementState(_ element: AXUIElement) -> ElementStateSnapshot {
        let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
        let roleDesc = stringAttribute(kAXRoleDescriptionAttribute as CFString, from: element)
        let ident = stringAttribute(kAXIdentifierAttribute as CFString, from: element)
        let editable = isEditableContext(element, role: role)
        let sel = stringAttribute(kAXSelectedTextAttribute as CFString, from: element)
        return ElementStateSnapshot(
            role: role,
            roleDescription: roleDesc,
            identifier: ident,
            isEditable: editable,
            selectedText: sel
        )
    }

    private func replaceBrowserGridLike(element: AXUIElement?, with replacement: String) -> Bool {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }

        guard setTransientPasteboardString(replacement) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        // F2 допустимий ТІЛЬКИ як частина підтвердженого write-flow.
        // Вимагається підтверджений initialElement:
        guard let initialElement = element ?? focusedTextElement() else {
            trace("browserGrid: initialElement == nil -> неможливо довести перехід у cell editor, скасовуємо")
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        let initialSnapshot = captureElementState(initialElement)
        let initialValue = stringAttribute(kAXValueAttribute as CFString, from: initialElement)

        // F2 для переходу у режим редагування комірки
        guard sendKeyboardShortcut(keyCode: KeyCode.f2, flags: []) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        // Вимагається доказане змінення стану на editable cell editor:
        guard waitForGridEditMode(before: initialSnapshot, timeout: 0.6) else {
            trace("browserGrid: F2 не підтвердив перехід у режим редагування комірки -> повертаємо false")
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        // Не виконуємо Cmd+A/Cmd+V наосліп — тепер стан гарантовано editable editor
        guard sendKeyboardShortcut(keyCode: KeyCode.a, flags: .maskCommand) else {
            trace("browserGrid: помилка надсилання Cmd+A")
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.05)

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            trace("browserGrid: помилка надсилання Cmd+V")
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }
        waitForKeyboardSideEffects(timeout: 0.45)

        // Повторний Cmd+A залишає нове значення виділеним для подальших циклічних перемикань
        _ = sendKeyboardShortcut(keyCode: KeyCode.a, flags: .maskCommand)
        waitForKeyboardSideEffects(timeout: 0.05)

        // Після вставки перевіряємо результат, а не просто повертаємо true:
        let verified = verifyGridReplacement(initialValue: initialValue, replacement: replacement, timeout: 0.45)
        guard verified else {
            trace("browserGrid: перевірка результату вставки не підтвердила зміну -> false")
            syncMain { snapshot.restore(to: pasteboard) }
            return false
        }

        trace("browserGrid: F2 → Cmd+A → Cmd+V → verified успішно")
        syncMain { snapshot.restore(to: pasteboard) }
        return true
    }

    private func verifyGridReplacement(initialValue: String?, replacement: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let currentElement = focusedTextElement() {
                if let val = stringAttribute(kAXValueAttribute as CFString, from: currentElement) {
                    if val == replacement || val.contains(replacement) {
                        return true
                    }
                    if let initial = initialValue, val != initial {
                        return true
                    }
                }
                if let sel = stringAttribute(kAXSelectedTextAttribute as CFString, from: currentElement) {
                    if sel == replacement || sel.contains(replacement) {
                        return true
                    }
                }
            }
            waitForKeyboardSideEffects(timeout: pollStep)
        } while Date() < deadline
        return false
    }

    private func pasteReplacement(
        _ replacement: String,
        settleTimeout: TimeInterval,
        targetElement: AXUIElement?,
        bundleIdentifier: String? = nil
    ) -> ReplaceOutcome {
        let snapshot = syncMain { PasteboardSnapshot.capture(from: pasteboard) }

        guard setTransientPasteboardString(replacement) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return .failed
        }

        let initialValue = targetElement.flatMap { stringAttribute(kAXValueAttribute as CFString, from: $0) }
        let initialSelected = targetElement.flatMap { stringAttribute(kAXSelectedTextAttribute as CFString, from: $0) }

        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand) else {
            syncMain { snapshot.restore(to: pasteboard) }
            return .failed
        }

        let isFirefox = (bundleIdentifier == "org.mozilla.firefox")
        let isVSCode = syncMain {
            AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: bundleIdentifier ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        }
        let outcome = verifyElementChanged(
            element: targetElement,
            initialValue: initialValue,
            initialSelectedText: initialSelected,
            expectedSubstring: replacement,
            timeout: 0.45,
            isVSCode: isVSCode,
            isFirefox: isFirefox
        )

        // Даємо безпечний час перед відновленням буфера обміну,
        // щоб браузери (Firefox) встигли прочитати NSPasteboard
        waitForKeyboardSideEffects(timeout: isFirefox ? 0.15 : 0.06)
        syncMain { snapshot.restore(to: pasteboard) }
        return outcome
    }

    private func verifyElementChanged(
        element: AXUIElement?,
        initialValue: String?,
        initialSelectedText: String?,
        expectedSubstring: String,
        timeout: TimeInterval,
        isVSCode: Bool = false,
        isFirefox: Bool = false
    ) -> ReplaceOutcome {
        guard let element else {
            // Якщо елемент відсутній (наприклад, non-AX застосунок або клавіатурний fallback)
            return isFirefox ? .deliveredUnconfirmedAX : .successVerified
        }

        let deadline = Date().addingTimeInterval(timeout)
        var lastCurrentVal: String? = nil
        var lastCurrentSel: String? = nil
        repeat {
            let currentValue = stringAttribute(kAXValueAttribute as CFString, from: element)
            let currentSelected = stringAttribute(kAXSelectedTextAttribute as CFString, from: element)
            lastCurrentVal = currentValue
            lastCurrentSel = currentSelected

            // 1. Якщо значення змінилося і містить очікуваний фрагмент (але не збігається з початковим)
            if let current = currentValue {
                if current != initialValue && current.contains(expectedSubstring) {
                    return .successVerified
                }
            }

            // 2. Якщо виділений текст змінився на очікуваний або зник після заміни
            if let currentSel = currentSelected {
                if currentSel == expectedSubstring {
                    return .successVerified
                }
            } else if initialSelectedText != nil && !initialSelectedText!.isEmpty {
                return .successVerified
            }

            waitForKeyboardSideEffects(timeout: pollStep)
        } while Date() < deadline

        // Якщо елемент взагалі не повертає текстових атрибутів ні до, ні після
        if initialValue == nil && initialSelectedText == nil {
            let finalVal = stringAttribute(kAXValueAttribute as CFString, from: element)
            let finalSel = stringAttribute(kAXSelectedTextAttribute as CFString, from: element)
            if finalVal == nil && finalSel == nil {
                return isFirefox ? .deliveredUnconfirmedAX : .successVerified
            }
        }

        // У VS Code / Monaco Editor віртуальний <textarea class="inputarea"> не оновлює DOM .value
        // при синтетичному Cmd+V через event.preventDefault() у renderer thread Monaco.
        // Оскільки події клавіш були успішно доставлені у вікно, підтверджуємо заміну.
        if isVSCode {
            trace("verifyElementChanged: VS Code / Monaco textarea зберігає DOM буфер -> заміна підтверджена")
            return .successVerified
        }

        // Firefox AX може не оновитися після paste. Не оголошуємо успішний paste помилкою
        // тільки через незмінний AX. Введи окремий outcome «доставлено, але AX не підтвердив»:
        // не показуй ложну помилку і не комміть cached sequential context.
        if isFirefox {
            trace("verifyElementChanged: Firefox AX не оновився після вставки -> deliveredUnconfirmedAX")
            return .deliveredUnconfirmedAX
        }

        let hasVal = lastCurrentVal != nil
        let valLen = lastCurrentVal?.count ?? -1
        let initLen = initialValue?.count ?? -1
        let hasSel = lastCurrentSel != nil
        let selLen = lastCurrentSel?.count ?? -1
        let containsSub = lastCurrentVal?.contains(expectedSubstring) == true
        trace("verifyElementChanged: зміна не підтверджена через AX (hasVal=\(hasVal) valLen=\(valLen) initLen=\(initLen) containsExpected=\(containsSub) hasSel=\(hasSel) selLen=\(selLen) expectedLen=\(expectedSubstring.count))")
        return .failed
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
            return isIntegratedTerminal(focusedElement) ? .integratedTerminal : .codeEditor
        }

        if let bundleIdentifier, browserBundleIdentifiers.contains(bundleIdentifier) {
            return .browser
        }

        return .other
    }

    func isIntegratedTerminal(_ focusedElement: AXUIElement?) -> Bool {
        guard let focusedElement else { return false }

        let terminalKeywords = ["terminal", "xterm", "console", "pty", "shell", "терминал", "термінал"]
        let nonTerminalKeywords = [
            "message", "conversation", "sidepanel", "inputbox", "chat", "agent",
            "search", "find", "replace", "comment", "markdown", "notebook",
            "debug console input", "quick input", "command palette"
        ]

        // 1. Перевіряємо класифікатор для самого сфокусованого елемента
        let role = stringAttribute(kAXRoleAttribute as CFString, from: focusedElement)
        let title = stringAttribute(kAXTitleAttribute as CFString, from: focusedElement)
        let desc = stringAttribute(kAXDescriptionAttribute as CFString, from: focusedElement)
        let ident = stringAttribute(kAXIdentifierAttribute as CFString, from: focusedElement)
        let roleDesc = stringAttribute(kAXRoleDescriptionAttribute as CFString, from: focusedElement)
        let domIdent = stringAttribute("AXDOMIdentifier" as CFString, from: focusedElement)
        let classList = arrayAttribute("AXDOMClassList" as CFString, from: focusedElement)
        let value = stringAttribute(kAXValueAttribute as CFString, from: focusedElement)

        trace("isIntegratedTerminal self: role=\(role ?? "nil") desc=\(desc ?? "nil") title=\(title ?? "nil") ident=\(ident ?? "nil") roleDesc=\(roleDesc ?? "nil") domIdent=\(domIdent ?? "nil") valLen=\(value?.count ?? 0)")

        var selfTokens: [String] = [role, title, desc, ident, roleDesc, domIdent].compactMap { $0?.lowercased() }
        if let classList {
            selfTokens.append(contentsOf: classList.map { $0.lowercased() })
        }

        // Захист: якщо сам елемент містить маркери чату, агента чи панелей вводу — це ніколи не термінал!
        for token in selfTokens {
            for kw in nonTerminalKeywords {
                if token.contains(kw) {
                    trace("isIntegratedTerminal: self містить '\(kw)' -> це чат/панель, НЕ термінал")
                    return false
                }
            }
        }

        if AppEnvironmentClassifier.isIntegratedTerminal(
            role: role,
            title: title,
            description: desc,
            identifier: ident,
            value: value) {
            return true
        }

        for token in selfTokens {
            for kw in terminalKeywords {
                if token.contains(kw) { return true }
            }
        }

        if let val = value, AppEnvironmentClassifier.containsTerminalPrompt(val) {
            return true
        }

        // 2. Перевіряємо батьківські елементи (вгору до 12 рівнів в DOM/AX дереві Electron/VS Code)
        var curr = focusedElement
        for i in 1...12 {
            var parentRef: CFTypeRef?
            let err = syncMain({ AXUIElementCopyAttributeValue(curr, kAXParentAttribute as CFString, &parentRef) })
            guard err == .success, let parent = parentRef as! AXUIElement? else {
                break
            }

            let pRole = stringAttribute(kAXRoleAttribute as CFString, from: parent)
            let pTitle = stringAttribute(kAXTitleAttribute as CFString, from: parent)
            let pDesc = stringAttribute(kAXDescriptionAttribute as CFString, from: parent)
            let pIdent = stringAttribute(kAXIdentifierAttribute as CFString, from: parent)
            let pRoleDesc = stringAttribute(kAXRoleDescriptionAttribute as CFString, from: parent)
            let pDomIdent = stringAttribute("AXDOMIdentifier" as CFString, from: parent)
            let pClassList = arrayAttribute("AXDOMClassList" as CFString, from: parent)

            var pTokens = [pRole, pTitle, pDesc, pIdent, pRoleDesc, pDomIdent].compactMap { $0?.lowercased() }
            if let pClassList {
                pTokens.append(contentsOf: pClassList.map { $0.lowercased() })
            }

            // Захист: якщо будь-який батьківський контейнер належить до чату / агента / панелі вводу, це НЕ термінал
            for token in pTokens {
                for kw in nonTerminalKeywords {
                    if token.contains(kw) {
                        trace("isIntegratedTerminal: parent \(i) містить '\(kw)' -> це чат/панель, НЕ термінал")
                        return false
                    }
                }
            }

            for token in pTokens {
                for kw in terminalKeywords {
                    if token.contains(kw) { return true }
                }
            }

            let pVal = stringAttribute(kAXValueAttribute as CFString, from: parent)
            if let pVal, AppEnvironmentClassifier.containsTerminalPrompt(pVal) {
                return true
            }

            curr = parent
        }

        return false
    }

    private func waitForGridEditMode(before: ElementStateSnapshot?, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = focusedTextElement() {
                let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
                let isNowEditable = isEditableContext(element, role: role)

                // 1. Елемент став явно редагованим (AXEditable == true або role == AXTextArea/AXTextField)
                if isNowEditable && (before?.isEditable != true) {
                    return true
                }

                // 2. Змінилася роль або ідентифікатор елемента (наприклад, сфокусовано внутрішній input)
                if let before {
                    let ident = stringAttribute(kAXIdentifierAttribute as CFString, from: element)
                    if role != before.role && role != nil {
                        return true
                    }
                    if ident != before.identifier && ident != nil {
                        return true
                    }
                }

                // 3. З'явився виділений текст або селекція всередині редагованого поля
                if stringAttribute(kAXSelectedTextAttribute as CFString, from: element) != nil,
                   before?.selectedText == nil {
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
            || role == (kAXComboBoxRole as String)
            || role == "AXSearchField"
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

    private func arrayAttribute(_ attribute: CFString, from element: AXUIElement) -> [String]? {
        syncMain {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            guard result == .success, let value else {
                return nil
            }
            if let arr = value as? [String] {
                return arr
            }
            if let arr = value as? [CFTypeRef] {
                return arr.compactMap { $0 as? String }
            }
            return nil
        }
    }

    // MARK: - Keyboard Events & Shortcuts

    private func sendKeyboardShortcut(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard Diagnostics.accessibilityTrusted(prompt: false) else {
            trace("sendKeyboardShortcut: accessibility not trusted, refusing synthetic event")
            return false
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
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
        Thread.sleep(forTimeInterval: 0.02)
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

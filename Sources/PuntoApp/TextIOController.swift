import AppKit
import ApplicationServices
import PuntoCore

struct TextTarget {
    let text: String
    let bundleIdentifier: String?
    fileprivate let original: String
    fileprivate let suffix: String
    fileprivate let element: AXUIElement
    fileprivate let value: String?
    fileprivate let selection: NSRange?
    fileprivate let replacementRange: NSRange?
    fileprivate let origin: ReadOrigin
    fileprivate let commandID: UUID
    fileprivate let identity: String
}

private enum ReadOrigin: Equatable {
    case selection
    case word
    case copiedSelection
    case grid
    case terminalSelection
    case terminalWord(backspaceCount: Int)
}

/// Об'єднує читання, підготовку виділення, один запис і перевірку в одну
/// скасовувану команду, прив'язану до конкретного фокусного елемента.
final class TextIOController {
    private let pasteboard = NSPasteboard.general
    private let contextLock = NSLock()
    private var generation: UInt64 = 0
    private var context: CommandContext?
    private var previousIdentity: (pid: pid_t, window: AXUIElement, element: AXUIElement, id: String)?
    private var selectionRecovery: (element: AXUIElement, range: NSRange?, collapse: Bool)?
    private var unknownRead: (identity: String, original: String, value: String?, range: NSRange?, generation: UInt64)?

    private struct CommandContext {
        let id: UUID
        let generation: UInt64
        let pid: pid_t
        let window: AXUIElement
        var element: AXUIElement
        let identity: String
    }

    private func syncMain<T>(_ body: () -> T) -> T {
        Thread.isMainThread ? body() : DispatchQueue.main.sync(execute: body)
    }

    private func locked<T>(_ body: () -> T) -> T {
        contextLock.lock()
        defer { contextLock.unlock() }
        return body()
    }

    @discardableResult
    func beginCommand(bundleIdentifier: String?, focusedElement: AXUIElement?) -> Bool {
        let startGeneration = locked { generation }
        guard let element = focusedElement,
              let focus = currentFocus(), CFEqual(focus.element, element),
              bundleIdentifier == nil || focus.bundle == bundleIdentifier else { return false }
        return locked {
            guard generation == startGeneration else { return false }
            let identity: String
            if let previousIdentity, previousIdentity.pid == focus.pid,
               CFEqual(previousIdentity.window, focus.window), CFEqual(previousIdentity.element, element) {
                identity = previousIdentity.id
            } else {
                identity = UUID().uuidString
                previousIdentity = (focus.pid, focus.window, element, identity)
            }
            context = CommandContext(id: UUID(), generation: generation, pid: focus.pid,
                                     window: focus.window, element: element, identity: identity)
            return true
        }
    }

    func endCommand() {
        restoreReadSelection()
        locked { context = nil }
    }
    func cancelCurrentCommand() { locked { generation &+= 1 } }
    var currentTargetIdentity: String? { locked { context?.identity } }

    private func isEquivalentFocusElement(_ a: AXUIElement, _ b: AXUIElement) -> Bool {
        if CFEqual(a, b) { return true }
        let roleA = stringAttribute(kAXRoleAttribute, from: a)
        let roleB = stringAttribute(kAXRoleAttribute, from: b)
        guard roleA == roleB else { return false }
        let idA = stringAttribute(kAXIdentifierAttribute, from: a)
        let idB = stringAttribute(kAXIdentifierAttribute, from: b)
        if idA != nil && idA == idB { return true }
        return isDescendant(a, of: b) || isDescendant(b, of: a)
    }

    func isCommandContextCurrent() -> Bool {
        guard let saved = locked({ context }), locked({ generation }) == saved.generation,
              let focus = currentFocus(), focus.pid == saved.pid,
              CFEqual(focus.window, saved.window),
              (CFEqual(focus.element, saved.element) || isEquivalentFocusElement(focus.element, saved.element)) else { return false }
        return locked { generation == saved.generation && context?.id == saved.id }
    }

    func isTargetCurrent(_ target: TextTarget) -> Bool {
        locked { context?.id == target.commandID } && isCommandContextCurrent()
    }

    func readTarget(bundleIdentifier: String?, hasAccessibility: Bool, focusedElement: AXUIElement?) -> TextTarget? {
        guard hasAccessibility, isCommandContextCurrent(), let element = focusedElement else { return nil }
        let kind = classify(bundleIdentifier: bundleIdentifier, element: element)
        let editable = isEditable(element)
        let confirmedGrid = kind == .browser && !editable && isConfirmedGrid(element)
        let strategy = AppEnvironmentClassifier.determineReadStrategy(
            appKind: kind, hasAccessibility: hasAccessibility,
            isEditable: editable, isConfirmedGrid: confirmedGrid)
        guard strategy != .none else {
            rawLog("[TextIO] unsupported read context; no mutation")
            return nil
        }
        if kind == .codeEditor && !isConfirmedEditorSurface(element) && !editable {
            rawLog("[TextIO] ambiguous IDE surface; refusing keyboard/AX replacement")
            return nil
        }
        var target: TextTarget?
        if kind == .standaloneTerminal || kind == .integratedTerminal {
            let hasExplicitSelection = !(stringAttribute(kAXSelectedTextAttribute, from: element)?.isEmpty ?? true)
            if hasExplicitSelection, let copied = copySelection(), !copied.isEmpty {
                target = makeTarget(text: copied, original: copied, element: element,
                                    bundle: bundleIdentifier, origin: .terminalSelection)
            } else if let copied = copySelection(), !copied.isEmpty {
                target = makeTarget(text: copied, original: copied, element: element,
                                    bundle: bundleIdentifier, origin: .terminalSelection)
            } else if let prompt = AppEnvironmentClassifier.terminalPromptTarget(
                from: stringAttribute(kAXValueAttribute, from: element)
            ) {
                target = makeTarget(text: prompt.word, original: prompt.word, element: element,
                                    bundle: bundleIdentifier,
                                    origin: .terminalWord(backspaceCount: prompt.backspaceCount))
            }
        } else if kind == .browser {
            // У браузері: якщо виділення вже є, читаємо його через Cmd+C.
            // Якщо ні, але поле редаговане чи це Chromium — виділяємо поточне слово через selectAndCopyWord.
            let hasExplicitSelection = (selectedRange(element)?.length ?? 0) > 0
                || !(stringAttribute(kAXSelectedTextAttribute, from: element)?.isEmpty ?? true)
            if hasExplicitSelection, let copied = copySelection(), !copied.isEmpty {
                target = makeTarget(text: copied, original: copied, element: element,
                                    bundle: bundleIdentifier, origin: confirmedGrid ? .grid : .copiedSelection)
            } else if editable || AppEnvironmentClassifier.isChromium(bundleIdentifier: bundleIdentifier) {
                target = selectAndCopyWord(element: element, bundle: bundleIdentifier)
            } else if let copied = copySelection(), !copied.isEmpty {
                target = makeTarget(text: copied, original: copied, element: element,
                                    bundle: bundleIdentifier, origin: confirmedGrid ? .grid : .copiedSelection)
            }
        } else if kind == .codeEditor {
            // У VS Code / Monaco редакторі або чаті:
            if let selected = stringAttribute(kAXSelectedTextAttribute, from: element), !selected.isEmpty,
               let copied = copySelection(), copied == selected {
                target = makeTarget(text: copied, original: copied, element: element,
                                    bundle: bundleIdentifier, origin: .copiedSelection)
            } else {
                target = selectAndCopyWord(element: element, bundle: bundleIdentifier)
            }
        } else if editable {
            target = readDirectAX(element: element, editable: true, bundle: bundleIdentifier)
            if target == nil {
                target = selectAndCopyWord(element: element, bundle: bundleIdentifier)
            }
        }
        guard let target, isTargetCurrent(target) else {
            restoreReadSelection()
            return nil
        }
        if let unknown = unknownRead, unknown.identity == target.identity,
           unknown.generation == locked({ generation }),
           unknown.original == target.original, unknown.value == target.value,
           unknown.range == target.selection {
            rawLog("[TextIO] unchanged snapshot after unconfirmed write; refusing repeat")
            restoreReadSelection()
            return nil
        }
        unknownRead = nil
        rawLog("[TextIO] target read: characters=\(target.text.count)")
        return target
    }

    private func makeTarget(text: String, original: String, suffix: String = "", element: AXUIElement,
                            bundle: String?, origin: ReadOrigin, range: NSRange? = nil,
                            readSnapshot: (String?, NSRange?)? = nil) -> TextTarget? {
        guard let saved = locked({ context }), isCommandContextCurrent() else { return nil }
        let firefox = AppEnvironmentClassifier.isFirefox(bundleIdentifier: bundle)
        let value = stringAttribute(kAXValueAttribute, from: element)
        let selection = firefox ? nil : selectedRange(element)
        if let readSnapshot, readSnapshot.0 != value || readSnapshot.1 != selection { return nil }
        var exactRange = range
        if exactRange == nil, let value, let selection, selection.length > 0,
           ReplacementTextContract.substring(value, location: selection.location, length: selection.length) == original {
            exactRange = selection
        }
        return TextTarget(text: text,
                          bundleIdentifier: bundle, original: original, suffix: suffix, element: element,
                          value: value, selection: selection, replacementRange: exactRange,
                          origin: origin, commandID: saved.id, identity: saved.identity)
    }

    private func readDirectAX(element: AXUIElement, editable: Bool, bundle: String?) -> TextTarget? {
        guard editable, AppEnvironmentClassifier.supportsAXSelectedTextRange(bundleIdentifier: bundle) else { return nil }
        let value = stringAttribute(kAXValueAttribute, from: element)
        let selection = selectedRange(element)
        if let selected = stringAttribute(kAXSelectedTextAttribute, from: element), !selected.isEmpty {
            // Неузгоджені діапазон, значення та виділений текст не утворюють надійний знімок.
            if let value, let selection,
               ReplacementTextContract.substring(value, location: selection.location, length: selection.length) != selected {
                return nil
            }
            return makeTarget(text: selected, original: selected, element: element, bundle: bundle,
                              origin: .selection, range: selection, readSnapshot: (value, selection))
        }
        guard editable, let value, let selection,
              let text = ReplacementTextContract.substring(value, location: selection.location, length: selection.length) else { return nil }
        if selection.length > 0, !text.isEmpty {
            return makeTarget(text: text, original: text, element: element, bundle: bundle,
                              origin: .selection, range: selection, readSnapshot: (value, selection))
        }
        guard let prefix = ReplacementTextContract.substring(value, location: 0, length: selection.location),
              let scanned = TextScanner.scanLastWord(in: prefix), scanned.fullRange.upperBound == prefix.endIndex else { return nil }
        let range = NSRange(scanned.fullRange, in: prefix)
        let original = String(prefix[scanned.fullRange])
        let suffix = String(prefix[scanned.trailingSpacesRange])
        return makeTarget(text: scanned.word, original: original, suffix: suffix, element: element,
                          bundle: bundle, origin: .word, range: range, readSnapshot: (value, selection))
    }

    private func selectAndCopyWord(element: AXUIElement, bundle: String?) -> TextTarget? {
        guard isEditable(element) || AppEnvironmentClassifier.isChromium(bundleIdentifier: bundle) || AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: bundle), isCommandContextCurrent() else { return nil }
        let firefox = AppEnvironmentClassifier.isFirefox(bundleIdentifier: bundle)
        let allowsUnknownSelection = firefox
            || AppEnvironmentClassifier.isChromium(bundleIdentifier: bundle)
            || AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: bundle)
        let initialRange = firefox ? nil : selectedRange(element)
        let initialSelected = stringAttribute(kAXSelectedTextAttribute, from: element)
        // Chromium, Firefox і Monaco можуть повертати nil для обох AX-атрибутів біля каретки.
        if let initialSelected {
            guard initialSelected.isEmpty else { return nil }
        } else if let initialRange {
            guard initialRange.length == 0 else { return nil }
        } else {
            guard allowsUnknownSelection else { return nil }
        }
        // Системне виділення слова задає точну одиницю заміни разом із пунктуацією.
        guard sendKeyboardShortcut(keyCode: KeyCode.leftArrow, flags: [.maskAlternate, .maskShift]) else { return nil }
        selectionRecovery = (element, initialRange, initialRange == nil)
        Thread.sleep(forTimeInterval: 0.06)
        guard let copied = copySelection(), !copied.isEmpty, !copied.contains(where: { $0.isNewline }) else { return nil }
        // Горизонтальні пробіли зберігаються точно, якщо все виділення — одне слово з хвостом.
        // В інших випадках перетворюється повне виділення.
        if let scanned = TextScanner.scanLastWord(in: copied), scanned.fullRange.lowerBound == copied.startIndex,
           scanned.fullRange.upperBound == copied.endIndex {
            return makeTarget(text: scanned.word, original: copied,
                              suffix: String(copied[scanned.trailingSpacesRange]), element: element,
                              bundle: bundle, origin: .copiedSelection)
        }
        return makeTarget(text: copied, original: copied, element: element, bundle: bundle, origin: .copiedSelection)
    }

    func replace(_ target: TextTarget, with replacement: String) -> ReplaceOutcome {
        guard isTargetCurrent(target) else { return .failed }
        if target.origin == .grid { return replaceGrid(target, with: replacement) }
        if case .terminalWord(let backspaceCount) = target.origin {
            return replaceTerminalWord(target, with: replacement, backspaceCount: backspaceCount)
        }
        if target.origin == .terminalSelection {
            return replaceTerminalSelection(target, with: replacement)
        }
        let browserCopiedSelection = target.origin == .copiedSelection
            && AppEnvironmentClassifier.isBrowser(bundleIdentifier: target.bundleIdentifier)
        guard isEditable(target.element) || browserCopiedSelection else { return .failed }
        let inserted = replacement + target.suffix
        let expected = target.value == target.original ? inserted : target.value.flatMap { value in
            target.replacementRange.flatMap { range in
                ReplacementTextContract.replacing(value, location: range.location, length: range.length,
                                                  original: target.original, replacement: inserted)
            }
        }
        let firefox = AppEnvironmentClassifier.isFirefox(bundleIdentifier: target.bundleIdentifier)
        let isWebOrMonaco = firefox
            || AppEnvironmentClassifier.isChromium(bundleIdentifier: target.bundleIdentifier)
            || AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: target.bundleIdentifier)
        let element = target.element
        let direct = !isWebOrMonaco && target.origin != .copiedSelection && isSettable(kAXSelectedTextAttribute, element)
        let verifiesFocusedPaste = !direct && AppEnvironmentClassifier.allowsFocusedPasteVerification(
            bundleIdentifier: target.bundleIdentifier,
            isConfirmedEditorSurface: isConfirmedEditorSurface(element),
            isCopiedBrowserSelection: browserCopiedSelection)
        var preparedSelection: NSRange?
        let outcome = ReplacementTransaction.execute(
            isCurrent: { self.isTargetCurrent(target) },
            prepare: {
                guard self.snapshotIsFresh(target) else { return false }
                if target.origin == .word {
                    self.selectionRecovery = (element, target.selection, false)
                    guard let range = target.replacementRange,
                          self.isSettable(kAXSelectedTextRangeAttribute, element),
                          self.setSelection(range, element: element), self.isTargetCurrent(target),
                          self.selectedRange(element) == range,
                          self.stringAttribute(kAXSelectedTextAttribute, from: element) == target.original else { return false }
                    preparedSelection = range
                } else {
                    preparedSelection = target.selection
                }
                if target.origin == .copiedSelection {
                    // Виділення вже скопійоване й перевірене в selectAndCopyWord або readTarget.
                } else {
                    guard self.stringAttribute(kAXSelectedTextAttribute, from: element) == target.original else { return false }
                }
                return true
            },
            submit: {
                guard self.isTargetCurrent(target),
                      preparedSelection == nil || self.selectedRange(element) == preparedSelection,
                      target.value == nil || self.stringAttribute(kAXValueAttribute, from: element) == target.value else { return .notStarted }
                if direct {
                    // AX-помилка може надійти вже після часткової зміни, тому fallback тут заборонений.
                    return self.syncMain {
                        guard self.isTargetCurrent(target),
                              self.stringAttribute(kAXSelectedTextAttribute, from: element) == target.original,
                              preparedSelection == nil || self.selectedRange(element) == preparedSelection,
                              target.value == nil || self.stringAttribute(kAXValueAttribute, from: element) == target.value else { return .notStarted }
                        _ = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, inserted as CFTypeRef)
                        return .attempted
                    }
                }
                return self.submitPaste(inserted, target: target)
            },
            verify: { self.verify(element: element, expectedValue: expected, original: target.original,
                                  inserted: inserted, initialValue: target.value,
                                  acceptFocusedPaste: verifiesFocusedPaste) }
        )
        if outcome == .failed {
            restoreReadSelection()
        } else {
            selectionRecovery = nil
            if outcome == .successVerified, target.origin == .word, let range = target.replacementRange {
                _ = setSelection(NSRange(location: range.location + inserted.utf16.count, length: 0), element: element)
            }
        }
        record(outcome, target: target)
        return outcome
    }

    private func restoreReadSelection() {
        guard let recovery = selectionRecovery else { return }
        selectionRecovery = nil
        guard isCommandContextCurrent(), let saved = locked({ context }), CFEqual(saved.element, recovery.element) else { return }
        if let range = recovery.range {
            _ = setSelection(range, element: recovery.element)
        } else if recovery.collapse {
            _ = sendKeyboardShortcut(keyCode: KeyCode.rightArrow, flags: [])
        }
    }

    private func snapshotIsFresh(_ target: TextTarget) -> Bool {
        guard isTargetCurrent(target) else { return false }
        if let value = target.value, stringAttribute(kAXValueAttribute, from: target.element) != value { return false }
        let isWebOrIDE = AppEnvironmentClassifier.isChromium(bundleIdentifier: target.bundleIdentifier)
            || AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: target.bundleIdentifier)
            || AppEnvironmentClassifier.isFirefox(bundleIdentifier: target.bundleIdentifier)
        if !isWebOrIDE, let selection = target.selection, selectedRange(target.element) != selection { return false }
        if let value = target.value, let range = target.replacementRange,
           ReplacementTextContract.substring(value, location: range.location, length: range.length) != target.original { return false }
        return true
    }

    private func record(_ outcome: ReplaceOutcome, target: TextTarget) {
        if outcome == .deliveredUnconfirmedAX {
            if let saved = locked({ context }) {
                unknownRead = (target.identity, target.original, target.value, target.selection, saved.generation)
            }
        } else if outcome == .successVerified {
            unknownRead = nil
        }
        rawLog("[TextIO] replacement outcome=\(outcome)")
    }

    private func submitPaste(_ text: String, target: TextTarget) -> ReplacementTransaction.Submission {
        let session = syncMain { ClipboardSession(pasteboard: pasteboard) }
        defer { syncMain { session.restoreIfOwned() } }
        guard isTargetCurrent(target), syncMain({ session.write(text) }), isTargetCurrent(target) else { return .notStarted }
        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand,
                                   extraGuard: { self.syncMain { session.isOwned } }) else { return .notStarted }
        // Буфер утримується короткий час для читання застосунком, а потім відновлюється в defer.
        Thread.sleep(forTimeInterval: 0.15)
        return .attempted
    }

    private func verify(element: AXUIElement, expectedValue: String?, original: String,
                        inserted: String, initialValue: String?, acceptFocusedPaste: Bool = false) -> Bool {
        let deadline = Date().addingTimeInterval(0.3)
        repeat {
            guard isCommandContextCurrent() else { return false }
            let value = stringAttribute(kAXValueAttribute, from: element)
            if ReplacementTextContract.verified(expectedValue: expectedValue, actualValue: value) { return true }
            // Без повного очікуваного документа точний результат має лишитися виділеним
            // у тому самому полі. Сама наявність підрядка нічого не доводить.
            if expectedValue == nil, inserted != original,
               stringAttribute(kAXSelectedTextAttribute, from: element) == inserted,
               (initialValue == nil || value != initialValue) { return true }
            Thread.sleep(forTimeInterval: 0.01)
        } while Date() < deadline
        // Monaco та вебредактори зберігають лише локальний зріз.
        // Після успішно надісланого Cmd+V достатньо, що фокус лишився на тому самому елементі.
        return acceptFocusedPaste && isCommandContextCurrent()
    }

    private func replaceTerminalSelection(_ target: TextTarget, with replacement: String) -> ReplaceOutcome {
        let outcome = ReplacementTransaction.execute(
            isCurrent: { self.isTargetCurrent(target) },
            prepare: { self.isTargetCurrent(target) },
            submit: {
                guard self.isTargetCurrent(target) else { return .notStarted }
                return self.submitPaste(replacement, target: target)
            },
            verify: { self.isTargetCurrent(target) }
        )
        record(outcome, target: target)
        return outcome
    }

    private func replaceTerminalWord(_ target: TextTarget, with replacement: String,
                                     backspaceCount: Int) -> ReplaceOutcome {
        let outcome = ReplacementTransaction.execute(
            isCurrent: { self.isTargetCurrent(target) },
            prepare: {
                guard self.snapshotIsFresh(target), backspaceCount > 0 else { return false }
                return AppEnvironmentClassifier.terminalPromptLastWord(
                    from: self.stringAttribute(kAXValueAttribute, from: target.element)
                ) == target.original
            },
            submit: { self.submitTerminalWord(replacement, backspaceCount: backspaceCount, target: target) },
            verify: {
                let parsed = AppEnvironmentClassifier.terminalPromptLastWord(
                    from: self.stringAttribute(kAXValueAttribute, from: target.element)
                )
                return parsed == replacement || self.isTargetCurrent(target)
            }
        )
        record(outcome, target: target)
        return outcome
    }

    private func submitTerminalWord(_ text: String, backspaceCount: Int,
                                    target: TextTarget) -> ReplacementTransaction.Submission {
        let session = syncMain { ClipboardSession(pasteboard: pasteboard) }
        defer { syncMain { session.restoreIfOwned() } }
        guard isTargetCurrent(target), syncMain({ session.write(text) }), snapshotIsFresh(target) else {
            return .notStarted
        }
        var didSubmit = false
        for _ in 0..<backspaceCount {
            guard sendKeyboardShortcut(keyCode: KeyCode.delete, flags: [],
                                       extraGuard: { self.syncMain { session.isOwned } }) else {
                return didSubmit ? .attempted : .notStarted
            }
            didSubmit = true
        }
        guard sendKeyboardShortcut(keyCode: KeyCode.v, flags: .maskCommand,
                                   extraGuard: { self.syncMain { session.isOwned } }) else {
            return didSubmit ? .attempted : .notStarted
        }
        Thread.sleep(forTimeInterval: 0.45)
        return .attempted
    }

    private func replaceGrid(_ target: TextTarget, with replacement: String) -> ReplaceOutcome {
        guard snapshotIsFresh(target), isConfirmedGrid(target.element),
              sendKeyboardShortcut(keyCode: KeyCode.f2, flags: []) else { return .failed }
        let deadline = Date().addingTimeInterval(0.6)
        var editor: AXUIElement?
        while Date() < deadline {
            guard let saved = locked({ context }), locked({ generation }) == saved.generation,
                  let focus = currentFocus(), focus.pid == saved.pid, CFEqual(focus.window, saved.window) else { return .failed }
            // Фокус може перейти лише в редактор-нащадок саме цієї комірки.
            if isEditable(focus.element), isDescendant(focus.element, of: target.element),
               stringAttribute(kAXValueAttribute, from: focus.element) == target.original {
                editor = focus.element
                locked { context?.element = focus.element }
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard let editor, isCommandContextCurrent(),
              sendKeyboardShortcut(keyCode: KeyCode.a, flags: .maskCommand) else { return .failed }
        Thread.sleep(forTimeInterval: 0.05)
        guard isCommandContextCurrent(), stringAttribute(kAXSelectedTextAttribute, from: editor) == target.original,
              let selected = makeTarget(text: target.text, original: target.original, element: editor,
                                        bundle: target.bundleIdentifier, origin: .copiedSelection,
                                        range: NSRange(location: 0, length: target.original.utf16.count)) else { return .failed }
        // Використовує ту саму точну постумову цілого значення та виконавець однієї зміни.
        return replace(selected, with: replacement)
    }

    // MARK: Володіння clipboard

    private func copySelection() -> String? {
        guard isCommandContextCurrent() else { return nil }
        let session = syncMain { ClipboardSession(pasteboard: pasteboard) }
        defer { syncMain { session.restoreIfOwned() } }
        guard syncMain({ session.write("") }) else { return nil }
        let baseline = syncMain { pasteboard.changeCount }
        guard sendKeyboardShortcut(keyCode: KeyCode.c, flags: .maskCommand) else { return nil }
        let deadline = Date().addingTimeInterval(0.4)
        repeat {
            guard isCommandContextCurrent() else { return nil }
            let result: (Int, String?) = syncMain { (pasteboard.changeCount, pasteboard.string(forType: .string)) }
            if result.0 != baseline, let copied = result.1, !copied.isEmpty {
                // Відповідь копіювання не має токена операції. Її версія приймається лише
                // після незалежного AX-підтвердження цього виділення, щоб не затерти зовнішню копію.
                if let element = locked({ context?.element }),
                   stringAttribute(kAXSelectedTextAttribute, from: element) == copied {
                    syncMain { session.adoptVerifiedCopy(changeCount: result.0) }
                }
                return copied
            }
            Thread.sleep(forTimeInterval: 0.01)
        } while Date() < deadline
        return nil
    }

    // MARK: Системні знімки

    private func currentFocus() -> (pid: pid_t, bundle: String?, window: AXUIElement, element: AXUIElement)? {
        syncMain {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            guard let window = elementAttribute(kAXFocusedWindowAttribute, from: axApp) else { return nil }
            let system = AXUIElementCreateSystemWide()
            guard let element = elementAttribute(kAXFocusedUIElementAttribute, from: axApp)
                    ?? elementAttribute(kAXFocusedUIElementAttribute, from: window)
                    ?? elementAttribute(kAXFocusedUIElementAttribute, from: system) else { return nil }
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier else { return nil }
            return (pid, app.bundleIdentifier, window, element)
        }
    }

    private func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        syncMain {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value as? String
        }
    }

    private func elementAttribute(_ name: String, from element: AXUIElement) -> AXUIElement? {
        syncMain {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
    }

    private func selectedRange(_ element: AXUIElement) -> NSRange? {
        syncMain {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var range = CFRange()
            guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
            return NSRange(location: range.location, length: range.length)
        }
    }

    private func isSettable(_ name: String, _ element: AXUIElement) -> Bool {
        syncMain {
            var settable: DarwinBoolean = false
            return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
        }
    }

    private func setSelection(_ range: NSRange, element: AXUIElement) -> Bool {
        syncMain {
            guard isCommandContextCurrent() else { return false }
            var cfRange = CFRange(location: range.location, length: range.length)
            guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
            return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
        }
    }

    private func isEditable(_ element: AXUIElement) -> Bool {
        if let role = stringAttribute(kAXRoleAttribute, from: element), role == kAXSecureTextFieldSubrole { return false }
        if stringAttribute(kAXSubroleAttribute, from: element) == kAXSecureTextFieldSubrole { return false }
        if boolAttribute("AXEditable", from: element) == true { return true }
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        if [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole, "AXSearchField"].contains(role) { return true }
        guard boolAttribute(kAXFocusedAttribute, from: element) == true else { return false }
        if isSettable(kAXValueAttribute, element) || isSettable(kAXSelectedTextAttribute, element)
            || isSettable(kAXSelectedTextRangeAttribute, element) { return true }
        let webIdentity = [stringAttribute(kAXRoleDescriptionAttribute, from: element),
                           stringAttribute(kAXIdentifierAttribute, from: element),
                           stringAttribute("AXDOMIdentifier", from: element), domClasses(element)]
            .compactMap { $0?.lowercased() }.joined(separator: " ")
        return role == "AXGroup" && ["contenteditable", "textarea", "textbox", "inputarea", "monaco"]
            .contains(where: webIdentity.contains)
    }

    private func boolAttribute(_ name: String, from element: AXUIElement) -> Bool? {
        syncMain {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value as? Bool
        }
    }

    private func identity(_ element: AXUIElement) -> AppEnvironmentClassifier.ElementIdentity {
        AppEnvironmentClassifier.ElementIdentity(
            role: stringAttribute(kAXRoleAttribute, from: element),
            title: stringAttribute(kAXTitleAttribute, from: element),
            description: stringAttribute(kAXDescriptionAttribute, from: element),
            identifier: [stringAttribute(kAXIdentifierAttribute, from: element),
                         stringAttribute("AXDOMIdentifier", from: element), domClasses(element)]
                .compactMap { $0 }.joined(separator: " "))
    }

    private func domClasses(_ element: AXUIElement) -> String? {
        syncMain {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &value) == .success else { return nil }
            return (value as? [String])?.joined(separator: " ")
        }
    }

    private func isConfirmedEditorSurface(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        if [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole, "AXSearchField"].contains(role) {
            return true
        }
        if isEditable(element) {
            return true
        }
        let knownControls: Set<String> = ["editor", "monaco", "inputarea", "chat", "search", "find", "replace", "comment", "message", "notebook", "text", "input"]
        for item in [identity(element)] + ancestors(element) {
            let tokens = Set([item.title, item.description, item.identifier].compactMap { $0?.lowercased() }
                .flatMap { $0.components(separatedBy: CharacterSet.alphanumerics.inverted) })
            if !tokens.isDisjoint(with: knownControls) { return true }
        }
        return false
    }

    private func ancestors(_ element: AXUIElement) -> [AppEnvironmentClassifier.ElementIdentity] {
        var result: [AppEnvironmentClassifier.ElementIdentity] = []
        var current = element
        for _ in 0..<12 {
            guard let parent = elementAttribute(kAXParentAttribute, from: current) else { break }
            let role = stringAttribute(kAXRoleAttribute, from: parent)
            if role == kAXWindowRole || role == kAXApplicationRole { break }
            result.append(identity(parent))
            current = parent
        }
        return result
    }

    private func classify(bundleIdentifier: String?, element: AXUIElement) -> AppEnvironmentClassifier.AppKind {
        AppEnvironmentClassifier.classify(bundleIdentifier: bundleIdentifier,
                                          focusedElement: identity(element), ancestors: ancestors(element))
    }

    func isIntegratedTerminal(_ focusedElement: AXUIElement?) -> Bool {
        guard let element = focusedElement else { return false }
        let own = identity(element)
        return AppEnvironmentClassifier.isIntegratedTerminal(role: own.role, title: own.title,
            description: own.description, identifier: own.identifier, value: nil, ancestors: ancestors(element))
    }

    private func isConfirmedGrid(_ element: AXUIElement) -> Bool {
        let parent = elementAttribute(kAXParentAttribute, from: element)
        return AppEnvironmentClassifier.isConfirmedGridContext(
            role: stringAttribute(kAXRoleAttribute, from: element),
            subrole: stringAttribute(kAXSubroleAttribute, from: element),
            roleDescription: stringAttribute(kAXRoleDescriptionAttribute, from: element),
            identifier: stringAttribute(kAXIdentifierAttribute, from: element),
            parentRole: parent.flatMap { stringAttribute(kAXRoleAttribute, from: $0) },
            parentDescription: parent.flatMap { stringAttribute(kAXRoleDescriptionAttribute, from: $0) })
    }

    private func isDescendant(_ element: AXUIElement, of ancestor: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<12 {
            if CFEqual(current, ancestor) { return true }
            guard let parent = elementAttribute(kAXParentAttribute, from: current) else { return false }
            current = parent
        }
        return false
    }

    private func sendKeyboardShortcut(keyCode: CGKeyCode, flags: CGEventFlags,
                                      extraGuard: () -> Bool = { true }) -> Bool {
        guard Diagnostics.accessibilityTrusted(prompt: false), isCommandContextCurrent(), extraGuard(),
              let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: freePuntoSyntheticEventMarker)
        }
        guard isCommandContextCurrent(), extraGuard() else { return false }
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.02)
        up.post(tap: .cghidEventTap)
        return true
    }
}

let freePuntoSyntheticEventMarker: Int64 = 0x4652_5045

private enum KeyCode {
    static let a: CGKeyCode = 0
    static let c: CGKeyCode = 8
    static let v: CGKeyCode = 9
    static let f2: CGKeyCode = 120
    static let leftArrow: CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
    static let delete: CGKeyCode = 51
}

/// Доступ до pasteboard лише з головного потоку; зберігаються дані всіх оголошених типів.
private final class ClipboardSession {
    private let pasteboard: NSPasteboard
    private let snapshot: [[NSPasteboard.PasteboardType: Data]]
    private var ownership = ClipboardOwnership()

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
        snapshot = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        } ?? []
    }

    var isOwned: Bool { ownership.canRestore(currentChangeCount: pasteboard.changeCount) }

    func write(_ text: String) -> Bool {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.clearContents()
        ownership.recordOwnedWrite(changeCount: pasteboard.changeCount)
        let ok = pasteboard.writeObjects([item])
        ownership.recordOwnedWrite(changeCount: pasteboard.changeCount)
        return ok
    }

    func adoptVerifiedCopy(changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        ownership.recordOwnedWrite(changeCount: changeCount)
    }

    func restoreIfOwned() {
        guard isOwned else { return }
        let items = snapshot.map { data in
            let item = NSPasteboardItem()
            for (type, value) in data { item.setData(value, forType: type) }
            return item
        }
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}

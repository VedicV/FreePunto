import Foundation

// * -- Класифікатор середовища активного застосунку --
public enum AppEnvironmentClassifier {
    // * -- Тип активного застосунку --
    public enum AppKind: String, Equatable, Sendable {
        case standaloneTerminal
        case integratedTerminal
        case browser
        case codeEditor
        case other
    }

    // * -- Стратегія читання тексту --
    public enum ReadStrategy: String, Equatable, Sendable {
        case terminalSelectionOrPrompt
        case browserEditableCmdCFirst
        case browserSelectionCmdC
        case browserConfirmedGrid
        case codeEditorDirectAXFirst
        case otherApp
        case none
    }

    // * -- Строга маршрутизація стратегії читання --
    public static func determineReadStrategy(
        appKind: AppKind,
        hasAccessibility: Bool,
        isEditable: Bool,
        isConfirmedGrid: Bool
    ) -> ReadStrategy {
        // 0. Без Accessibility або в невідомому нередагованому контексті без прав повертаємо none (nil)
        guard hasAccessibility else { return .none }

        switch appKind {
        case .standaloneTerminal, .integratedTerminal:
            return .terminalSelectionOrPrompt

        case .browser:
            if isConfirmedGrid {
                return .browserConfirmedGrid
            } else if isEditable {
                return .browserEditableCmdCFirst
            } else {
                // Навіть статична вебсторінка може мати явне виділення, яке читається через Cmd+C.
                return .browserSelectionCmdC
            }

        case .codeEditor:
            return .codeEditorDirectAXFirst

        case .other:
            return .otherApp
        }
    }

    // * -- Перевірка, чи є контекст елемента підтвердженою таблицею/сіткою в браузері --
    public static func isConfirmedGridContext(
        role: String?,
        subrole: String? = nil,
        roleDescription: String? = nil,
        identifier: String? = nil,
        parentRole: String? = nil,
        parentDescription: String? = nil
    ) -> Bool {
        let gridKeywords = ["grid", "table", "cell", "sheet", "spreadsheet"]
        let fields = [role, subrole, roleDescription, identifier, parentRole, parentDescription]
            .compactMap { $0?.lowercased() }

        for field in fields {
            for kw in gridKeywords {
                if field.contains(kw) {
                    return true
                }
            }
        }
        return false
    }

    // * -- Ідентифікатори сімейства VS Code --
    private static let vscodeFamilyIdentifiers: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.microsoft.VSCodeExploration",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92",
        "com.google.antigravity",
        "com.google.antigravity-ide",
    ]

    /// Ідентичність одного AX-елемента. Навмисно не містить редаговане значення та назву вікна.
    public struct ElementIdentity: Equatable, Sendable {
        public var role: String?
        public var title: String?
        public var description: String?
        public var identifier: String?

        public init(role: String? = nil, title: String? = nil,
                    description: String? = nil, identifier: String? = nil) {
            self.role = role
            self.title = title
            self.description = description
            self.identifier = identifier
        }
    }

    private static let terminalPromptIndicators = ["$ ", "% ", "❯ ", "λ "]
    private static let shellNames: Set<String> = ["zsh", "bash", "fish", "sh", "tmux", "screen"]
    private static let terminalTokens: Set<String> = ["terminal", "xterm", "shell", "pty", "терминал", "термінал"]

    public static func isVSCodeFamily(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return vscodeFamilyIdentifiers.contains(bundleIdentifier)
    }

    /// Батьківські елементи впорядковані від найближчого. Пошук зупиняється на межі
    /// документа/редактора і не використовує назву вікна чи текст, схожий на промпт.
    public static func isIntegratedTerminal(
        role: String?, title: String?, description: String?, identifier: String?, value: String?,
        ancestors: [ElementIdentity] = []
    ) -> Bool {
        let focused = ElementIdentity(role: role, title: title, description: description, identifier: identifier)
        for element in [focused] + Array(ancestors.prefix(8)) {
            if element.role == "AXWindow" || element.role == "AXApplication" { break }
            let identity = [element.title, element.description, element.identifier]
                .compactMap { $0?.lowercased() }
            let tokens = Set(identity.flatMap { $0.components(separatedBy: CharacterSet.alphanumerics.inverted) })
            // Редактор та його пошук або чат не є терміналом у сусідній панелі.
            if element.role == "AXDocument" || !tokens.isDisjoint(with: ["editor", "document", "find", "search", "chat"]) {
                return false
            }
            // Назва файла або шлях на кшталт terminal.swift чи shell.md не визначає термінал.
            let scopedTitle = element.title.flatMap { title -> String? in
                title.contains(".") || title.contains("/") ? nil : title
            }
            let terminalIdentity = [scopedTitle, element.description, element.identifier]
                .compactMap { $0?.lowercased() }
            let terminalIdentityTokens = Set(terminalIdentity.flatMap {
                $0.components(separatedBy: CharacterSet.alphanumerics.inverted)
            })
            if !terminalIdentityTokens.isDisjoint(with: terminalTokens) { return true }
            if terminalIdentity.contains(where: { shellNames.contains($0) }) { return true }
        }
        return false
    }

    public static func classify(bundleIdentifier: String?, focusedElement: ElementIdentity,
                                ancestors: [ElementIdentity] = []) -> AppKind {
        appKind(bundleIdentifier: bundleIdentifier, isIntegratedTerminal: isIntegratedTerminal(
            role: focusedElement.role, title: focusedElement.title,
            description: focusedElement.description, identifier: focusedElement.identifier,
            value: nil, ancestors: ancestors))
    }

    public static func containsTerminalPrompt(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }

        // Промпти зі спеціальними символами стрілок/лямбди (Starship, Powerlevel10k, Oh-My-Zsh тощо)
        let specialSymbols = ["❯", "➜", "λ", "⚡"]
        for sym in specialSymbols {
            if line.contains(sym) { return true }
        }

        // Промпти на початку рядка: наприклад "$ ", "% ", "# "
        for ind in terminalPromptIndicators {
            if line.hasPrefix(ind) { return true }
        }

        // Промпти виду user@host:~$, user@host:~%, root@host:~# або (env) user@host:path$
        // Можуть знаходитися не на початку рядка (наприклад, після статусу або часу)
        if let atIdx = line.firstIndex(of: "@") {
            let afterAt = line[atIdx...]
            if let symIdx = afterAt.firstIndex(where: { $0 == "$" || $0 == "%" || $0 == "#" }) {
                let between = afterAt[afterAt.index(after: atIdx)..<symIdx]
                // У шелл-промпті між @ і $/%/# ім'я хоста, двокрапка, шлях/тильда (без лапок, дужок, крапок з комою, операторів)
                let forbiddenInHostPath: Set<Character> = ["\"", "'", ";", "(", ")", "{", "}", "=", "<", ">", ",", "\t", "[", "]"]
                if !between.contains(where: { forbiddenInHostPath.contains($0) }) {
                    let afterSym = afterAt[afterAt.index(after: symIdx)...]
                    if afterSym.isEmpty || afterSym.hasPrefix(" ") {
                        return true
                    }
                }
            }
        }

        // Промпти виду :~$ або :~% або ~ $
        if line.contains(":~$") || line.contains(":~%") || line.contains(":~#") ||
           line.contains("~ $") || line.contains("~ %") || line.contains("~ #") {
            return true
        }

        return false
    }

    // * -- Ідентифікатори автономних термінальних застосунків --
    private static let standaloneTerminalIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "io.alacritty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
    ]

    // * -- Перевірка, чи є застосунок автономним терміналом --
    public static func isStandaloneTerminal(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else {
            return false
        }

        return standaloneTerminalIdentifiers.contains(bundleIdentifier)
    }

    // * -- Ідентифікатори веб-браузерів --
    public static let browserBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "org.mozilla.firefoxnightly",
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
    ]

    private static let chromiumBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
    ]

    // * -- Перевірка, чи є застосунок веб-браузером --
    public static func isBrowser(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return browserBundleIdentifiers.contains(bundleIdentifier)
    }

    // * -- Chromium може не повертати AXSelectedText та AXSelectedTextRange у вебвмісті --
    public static func isChromium(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return chromiumBundleIdentifiers.contains(bundleIdentifier)
    }

    // Визначає вузький виняток для компонентів, які не повертають повний AXValue після paste.
    public static func allowsFocusedPasteVerification(
        bundleIdentifier: String?,
        isConfirmedEditorSurface: Bool,
        isCopiedBrowserSelection: Bool
    ) -> Bool {
        (isVSCodeFamily(bundleIdentifier: bundleIdentifier) && isConfirmedEditorSurface)
            || (isChromium(bundleIdentifier: bundleIdentifier) && isCopiedBrowserSelection)
    }

    // * -- Визначення типу застосунку за bundleIdentifier та контекстом елемента --
    public static func appKind(bundleIdentifier: String?, isIntegratedTerminal: Bool = false) -> AppKind {
        if isStandaloneTerminal(bundleIdentifier: bundleIdentifier) {
            return .standaloneTerminal
        }
        if isVSCodeFamily(bundleIdentifier: bundleIdentifier) {
            return isIntegratedTerminal ? .integratedTerminal : .codeEditor
        }
        if isBrowser(bundleIdentifier: bundleIdentifier) {
            return .browser
        }
        return .other
    }

    public struct TerminalPromptTarget: Equatable, Sendable {
        public let word: String
        public let backspaceCount: Int

        public init(word: String, backspaceCount: Int) {
            self.word = word
            self.backspaceCount = backspaceCount
        }
    }

    // Повертає ціль лише тоді, коли останній змістовний рядок схожий на активний промпт.
    public static func terminalPromptTarget(from axValue: String?) -> TerminalPromptTarget? {
        guard let word = terminalPromptLastWord(from: axValue) else { return nil }
        return TerminalPromptTarget(word: word, backspaceCount: word.count)
    }

    // Парсер навмисно відкидає вивід, порожній промпт і фрагменти оформлення промпту.
    public static func terminalPromptLastWord(from axValue: String?) -> String? {
        guard let axValue, !axValue.isEmpty, !axValue.contains("Screen Reader Accessibility") else {
            return nil
        }
        let lines = axValue.components(separatedBy: .newlines)
        guard let currentLine = lines.last(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return nil
        }
        guard containsTerminalPrompt(currentLine) else {
            return nil
        }

        // Перевіряємо, чи активний рядок не закінчується безпосередньо символом промпту
        let promptEndSymbols: Set<Character> = ["$", "%", ">", "❯", "λ", "#", "➜", "⚡"]
        let trimmedLine = currentLine.trimmingCharacters(in: .whitespaces)
        if let lastChar = trimmedLine.last, promptEndSymbols.contains(lastChar) {
            return nil
        }

        // Шукаємо межу промпту і введеної команди за стандартними розділювачами з пробілом після них
        let promptSeparators = [":~$ ", ":~% ", ":~# ", "$ ", "% ", "# ", "> ", "❯ ", "➜ ", "λ ", "⚡ "]
        var commandText = currentLine
        var foundSeparator = false
        for sep in promptSeparators {
            if let range = currentLine.range(of: sep, options: .backwards) {
                let candidate = String(currentLine[range.upperBound...])
                if !foundSeparator || candidate.count < commandText.count {
                    commandText = candidate
                    foundSeparator = true
                }
            }
        }

        if foundSeparator {
            let trimmedCmd = commandText.trimmingCharacters(in: .whitespaces)
            if trimmedCmd.isEmpty {
                return nil
            }
        }

        guard let wordResult = TextScanner.lastWord(in: commandText) else {
            return nil
        }
        let word = wordResult.word.trimmingCharacters(in: .whitespaces)
        if word.isEmpty {
            return nil
        }

        let promptSymbolsSet: Set<String> = ["$", "%", ">", "❯", "λ", "#", "➜", "⚡"]
        if promptSymbolsSet.contains(word) {
            return nil
        }

        // Відфільтровуємо фрагменти самого промпту (user@host, (main), git:(branch) тощо)
        if word.contains("@") && (word.contains(":") || word.contains("$") || word.contains("%")) {
            return nil
        }
        if (word.hasPrefix("(") && word.hasSuffix(")")) || word.hasPrefix("git:(") {
            return nil
        }
        if word.contains("❯") || word.contains("➜") || word.contains("λ") || word.contains("⚡") {
            return nil
        }

        return wordResult.word
    }

    // * -- Перевірка, чи підтримує застосунок AXSelectedTextRange для читання чи виділення --
    // * -- Для org.mozilla.firefox AXSelectedTextRange нестабільний і не повинен використовуватися --
    public static func isFirefox(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
                "org.mozilla.nightly", "org.mozilla.firefoxnightly"].contains(bundleIdentifier)
    }

    public static func supportsAXSelectedTextRange(bundleIdentifier: String?) -> Bool {
        !isFirefox(bundleIdentifier: bundleIdentifier)
    }

}

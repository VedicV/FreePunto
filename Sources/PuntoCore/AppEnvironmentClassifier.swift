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
        case terminalActiveLineAXValue
        case browserEditableCmdCFirst
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
            return .terminalActiveLineAXValue

        case .browser:
            if isEditable {
                return .browserEditableCmdCFirst
            } else if isConfirmedGrid {
                return .browserConfirmedGrid
            } else {
                // Звичайна веб-сторінка (non-editable, non-grid) повертає none (nil)
                return .none
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

    // * -- Ключові слова інтегрованого терміналу (загальні) --
    private static let generalTerminalKeywords = [
        "terminal",
        "xterm",
        "shell",
        "console",
        "command line",
        "pty",
        "терминал",
        "термінал"
    ]

    // * -- Ключові символи запросу командного рядка --
    private static let terminalPromptIndicators = [
        "$ ",
        "% ",
        "❯ ",
        "λ "
    ]

    // * -- Назви оболонок (тільки для властивостей елемента, не для заголовка вікна) --
    private static let shellNames = [
        "zsh",
        "bash",
        "fish",
        "sh",
        "tmux",
        "screen"
    ]

    // * -- Перевірка належності до сімейства VS Code --
    public static func isVSCodeFamily(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else {
            return false
        }

        return vscodeFamilyIdentifiers.contains(bundleIdentifier)
    }

    // * -- Перевірка, чи є елемент інтегрованим терміналом --
    public static func isIntegratedTerminal(
        role: String?,
        title: String?,
        description: String?,
        identifier: String?,
        value: String?
    ) -> Bool {
        // AXTextField у VS Code / Electron може бути полем xterm, але може бути і Find/чат.
        // Якщо це AXTextField без термінальних ключових слів в ідентифікаторах і без промпту, це редактор.
        if role == "AXTextField" {
            let fields = [title, description, identifier].compactMap { $0?.lowercased() }
            let hasTerminalIdentity = fields.contains { f in
                generalTerminalKeywords.contains { f.contains($0) } ||
                shellNames.contains { f.contains($0) }
            }
            if !hasTerminalIdentity && !(value.map(containsTerminalPrompt) ?? false) {
                return false
            }
        }

        // 1. Шукаємо термінальні ключові слова у властивостях самого елемента (не в довільному тексті коду!)
        let elementIdentityFields = [role, title, description, identifier]
            .compactMap { $0?.lowercased() }

        for field in elementIdentityFields {
            for kw in generalTerminalKeywords {
                if field.contains(kw) { return true }
            }
            // Назви оболонок шукаємо як окремі слова/токени (щоб 'English' не матчився на 'sh')
            let tokens = field.components(separatedBy: CharacterSet.alphanumerics.inverted)
            for shell in shellNames {
                if tokens.contains(shell) {
                    return true
                }
            }
        }

        // 2. Якщо в ідентифікаторах немає прямого збігу, перевіряємо промпт в останньому рядку,
        // якщо це не звичайний текстовий редактор/документ.
        let isEditor = elementIdentityFields.contains { $0.contains("editor") || $0.contains("document") }
        if !isEditor, let val = value, !val.isEmpty {
            let lastLine = val.components(separatedBy: .newlines)
                .last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
                .trimmingCharacters(in: .whitespaces) ?? ""

            if containsTerminalPrompt(lastLine) {
                return true
            }
        }

        return false
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

    // * -- Перевірка, чи є застосунок веб-браузером --
    public static func isBrowser(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return browserBundleIdentifiers.contains(bundleIdentifier)
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

    // * -- Витяг останнього слова з активного рядка промпту терміналу --
    // * -- Повертає nil, якщо буфер порожній, не містить промпту (output), або рядок містить лише символ промпту --
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
    public static func supportsAXSelectedTextRange(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return true }
        if bundleIdentifier == "org.mozilla.firefox" {
            return false
        }
        return true
    }

    // * -- План синтетичних дій для заміни останнього слова в інтегрованому терміналі --
    // * -- Рівно wordLength разів Backspace, потім Cmd+V (без Ctrl+W та Cmd+C) --
    public static func integratedTerminalReplacementPlan(wordLength: Int, replacement: String) -> [SyntheticKeyAction] {
        guard wordLength > 0 else { return [] }
        return [
            .backspace(count: wordLength),
            .cmdV(text: replacement)
        ]
    }

}

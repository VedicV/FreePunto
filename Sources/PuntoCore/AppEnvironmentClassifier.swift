// * -- Класифікатор середовища активного застосунку --
public enum AppEnvironmentClassifier {
    // * -- Ідентифікатори сімейства VS Code --
    private static let vscodeFamilyIdentifiers: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.microsoft.VSCodeExploration",
        "com.vscodium",
        "com.google.antigravity",
        "com.google.antigravity-ide",
    ]

    // * -- Ключові слова інтегрованого терміналу --
    private static let integratedTerminalKeywords = [
        "terminal",
        "shell",
        "console",
        "command line",
        "pty",
        "$",
        "%",
        ">",
        "❯",
        "λ",
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
        windowTitle: String?,
        value: String?
    ) -> Bool {
        // Збираємо всі можливі властивості для пошуку ключових слів терміналу.
        let candidates = [title, description, identifier, windowTitle, value]
            .compactMap { $0?.lowercased() }

        // Якщо хоч один рядок містить ключове слово, вважаємо це терміналом.
        return candidates.contains { candidate in
            integratedTerminalKeywords.contains { keyword in
                candidate.contains(keyword)
            }
        }
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

    // * -- Підказки для визначення CanvasTable у заголовку вікна --
    private static let canvasTableTitleHints = [
        "canvastable",
        "canvas table",
    ]

    // * -- Перевірка, чи є вікно застосунком CanvasTable --
    public static func isCanvasTableApp(windowTitle: String?) -> Bool {
        guard let title = windowTitle?.lowercased() else {
            return false
        }

        return canvasTableTitleHints.contains { title.contains($0) }
    }

    // * -- Підказки для визначення Google Sheets у заголовку вікна --
    private static let googleSheetsTitleHints = [
        "google sheets",
        "google таблицы",
        "google таблиці",
        "таблицы google",
        "таблиці google",
    ]

    // * -- Перевірка, чи є вікно Google Sheets --
    public static func isGoogleSheetsWindow(windowTitle: String?) -> Bool {
        guard let title = windowTitle?.lowercased() else {
            return false
        }

        return googleSheetsTitleHints.contains { title.contains($0) }
    }
}

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

    // * -- Ключові слова інтегрованого терміналу (загальні) --
    private static let generalTerminalKeywords = [
        "terminal",
        "shell",
        "console",
        "command line",
        "pty",
        "терминал",
        "термінал"
    ]

    // * -- Ключові символи запросу командного рядка --
    private static let terminalPromptIndicators = [
        "$",
        "%",
        ">",
        "❯",
        "λ"
    ]

    // * -- Назви оболонок (тільки для властивостей елемента, не для заголовка вікна) --
    private static let shellNames = [
        "zsh",
        "bash",
        "fish",
        "sh",
        "tmux",
        "screen",
        "node",
        "npm",
        "yarn",
        "python",
        "ruby"
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
        // 1. Шукаємо загальні термінальні слова у властивостях element і значенні.
        // Заголовок вікна не є надійним сигналом: він часто містить назви файлів або вкладок.
        let allFields = [role, title, description, identifier, value]
            .compactMap { $0?.lowercased() }

        for field in allFields {
            for kw in generalTerminalKeywords {
                if field.contains(kw) { return true }
            }
        }

        // 2. Шукаємо символи промпту в значенні елемента.
        if let val = value?.lowercased() {
            for ind in terminalPromptIndicators {
                if val.contains(ind) { return true }
            }
        }

        // 3. Шукаємо назви оболонок тільки у властивостях самого елемента (ігноруючи заголовок вікна).
        let elementProps = [role, title, description, identifier]
            .compactMap { $0?.lowercased() }

        for prop in elementProps {
            for shell in shellNames {
                if prop == shell || prop.contains(" " + shell) || prop.contains(shell + " ") {
                    return true
                }
            }
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

}

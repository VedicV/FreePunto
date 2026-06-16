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
}

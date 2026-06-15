import Foundation

// * -- Преобразование регистра --
public enum CaseTransformer {
    // * -- Выбор режима регистра --
    public static func transform(_ text: String, mode: CaseMode) -> String {
        switch mode {
        case .lower:
            return text.lowercased()
        case .sentence:
            return sentenceCase(text)
        case .title:
            return titleCase(text)
        case .normalizeCapsLock:
            return text.lowercased()
        }
    }

    // Новое предложение начинается после `.`, `!` или `?`, пробелы и пунктуация сохраняются.
    private static func sentenceCase(_ text: String) -> String {
        var result = ""
        var shouldCapitalize = true

        for character in text {
            let value = String(character)

            if isLetter(character) {
                if shouldCapitalize {
                    result += value.uppercased()
                    shouldCapitalize = false
                } else {
                    result += value.lowercased()
                }
                continue
            }

            result += value
            if ".!?".contains(character) {
                shouldCapitalize = true
            }
        }

        return result
    }

    // Апостроф не начинает новое слово, чтобы английские сокращения выглядели естественно.
    private static func titleCase(_ text: String) -> String {
        var result = ""
        var atWordStart = true

        for character in text {
            let value = String(character)
            if isLetter(character) {
                if atWordStart {
                    result += value.uppercased()
                    atWordStart = false
                } else {
                    result += value.lowercased()
                }
            } else {
                result += value
                atWordStart = !isApostrophe(character)
            }
        }

        return result
    }

    private static func isLetter(_ character: Character) -> Bool {
        String(character).rangeOfCharacter(from: .letters) != nil
    }

    private static func isApostrophe(_ character: Character) -> Bool {
        character == "'" || character == "’"
    }
}

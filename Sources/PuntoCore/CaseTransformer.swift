import Foundation

// * -- Перетворення регістру --
public enum CaseTransformer {
    // * -- Вибір режиму регістру --
    public static func transform(_ text: String, mode: CaseMode) -> String {
        switch mode {
        case .lower:
            return text.lowercased()
        case .sentence:
            return sentenceCase(text)
        case .title:
            return titleCase(text)
        case .normalizeCapsLock:
            return swapCase(text)
        }
    }

    // Нове речення починається після `.`, `!` або `?`, пробіли й пунктуація зберігаються.
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

    // Апостроф не починає нове слово, щоб англійські скорочення виглядали природно.
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

    private static func swapCase(_ text: String) -> String {
        return text.map { character in
            let value = String(character)
            if value == value.uppercased() {
                return value.lowercased()
            } else {
                return value.uppercased()
            }
        }.joined()
    }
}

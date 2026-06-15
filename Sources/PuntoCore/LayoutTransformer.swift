import Foundation

// * -- Преобразование раскладки через физические клавиши --
public enum LayoutTransformer {
    private static let englishToRussian: [String: String] = [
        "`": "ё",
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н",
        "u": "г", "i": "ш", "o": "щ", "p": "з", "[": "х", "]": "ъ",
        "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р",
        "j": "о", "k": "л", "l": "д", ";": "ж", "'": "э",
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т",
        "m": "ь", ",": "б", ".": "ю"
    ]

    private static let englishToUkrainian: [String: String] = [
        "`": "ґ",
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н",
        "u": "г", "i": "ш", "o": "щ", "p": "з", "[": "х", "]": "ї",
        "a": "ф", "s": "і", "d": "в", "f": "а", "g": "п", "h": "р",
        "j": "о", "k": "л", "l": "д", ";": "ж", "'": "є",
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т",
        "m": "ь", ",": "б", ".": "ю"
    ]

    private static let russianToEnglish = Dictionary(uniqueKeysWithValues: englishToRussian.map { ($0.value, $0.key) })
    private static let ukrainianToEnglish = Dictionary(uniqueKeysWithValues: englishToUkrainian.map { ($0.value, $0.key) })

    // * -- Преобразование текста между раскладками --
    public static func transform(_ text: String, from source: PuntoLanguage, to target: PuntoLanguage) -> String {
        guard source != target else {
            return text
        }

        return text.map { character in
            transform(character, from: source, to: target)
        }.joined()
    }

    // Каждый символ сначала приводится к общей EN-клавише, затем переводится в целевую раскладку.
    private static func transform(_ character: Character, from source: PuntoLanguage, to target: PuntoLanguage) -> String {
        let original = String(character)
        let lower = original.lowercased()

        guard let englishKey = englishKey(for: lower, source: source),
              let replacement = replacement(for: englishKey, target: target) else {
            return original
        }

        return preserveLetterCase(from: original, replacement: replacement)
    }

    private static func englishKey(for lowerCharacter: String, source: PuntoLanguage) -> String? {
        switch source {
        case .english:
            return lowerCharacter
        case .russian:
            return russianToEnglish[lowerCharacter]
        case .ukrainian:
            return ukrainianToEnglish[lowerCharacter]
        }
    }

    private static func replacement(for englishKey: String, target: PuntoLanguage) -> String? {
        switch target {
        case .english:
            return englishKey
        case .russian:
            return englishToRussian[englishKey]
        case .ukrainian:
            return englishToUkrainian[englishKey]
        }
    }

    // Сохраняем регистр символа, но не трогаем пробелы, пунктуацию и неизвестные символы.
    private static func preserveLetterCase(from original: String, replacement: String) -> String {
        guard original != original.lowercased() else {
            return replacement
        }

        if original == original.uppercased() {
            return replacement.uppercased()
        }

        let first = replacement.prefix(1).uppercased()
        let rest = replacement.dropFirst().lowercased()
        return first + rest
    }
}

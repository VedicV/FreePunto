import Foundation

// * -- Фонетическая транслитерация --
public enum Transliterator {
    private static let russianToLatin: [String: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo",
        "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
        "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
        "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch",
        "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
    ]

    private static let ukrainianToLatin: [String: String] = [
        "а": "a", "б": "b", "в": "v", "г": "h", "ґ": "g", "д": "d", "е": "e",
        "є": "ye", "ж": "zh", "з": "z", "и": "y", "і": "i", "ї": "yi", "й": "y",
        "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r",
        "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts",
        "ч": "ch", "ш": "sh", "щ": "sch", "ь": "", "ю": "yu", "я": "ya",
    ]

    private static let latinToRussian: [(String, String)] = [
        ("shch", "щ"), ("sch", "щ"), ("yo", "ё"), ("yu", "ю"), ("ya", "я"),
        ("ye", "е"), ("zh", "ж"), ("kh", "х"), ("ts", "ц"), ("ch", "ч"),
        ("sh", "ш"), ("a", "а"), ("b", "б"), ("v", "в"), ("g", "г"),
        ("d", "д"), ("e", "е"), ("z", "з"), ("i", "и"), ("j", "й"),
        ("y", "й"), ("k", "к"), ("l", "л"), ("m", "м"), ("n", "н"),
        ("o", "о"), ("p", "п"), ("r", "р"), ("s", "с"), ("t", "т"),
        ("u", "у"), ("f", "ф"), ("h", "х"), ("c", "к"),
    ]

    private static let latinToUkrainian: [(String, String)] = [
        ("shch", "щ"), ("sch", "щ"), ("yi", "ї"), ("ye", "є"), ("yu", "ю"),
        ("ya", "я"), ("zh", "ж"), ("kh", "х"), ("ts", "ц"), ("ch", "ч"),
        ("sh", "ш"), ("a", "а"), ("b", "б"), ("v", "в"), ("h", "г"),
        ("g", "ґ"), ("d", "д"), ("e", "е"), ("z", "з"), ("i", "і"),
        ("j", "й"), ("y", "й"), ("k", "к"), ("l", "л"), ("m", "м"),
        ("n", "н"), ("o", "о"), ("p", "п"), ("r", "р"), ("s", "с"),
        ("t", "т"), ("u", "у"), ("f", "ф"), ("c", "к"),
    ]

    // * -- Выбор направления транслитерации --
    public static func transliterate(_ text: String, targetLanguage: PuntoLanguage)
        -> TransformationResult
    {
        if LanguageDetector.containsCyrillic(text) {
            let source = detectCyrillicSourceLanguage(text, fallback: targetLanguage)
            let replacement = cyrillicToLatin(text, sourceLanguage: source)
            return TransformationResult(
                command: .transliteration,
                originalText: text,
                replacementText: replacement,
                sourceLanguage: source,
                targetLanguage: .english
            )
        }

        let target = targetLanguage == .ukrainian ? PuntoLanguage.ukrainian : .russian
        let replacement = latinToCyrillic(text, targetLanguage: target)
        return TransformationResult(
            command: .transliteration,
            originalText: text,
            replacementText: replacement,
            sourceLanguage: .english,
            targetLanguage: target
        )
    }

    // Кириллицу можно обрабатывать посимвольно: каждая буква имеет самостоятельную латинскую замену.
    private static func cyrillicToLatin(_ text: String, sourceLanguage: PuntoLanguage) -> String {
        let table = sourceLanguage == .ukrainian ? ukrainianToLatin : russianToLatin
        return text.map { character in
            let original = String(character)
            let lower = original.lowercased()
            guard let mapped = table[lower] else {
                return original
            }
            return preserveCase(from: original, replacement: mapped)
        }.joined()
    }

    // Латиницу читаем самым длинным совпадением, чтобы `shch` не распалось на `sh` + `ch`.
    private static func latinToCyrillic(_ text: String, targetLanguage: PuntoLanguage) -> String {
        let table = targetLanguage == .ukrainian ? latinToUkrainian : latinToRussian
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            let remaining = String(text[index...])
            let lowerRemaining = remaining.lowercased()
            var matched: (latin: String, cyrillic: String)?

            for pair in table where lowerRemaining.hasPrefix(pair.0) {
                matched = pair
                break
            }

            guard let matched else {
                result += String(text[index])
                index = text.index(after: index)
                continue
            }

            let latinEnd = text.index(index, offsetBy: matched.latin.count)
            let originalChunk = String(text[index..<latinEnd])
            result += preserveCase(from: originalChunk, replacement: matched.cyrillic)
            index = latinEnd
        }

        return result
    }

    // Для смешанного текста даем приоритет буквам, характерным для конкретного языка.
    private static func detectCyrillicSourceLanguage(_ text: String, fallback: PuntoLanguage)
        -> PuntoLanguage
    {
        if containsAny(text, from: "іїєґІЇЄҐ") {
            return .ukrainian
        }

        if containsAny(text, from: "ёъыэЁЪЫЭ") {
            return .russian
        }

        let normalizedFallback: PuntoLanguage = fallback == .ukrainian ? .ukrainian : .russian
        let detected = LanguageDetector.detect(text, fallback: normalizedFallback)
        return detected == .english ? normalizedFallback : detected
    }

    private static func containsAny(_ text: String, from characters: String) -> Bool {
        let charset = Set(characters.unicodeScalars)
        return text.unicodeScalars.contains(where: { charset.contains($0) })
    }

    // Регистр переносится с исходного фрагмента на замену, включая многобуквенные сочетания.
    private static func preserveCase(from original: String, replacement: String) -> String {
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

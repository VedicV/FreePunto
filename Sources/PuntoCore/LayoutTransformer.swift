import Foundation

// * -- Перетворення розкладки через фізичні клавіші та системний UCKeyTranslate --
public enum LayoutTransformer {
    // Повні статичні таблиці маппінгу символів (клавіша за клавішею, включно з Shift, <, >, пунктуацією)
    private static let englishToUkrainianStatic: [Character: Character] = [
        // Нижній регістр
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ї", "a": "ф", "s": "і", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
        "l": "д", ";": "ж", "'": "є", "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
        ",": "б", ".": "ю", "/": ".", "`": "ґ", "\\": "ʼ",

        // Верхній регістр (літери)
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ї", "A": "Ф", "S": "І", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л",
        "L": "Д", ":": "Ж", "\"": "Є", "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь",
        "<": "Б", ">": "Ю", "?": ",", "~": "Ґ", "|": "₴",

        // Shift + Цифровий ряд
        "@": "\"", "#": "№", "$": ";", "^": ":", "&": "?",
    ]

    private static let englishToRussianStatic: [Character: Character] = [
        // Нижній регістр
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ъ", "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
        "l": "д", ";": "ж", "'": "э", "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
        ",": "б", ".": "ю", "/": ".", "`": "ё", "\\": "\\",

        // Верхній регістр (літери)
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ъ", "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л",
        "L": "Д", ":": "Ж", "\"": "Э", "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь",
        "<": "Б", ">": "Ю", "?": ",", "~": "Ё", "|": "/",

        // Shift + Цифровий ряд
        "@": "\"", "#": "№", "$": ";", "^": ":", "&": "?",
    ]

    private static let ukrainianToEnglishStatic: [Character: Character] = {
        var dict: [Character: Character] = [:]
        for (k, v) in englishToUkrainianStatic {
            dict[v] = k
        }
        return dict
    }()

    private static let russianToEnglishStatic: [Character: Character] = {
        var dict: [Character: Character] = [:]
        for (k, v) in englishToRussianStatic {
            dict[v] = k
        }
        return dict
    }()

    // Прямий переклад між кириличними розкладками UA <-> RU (клавіші з різними літерами)
    private static let ukrainianToRussianStatic: [Character: Character] = [
        "і": "ы", "І": "Ы",
        "ї": "ъ", "Ї": "Ъ",
        "є": "э", "Є": "Э",
        "ґ": "ё", "Ґ": "Ё",
        "ʼ": "\\", "₴": "/"
    ]

    private static let russianToUkrainianStatic: [Character: Character] = [
        "ы": "і", "Ы": "І",
        "ъ": "ї", "Ъ": "Ї",
        "э": "є", "Э": "Є",
        "ё": "ґ", "Ё": "Ґ",
        "\\": "ʼ", "/": "₴"
    ]

    // * -- Перетворення тексту між розкладками --
    public static func transform(_ text: String, from source: PuntoLanguage, to target: PuntoLanguage) -> String {
        guard source != target else {
            return text
        }

        // Обробка трикрапки наприкінці (зберігаємо '...', якщо це очевидна пунктуаційна крапка)
        if (source == .english && (target == .russian || target == .ukrainian)) {
            let dotsCount = text.reversed().prefix(while: { $0 == "." }).count
            if dotsCount >= 2 {
                let prefix = text.dropLast(dotsCount)
                let suffix = text.suffix(dotsCount)
                let transformedPrefix = prefix.map { character in
                    transformSingleCharacter(character, from: source, to: target)
                }
                return String(transformedPrefix) + String(suffix)
            }
        }

        let transformed = text.map { character in
            transformSingleCharacter(character, from: source, to: target)
        }
        return String(transformed)
    }

    // * -- Перетворення одного символу --
    public static func transformSingleCharacter(_ character: Character, from source: PuntoLanguage, to target: PuntoLanguage) -> Character {
        guard source != target else { return character }

        // 1. Спочатку пробуємо динамічний системний маппер UCKeyTranslate
        if let dynamicChar = DynamicLayoutMapper.shared.translateCharacter(character, from: source, to: target) {
            return dynamicChar
        }

        // 2. Статичний fallback для прямого перетворення
        switch (source, target) {
        case (.english, .ukrainian):
            return englishToUkrainianStatic[character] ?? character
        case (.english, .russian):
            return englishToRussianStatic[character] ?? character
        case (.ukrainian, .english):
            return ukrainianToEnglishStatic[character] ?? russianToEnglishStatic[character] ?? character
        case (.russian, .english):
            return russianToEnglishStatic[character] ?? ukrainianToEnglishStatic[character] ?? character
        case (.ukrainian, .russian):
            return ukrainianToRussianStatic[character] ?? character
        case (.russian, .ukrainian):
            return russianToUkrainianStatic[character] ?? character
        default:
            return character
        }
    }
}

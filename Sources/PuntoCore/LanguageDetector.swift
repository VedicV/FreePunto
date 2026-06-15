import Foundation

// * -- Просте визначення мови фрагмента --
public enum LanguageDetector {
    // * -- Вибір домінантної писемності --
    public static func detect(_ text: String, fallback: PuntoLanguage = .english) -> PuntoLanguage {
        var latin = 0
        var cyrillic = 0
        var ukrainianSpecific = 0
        var russianSpecific = 0

        for scalar in text.unicodeScalars {
            if isLatin(scalar) {
                latin += 1
            } else if isCyrillic(scalar) {
                cyrillic += 1
                if isUkrainianSpecific(scalar) {
                    ukrainianSpecific += 2
                }
                if isRussianSpecific(scalar) {
                    russianSpecific += 1
                }
            }
        }

        if latin == 0 && cyrillic == 0 {
            return fallback
        }

        if latin >= cyrillic {
            return .english
        }

        if ukrainianSpecific > russianSpecific {
            return .ukrainian
        }

        return .russian
    }

    // * -- Швидка перевірка напряму транслітерації --
    public static func containsCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isCyrillic)
    }

    private static func isLatin(_ scalar: UnicodeScalar) -> Bool {
        (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    private static func isCyrillic(_ scalar: UnicodeScalar) -> Bool {
        (0x0400...0x052F).contains(Int(scalar.value))
    }

    private static func isUkrainianSpecific(_ scalar: UnicodeScalar) -> Bool {
        "іїєґІЇЄҐ".unicodeScalars.contains(scalar)
    }

    private static func isRussianSpecific(_ scalar: UnicodeScalar) -> Bool {
        "ёъыэЁЪЫЭ".unicodeScalars.contains(scalar)
    }
}

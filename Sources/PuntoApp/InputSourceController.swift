import Carbon
import Foundation
import PuntoCore

// * -- Перемикання системної розкладки macOS --
final class InputSourceController {
    private struct InputSourceCandidate {
        let source: TISInputSource
        let score: Int
    }

    // * -- Вибір розкладки для мови результату --
    @discardableResult
    func selectInputSource(for language: PuntoLanguage) -> Bool {
        guard let source = findInputSource(for: language) else {
            return false
        }

        return TISSelectInputSource(source) == noErr
    }

    // * -- Отримання поточної активної мови клавіатури --
    func currentLanguage() -> PuntoLanguage? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        for lang in PuntoLanguage.allCases {
            if sourceMatchScore(current, language: lang) != nil {
                return lang
            }
        }
        return nil
    }

    // * -- Отримання списку активних мов --
    func activeLanguages() -> [PuntoLanguage] {
        guard let categoryKey = kTISPropertyInputSourceCategory,
            let keyboardCategory = kTISCategoryKeyboardInputSource
        else {
            return PuntoLanguage.allCases
        }

        let conditions = NSDictionary(
            object: keyboardCategory as String as NSString,
            forKey: categoryKey as String as NSString
        )

        guard let unmanagedList = TISCreateInputSourceList(conditions, false) else {
            return PuntoLanguage.allCases
        }

        let list = unmanagedList.takeRetainedValue() as NSArray
        var active: Set<PuntoLanguage> = []

        for item in list {
            let cfItem = item as CFTypeRef
            guard CFGetTypeID(cfItem) == TISInputSourceGetTypeID() else {
                continue
            }

            let source = unsafeBitCast(cfItem, to: TISInputSource.self)
            guard sourceIsSelectable(source) else {
                continue
            }

            for lang in PuntoLanguage.allCases {
                if sourceMatchScore(source, language: lang) != nil {
                    active.insert(lang)
                }
            }
        }

        let result = PuntoLanguage.allCases.filter { active.contains($0) }
        return result.isEmpty ? PuntoLanguage.allCases : result
    }

    // Шукаємо selectable keyboard input source за мовним кодом або назвою розкладки.
    private func findInputSource(for language: PuntoLanguage) -> TISInputSource? {
        guard let categoryKey = kTISPropertyInputSourceCategory,
            let keyboardCategory = kTISCategoryKeyboardInputSource
        else {
            return nil
        }

        let conditions = NSDictionary(
            object: keyboardCategory as String as NSString,
            forKey: categoryKey as String as NSString
        )

        guard let unmanagedList = TISCreateInputSourceList(conditions, false) else {
            return nil
        }

        let list = unmanagedList.takeRetainedValue() as NSArray
        var candidates: [InputSourceCandidate] = []
        for item in list {
            let cfItem = item as CFTypeRef
            guard CFGetTypeID(cfItem) == TISInputSourceGetTypeID() else {
                continue
            }

            let source = unsafeBitCast(cfItem, to: TISInputSource.self)
            guard sourceIsSelectable(source),
                let score = sourceMatchScore(source, language: language)
            else {
                continue
            }
            candidates.append(InputSourceCandidate(source: source, score: score))
        }

        return candidates.min { lhs, rhs in lhs.score < rhs.score }?.source
    }

    // Відкидаємо джерела, які не можна вибрати.
    private func sourceIsSelectable(_ source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable)
        else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }

    // Порівнюємо input source з PuntoLanguage і вибираємо найточніший збіг.
    private func sourceMatchScore(_ source: TISInputSource, language: PuntoLanguage) -> Int? {
        let nameScore = sourceNameMatchScore(source, language: language)
        let languageScore = sourceLanguageMatches(source, language: language) ? 20 : nil

        switch (nameScore, languageScore) {
        case let (.some(nameScore), .some(languageScore)):
            return min(nameScore, languageScore)
        case let (.some(score), .none), let (.none, .some(score)):
            return score
        case (.none, .none):
            return nil
        }
    }

    // Перевіряємо, чи збігається мова input source з мовою PuntoLanguage.
    private func sourceLanguageMatches(_ source: TISInputSource, language: PuntoLanguage) -> Bool {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return false
        }

        let languages = Unmanaged<CFArray>.fromOpaque(value).takeUnretainedValue() as NSArray
        for entry in languages {
            guard let code = entry as? String else {
                continue
            }
            if code == language.inputSourceLanguageCode
                || code.hasPrefix(language.inputSourceLanguageCode + "-")
            {
                return true
            }
        }
        return false
    }

    // Перевіряємо, чи збігається назва input source з мовою PuntoLanguage.
    private func sourceNameMatchScore(_ source: TISInputSource, language: PuntoLanguage) -> Int? {
        let identifier = stringProperty(kTISPropertyInputSourceID, from: source)?.lowercased()
        let localizedName = stringProperty(kTISPropertyLocalizedName, from: source)?.lowercased()
        let values = [identifier, localizedName].compactMap { $0 }

        for value in values {
            if language.preferredInputSourceIDs.contains(value) {
                return 0
            }
        }

        for value in values {
            if language.inputSourceNameHints.contains(where: { value.contains($0) }) {
                return 10
            }
        }

        return nil
    }

    // Отримуємо рядкове значення властивості input source.
    private func stringProperty(_ property: CFString, from source: TISInputSource) -> String? {
        guard let value = TISGetInputSourceProperty(source, property) else {
            return nil
        }
        return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue() as? String
    }
}

// * -- Розширення для отримання пріоритетних ідентифікаторів та підказок назв розкладок для кожної мови --
private extension PuntoLanguage {
    var preferredInputSourceIDs: Set<String> {
        switch self {
        case .english:
            return [
                "com.apple.keylayout.abc",
                "com.apple.keylayout.us",
            ]
        case .russian:
            return [
                "com.apple.keylayout.russian",
                "com.apple.keylayout.russian-pc",
                "com.apple.keylayout.russianwin",
            ]
        case .ukrainian:
            return [
                "com.apple.keylayout.ukrainian",
                "com.apple.keylayout.ukrainian-pc",
            ]
        }
    }

    var inputSourceNameHints: [String] {
        switch self {
        case .english:
            return ["abc", "english", "u.s."]
        case .russian:
            return ["russian", "ru-"]
        case .ukrainian:
            return ["ukrainian", "uk-"]
        }
    }
}

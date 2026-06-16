import Carbon
import Foundation
import PuntoCore

// * -- Перемикання системної розкладки macOS --
final class InputSourceController {
    // * -- Вибір розкладки для мови результату --
    @discardableResult
    func selectInputSource(for language: PuntoLanguage) -> Bool {
        guard let source = findInputSource(for: language) else {
            return false
        }

        return TISSelectInputSource(source) == noErr
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
        for item in list {
            let cfItem = item as CFTypeRef
            guard CFGetTypeID(cfItem) == TISInputSourceGetTypeID() else {
                continue
            }

            let source = unsafeBitCast(cfItem, to: TISInputSource.self)
            guard sourceIsSelectable(source),
                sourceMatches(source, language: language)
            else {
                continue
            }
            return source
        }

        return nil
    }

    // Відкидаємо джерела, які не можна вибрати.
    private func sourceIsSelectable(_ source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable)
        else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }

    // Порівнюємо мови input source з кодом PuntoLanguage.
    private func sourceMatches(_ source: TISInputSource, language: PuntoLanguage) -> Bool {
        if sourceLanguageMatches(source, language: language) {
            return true
        }

        return sourceNameMatches(source, language: language)
    }

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

    private func sourceNameMatches(_ source: TISInputSource, language: PuntoLanguage) -> Bool {
        let values = [
            stringProperty(kTISPropertyInputSourceID, from: source),
            stringProperty(kTISPropertyLocalizedName, from: source),
        ].compactMap { $0?.lowercased() }

        return values.contains { value in
            switch language {
            case .english:
                return value.contains("abc") || value.contains("us") || value.contains("english")
            case .russian:
                return value.contains("russian") || value.contains("ru-") || value.contains(".ru")
            case .ukrainian:
                return value.contains("ukrainian") || value.contains("uk-") || value.contains(".uk")
            }
        }
    }

    private func stringProperty(_ property: CFString, from source: TISInputSource) -> String? {
        guard let value = TISGetInputSourceProperty(source, property) else {
            return nil
        }
        return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue() as? String
    }
}

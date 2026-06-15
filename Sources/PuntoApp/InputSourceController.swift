import Carbon
import Foundation
import PuntoCore

// * -- Переключение системной раскладки macOS --
final class InputSourceController {
    // * -- Выбор раскладки для языка результата --
    @discardableResult
    func selectInputSource(for language: PuntoLanguage) -> Bool {
        guard let source = findInputSource(for: language) else {
            return false
        }

        return TISSelectInputSource(source) == noErr
    }

    // Ищем selectable keyboard input source по языковому коду.
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

    // Отбрасываем источники, которые нельзя выбрать.
    private func sourceIsSelectable(_ source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable)
        else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }

    // Сравниваем языки input source с кодом PuntoLanguage.
    private func sourceMatches(_ source: TISInputSource, language: PuntoLanguage) -> Bool {
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
}

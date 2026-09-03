import Carbon
import Foundation

// * -- Динамічний маппер розкладок клавіатури через системний UCKeyTranslate --
public final class DynamicLayoutMapper: @unchecked Sendable {
    public static let shared = DynamicLayoutMapper()

    // Кешовані таблиці трансляції: [SourceLang: [TargetLang: [Character: Character]]]
    private var translationTables: [PuntoLanguage: [PuntoLanguage: [Character: Character]]] = [:]
    private let lock = NSLock()

    public init() {
        refreshTables()
    }

    // * -- Оновлення таблиць на основі поточних системних розкладок --
    public func refreshTables() {
        lock.lock()
        defer { lock.unlock() }

        var tables: [PuntoLanguage: [PuntoLanguage: [Character: Character]]] = [:]

        // Отримуємо TIS розкладки для підтримуваних мов
        let layoutSources = findLayoutSources()

        var keyLayouts: [PuntoLanguage: [UInt32: Character]] = [:]
        for (lang, source) in layoutSources {
            if let data = layoutData(from: source) {
                keyLayouts[lang] = buildKeyToCharTable(from: data)
            }
        }

        // Для кожної пари мов будуємо пряму таблицю заміни
        let allLangs = PuntoLanguage.allCases
        for sourceLang in allLangs {
            tables[sourceLang] = [:]
            guard let sourceTable = keyLayouts[sourceLang] else { continue }

            // Інвертуємо таблицю джерела: Character -> KeyIdentifier (keyCode + shift)
            var charToKey: [Character: UInt32] = [:]
            for (keyId, ch) in sourceTable {
                charToKey[ch] = keyId
            }

            for targetLang in allLangs where targetLang != sourceLang {
                guard let targetTable = keyLayouts[targetLang] else { continue }

                var mapping: [Character: Character] = [:]
                for (ch, keyId) in charToKey {
                    if let targetCh = targetTable[keyId] {
                        mapping[ch] = targetCh
                    }
                }
                tables[sourceLang]?[targetLang] = mapping
            }
        }

        self.translationTables = tables
    }

    // * -- Отримання заміни для одного символу --
    public func translateCharacter(_ character: Character, from source: PuntoLanguage, to target: PuntoLanguage) -> Character? {
        lock.lock()
        let charMap = translationTables[source]?[target]
        lock.unlock()

        return charMap?[character]
    }

    // * -- Пошук активних TIS-розкладок для мов --
    private func findLayoutSources() -> [PuntoLanguage: TISInputSource] {
        guard let categoryKey = kTISPropertyInputSourceCategory,
              let keyboardCategory = kTISCategoryKeyboardInputSource else {
            return [:]
        }

        let conditions = NSDictionary(
            object: keyboardCategory as String as NSString,
            forKey: categoryKey as String as NSString
        )

        guard let unmanagedList = TISCreateInputSourceList(conditions, false) else {
            return [:]
        }

        let list = unmanagedList.takeRetainedValue() as NSArray
        var result: [PuntoLanguage: TISInputSource] = [:]

        // Збираємо selectable розкладки
        var candidates: [(source: TISInputSource, id: String, langCodes: [String])] = []
        for item in list {
            let cfItem = item as CFTypeRef
            guard CFGetTypeID(cfItem) == TISInputSourceGetTypeID() else { continue }
            let source = unsafeBitCast(cfItem, to: TISInputSource.self)

            guard isSelectCapable(source) else { continue }

            let id = sourcePropertyString(source, key: kTISPropertyInputSourceID) ?? ""
            let langs = sourcePropertyStringArray(source, key: kTISPropertyInputSourceLanguages) ?? []
            candidates.append((source, id, langs))
        }

        for lang in PuntoLanguage.allCases {
            // Шукаємо розкладку за пріоритетом
            if let best = findBestSource(for: lang, in: candidates) {
                result[lang] = best
            }
        }

        return result
    }

    private func findBestSource(for lang: PuntoLanguage, in candidates: [(source: TISInputSource, id: String, langCodes: [String])]) -> TISInputSource? {
        // 1. Точний збіг ID розкладки (найкращі типові розкладки на Mac)
        let preferredIds: [String]
        switch lang {
        case .english:
            preferredIds = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
        case .ukrainian:
            // Пріоритет: Ukrainian-PC (популярна на Mac), потім Ukrainian standard
            preferredIds = ["com.apple.keylayout.Ukrainian-PC", "com.apple.keylayout.Ukrainian", "com.apple.keylayout.Ukrainian-Legacy"]
        case .russian:
            preferredIds = ["com.apple.keylayout.RussianWin", "com.apple.keylayout.Russian", "com.apple.keylayout.Russian-Typographic"]
        }

        for pref in preferredIds {
            if let match = candidates.first(where: { $0.id == pref }) {
                return match.source
            }
        }

        // 2. Збіг за мовним кодом
        let langCode = lang.inputSourceLanguageCode
        if let match = candidates.first(where: { $0.langCodes.contains(langCode) }) {
            return match.source
        }

        return nil
    }

    private func layoutData(from source: TISInputSource) -> CFData? {
        guard let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        return unsafeBitCast(layoutDataPtr, to: CFData.self)
    }

    // * -- Побудова таблиці (keyCode + shift) -> Character через UCKeyTranslate --
    private func buildKeyToCharTable(from layoutData: CFData) -> [UInt32: Character] {
        var table: [UInt32: Character] = [:]
        let rawLayout = CFDataGetBytePtr(layoutData)
        guard let rawLayout else { return table }

        let keyboardLayout = rawLayout.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }
        let maxLen = 4
        var chars = [UniChar](repeating: 0, count: maxLen)

        // Скануємо всі стандартні коди клавіш macOS (0...127)
        for keyCode in UInt16(0)...UInt16(127) {
            for shift in [false, true] {
                var deadKeyState: UInt32 = 0
                var actualLen = 0
                let modifierKeyState = shift ? UInt32(shiftKey >> 8) : 0

                let status = UCKeyTranslate(
                    keyboardLayout,
                    keyCode,
                    UInt16(kUCKeyActionDisplay),
                    modifierKeyState,
                    UInt32(LMGetKbdType()),
                    UInt32(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    maxLen,
                    &actualLen,
                    &chars
                )

                if status == noErr && actualLen == 1 {
                    if let scalar = UnicodeScalar(chars[0]) {
                        let val = scalar.value
                        // Пропускаємо невидимі керуючі символи (0...31, 127...159)
                        if val >= 32 && !(val >= 127 && val <= 159) {
                            let ch = Character(scalar)
                            let keyId = (UInt32(keyCode) << 1) | (shift ? 1 : 0)
                            table[keyId] = ch
                        }
                    }
                }
            }
        }

        return table
    }

    private func isSelectCapable(_ source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }

    private func sourcePropertyString(_ source: TISInputSource, key: CFString?) -> String? {
        guard let key, let value = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    private func sourcePropertyStringArray(_ source: TISInputSource, key: CFString?) -> [String]? {
        guard let key, let value = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFArray>.fromOpaque(value).takeUnretainedValue() as? [String]
    }
}

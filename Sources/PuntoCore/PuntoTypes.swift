import Foundation

// * -- Перелік підтримуваних мов та їхнього відображення --
public enum PuntoLanguage: String, CaseIterable, Codable, Sendable, Equatable {
    case english = "en"
    case russian = "ru"
    case ukrainian = "ua"

    // * -- Повна назва мови --
    public var title: String {
        switch self {
        case .english: "English"
        case .russian: "Russian"
        case .ukrainian: "Ukrainian"
        }
    }

    // * -- Скорочена назва для статус-бару (2 символи) --
    public var statusTitle: String {
        switch self {
        case .english: "EN"
        case .russian: "RU"
        case .ukrainian: "UA"
        }
    }

    // * -- Системний код мови розкладки macOS --
    public var inputSourceLanguageCode: String {
        switch self {
        case .english: "en"
        case .russian: "ru"
        case .ukrainian: "uk"
        }
    }
}

// * -- Режими перемикання розкладки клавіатури --
public enum SwitchingMode: String, CaseIterable, Codable, Sendable, Equatable {
    case sequential   // Перемикання по черзі між усіма активними мовами (по колу)
    case fixedTarget  // Перемикання між англійською та однією обраною фіксованою мовою

    // * -- Текстова назва режиму --
    public var title: String {
        switch self {
        case .sequential: "Sequential"
        case .fixedTarget: "Fixed target"
        }
    }
}

// * -- Режими автоматичної зміни регістру тексту --
public enum CaseMode: String, CaseIterable, Codable, Sendable, Equatable {
    case lower              // Нижній регістр (маленькі літери)
    case sentence           // Перша літера речення велика
    case title              // Перша літера кожного слова велика
    case normalizeCapsLock  // Інвертування регістру (виправлення Caps Lock)

    // * -- Текстова назва режиму зміни регістру --
    public var title: String {
        switch self {
        case .lower: "Lowercase"
        case .sentence: "Sentence case"
        case .title: "Title Case"
        case .normalizeCapsLock: "Normalize Caps Lock"
        }
    }
}

// * -- Мова інтерфейсу застосунку --
public enum InterfaceLanguage: String, CaseIterable, Codable, Sendable, Equatable {
    case russian
    case ukrainian
    case english

    // * -- Визначення мови системи за замовчуванням --
    public static var systemDefault: InterfaceLanguage {
        let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferredLanguage.hasPrefix("uk") {
            return .ukrainian
        }
        if preferredLanguage.hasPrefix("ru") {
            return .russian
        }
        if preferredLanguage.hasPrefix("en") {
            return .english
        }
        return .ukrainian
    }

    // * -- Локалізована назва мови для меню вибору --
    public var title: String {
        switch self {
        case .russian: "Русский"
        case .ukrainian: "Українська"
        case .english: "English"
        }
    }
}

// * -- Команди перетворення тексту --
public enum PuntoCommand: String, Codable, Sendable, Equatable {
    case layout          // Зміна розкладки клавіатури
    case letterCase      // Зміна регістру літер
    case transliteration // Транслітерація символів
}

// * -- Модифікатори гарячих клавіш (OptionSet) --
public struct HotKeyModifiers: OptionSet, Codable, Sendable, Equatable {
    public let rawValue: Int

    public static let control = HotKeyModifiers(rawValue: 1 << 0)
    public static let option = HotKeyModifiers(rawValue: 1 << 1)
    public static let shift = HotKeyModifiers(rawValue: 1 << 2)
    public static let command = HotKeyModifiers(rawValue: 1 << 3)

    // * -- Ініціалізація через бітову маску --
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    // * -- Декодування з JSON --
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(Int.self))
    }

    // * -- Кодування в JSON --
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// * -- Модель гарячої клавіші або комбінації клавіш --
public struct HotKey: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case singleControl   // Подвійне натискання клавіші Control (або одиночне)
        case keyCombination  // Класична комбінація модифікаторів та звичайної клавіші
    }

    public var kind: Kind
    public var keyCode: Int?
    public var modifiers: HotKeyModifiers

    // * -- Ініціалізатор комбінації --
    public init(kind: Kind, keyCode: Int? = nil, modifiers: HotKeyModifiers = []) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // Зручні фабричні методи для створення гарячих клавіш
    public static let singleControl = HotKey(kind: .singleControl)
    public static func combination(keyCode: Int, modifiers: HotKeyModifiers) -> HotKey {
        HotKey(kind: .keyCombination, keyCode: keyCode, modifiers: modifiers)
    }

    // * -- Рядок для відображення комбінації в інтерфейсі (наприклад, 'Option+Shift+A') --
    public var displayTitle: String {
        switch kind {
        case .singleControl:
            return "Control"
        case .keyCombination:
            var parts: [String] = []
            if modifiers.contains(.control) { parts.append("Control") }
            if modifiers.contains(.option) { parts.append("Option") }
            if modifiers.contains(.shift) { parts.append("Shift") }
            if modifiers.contains(.command) { parts.append("Command") }
            if let keyCode {
                parts.append(Self.keyName(for: keyCode))
            }
            return parts.joined(separator: "+")
        }
    }

    // Мапа кодів клавіш для їхнього текстового відображення
    private static func keyName(for keyCode: Int) -> String {
        let names = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 35: "P", 37: "L", 40: "K", 45: "N",
            46: "M", 49: "Space", 123: "Left", 124: "Right", 125: "Down", 126: "Up"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

// * -- Усі налаштування застосунку Punto --
public struct PuntoSettings: Codable, Sendable, Equatable {
    public var schemaVersion: Int                   // Версія структури збережених налаштувань
    public var isEnabled: Bool                      // Прапорець активності Punto (увімкнено/вимкнено)
    public var launchAtLogin: Bool                  // Чи запускати застосунок автоматично при старті системи
    public var mainHotKey: HotKey                   // Гаряча клавіша для зміни розкладки останнього слова/виділення
    public var caseHotKey: HotKey                   // Гаряча клавіша для зміни регістру літер
    public var transliterationHotKey: HotKey         // Гаряча клавіша для транслітерації
    public var pauseHotKey: HotKey                  // Гаряча клавіша для паузи/увімкнення роботи Punto
    public var switchingMode: SwitchingMode         // Режим зміни розкладки (по колу / фіксована)
    public var fixedTargetLanguage: PuntoLanguage   // Цільова мова при фіксованому перемиканні
    public var transliterationTargetLanguage: PuntoLanguage // Цільова мова транслітерації
    public var caseMode: CaseMode                   // Режим зміни регістру за замовчуванням
    public var interfaceLanguage: InterfaceLanguage // Обрана мова інтерфейсу застосунку

    // * -- Ініціалізатор з дефолтними значеннями --
    public init(
        schemaVersion: Int = 1,
        isEnabled: Bool = true,
        launchAtLogin: Bool = false,
        mainHotKey: HotKey = .singleControl,
        caseHotKey: HotKey = .combination(keyCode: 8, modifiers: [.control, .option]),
        transliterationHotKey: HotKey = .combination(keyCode: 17, modifiers: [.control, .option]),
        pauseHotKey: HotKey = .combination(keyCode: 35, modifiers: [.control, .option]),
        switchingMode: SwitchingMode = .sequential,
        fixedTargetLanguage: PuntoLanguage = .russian,
        transliterationTargetLanguage: PuntoLanguage = .russian,
        caseMode: CaseMode = .sentence,
        interfaceLanguage: InterfaceLanguage = .systemDefault
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.launchAtLogin = launchAtLogin
        self.mainHotKey = mainHotKey
        self.caseHotKey = caseHotKey
        self.transliterationHotKey = transliterationHotKey
        self.pauseHotKey = pauseHotKey
        self.switchingMode = switchingMode
        self.fixedTargetLanguage = fixedTargetLanguage
        self.transliterationTargetLanguage = transliterationTargetLanguage
        self.caseMode = caseMode
        self.interfaceLanguage = interfaceLanguage
    }

    // * -- Налаштування за замовчуванням --
    public static let `default` = PuntoSettings()
}

// * -- Результат успішного перетворення тексту --
public struct TransformationResult: Sendable, Equatable {
    public var command: PuntoCommand             // Яка саме команда виконалася
    public var originalText: String              // Початковий текст перед перетворенням
    public var replacementText: String           // Новий текст для заміни
    public var sourceLanguage: PuntoLanguage?    // Виявлена початкова мова (якщо застосовно)
    public var targetLanguage: PuntoLanguage?    // Кінцева мова розкладки або транслітерації (якщо застосовно)

    // * -- Ініціалізатор результату --
    public init(
        command: PuntoCommand,
        originalText: String,
        replacementText: String,
        sourceLanguage: PuntoLanguage?,
        targetLanguage: PuntoLanguage?
    ) {
        self.command = command
        self.originalText = originalText
        self.replacementText = replacementText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }

    // * -- Чи призвела операція до реальних змін у тексті --
    public var didChange: Bool {
        originalText != replacementText || (sourceLanguage != nil && targetLanguage != nil && sourceLanguage != targetLanguage)
    }
}

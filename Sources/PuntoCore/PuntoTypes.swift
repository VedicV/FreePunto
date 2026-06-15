import Foundation

public enum PuntoLanguage: String, CaseIterable, Codable, Sendable, Equatable {
    case english = "en"
    case russian = "ru"
    case ukrainian = "ua"

    public var title: String {
        switch self {
        case .english: "English"
        case .russian: "Russian"
        case .ukrainian: "Ukrainian"
        }
    }

    public var statusTitle: String {
        switch self {
        case .english: "EN"
        case .russian: "RU"
        case .ukrainian: "UA"
        }
    }

    public var inputSourceLanguageCode: String {
        switch self {
        case .english: "en"
        case .russian: "ru"
        case .ukrainian: "uk"
        }
    }
}

public enum SwitchingMode: String, CaseIterable, Codable, Sendable, Equatable {
    case sequential
    case fixedTarget

    public var title: String {
        switch self {
        case .sequential: "Sequential"
        case .fixedTarget: "Fixed target"
        }
    }
}

public enum CaseMode: String, CaseIterable, Codable, Sendable, Equatable {
    case lower
    case sentence
    case title
    case normalizeCapsLock

    public var title: String {
        switch self {
        case .lower: "Lowercase"
        case .sentence: "Sentence case"
        case .title: "Title Case"
        case .normalizeCapsLock: "Normalize Caps Lock"
        }
    }
}

public enum InterfaceLanguage: String, CaseIterable, Codable, Sendable, Equatable {
    case russian
    case ukrainian
    case english

    public var title: String {
        switch self {
        case .russian: "Русский"
        case .ukrainian: "Українська"
        case .english: "English"
        }
    }
}

public enum PuntoCommand: String, Codable, Sendable, Equatable {
    case layout
    case letterCase
    case transliteration
}

public struct HotKeyModifiers: OptionSet, Codable, Sendable, Equatable {
    public let rawValue: Int

    public static let control = HotKeyModifiers(rawValue: 1 << 0)
    public static let option = HotKeyModifiers(rawValue: 1 << 1)
    public static let shift = HotKeyModifiers(rawValue: 1 << 2)
    public static let command = HotKeyModifiers(rawValue: 1 << 3)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct HotKey: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case singleControl
        case keyCombination
    }

    public var kind: Kind
    public var keyCode: Int?
    public var modifiers: HotKeyModifiers

    public init(kind: Kind, keyCode: Int? = nil, modifiers: HotKeyModifiers = []) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let singleControl = HotKey(kind: .singleControl)
    public static func combination(keyCode: Int, modifiers: HotKeyModifiers) -> HotKey {
        HotKey(kind: .keyCombination, keyCode: keyCode, modifiers: modifiers)
    }

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

public struct PuntoSettings: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var isEnabled: Bool
    public var launchAtLogin: Bool
    public var mainHotKey: HotKey
    public var caseHotKey: HotKey
    public var transliterationHotKey: HotKey
    public var pauseHotKey: HotKey
    public var switchingMode: SwitchingMode
    public var fixedTargetLanguage: PuntoLanguage
    public var transliterationTargetLanguage: PuntoLanguage
    public var caseMode: CaseMode
    public var interfaceLanguage: InterfaceLanguage

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
        interfaceLanguage: InterfaceLanguage = .russian
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

    public static let `default` = PuntoSettings()
}

public struct TransformationResult: Sendable, Equatable {
    public var command: PuntoCommand
    public var originalText: String
    public var replacementText: String
    public var sourceLanguage: PuntoLanguage?
    public var targetLanguage: PuntoLanguage?

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

    public var didChange: Bool {
        originalText != replacementText
    }
}

import Foundation

/// Платформний адаптер виконує одну зміну. Після спроби запису інша стратегія
/// не запускається, бо AX-помилка може надійти вже після часткового редагування.
public enum ReplacementTransaction {
    public enum Submission: Equatable {
        case notStarted
        case attempted
    }

    public static func execute(
        isCurrent: () -> Bool,
        prepare: () -> Bool,
        submit: () -> Submission,
        verify: () -> Bool
    ) -> ReplaceOutcome {
        guard isCurrent(), prepare(), isCurrent() else { return .failed }
        guard submit() == .attempted else { return .failed }
        guard isCurrent(), verify(), isCurrent() else { return .deliveredUnconfirmedAX }
        return .successVerified
    }
}

/// Точна перевірка UTF-16 діапазонів для AX-адаптера та регресійних тестів.
public enum ReplacementTextContract {
    private static func exactRange(_ value: String, location: Int, length: Int) -> Range<String.Index>? {
        let utf16 = value.utf16
        guard location >= 0, length >= 0, location <= utf16.count,
              length <= utf16.count - location else { return nil }
        let lower = utf16.index(utf16.startIndex, offsetBy: location)
        let upper = utf16.index(lower, offsetBy: length)
        guard let start = String.Index(lower, within: value),
              let end = String.Index(upper, within: value),
              (start == value.endIndex || value.indices.contains(start)),
              (end == value.endIndex || value.indices.contains(end)) else { return nil }
        return start..<end
    }

    public static func substring(_ value: String, location: Int, length: Int) -> String? {
        guard let range = exactRange(value, location: location, length: length) else { return nil }
        return String(value[range])
    }

    public static func replacing(_ value: String, location: Int, length: Int,
                                 original: String, replacement: String) -> String? {
        guard let range = exactRange(value, location: location, length: length),
              value[range].utf8.elementsEqual(original.utf8) else { return nil }
        var result = value
        result.replaceSubrange(range, with: replacement)
        return result
    }

    public static func verified(expectedValue: String?, actualValue: String?) -> Bool {
        guard let expectedValue, let actualValue else { return false }
        return expectedValue.utf8.elementsEqual(actualValue.utf8)
    }
}

/// Знімок clipboard може відновити лише ту версію, якою володіє поточна операція.
public struct ClipboardOwnership: Sendable {
    private var ownedChangeCount: Int?
    public init() {}
    public mutating func recordOwnedWrite(changeCount: Int) { ownedChangeCount = changeCount }
    public func canRestore(currentChangeCount: Int) -> Bool { ownedChangeCount == currentChangeCount }
}

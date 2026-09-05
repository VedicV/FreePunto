import Foundation

// * -- Результат детального сканування останнього слова --
public struct ScannedWord: Equatable, Sendable {
    public let word: String
    public let wordRange: Range<String.Index>
    public let trailingSpacesCount: Int
    public let trailingSpacesRange: Range<String.Index>
    public let fullRange: Range<String.Index>

    public init(
        word: String,
        wordRange: Range<String.Index>,
        trailingSpacesCount: Int,
        trailingSpacesRange: Range<String.Index>,
        fullRange: Range<String.Index>
    ) {
        self.word = word
        self.wordRange = wordRange
        self.trailingSpacesCount = trailingSpacesCount
        self.trailingSpacesRange = trailingSpacesRange
        self.fullRange = fullRange
    }
}

// * -- Чисті текстові функції для пошуку останнього слова і виявлення авто-копії рядка --
public enum TextScanner {
    // * -- Детальне сканування останнього слова з точними діапазонами в тексті --
    public static func scanLastWord<T: StringProtocol>(in text: T) -> ScannedWord? {
        var cursor = text.endIndex

        // 1. Пропускаємо кінцеві переводи рядків (\r, \n), якщо вони є,
        // щоб випадковий newline не рахувався як кінцеві пробіли для Backspace.
        while cursor > text.startIndex {
            let prev = text.index(before: cursor)
            if text[prev].isNewline {
                cursor = prev
            } else {
                break
            }
        }

        let lineEnd = cursor

        // 2. Рахуємо тільки горизонтальні пробіли/таби (trailing spaces)
        while cursor > text.startIndex {
            let prev = text.index(before: cursor)
            if text[prev].isWhitespace && !text[prev].isNewline {
                cursor = prev
            } else {
                break
            }
        }

        let wordEnd = cursor
        let trailingSpacesRange = wordEnd..<lineEnd
        let trailingSpacesCount = text.distance(from: wordEnd, to: lineEnd)

        let wordPrefix = text[..<wordEnd]
        let wordStart: String.Index
        if let lastWhitespace = wordPrefix.rangeOfCharacter(
            from: .whitespacesAndNewlines, options: .backwards)
        {
            wordStart = lastWhitespace.upperBound
        } else {
            wordStart = text.startIndex
        }

        guard wordStart < wordEnd else {
            return nil
        }

        let word = String(text[wordStart..<wordEnd])
        let wordLength = (word as NSString).length
        guard wordLength > 0, wordLength <= 300 else {
            return nil
        }

        return ScannedWord(
            word: word,
            wordRange: wordStart..<wordEnd,
            trailingSpacesCount: trailingSpacesCount,
            trailingSpacesRange: trailingSpacesRange,
            fullRange: wordStart..<lineEnd
        )
    }

    // * -- Останнє слово в рядку або значенні (з кількістю кінцевих пробілів) --
    public static func lastWord(in text: String) -> (word: String, trailingSpacesCount: Int)? {
        guard let scanned = scanLastWord(in: text) else { return nil }
        return (word: scanned.word, trailingSpacesCount: scanned.trailingSpacesCount)
    }

    // * -- Чи схоже скопійоване на автоматичну копію цілого рядка без виділення --
    public static func looksLikeAutomaticLineCopy(_ copiedText: String) -> Bool {
        let normalized = copiedText.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized.hasSuffix("\n")
    }
}


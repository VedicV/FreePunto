import Foundation

// * -- Чисті текстові функції для пошуку останнього слова і виявлення авто-копії рядка --
public enum TextScanner {
    // * -- Останнє слово в рядку або значенні (з кількістю кінцевих пробілів) --
    public static func lastWord(in text: String) -> (word: String, trailingSpacesCount: Int)? {
        var endIndex = text.endIndex
        while endIndex > text.startIndex {
            let prevIndex = text.index(before: endIndex)
            if text[prevIndex].isWhitespace || text[prevIndex].isNewline {
                endIndex = prevIndex
            } else {
                break
            }
        }

        let wordText = text[..<endIndex]
        let word: String
        if let lastWhitespaceRange = wordText.rangeOfCharacter(
            from: .whitespacesAndNewlines, options: .backwards)
        {
            word = String(wordText.suffix(from: lastWhitespaceRange.upperBound))
        } else {
            word = String(wordText)
        }

        let wordLength = (word as NSString).length
        guard wordLength > 0, wordLength <= 40 else {
            return nil
        }

        return (
            word: word,
            trailingSpacesCount: text.distance(from: endIndex, to: text.endIndex)
        )
    }

    // * -- Чи схоже скопійоване на автоматичну копію цілого рядка без виділення --
    public static func looksLikeAutomaticLineCopy(_ copiedText: String) -> Bool {
        let normalized = copiedText.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized.hasSuffix("\n")
    }
}

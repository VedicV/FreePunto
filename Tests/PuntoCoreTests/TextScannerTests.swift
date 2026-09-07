import XCTest

@testable import PuntoCore

final class TextScannerTests: XCTestCase {

    // MARK: - lastWord

    // * -- Звичайне речення → останнє слово, trailingSpacesCount == 0 --
    func testLastWordOrdinarySentence() {
        let result = TextScanner.lastWord(in: "hello world")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.word, "world")
        XCTAssertEqual(result?.trailingSpacesCount, 0)
    }

    // * -- Рядок з кінцевими пробілами → word == "world", trailingSpacesCount == 3 --
    func testLastWordTrailingSpaces() {
        let result = TextScanner.lastWord(in: "hello world   ")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.word, "world")
        XCTAssertEqual(result?.trailingSpacesCount, 3)
    }

    // * -- Одиночне слово без пробілів → само слово, trailingSpacesCount == 0 --
    func testLastWordSingleWord() {
        let result = TextScanner.lastWord(in: "word")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.word, "word")
        XCTAssertEqual(result?.trailingSpacesCount, 0)
    }

    // * -- Порожній рядок → nil --
    func testLastWordEmptyString() {
        XCTAssertNil(TextScanner.lastWord(in: ""))
    }

    // * -- Тільки пробіли → nil --
    func testLastWordOnlySpaces() {
        XCTAssertNil(TextScanner.lastWord(in: "   "))
    }

    // * -- Слово довше 300 символів → nil --
    func testLastWordTooLong() {
        let longWord = String(repeating: "a", count: 301)
        XCTAssertNil(TextScanner.lastWord(in: longWord))
    }

    // * -- Слово рівно 300 символів → повертається --
    func testLastWordExactly300() {
        let word300 = String(repeating: "a", count: 300)
        let result = TextScanner.lastWord(in: word300)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.word, word300)
        XCTAssertEqual(result?.trailingSpacesCount, 0)
    }

    // * -- Багаторядковий текст → останнє слово останньої непустої частини --
    // * -- lastWord шукає з кінця рядка, тому \n є whitespace/newline і пропускається --
    func testLastWordMultiline() {
        // "first line\nsecond line" — функція шукає з кінця: "line" є останнім словом
        let result = TextScanner.lastWord(in: "first line\nsecond line")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.word, "line")
        XCTAssertEqual(result?.trailingSpacesCount, 0)
    }

    func testLastWordDoesNotCrossTrailingLineBoundary() {
        for text in ["hello world\n", "hello world\r\n", "word\n \t"] {
            XCTAssertNil(TextScanner.lastWord(in: text))
        }
    }

    func testExactWhitespaceAndSubstringRangesPreserveCaretSuffix() {
        let text = "😀 cafe\u{0301} ghbdtn \t\u{00A0} suffix"
        let caret = text.index(text.endIndex, offsetBy: -7)
        let scanned = TextScanner.scanLastWord(in: text[..<caret])!
        XCTAssertEqual(scanned.trailingWhitespace, " \t\u{00A0}")
        XCTAssertEqual(String(text[scanned.wordRange]), "ghbdtn")
        var result = text
        result.replaceSubrange(scanned.wordRange, with: "привет")
        XCTAssertEqual(result, "😀 cafe\u{0301} привет \t\u{00A0} suffix")
    }

    // MARK: - looksLikeAutomaticLineCopy

    // * -- "line\n" → true --
    func testLooksLikeLineCopyWithNewline() {
        XCTAssertTrue(TextScanner.looksLikeAutomaticLineCopy("line\n"))
    }

    // * -- "line\r\n" → true (нормалізація \r\n → \n) --
    func testLooksLikeLineCopyWithCRLF() {
        XCTAssertTrue(TextScanner.looksLikeAutomaticLineCopy("line\r\n"))
    }

    // * -- "word" без переносу → false --
    func testLooksLikeLineCopyNoNewline() {
        XCTAssertFalse(TextScanner.looksLikeAutomaticLineCopy("word"))
    }

    // * -- "two words no newline" → false --
    func testLooksLikeLineCopyTwoWordsNoNewline() {
        XCTAssertFalse(TextScanner.looksLikeAutomaticLineCopy("two words no newline"))
    }
}

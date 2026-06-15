import XCTest

@testable import PuntoCore

final class PuntoCoreTests: XCTestCase {
    func testLayoutTransformsEnglishRussianAndUkrainianKeyboards() {
        XCTAssertEqual(
            LayoutTransformer.transform("ghbdtn vbh!", from: .english, to: .russian),
            "привет мир!"
        )
        XCTAssertEqual(
            LayoutTransformer.transform("s]'", from: .english, to: .ukrainian),
            "іїє"
        )
        XCTAssertEqual(
            LayoutTransformer.transform("її є ґ", from: .ukrainian, to: .english),
            "]] ' `"
        )
        XCTAssertEqual(
            LayoutTransformer.transform("ёъыэ", from: .russian, to: .english),
            "`]s'"
        )
    }

    func testLayoutRoundTripsBetweenSupportedLanguages() {
        let englishSample = "Qwerty, asdf; zxcv. []'"
        let russian = LayoutTransformer.transform(englishSample, from: .english, to: .russian)
        XCTAssertEqual(
            LayoutTransformer.transform(russian, from: .russian, to: .english), englishSample)

        let ukrainian = LayoutTransformer.transform(englishSample, from: .english, to: .ukrainian)
        XCTAssertEqual(
            LayoutTransformer.transform(ukrainian, from: .ukrainian, to: .english), englishSample)

        let russianSource = "Привет, ёж!"
        let ukrainianFromRussian = LayoutTransformer.transform(
            russianSource, from: .russian, to: .ukrainian)
        XCTAssertEqual(
            LayoutTransformer.transform(ukrainianFromRussian, from: .ukrainian, to: .russian),
            russianSource)
    }

    func testLayoutPreservesLetterCase() {
        XCTAssertEqual(
            LayoutTransformer.transform("GhBdTn", from: .english, to: .russian),
            "ПрИвЕт"
        )
        XCTAssertEqual(
            LayoutTransformer.transform("ІЇЄ Ґ", from: .ukrainian, to: .english),
            "S]' `"
        )
    }

    func testSequentialModeCyclesThroughEnglishRussianAndUkrainian() {
        let engine = PuntoEngine()
        let settings = PuntoSettings(switchingMode: .sequential)

        let russian = engine.convertLayout("ghbdtn", settings: settings)
        XCTAssertEqual(russian.replacementText, "привет")
        XCTAssertEqual(russian.sourceLanguage, .english)
        XCTAssertEqual(russian.targetLanguage, .russian)
        XCTAssertEqual(engine.nextLayoutLanguageHint(settings: settings), .ukrainian)

        let ukrainian = engine.convertLayout(russian.replacementText, settings: settings)
        XCTAssertEqual(ukrainian.replacementText, "привет")
        XCTAssertEqual(ukrainian.sourceLanguage, .russian)
        XCTAssertEqual(ukrainian.targetLanguage, .ukrainian)
        XCTAssertEqual(engine.nextLayoutLanguageHint(settings: settings), .english)

        let english = engine.convertLayout(ukrainian.replacementText, settings: settings)
        XCTAssertEqual(english.replacementText, "ghbdtn")
        XCTAssertEqual(english.sourceLanguage, .ukrainian)
        XCTAssertEqual(english.targetLanguage, .english)
        XCTAssertEqual(engine.nextLayoutLanguageHint(settings: settings), .russian)
    }

    func testFixedTargetModeUsesConfiguredTargetForEnglishAndEnglishForCyrillic() {
        let engine = PuntoEngine()
        let settings = PuntoSettings(switchingMode: .fixedTarget, fixedTargetLanguage: .ukrainian)

        let ukrainian = engine.convertLayout("s]'", settings: settings)
        XCTAssertEqual(ukrainian.replacementText, "іїє")
        XCTAssertEqual(ukrainian.sourceLanguage, .english)
        XCTAssertEqual(ukrainian.targetLanguage, .ukrainian)
        XCTAssertEqual(engine.nextLayoutLanguageHint(settings: settings), .ukrainian)

        let english = engine.convertLayout("іїє", settings: settings)
        XCTAssertEqual(english.replacementText, "s]'")
        XCTAssertEqual(english.sourceLanguage, .ukrainian)
        XCTAssertEqual(english.targetLanguage, .english)
    }

    func testCaseTransformations() {
        XCTAssertEqual(CaseTransformer.transform("ПРИВЕТ, HELLO!", mode: .lower), "привет, hello!")
        XCTAssertEqual(
            CaseTransformer.transform("пРИВЕТ. hELLO! як СПРАВИ?", mode: .sentence),
            "Привет. Hello! Як справи?")
        XCTAssertEqual(
            CaseTransformer.transform("ivan's test іванів ТЕСТ", mode: .title),
            "Ivan's Test Іванів Тест")
        XCTAssertEqual(
            CaseTransformer.transform("CAPS ЁЖ ЇЖАК", mode: .normalizeCapsLock), "caps ёж їжак")
        XCTAssertEqual(
            CaseTransformer.transform("пРИВЕТ, hELLO!", mode: .normalizeCapsLock), "Привет, Hello!")
    }

    func testTransliterationFromRussianUkrainianAndLatin() {
        let russianToLatin = Transliterator.transliterate("Привет, ёж!", targetLanguage: .russian)
        XCTAssertEqual(russianToLatin.replacementText, "Privet, yozh!")
        XCTAssertEqual(russianToLatin.sourceLanguage, .russian)
        XCTAssertEqual(russianToLatin.targetLanguage, .english)

        let ukrainianToLatin = Transliterator.transliterate(
            "Привіт, їжак і ґава!", targetLanguage: .ukrainian)
        XCTAssertEqual(ukrainianToLatin.replacementText, "Pryvit, yizhak i gava!")
        XCTAssertEqual(ukrainianToLatin.sourceLanguage, .ukrainian)
        XCTAssertEqual(ukrainianToLatin.targetLanguage, .english)

        let latinToRussian = Transliterator.transliterate("Privet, mir!", targetLanguage: .russian)
        XCTAssertEqual(latinToRussian.replacementText, "Привет, мир!")
        XCTAssertEqual(latinToRussian.sourceLanguage, .english)
        XCTAssertEqual(latinToRussian.targetLanguage, .russian)

        let latinToUkrainian = Transliterator.transliterate(
            "Hlib i gava", targetLanguage: .ukrainian)
        XCTAssertEqual(latinToUkrainian.replacementText, "Гліб і ґава")
        XCTAssertEqual(latinToUkrainian.sourceLanguage, .english)
        XCTAssertEqual(latinToUkrainian.targetLanguage, .ukrainian)
    }

    func testTransliterationMixedTextUsesLanguageSpecificCyrillicLetters() {
        let mixedUkrainian = Transliterator.transliterate("abc їж", targetLanguage: .russian)
        XCTAssertEqual(mixedUkrainian.replacementText, "abc yizh")
        XCTAssertEqual(mixedUkrainian.sourceLanguage, .ukrainian)
        XCTAssertEqual(mixedUkrainian.targetLanguage, .english)

        let mixedRussian = Transliterator.transliterate("abc ёж", targetLanguage: .ukrainian)
        XCTAssertEqual(mixedRussian.replacementText, "abc yozh")
        XCTAssertEqual(mixedRussian.sourceLanguage, .russian)
        XCTAssertEqual(mixedRussian.targetLanguage, .english)
    }

    func testPunctuationWhitespaceAndUnmappedCharactersArePreserved() {
        XCTAssertEqual(
            LayoutTransformer.transform("hi  123\t🙂\n[]", from: .english, to: .ukrainian),
            "рш  123\t🙂\nхї"
        )
        XCTAssertEqual(
            Transliterator.transliterate("Privet,\t mir 123 🙂", targetLanguage: .russian)
                .replacementText,
            "Привет,\t мир 123 🙂"
        )
        XCTAssertEqual(
            CaseTransformer.transform("  hello,\tМИР!  ", mode: .sentence),
            "  Hello,\tмир!  "
        )
    }
}

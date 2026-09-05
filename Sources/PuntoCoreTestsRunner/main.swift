import Foundation
import PuntoCore

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") {
    if actual != expected {
        print("❌ FAIL: expected '\(expected)', got '\(actual)' - \(message)")
        exit(1)
    } else {
        print("✅ PASS: \(message.isEmpty ? String(describing: actual) : message) -> \(actual)")
    }
}

print("=== Running PuntoCore Autonomous Tests ===")

print("\n--- Test 1: LayoutTransformer < and > ---")
let enAngled = "<hello>"
let uaAngled = LayoutTransformer.transform(enAngled, from: .english, to: .ukrainian)
assertEqual(uaAngled, "БруддщЮ", "<hello> -> БруддщЮ")

let enBack = LayoutTransformer.transform(uaAngled, from: .ukrainian, to: .english)
assertEqual(enBack, enAngled, "БруддщЮ -> <hello>")

print("\n--- Test 1b: DynamicLayoutMapper character translation (. -> ю, , -> б) ---")
let enToRuDot = DynamicLayoutMapper.shared.translateCharacter(".", from: .english, to: .russian)
assertEqual(enToRuDot, "ю", "Dynamic translate '.' EN -> RU must be 'ю'")

let enToUaDot = DynamicLayoutMapper.shared.translateCharacter(".", from: .english, to: .ukrainian)
assertEqual(enToUaDot, "ю", "Dynamic translate '.' EN -> UA must be 'ю'")

let enToRuComma = DynamicLayoutMapper.shared.translateCharacter(",", from: .english, to: .russian)
assertEqual(enToRuComma, "б", "Dynamic translate ',' EN -> RU must be 'б'")

let testWord = LayoutTransformer.transform("cktle.otve", from: .english, to: .russian)
assertEqual(testWord, "следующему", "cktle.otve -> следующему (not следу,щему)")

let ruToEn = LayoutTransformer.transform("следующему", from: .russian, to: .english)
assertEqual(ruToEn, "cktle.otve", "следующему -> cktle.otve")

let uaToEn = LayoutTransformer.transform("ю", from: .ukrainian, to: .english)
assertEqual(uaToEn, ".", "ю UA -> . EN")


print("\n--- Test 2: Number row Shift symbols ---")
let enSymbols = "!@#$%^&*()"
let uaSymbols = LayoutTransformer.transform(enSymbols, from: .english, to: .ukrainian)
assertEqual(uaSymbols, "!\"№;%:?*()", "!@#$%^&*() -> !\"№;%:?*()")

let enSymbolsBack = LayoutTransformer.transform(uaSymbols, from: .ukrainian, to: .english)
assertEqual(enSymbolsBack, enSymbols, "!\"№;%:?*() -> !@#$%^&*()")

print("\n--- Test 3: Ukrainian apostrophe ---")
let uaApostrophe = "мʼясо"
let enApostrophe = LayoutTransformer.transform(uaApostrophe, from: .ukrainian, to: .english)
assertEqual(enApostrophe, "v\\zcj", "мʼясо -> v\\zcj")

let uaBackApos = LayoutTransformer.transform(enApostrophe, from: .english, to: .ukrainian)
assertEqual(uaBackApos, uaApostrophe, "v\\zcj -> мʼясо")

print("\n--- Test 4: PuntoEngine sequential cycle (EN <-> UA only) ---")
let engine = PuntoEngine()
let settings = PuntoSettings(switchingMode: .sequential)
let activeLangs: [PuntoLanguage] = [.english, .ukrainian]

// Type in English: "ghbdsn" -> should convert to Ukrainian "привіт"
let res1 = engine.convertLayout("ghbdsn", settings: settings, enabledLanguages: activeLangs)
assertEqual(res1.targetLanguage, .ukrainian, "EN -> UA targetLanguage")
assertEqual(res1.replacementText, "привіт", "EN -> UA text")

// Subsequent press on the converted text -> should cycle back to English "ghbdsn", NOT Russian!
let res2 = engine.convertLayout(res1.replacementText, settings: settings, enabledLanguages: activeLangs)
assertEqual(res2.targetLanguage, .english, "UA -> EN targetLanguage")
assertEqual(res2.replacementText, "ghbdsn", "UA -> EN text")

print("\n--- Test 4b: PuntoEngine full circular cycle (EN -> RU -> UA -> EN) ---")
let fullEngine = PuntoEngine()
let allLangs: [PuntoLanguage] = [.english, .russian, .ukrainian]

// Step 1: English "csh" -> Russian "сыр"
let cycle1 = fullEngine.convertLayout("csh", settings: settings, enabledLanguages: allLangs)
assertEqual(cycle1.targetLanguage, .russian, "Step 1: EN -> RU targetLanguage")
assertEqual(cycle1.replacementText, "сыр", "Step 1: EN -> RU text (сыр)")

// Step 2: Russian "сыр" -> Ukrainian "сір"
let cycle2 = fullEngine.convertLayout(cycle1.replacementText, settings: settings, enabledLanguages: allLangs)
assertEqual(cycle2.targetLanguage, .ukrainian, "Step 2: RU -> UA targetLanguage")
assertEqual(cycle2.replacementText, "сір", "Step 2: RU -> UA text (сір)")

// Step 3: Ukrainian "сір" -> English "csh"
let cycle3 = fullEngine.convertLayout(cycle2.replacementText, settings: settings, enabledLanguages: allLangs)
assertEqual(cycle3.targetLanguage, .english, "Step 3: UA -> EN targetLanguage")
assertEqual(cycle3.replacementText, "csh", "Step 3: UA -> EN text (csh)")

// Step 4: English "csh" -> Russian "сыр" (loop closed)
let cycle4 = fullEngine.convertLayout(cycle3.replacementText, settings: settings, enabledLanguages: allLangs)
assertEqual(cycle4.targetLanguage, .russian, "Step 4: EN -> RU targetLanguage")
assertEqual(cycle4.replacementText, "сыр", "Step 4: EN -> RU text (сыр)")


print("\n--- Test 5: TextScanner.lastWord up to nearest whitespace (preserving dots, commas, keys) ---")
let testLine = "export API_KEY=sk_live.12345,678.ghbdsn"
let wordRes = TextScanner.lastWord(in: testLine)
assertEqual(wordRes?.word, "API_KEY=sk_live.12345,678.ghbdsn", "Word with dots and commas up to whitespace")
assertEqual(wordRes?.trailingSpacesCount, 0, "Trailing spaces count 0")

let testWithSpaces = "prefix my.token,key.123 "
let spaceRes = TextScanner.lastWord(in: testWithSpaces)
assertEqual(spaceRes?.word, "my.token,key.123", "Word with trailing space")
assertEqual(spaceRes?.trailingSpacesCount, 1, "Trailing spaces count 1")

print("\n--- Test 5b: TextScanner.scanLastWord & UTF-16 word range safety (no eaten spaces) ---")
// 1. Newline handling: newlines should NOT count as trailing spaces
let textWithNewline = "предыдущее слово\n"
let newlineScan = TextScanner.scanLastWord(in: textWithNewline)
assertEqual(newlineScan?.word, "слово", "Word before newline")
assertEqual(newlineScan?.trailingSpacesCount, 0, "Trailing spaces before newline should be 0, not 1")

// 2. CRLF handling: \r\n should NOT count as trailing spaces
let textWithCRLF = "предыдущее слово\r\n"
let crlfScan = TextScanner.scanLastWord(in: textWithCRLF)
assertEqual(crlfScan?.word, "слово", "Word before CRLF")
assertEqual(crlfScan?.trailingSpacesCount, 0, "Trailing spaces before CRLF should be 0")

// 3. Emojis before word: UTF-16 range must strictly point to the word and never eat the preceding space
let textWithEmoji = "😊 предыдущее слово и еще"
let prefixEmoji = "😊 предыдущее слово"
let cursorUtf16Emoji = prefixEmoji.utf16.count
let cursorIndexEmoji = String.Index(utf16Offset: cursorUtf16Emoji, in: textWithEmoji)
let scannedEmoji = TextScanner.scanLastWord(in: textWithEmoji[..<cursorIndexEmoji])
assertEqual(scannedEmoji?.word, "слово", "Emoji text word")
if let scanned = scannedEmoji {
    let wordStartLoc = textWithEmoji.utf16.distance(from: textWithEmoji.startIndex, to: scanned.wordRange.lowerBound)
    let wordLenUtf16 = textWithEmoji.utf16.distance(from: scanned.wordRange.lowerBound, to: scanned.fullRange.upperBound)
    let subStart = String.Index(utf16Offset: wordStartLoc, in: textWithEmoji)
    let subEnd = String.Index(utf16Offset: wordStartLoc + wordLenUtf16, in: textWithEmoji)
    let extracted = String(textWithEmoji[subStart..<subEnd])
    assertEqual(extracted, "слово", "Extracted text via CFRange must be 'слово' WITHOUT preceding space")
    let charBeforeWord = textWithEmoji[textWithEmoji.index(before: subStart)]
    assertEqual(charBeforeWord, " ", "Character immediately before CFRange must be the space")
}

// 4. Decomposed Cyrillic (NFD й = \u{0438}\u{0306}) before word: UTF-16 range must strictly point to the word
let textWithNFD = "мо\u{0438}\u{0306} слово и еще"
let prefixNFD = "мо\u{0438}\u{0306} слово"
let cursorUtf16NFD = prefixNFD.utf16.count
let cursorIndexNFD = String.Index(utf16Offset: cursorUtf16NFD, in: textWithNFD)
let scannedNFD = TextScanner.scanLastWord(in: textWithNFD[..<cursorIndexNFD])
assertEqual(scannedNFD?.word, "слово", "NFD text word")
if let scanned = scannedNFD {
    let wordStartLoc = textWithNFD.utf16.distance(from: textWithNFD.startIndex, to: scanned.wordRange.lowerBound)
    let wordLenUtf16 = textWithNFD.utf16.distance(from: scanned.wordRange.lowerBound, to: scanned.fullRange.upperBound)
    let subStart = String.Index(utf16Offset: wordStartLoc, in: textWithNFD)
    let subEnd = String.Index(utf16Offset: wordStartLoc + wordLenUtf16, in: textWithNFD)
    let extracted = String(textWithNFD[subStart..<subEnd])
    assertEqual(extracted, "слово", "Extracted text via CFRange must be 'слово' WITHOUT preceding space")
    let charBeforeWord = textWithNFD[textWithNFD.index(before: subStart)]
    assertEqual(charBeforeWord, " ", "Character immediately before CFRange must be the space")
}

// 5. Multiple spaces before word: UTF-16 range must not include any of the spaces
let textWithMultiSpaces = "предыдущее   новое"
let cursorUtf16Multi = textWithMultiSpaces.utf16.count
let cursorIndexMulti = String.Index(utf16Offset: cursorUtf16Multi, in: textWithMultiSpaces)
let scannedMulti = TextScanner.scanLastWord(in: textWithMultiSpaces[..<cursorIndexMulti])
assertEqual(scannedMulti?.word, "новое", "Multiple spaces word")
if let scanned = scannedMulti {
    let wordStartLoc = textWithMultiSpaces.utf16.distance(from: textWithMultiSpaces.startIndex, to: scanned.wordRange.lowerBound)
    let wordLenUtf16 = textWithMultiSpaces.utf16.distance(from: scanned.wordRange.lowerBound, to: scanned.fullRange.upperBound)
    let subStart = String.Index(utf16Offset: wordStartLoc, in: textWithMultiSpaces)
    let subEnd = String.Index(utf16Offset: wordStartLoc + wordLenUtf16, in: textWithMultiSpaces)
    let extracted = String(textWithMultiSpaces[subStart..<subEnd])
    assertEqual(extracted, "новое", "Extracted text via CFRange must be 'новое' without multiple preceding spaces")
}

print("\n🎉 ALL PUNTOCORE AUTONOMOUS TESTS PASSED!")


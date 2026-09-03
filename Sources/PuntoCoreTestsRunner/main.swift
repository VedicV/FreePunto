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

print("\n--- Test 5: TextScanner.lastWord up to nearest whitespace (preserving dots, commas, keys) ---")
let testLine = "export API_KEY=sk_live.12345,678.ghbdsn"
let wordRes = TextScanner.lastWord(in: testLine)
assertEqual(wordRes?.word, "API_KEY=sk_live.12345,678.ghbdsn", "Word with dots and commas up to whitespace")
assertEqual(wordRes?.trailingSpacesCount, 0, "Trailing spaces count 0")

let testWithSpaces = "prefix my.token,key.123 "
let spaceRes = TextScanner.lastWord(in: testWithSpaces)
assertEqual(spaceRes?.word, "my.token,key.123", "Word with trailing space")
assertEqual(spaceRes?.trailingSpacesCount, 1, "Trailing spaces count 1")

print("\n🎉 ALL PUNTOCORE AUTONOMOUS TESTS PASSED!")

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

print("\n--- Test 6: AppEnvironmentClassifier false-positive prevention ---")
// Редактор коду зі знаками $, >, <, %, console.log НЕ повинен визначатися як термінал
let isCodeTerminal = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextArea",
    title: "index.ts",
    description: "editor document",
    identifier: "workbench.parts.editor",
    value: "if (x > y && count % 2 === 0) { console.log($user); }"
)
assertEqual(isCodeTerminal, false, "Code editor containing $, >, %, console.log must NOT be classified as terminal")

let isRealTerminal = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextArea",
    title: "zsh",
    description: "Terminal 1",
    identifier: "terminal.view",
    value: "user@mac:~$ "
)
assertEqual(isRealTerminal, true, "Real terminal element must be classified as terminal")

print("\n--- Test 7: PuntoEngine deferred commit & enabledLanguages reactivity ---")
let testEngine = PuntoEngine()
let testSettings = PuntoSettings.default // sequential mode

// 1. autoCommit = false без commit: стан не повинен змінюватися
let preview1 = testEngine.convertLayout("ghbdsn", settings: testSettings, enabledLanguages: [.english, .russian], autoCommit: false)
assertEqual(preview1.targetLanguage, .russian, "First layout preview -> RU")
let hintBeforeCommit = testEngine.nextLayoutLanguageHint(settings: testSettings, enabledLanguages: [.english, .russian])
// Оскільки autoCommit = false і commit не викликано, hint показує початковий наступний стан (не просунутий)
assertEqual(hintBeforeCommit, .russian, "Hint before commit is initial target")

// Тепер фіксуємо
testEngine.commitPendingConversion()

// Наступне перетворення того самого тексту має піти на наступну мову (в нашому випадку [.english, .russian] повертає в .english)
let preview2 = testEngine.convertLayout("привет", settings: testSettings, enabledLanguages: [.english, .russian], autoCommit: false)
assertEqual(preview2.targetLanguage, .english, "Committed cycle moves forward: RU -> EN")
testEngine.commitPendingConversion()

// 2. Зміна enabledLanguages на льоту: якщо мови змінилися, старий цикл скидається
let previewWithUa = testEngine.convertLayout("ghbdsn", settings: testSettings, enabledLanguages: [.english, .ukrainian], autoCommit: false)
assertEqual(previewWithUa.targetLanguage, .ukrainian, "Updated enabledLanguages (.english, .ukrainian) uses new cycle -> UA")
testEngine.commitPendingConversion()

print("\n--- Test 8: DynamicLayoutMapper refreshTables ---")
DynamicLayoutMapper.shared.refreshTables()
let dotTranslation = DynamicLayoutMapper.shared.translateCharacter(".", from: .english, to: .russian)
assertEqual(dotTranslation, "ю", "DynamicLayoutMapper still translates '.' -> 'ю' after refresh")

print("\n--- Test 9: Common Cyrillic word (текст) never results in a no-op identical replacement ---")
let testEngine9 = PuntoEngine()
let res9_1 = testEngine9.convertLayout(
    "текст",
    settings: testSettings,
    enabledLanguages: [.english, .ukrainian, .russian],
    currentLanguage: .ukrainian,
    autoCommit: true
)
assertEqual(res9_1.replacementText, "ntrcn", "Cyrillic 'текст' on UA layout must convert to 'ntrcn' in English")
assertEqual(res9_1.targetLanguage, .english, "Target language must be English")
assertEqual(res9_1.originalText != res9_1.replacementText, true, "Text must change")

let res9_2 = testEngine9.convertLayout(
    "ntrcn",
    settings: testSettings,
    enabledLanguages: [.english, .ukrainian, .russian],
    currentLanguage: .english,
    autoCommit: true
)
assertEqual(res9_2.replacementText, "текст", "English 'ntrcn' must convert to Cyrillic 'текст'")
assertEqual(res9_2.originalText != res9_2.replacementText, true, "Text must change")

print("\n--- Test 10: Deterministic cycle EN -> RU -> UA -> EN from any starting language ---")
let detEngine = PuntoEngine()
let detSettings = PuntoSettings(switchingMode: .sequential)
let detLangs: [PuntoLanguage] = [.english, .russian, .ukrainian]

// 1. Starting with Russian: RU "сыр" -> UA "сір" -> EN "csh" -> RU "сыр"
let fromRu1 = detEngine.convertLayout("сыр", settings: detSettings, enabledLanguages: detLangs)
assertEqual(fromRu1.targetLanguage, .ukrainian, "Starting RU: step 1 must be UA")
let fromRu2 = detEngine.convertLayout(fromRu1.replacementText, settings: detSettings, enabledLanguages: detLangs)
assertEqual(fromRu2.targetLanguage, .english, "Starting RU: step 2 must be EN")
let fromRu3 = detEngine.convertLayout(fromRu2.replacementText, settings: detSettings, enabledLanguages: detLangs)
assertEqual(fromRu3.targetLanguage, .russian, "Starting RU: step 3 must be RU")

// 2. Starting with Ukrainian: UA "сір" -> EN "csh" -> RU "сыр" -> UA "сір"
let detEngineUa = PuntoEngine()
let fromUa1 = detEngineUa.convertLayout("сір", settings: detSettings, enabledLanguages: detLangs)
assertEqual(fromUa1.targetLanguage, .english, "Starting UA: step 1 must be EN")
let fromUa2 = detEngineUa.convertLayout(fromUa1.replacementText, settings: detSettings, enabledLanguages: detLangs)
assertEqual(fromUa2.targetLanguage, .russian, "Starting UA: step 2 must be RU")
let fromUa3 = detEngineUa.convertLayout(fromUa2.replacementText, settings: detSettings, enabledLanguages: detLangs)
assertEqual(fromUa3.targetLanguage, .ukrainian, "Starting UA: step 3 must be UA")

print("\n--- Test 11: Integrated terminal prompt classification ---")
// 1. Typical VS Code / Cursor generic AX element with role "AXTextArea", no title/desc/id, and value "user@mac:~$ "
let genericVsCodeTerminal = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextArea",
    title: nil,
    description: nil,
    identifier: nil,
    value: "user@mac:~$ "
)
assertEqual(genericVsCodeTerminal, true, "Generic VS Code AX element with 'user@mac:~$ ' must be classified as terminal")

// 2. Terminal prompt with zsh: "user@mac:~% "
let zshTerminal = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextArea",
    title: nil,
    description: nil,
    identifier: nil,
    value: "user@mac:~% "
)
assertEqual(zshTerminal, true, "Generic AX element with 'user@mac:~% ' must be classified as terminal")

// 3. Terminal prompt NOT at start of line: "[12:34:56] user@host:~% ls"
let midLineZsh = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextArea",
    title: nil,
    description: nil,
    identifier: nil,
    value: "[12:34:56] user@host:~% ls"
)
assertEqual(midLineZsh, true, "Prompt not at start of line '[12:34:56] user@host:~% ls' must be classified as terminal")

// 4. Terminal prompt with Starship in middle of line: "~/projects/Punto (main) ❯ git status"
let starshipTerminal = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextArea",
    title: nil,
    description: nil,
    identifier: nil,
    value: "~/projects/Punto (main) ❯ git status"
)
assertEqual(starshipTerminal, true, "Starship prompt with ❯ must be classified as terminal")

// 5. Terminal prompt with virtualenv and root: "(venv) root@server:/var/log# cat app.log"
let venvTerminal = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextArea",
    title: nil,
    description: nil,
    identifier: nil,
    value: "(venv) root@server:/var/log# cat app.log"
)
assertEqual(venvTerminal, true, "Virtualenv root prompt must be classified as terminal")

// 6. Normal code with $, %, > must NOT be classified as terminal
let normalCode1 = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextArea",
    title: nil,
    description: nil,
    identifier: nil,
    value: "if (count % 2 == 0) { return $total; }"
)
assertEqual(normalCode1, false, "Code 'if (count % 2 == 0) { return $total; }' must NOT be classified as terminal")

// 7. Code containing email and $ variable must NOT be classified as terminal
let normalCode2 = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextArea",
    title: nil,
    description: nil,
    identifier: nil,
    value: "const email = \"user@host.com\"; if ($var > 0) {}"
)
assertEqual(normalCode2, false, "Code with email and $var must NOT be classified as terminal")

// 8. Editor document containing prompt text in code/markdown must NOT be classified as terminal
let editorWithPromptText = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextArea",
    title: "README.md",
    description: "editor document",
    identifier: "workbench.parts.editor",
    value: "Run this command: user@mac:~$ ls"
)
assertEqual(editorWithPromptText, false, "Editor element containing prompt text must NOT be classified as terminal")

// 9. AXTextField without prompt in value must NOT be classified as terminal
let textFieldWithoutPrompt = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextField",
    title: nil,
    description: "Find",
    identifier: "findInput",
    value: "hello world"
)
assertEqual(textFieldWithoutPrompt, false, "AXTextField without prompt must NOT be classified as terminal")

// 10. AXTextField with prompt in value MUST be classified as terminal
let textFieldWithPrompt = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextField",
    title: nil,
    description: nil,
    identifier: nil,
    value: "user@mac:~$ ls"
)
assertEqual(textFieldWithPrompt, true, "AXTextField with prompt in value must be classified as terminal")

// 11. Description containing 'English' or other words ending in 'sh' must NOT match shell 'sh'
let englishDescription = AppEnvironmentClassifier.isIntegratedTerminal(
    role: "AXTextArea",
    title: nil,
    description: "English (US) text input",
    identifier: nil,
    value: "normal text without prompt"
)
assertEqual(englishDescription, false, "Description with 'English' must NOT match shell 'sh'")

print("\n--- Test 12: Read routing strategy strict resolution ---")
// 1. No accessibility -> .none (nil)
let noAxStrategy = AppEnvironmentClassifier.determineReadStrategy(
    appKind: .other,
    hasAccessibility: false,
    isEditable: false,
    isConfirmedGrid: false
)
assertEqual(noAxStrategy, .none, "No accessibility must return .none")

// 2. Browser editable -> .browserEditableCmdCFirst
let browserEditStrategy = AppEnvironmentClassifier.determineReadStrategy(
    appKind: .browser,
    hasAccessibility: true,
    isEditable: true,
    isConfirmedGrid: false
)
assertEqual(browserEditStrategy, .browserEditableCmdCFirst, "Browser editable must return .browserEditableCmdCFirst")

// 3. Browser non-editable normal page -> .none (must return nil, no synthetic keys)
let browserNormalStrategy = AppEnvironmentClassifier.determineReadStrategy(
    appKind: .browser,
    hasAccessibility: true,
    isEditable: false,
    isConfirmedGrid: false
)
assertEqual(browserNormalStrategy, .none, "Browser non-editable normal page must return .none")

// 4. Browser confirmed grid -> .browserConfirmedGrid
let browserGridStrategy = AppEnvironmentClassifier.determineReadStrategy(
    appKind: .browser,
    hasAccessibility: true,
    isEditable: false,
    isConfirmedGrid: true
)
assertEqual(browserGridStrategy, .browserConfirmedGrid, "Browser confirmed grid must return .browserConfirmedGrid")

// 5. Standalone terminal -> .terminalActiveLineAXValue
let standaloneStrategy = AppEnvironmentClassifier.determineReadStrategy(
    appKind: .standaloneTerminal,
    hasAccessibility: true,
    isEditable: false,
    isConfirmedGrid: false
)
assertEqual(standaloneStrategy, .terminalActiveLineAXValue, "Standalone terminal must return .terminalActiveLineAXValue")

// 6. Integrated terminal -> .terminalActiveLineAXValue
let integratedStrategy = AppEnvironmentClassifier.determineReadStrategy(
    appKind: .integratedTerminal,
    hasAccessibility: true,
    isEditable: true,
    isConfirmedGrid: false
)
assertEqual(integratedStrategy, .terminalActiveLineAXValue, "Integrated terminal must return .terminalActiveLineAXValue")

print("\n--- Test 13: Browser confirmed grid context detection ---")
// 1. Element with role AXCell
let isCellGrid = AppEnvironmentClassifier.isConfirmedGridContext(
    role: "AXCell",
    subrole: nil,
    roleDescription: nil,
    identifier: nil
)
assertEqual(isCellGrid, true, "AXCell must be confirmed grid")

// 2. Element with role AXTable
let isTableGrid = AppEnvironmentClassifier.isConfirmedGridContext(
    role: "AXTable",
    subrole: nil,
    roleDescription: nil,
    identifier: nil
)
assertEqual(isTableGrid, true, "AXTable must be confirmed grid")

// 3. Parent element with sheet keyword
let isParentSheetGrid = AppEnvironmentClassifier.isConfirmedGridContext(
    role: "AXGroup",
    subrole: nil,
    roleDescription: nil,
    identifier: "canvas-view",
    parentRole: "AXTable",
    parentDescription: "Spreadsheet"
)
assertEqual(isParentSheetGrid, true, "Parent with Spreadsheet description must be confirmed grid")

// 4. Normal web page element (div / article)
let isNormalWebArticle = AppEnvironmentClassifier.isConfirmedGridContext(
    role: "AXGroup",
    subrole: nil,
    roleDescription: "article",
    identifier: "post-content"
)
assertEqual(isNormalWebArticle, false, "Normal article div must NOT be confirmed grid")

print("\n--- Test 14: PuntoEngine sequential cycle continues ONLY when input matches textAfterConversion ---")
let cycleEngine = PuntoEngine()
var cycleSettings = PuntoSettings()
cycleSettings.switchingMode = .sequential
let test14Langs: [PuntoLanguage] = [.english, .russian, .ukrainian]

// Step 1: Initial word: "csh" (English) -> Russian "сыр"
let step1 = cycleEngine.convertLayout("csh", settings: cycleSettings, enabledLanguages: test14Langs)
cycleEngine.commitPendingConversion()
assertEqual(step1.targetLanguage, PuntoLanguage.russian, "Step 1: EN -> RU targetLanguage")
assertEqual(step1.replacementText, "сыр", "Step 1: EN -> RU text (сыр)")

// Step 2: Read text matches textAfterConversion ("сыр") -> continues cycle to Ukrainian "сір"
let step2 = cycleEngine.convertLayout("сыр", settings: cycleSettings, enabledLanguages: test14Langs)
cycleEngine.commitPendingConversion()
assertEqual(step2.targetLanguage, PuntoLanguage.ukrainian, "Step 2: Matches textAfterConversion -> continues to UA")
assertEqual(step2.replacementText, "сір", "Step 2: сыр -> Ukrainian сір")

// Step 3: Read text matches textAfterConversion ("сір") -> cycles back to English "csh"
let step3 = cycleEngine.convertLayout("сір", settings: cycleSettings, enabledLanguages: test14Langs)
cycleEngine.commitPendingConversion()
assertEqual(step3.targetLanguage, PuntoLanguage.english, "Step 3: Matches textAfterConversion -> cycles back to EN")
assertEqual(step3.replacementText, "csh", "Step 3: сір -> English csh")
assertEqual(step3.requiresTextReplacement, true, "Step 3: requiresTextReplacement MUST BE TRUE on return to English!")

// Step 4: If screen text does NOT match textAfterConversion (stale originalText "csh"),
// engine MUST NOT continue the cycle to Ukrainian; it starts a fresh conversion from detected source EN -> RU
let staleInputEngine = PuntoEngine()
let conv1 = staleInputEngine.convertLayout("csh", settings: cycleSettings, enabledLanguages: test14Langs)
staleInputEngine.commitPendingConversion()
assertEqual(conv1.replacementText, "сыр", "conv1 produced сыр")
// Stale read returns "csh" instead of "сыр":
let conv2Stale = staleInputEngine.convertLayout("csh", settings: cycleSettings, enabledLanguages: test14Langs)
assertEqual(conv2Stale.targetLanguage, PuntoLanguage.russian, "Stale 'csh' does NOT continue cycle to UA; starts fresh EN -> RU")
assertEqual(conv2Stale.replacementText, "сыр", "Stale 'csh' produces fresh 'сыр'")

print("\n--- Test 15: PuntoEngine sequential cycle with RU/UA identical word (git) ---")
let gitEngine = PuntoEngine()
let git1 = gitEngine.convertLayout("git", settings: cycleSettings, enabledLanguages: test14Langs)
gitEngine.commitPendingConversion()
assertEqual(git1.targetLanguage, PuntoLanguage.russian, "git Step 1: EN -> RU")
assertEqual(git1.replacementText, "пше", "git Step 1 text (пше)")
assertEqual(git1.requiresTextReplacement, true, "git Step 1 requiresTextReplacement")

// Step 2: Read text is "пше" (matches textAfterConversion). RU -> UA would produce identical "пше",
// so engine skips identical UA and cycles to EN "git"!
let git2 = gitEngine.convertLayout("пше", settings: cycleSettings, enabledLanguages: test14Langs)
gitEngine.commitPendingConversion()
assertEqual(git2.targetLanguage, PuntoLanguage.english, "git Step 2: skips identical UA -> cycles to EN")
assertEqual(git2.replacementText, "git", "git Step 2 text (git)")
assertEqual(git2.requiresTextReplacement, true, "git Step 2 requiresTextReplacement MUST BE TRUE!")

print("\n--- Test 16: Cyrillic fallback translation to English ---")
// Ukrainian layout translating Russian 'ы':
let ruWordWithUaSource = LayoutTransformer.transform("ыефегы", from: .ukrainian, to: .english)
assertEqual(ruWordWithUaSource, "status", "Cyrillic 'ыефегы' with UA source must translate to 'status'")

// Russian layout translating Ukrainian 'і':
let uaWordWithRuSource = LayoutTransformer.transform("іефегі", from: .russian, to: .english)
assertEqual(uaWordWithRuSource, "status", "Cyrillic 'іефегі' with RU source must translate to 'status'")

print("\n--- Test 17: Terminal AXValue prompt validation (stale/empty/output -> nil) ---")
// 1. Empty / nil / reader accessibility values -> nil
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: nil), nil, "nil AXValue -> nil")
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: ""), nil, "empty AXValue -> nil")
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "   \n\n  "), nil, "whitespace-only AXValue -> nil")
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "Screen Reader Accessibility"), nil, "Screen reader placeholder -> nil")

// 2. Terminal output without prompt indicators must NOT be treated as a command
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "[11:20:40] Build failed with exit code 1"), nil, "Compiler output -> nil")
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "drwxr-xr-x  12 user staff  384 Sep  6 11:20 Sources"), nil, "ls output -> nil")
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "npm error code ENOENT\nnpm error syscall open"), nil, "npm error log -> nil")

// 3. Stale prompt lines containing ONLY prompt characters -> nil
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "user@mac:~$ "), nil, "Bare prompt with trailing space -> nil")
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "user@mac:~$ $"), nil, "Bare prompt symbol -> nil")
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "❯ "), nil, "Bare Starship prompt -> nil")
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "➜ "), nil, "Bare Oh-My-Zsh prompt -> nil")

// 4. Valid prompt lines with active command
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "user@mac:~$ csh"), "csh", "Prompt command 'csh'")
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "user@mac:~/repo$ git status"), "status", "Prompt command 'status'")
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "❯ cargo build"), "build", "Starship prompt command 'build'")
assertEqual(AppEnvironmentClassifier.terminalPromptLastWord(from: "➜ punto-core git:(main) csh"), "csh", "Zsh prompt command 'csh'")

print("\n--- Test 18: Integrated terminal replacement plan (Backspace wordLength times, Cmd+V, no Ctrl+W) ---")
let plan5 = AppEnvironmentClassifier.integratedTerminalReplacementPlan(wordLength: 5, replacement: "hello")
assertEqual(plan5.count, 2, "Integrated terminal plan must have exactly 2 actions")
assertEqual(plan5[0], SyntheticKeyAction.backspace(count: 5), "Action 0: Backspace exactly 5 times")
assertEqual(plan5[1], SyntheticKeyAction.cmdV(text: "hello"), "Action 1: Cmd+V with replacement text")
assertEqual(plan5.contains(.ctrlW), false, "Integrated terminal plan must NEVER contain Ctrl+W")
assertEqual(plan5.contains(.cmdC), false, "Integrated terminal plan must NEVER contain Cmd+C")

let plan0 = AppEnvironmentClassifier.integratedTerminalReplacementPlan(wordLength: 0, replacement: "")
assertEqual(plan0.isEmpty, true, "Plan with wordLength 0 is empty")

print("\n--- Test 19: Firefox routing & outcome invariants ---")
// 1. Firefox must NOT use AXSelectedTextRange
assertEqual(AppEnvironmentClassifier.supportsAXSelectedTextRange(bundleIdentifier: "org.mozilla.firefox"), false, "Firefox does NOT support AXSelectedTextRange")
assertEqual(AppEnvironmentClassifier.supportsAXSelectedTextRange(bundleIdentifier: "com.google.Chrome"), true, "Chrome supports AXSelectedTextRange")

// 2. Strategy for Firefox editable fields must start with Cmd+C
let ffKind = AppEnvironmentClassifier.appKind(bundleIdentifier: "org.mozilla.firefox")
assertEqual(ffKind, AppEnvironmentClassifier.AppKind.browser, "Firefox must classify as .browser")
let ffEditableStrategy = AppEnvironmentClassifier.determineReadStrategy(
    appKind: ffKind,
    hasAccessibility: true,
    isEditable: true,
    isConfirmedGrid: false
)
assertEqual(ffEditableStrategy, AppEnvironmentClassifier.ReadStrategy.browserEditableCmdCFirst, "Firefox editable uses .browserEditableCmdCFirst")

// 3. ReplaceOutcome states
let deliveredUnconfirmed: ReplaceOutcome = .deliveredUnconfirmedAX
let failedOutcome: ReplaceOutcome = .failed
let verifiedOutcome: ReplaceOutcome = .successVerified
assertEqual(deliveredUnconfirmed != failedOutcome, true, "deliveredUnconfirmedAX does NOT equal failed (avoids false error)")
assertEqual(deliveredUnconfirmed != verifiedOutcome, true, "deliveredUnconfirmedAX does NOT equal successVerified (avoids corrupting sequential cycle)")

print("\n🎉 ALL PUNTOCORE AUTONOMOUS TESTS PASSED!")

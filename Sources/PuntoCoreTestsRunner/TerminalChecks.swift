import Foundation
import PuntoCore

func runTerminalChecks() {
    print("\n--- Terminal identity and exact caret scanning regressions ---")
    typealias Identity = AppEnvironmentClassifier.ElementIdentity
    let xterm = Identity(role: "AXGroup", identifier: "terminal-wrapper xterm")
    let unknown = Identity(role: "AXTextArea")
    for bundle in ["com.microsoft.VSCode", "com.google.antigravity"] {
        assertEqual(AppEnvironmentClassifier.classify(bundleIdentifier: bundle,
            focusedElement: unknown, ancestors: [xterm]), .integratedTerminal,
            "Terminal ancestor routes IDE input")
        assertEqual(AppEnvironmentClassifier.classify(bundleIdentifier: bundle,
            focusedElement: Identity(role: "AXTextArea", title: "Editor"), ancestors: [xterm]),
            .codeEditor, "Editor identity stops terminal ancestor search")
    }
    assertEqual(AppEnvironmentClassifier.classify(bundleIdentifier: "org.mozilla.firefox",
        focusedElement: unknown, ancestors: [xterm]), .browser, "Browser terminal text stays browser")
    assertEqual(AppEnvironmentClassifier.isIntegratedTerminal(role: "AXTextArea", title: nil,
        description: nil, identifier: nil, value: "user@host:~$ ghbdtn"), false,
        "Prompt text alone does not identify terminal")
    assertEqual(AppEnvironmentClassifier.isIntegratedTerminal(role: "AXTextArea", title: nil,
        description: nil, identifier: nil, value: nil,
        ancestors: [Identity(role: "AXWindow", title: "Terminal — editor")]), false,
        "Window title cannot identify focused terminal")
    for bundle in ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"] {
        assertEqual(AppEnvironmentClassifier.isFirefox(bundleIdentifier: bundle), true, "Firefox family recognized")
        assertEqual(AppEnvironmentClassifier.supportsAXSelectedTextRange(bundleIdentifier: bundle), false,
                    "Firefox family uses consistent selected range policy")
    }
    for text in ["word\n", "word\r\n", "word\n \t"] {
        assertEqual(TextScanner.scanLastWord(in: text)?.word, nil, "No previous line scan at empty caret line")
    }
    let buffer = "😀 prefix ghbdtn \t\u{00A0}suffix"
    let caret = buffer.index(buffer.endIndex, offsetBy: -6)
    let prefix = buffer[..<caret]
    let scanned = TextScanner.scanLastWord(in: prefix)!
    assertEqual(scanned.word, "ghbdtn", "Scan only actual left buffer")
    assertEqual(scanned.trailingWhitespace, " \t\u{00A0}", "Preserve exact space/tab/NBSP")
    var replaced = buffer
    replaced.replaceSubrange(scanned.wordRange, with: "привет")
    assertEqual(replaced, "😀 prefix привет \t\u{00A0}suffix", "Exact ranges preserve prefix, whitespace and right buffer")
    assertEqual(TextScanner.lastWord(in: String(repeating: "a", count: 300))?.word.count, 300,
                "300 UTF16 word accepted")
    assertEqual(TextScanner.lastWord(in: String(repeating: "a", count: 301))?.word, nil,
                "301 UTF16 word declined")
}

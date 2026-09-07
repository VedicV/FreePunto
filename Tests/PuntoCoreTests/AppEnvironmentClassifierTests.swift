import XCTest

@testable import PuntoCore

final class AppEnvironmentClassifierTests: XCTestCase {
    func testRecognizesVSCodeFamilyBundleIdentifiers() {
        XCTAssertTrue(AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: "com.microsoft.VSCode"))
        XCTAssertTrue(AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: "com.microsoft.VSCodeInsiders"))
        XCTAssertTrue(AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: "com.todesktop.230313mzl4w4u92"))
        XCTAssertTrue(AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: "com.google.antigravity"))
        XCTAssertTrue(AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: "com.google.antigravity-ide"))
        XCTAssertFalse(AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: "com.apple.Terminal"))
    }

    func testDetectsIntegratedTerminalContextInsideVSCodeFamily() {
        XCTAssertTrue(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: "AXTextArea",
                title: "Terminal",
                description: nil,
                identifier: nil,
                value: nil
            )
        )

        XCTAssertTrue(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: "AXTextArea",
                title: nil,
                description: "Terminal shell",
                identifier: "terminal",
                value: nil
            )
        )

        XCTAssertFalse(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: "AXTextArea",
                title: "Untitled-1",
                description: nil,
                identifier: nil,
                value: nil
            )
        )

        XCTAssertFalse(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: "AXTextArea",
                title: nil,
                description: nil,
                identifier: nil,
                value: nil
            )
        )

        XCTAssertFalse(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: nil,
                title: nil,
                description: nil,
                identifier: nil,
                value: nil
            )
        )
    }

    func testIntegratedTerminalShellNamesStayScopedToElementProperties() {
        // Назви оболонок у властивостях елемента мають розпізнаватися
        XCTAssertTrue(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: nil,
                title: "zsh",
                description: nil,
                identifier: nil,
                value: nil
            )
        )
        XCTAssertTrue(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: nil,
                title: nil,
                description: "active bash shell",
                identifier: nil,
                value: nil
            )
        )

        // Назви оболонок у назві файлу НЕ мають призводити до хибного детекту терміналу
        XCTAssertFalse(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: "AXTextArea",
                title: ".zshrc",
                description: nil,
                identifier: nil,
                value: nil
            )
        )
        XCTAssertFalse(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: "AXTextArea",
                title: "script.sh",
                description: nil,
                identifier: nil,
                value: nil
            )
        )
    }
}

extension AppEnvironmentClassifierTests {
    func testFilenameDoesNotConfirmTerminal() {
        for title in ["terminal.swift", "shell.md", "script.sh", ".zshrc", "/tmp/terminal"] {
            XCTAssertFalse(AppEnvironmentClassifier.isIntegratedTerminal(
                role: "AXTextArea", title: title, description: nil, identifier: nil, value: nil))
        }
    }

    func testPromptTextNeverConfirmsTerminal() {
        for role in ["AXTextArea", "AXTextField"] {
            for text in ["user@host:~$ command", "❯ ghbdtn", "(venv) root@host:~# ls"] {
                XCTAssertFalse(AppEnvironmentClassifier.isIntegratedTerminal(
                    role: role, title: nil, description: nil, identifier: nil, value: text))
            }
        }
    }

    func testAncestorsRequireLocalIdentityAndRespectEditorBoundary() {
        typealias Identity = AppEnvironmentClassifier.ElementIdentity
        let terminal = Identity(role: "AXGroup", identifier: "xterm-wrapper")
        XCTAssertEqual(AppEnvironmentClassifier.classify(bundleIdentifier: "com.google.antigravity",
            focusedElement: Identity(role: "AXTextArea"), ancestors: [terminal]), .integratedTerminal)
        XCTAssertEqual(AppEnvironmentClassifier.classify(bundleIdentifier: "com.microsoft.VSCode",
            focusedElement: Identity(role: "AXTextArea", description: "editor document"),
            ancestors: [terminal]), .codeEditor)
        XCTAssertEqual(AppEnvironmentClassifier.classify(bundleIdentifier: "com.microsoft.VSCode",
            focusedElement: Identity(role: "AXTextArea"),
            ancestors: [Identity(role: "AXWindow", title: "zsh terminal")]), .codeEditor)
        XCTAssertEqual(AppEnvironmentClassifier.classify(bundleIdentifier: "com.google.antigravity",
            focusedElement: Identity(role: "AXTextArea"),
            ancestors: [Identity(role: "AXGroup", title: "Agent"), terminal]), .integratedTerminal)
    }

    func testFirefoxRangePolicyAppliesToFamily() {
        for bundle in ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
                       "org.mozilla.nightly", "org.mozilla.firefoxnightly"] {
            XCTAssertTrue(AppEnvironmentClassifier.isFirefox(bundleIdentifier: bundle))
            XCTAssertTrue(AppEnvironmentClassifier.isBrowser(bundleIdentifier: bundle))
            XCTAssertFalse(AppEnvironmentClassifier.supportsAXSelectedTextRange(bundleIdentifier: bundle))
        }
        XCTAssertTrue(AppEnvironmentClassifier.supportsAXSelectedTextRange(bundleIdentifier: "com.google.Chrome"))
    }

    func testTerminalAndStaticBrowserRemainRoutable() {
        XCTAssertEqual(AppEnvironmentClassifier.determineReadStrategy(
            appKind: .standaloneTerminal, hasAccessibility: true,
            isEditable: false, isConfirmedGrid: false), .terminalSelectionOrPrompt)
        XCTAssertEqual(AppEnvironmentClassifier.determineReadStrategy(
            appKind: .integratedTerminal, hasAccessibility: true,
            isEditable: true, isConfirmedGrid: false), .terminalSelectionOrPrompt)
        XCTAssertEqual(AppEnvironmentClassifier.determineReadStrategy(
            appKind: .browser, hasAccessibility: true,
            isEditable: false, isConfirmedGrid: false), .browserSelectionCmdC)
    }

    func testChromiumFamilyUsesKeyboardSelectionFallback() {
        for bundle in ["com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser",
                       "com.microsoft.edgemac", "org.chromium.Chromium"] {
            XCTAssertTrue(AppEnvironmentClassifier.isChromium(bundleIdentifier: bundle))
        }
        XCTAssertFalse(AppEnvironmentClassifier.isChromium(bundleIdentifier: "org.mozilla.firefox"))
    }

    func testFocusedPasteVerificationIsScopedToMonacoAndChromiumCopy() {
        XCTAssertTrue(AppEnvironmentClassifier.allowsFocusedPasteVerification(
            bundleIdentifier: "com.google.antigravity-ide",
            isConfirmedEditorSurface: true,
            isCopiedBrowserSelection: false))
        XCTAssertTrue(AppEnvironmentClassifier.allowsFocusedPasteVerification(
            bundleIdentifier: "com.google.Chrome",
            isConfirmedEditorSurface: false,
            isCopiedBrowserSelection: true))
        XCTAssertFalse(AppEnvironmentClassifier.allowsFocusedPasteVerification(
            bundleIdentifier: "com.google.Chrome",
            isConfirmedEditorSurface: false,
            isCopiedBrowserSelection: false))
        XCTAssertFalse(AppEnvironmentClassifier.allowsFocusedPasteVerification(
            bundleIdentifier: "com.apple.Safari",
            isConfirmedEditorSurface: false,
            isCopiedBrowserSelection: true))
    }

    func testTerminalPromptTargetCarriesBackspaceCount() {
        XCTAssertEqual(AppEnvironmentClassifier.terminalPromptTarget(from: "user@mac:~$ ghbdtn"),
                       .init(word: "ghbdtn", backspaceCount: 6))
        XCTAssertNil(AppEnvironmentClassifier.terminalPromptTarget(from: "build output"))
    }
}

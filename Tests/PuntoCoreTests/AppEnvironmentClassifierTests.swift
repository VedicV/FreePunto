import XCTest

@testable import PuntoCore

final class AppEnvironmentClassifierTests: XCTestCase {
    func testRecognizesVSCodeFamilyBundleIdentifiers() {
        XCTAssertTrue(AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: "com.microsoft.VSCode"))
        XCTAssertTrue(AppEnvironmentClassifier.isVSCodeFamily(bundleIdentifier: "com.microsoft.VSCodeInsiders"))
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
                windowTitle: nil,
                value: nil
            )
        )

        XCTAssertTrue(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: "AXTextArea",
                title: nil,
                description: "Terminal shell",
                identifier: "terminal",
                windowTitle: nil,
                value: nil
            )
        )

        XCTAssertFalse(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: "AXTextArea",
                title: "Untitled-1",
                description: nil,
                identifier: nil,
                windowTitle: nil,
                value: nil
            )
        )

        XCTAssertTrue(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: "AXTextArea",
                title: nil,
                description: nil,
                identifier: nil,
                windowTitle: "Terminal — zsh",
                value: nil
            )
        )

        XCTAssertTrue(
            AppEnvironmentClassifier.isIntegratedTerminal(
                role: nil,
                title: nil,
                description: nil,
                identifier: nil,
                windowTitle: "Terminal — zsh",
                value: nil
            )
        )
    }
}

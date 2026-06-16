import XCTest

@testable import PuntoCore

final class AccessibilityTextSelectionTests: XCTestCase {
    func testCellValueIsPreferredForCanvasLikeCells() {
        XCTAssertEqual(
            AccessibilityTextSelection.preferredText(
                selectedText: "A1\nB2\nC3",
                valueText: "active cell",
                role: "AXCell"
            ),
            "active cell"
        )
    }

    func testSelectedTextStillWinsForRegularTextFields() {
        XCTAssertEqual(
            AccessibilityTextSelection.preferredText(
                selectedText: "selected text",
                valueText: "full field text",
                role: "AXTextField"
            ),
            "selected text"
        )
    }

    func testFallsBackToValueTextWhenSelectionIsEmpty() {
        XCTAssertEqual(
            AccessibilityTextSelection.preferredText(
                selectedText: "",
                valueText: "cell value",
                role: "AXCell"
            ),
            "cell value"
        )
    }
}

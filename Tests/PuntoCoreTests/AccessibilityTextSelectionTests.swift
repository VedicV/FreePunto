import XCTest

@testable import PuntoCore

// Тестуємо логіку вибору тексту для перетворення, особливо для випадків, коли роль елемента Accessibility може вказувати на те, що це клітинка в таблиці або канвас, де значення може бути більш релевантним для трансформації, ніж виділений текст. Це важливо для забезпечення коректного вибору тексту в різних контекстах застосунків, таких як електронні таблиці або спеціалізовані редактори.
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

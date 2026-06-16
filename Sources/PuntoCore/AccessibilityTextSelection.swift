import Foundation

public enum AccessibilityTextSelection {
    public static func preferredText(
        selectedText: String?,
        valueText: String?,
        role: String?
    ) -> String? {
        let normalizedSelected = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = valueText?.trimmingCharacters(in: .whitespacesAndNewlines)

        let cellRole = role == "AXCell" || role == "AXTableCell" || role == "AXGroup"
        let selectedLooksLikeRange = normalizedSelected?.contains("\t") == true
            || normalizedSelected?.contains("\n") == true

        if cellRole, let normalizedValue, !normalizedValue.isEmpty {
            if selectedLooksLikeRange {
                return normalizedValue
            }
            if let normalizedSelected, !normalizedSelected.isEmpty,
                normalizedSelected != normalizedValue
            {
                return normalizedValue
            }
        }

        if let normalizedSelected, !normalizedSelected.isEmpty {
            return normalizedSelected
        }

        if let normalizedValue, !normalizedValue.isEmpty {
            return normalizedValue
        }

        return nil
    }
}

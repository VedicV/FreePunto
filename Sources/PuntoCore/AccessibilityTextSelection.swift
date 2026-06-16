import Foundation

// * -- Вибір кращого тексту з Accessibility API --
public enum AccessibilityTextSelection {
    // * -- Визначення пріоритетного текстового значення --
    public static func preferredText(
        selectedText: String?,
        valueText: String?,
        role: String?
    ) -> String? {
        // Очищаємо пробіли та символи нового рядка для точного порівняння.
        let normalizedSelected = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = valueText?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Перевіряємо, чи є елемент табличною коміркою або групою.
        let cellRole = role == "AXCell" || role == "AXTableCell" || role == "AXGroup"
        // Виділений текст вважається діапазоном, якщо містить знаки табуляції чи нового рядка.
        let selectedLooksLikeRange = normalizedSelected?.contains("\t") == true
            || normalizedSelected?.contains("\n") == true

        // Якщо це комірка і є значення, надаємо йому пріоритет.
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

        // Повертаємо виділений текст, якщо він не порожній.
        if let normalizedSelected, !normalizedSelected.isEmpty {
            return normalizedSelected
        }

        // Якщо виділеного тексту немає, повертаємо загальне значення елемента.
        if let normalizedValue, !normalizedValue.isEmpty {
            return normalizedValue
        }

        return nil
    }
}

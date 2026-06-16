import AppKit
import ApplicationServices
import PuntoCore

// * -- Діагностика прав доступу та виведення системних вікон --
enum Diagnostics {
    // * -- Перевірка, чи має застосунок доступ до Accessibility (доступності) --
    static func accessibilityTrusted(prompt: Bool) -> Bool {
        // Параметр prompt визначає, чи показувати системний діалог macOS, якщо доступ відсутній.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // * -- Відображення вікна з інформацією про стан дозволів доступності --
    static func showPermissionsWindow(language: InterfaceLanguage = .systemDefault) {
        let trusted = accessibilityTrusted(prompt: true)
        let alert = NSAlert()
        alert.messageText = AppText.get(.permissionsTitle, language)
        alert.informativeText = trusted
            ? AppText.get(.permissionsEnabledDetail, language)
            : AppText.get(.permissionsMissingDetail, language)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // * -- Відображення вікна помилки (модального попередження) --
    static func showError(_ message: String, detail: String? = nil, language: InterfaceLanguage = .systemDefault) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail ?? ""
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

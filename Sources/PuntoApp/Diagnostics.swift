import AppKit
import ApplicationServices
import PuntoCore

enum Diagnostics {
    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func showPermissionsWindow(language: InterfaceLanguage = .russian) {
        let trusted = accessibilityTrusted(prompt: true)
        let alert = NSAlert()
        alert.messageText = AppText.get(.permissionsTitle, language)
        alert.informativeText = trusted
            ? AppText.get(.permissionsEnabledDetail, language)
            : AppText.get(.permissionsMissingDetail, language)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func showError(_ message: String, detail: String? = nil, language: InterfaceLanguage = .russian) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail ?? ""
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

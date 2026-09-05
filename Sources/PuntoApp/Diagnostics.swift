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

    // * -- Відкриття Системних параметрів на сторінці Доступності --
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // * -- Відкриття Системних параметрів на сторінці Моніторингу вводу --
    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // * -- Відображення вікна з інформацією про стан дозволів доступності --
    static func showPermissionsWindow(language: InterfaceLanguage = .systemDefault) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                showPermissionsWindow(language: language)
            }
            return
        }

        let trusted = accessibilityTrusted(prompt: false)
        let alert = NSAlert()
        alert.messageText = AppText.get(.permissionsTitle, language)
        alert.informativeText = trusted
            ? AppText.get(.permissionsEnabledDetail, language)
            : AppText.get(.permissionsMissingDetail, language)

        alert.addButton(withTitle: AppText.get(.openAccessibility, language))
        alert.addButton(withTitle: AppText.get(.openInputMonitoring, language))
        let closeButton = alert.addButton(withTitle: AppText.get(.close, language))
        closeButton.keyEquivalent = "\u{1b}"

        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if !trusted {
                _ = accessibilityTrusted(prompt: true)
            }
            openAccessibilitySettings()
        case .alertSecondButtonReturn:
            openInputMonitoringSettings()
        default:
            break
        }
    }

    // * -- Відображення вікна помилки (модального попередження) --
    static func showError(_ message: String, detail: String? = nil, language: InterfaceLanguage = .systemDefault) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                showError(message, detail: detail, language: language)
            }
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail ?? ""
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

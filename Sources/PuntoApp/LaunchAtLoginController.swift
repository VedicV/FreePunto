import Foundation
import ServiceManagement

// * -- Управління автозапуском застосунку при вході в систему --
enum LaunchAtLoginController {
    // * -- Увімкнення або вимкнення запуску при вході --
    static func setEnabled(_ enabled: Bool) throws {
        // Використовуємо новий API SMAppService, доступний починаючи з macOS 13.0
        if #available(macOS 13.0, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}

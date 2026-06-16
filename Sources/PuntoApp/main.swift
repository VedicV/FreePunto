import AppKit

// * -- Точка входу в застосунок та запобігання запуску копій --
if let bundleIdentifier = Bundle.main.bundleIdentifier {
   
    // Шукаємо вже запущені екземпляри застосунку з таким самим bundle identifier.
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    let otherInstances = runningApps.filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    
    // Якщо знайдено іншу працюючу копію застосунку, завершуємо поточний процес.
    if !otherInstances.isEmpty {
        exit(0)
    }
}

// * -- Ініціалізація та запуск головного циклу подій NSApplication --
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate

// Задаємо політику активації як accessory (застосунок відображається тільки в статус-барі, без Dock).
application.setActivationPolicy(.accessory)
application.run()

import AppKit

if let bundleIdentifier = Bundle.main.bundleIdentifier {
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    let otherInstances = runningApps.filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !otherInstances.isEmpty {
        exit(0)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

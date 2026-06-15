import Foundation
import PuntoCore

final class AppState {
    let engine = PuntoEngine()
    let settingsStore: SettingsStore
    var onSettingsChanged: (() -> Void)?

    var settings: PuntoSettings {
        didSet {
            settingsStore.save(settings)
            onSettingsChanged?()
        }
    }

    init(settingsStore: SettingsStore = SettingsStore()) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
    }

    func toggleEnabled() {
        settings.isEnabled.toggle()
        if !settings.isEnabled {
            engine.resetContext()
        }
    }
}

import Foundation
import PuntoCore

final class SettingsStore {
    private let key = "freepunto.settings.v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PuntoSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? decoder.decode(PuntoSettings.self, from: data) else {
            return .default
        }
        return settings.schemaVersion == PuntoSettings.default.schemaVersion ? settings : .default
    }

    func save(_ settings: PuntoSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

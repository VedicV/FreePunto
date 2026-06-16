import Foundation
import PuntoCore

// * -- Збереження та завантаження налаштувань користувача --
final class SettingsStore {
    private let key = "freepunto.settings.v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // * -- Ініціалізація сховища налаштувань --
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // * -- Завантаження збережених налаштувань із UserDefaults --
    func load() -> PuntoSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? decoder.decode(PuntoSettings.self, from: data) else {
            return .default
        }
        // Перевіряємо версію схеми: якщо вона застаріла, повертаємо дефолтні налаштування
        return settings.schemaVersion == PuntoSettings.default.schemaVersion ? settings : .default
    }

    // * -- Збереження поточних налаштувань у UserDefaults --
    func save(_ settings: PuntoSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

import Foundation
import PuntoCore

// * -- Управління станом застосунку та налаштуваннями --
final class AppState {
    let engine = PuntoEngine()
    let settingsStore: SettingsStore
    
    // Обробник зміни налаштувань (для сповіщення AppDelegate та перезбирання статус-меню)
    var onSettingsChanged: (() -> Void)?

    // Поточні налаштування застосунку з автоматичним збереженням при зміні
    var settings: PuntoSettings {
        didSet {
            settingsStore.save(settings)
            onSettingsChanged?()
        }
    }

    // * -- Ініціалізація та завантаження збережених налаштувань --
    init(settingsStore: SettingsStore = SettingsStore()) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
    }

    // * -- Увімкнення/вимкнення перехоплення клавіш --
    func toggleEnabled() {
        settings.isEnabled.toggle()
        // При вимкненні скидаємо контекст попередніх перетворень, щоб запобігти помилковим циклам
        if !settings.isEnabled {
            engine.resetContext()
        }
    }
}

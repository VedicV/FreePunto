import AppKit
import PuntoCore

// * -- Иконка для строки меню --
enum StatusIconFactory {
    enum Kind {
        case language(PuntoLanguage, fixedMode: Bool)
        case paused
    }

    // * -- Создание текущей иконки статуса --
    static func make(_ kind: Kind) -> NSImage {
        switch kind {
        case .language(let language, let fixedMode):
            return languageIcon(language.statusTitle, fixedMode: fixedMode)
        case .paused:
            return pauseIcon()
        }
    }

    // Рисуем узкую клавишу: снизу слева `⌃`, сверху справа язык или пауза.
    private static func languageIcon(_ text: String, fixedMode: Bool) -> NSImage {
        keyIcon(topRight: .text(text), fixedMode: fixedMode)
    }

    // Значок паузы рисуем как две вертикальные полосы, привычные по магнитофону.
    private static func pauseIcon() -> NSImage {
        keyIcon(topRight: .pause, fixedMode: false)
    }

    private enum TopRight {
        case text(String)
        case pause
    }

    private static func keyIcon(topRight: TopRight, fixedMode: Bool) -> NSImage {

        // РАЗМЕР ХОЛСТА ИКОНКИ: Ширина 23 (меньше ширина - меньше отступы до соседей), высота 18
        let size = NSSize(width: 23, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            NSColor.clear.setFill()
            rect.fill()

            // КОНТУР КЛАВИШИ: x: 1 (отступ слева), y: 1 (отступ снизу), ширина 21, высота 15
            let key = NSRect(x: 1, y: 1, width: 21, height: 15)
            let keyPath = NSBezierPath(roundedRect: key, xRadius: 2.6, yRadius: 2.6)
            NSColor.black.setStroke()

            // ТОЛЩИНА ЛИНИИ КОНТУРА КЛАВИШИ (сейчас 1.0)
            keyPath.lineWidth = 1.0
            keyPath.stroke()

            // НАСТРОЙКИ СИМВОЛА "⌃" (размер шрифта, жирность)
            let controlAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8.2, weight: .bold),
                .foregroundColor: NSColor.black,
            ]
            // ОТРИСОВКА "⌃": x: 3.2, y: 0.6 (координаты левого нижнего угла символа)
            NSAttributedString(string: "⌃", attributes: controlAttributes).draw(
                at: NSPoint(x: 3.2, y: 0.6))

            switch topRight {
            case .text(let text):

                // НАСТРОЙКИ ТЕКСТА ЯЗЫКА (RU/EN): шрифт, размер, начертание
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 6.8, weight: .heavy),
                    .foregroundColor: NSColor.black,
                ]
                let label = NSAttributedString(string: text, attributes: attributes)
                let textSize = label.size()

                // ОТРИСОВКА ТЕКСТА ЯЗЫКА: x: 19.0 - ширина текста (выравнивание по правому краю), y: 5.8
                label.draw(at: NSPoint(x: 19.0 - textSize.width, y: 5.8))
            case .pause:
                NSColor.black.setFill()

                // ЛЕВАЯ ПОЛОСА ПАУЗЫ: x: 13.0, y: 6.0, ширина 2.0, высота 5.6
                NSBezierPath(
                    roundedRect: NSRect(x: 13.0, y: 6.0, width: 2.0, height: 5.6), xRadius: 0.6,
                    yRadius: 0.6
                ).fill()

                // ПРАВАЯ ПОЛОСА ПАУЗЫ: x: 16.0, y: 6.0, ширина 2.0, высота 5.6
                NSBezierPath(
                    roundedRect: NSRect(x: 16.0, y: 6.0, width: 2.0, height: 5.6), xRadius: 0.6,
                    yRadius: 0.6
                ).fill()
            }

            if fixedMode {
                NSColor.black.setFill()

                // ИНДИКАТОР ФИКСИРОВАННОГО РЕЖИМА (круг): x: 3.0, y: 10.5, ширина/высота 2.2 (диаметр)
                NSBezierPath(ovalIn: NSRect(x: 3.0, y: 10.5, width: 2.2, height: 2.2)).fill()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}

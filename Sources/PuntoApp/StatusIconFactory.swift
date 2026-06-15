import AppKit
import PuntoCore

// * -- Іконка для рядка меню --
enum StatusIconFactory {
    enum Kind {
        case language(PuntoLanguage, fixedMode: Bool)
        case paused
    }

    // * -- Створення поточної іконки статусу --
    static func make(_ kind: Kind) -> NSImage {
        switch kind {
        case .language(let language, let fixedMode):
            return languageIcon(language.statusTitle, fixedMode: fixedMode)
        case .paused:
            return pauseIcon()
        }
    }

    // Малюємо вузьку клавішу: знизу ліворуч `⌃`, зверху праворуч мова або пауза.
    private static func languageIcon(_ text: String, fixedMode: Bool) -> NSImage {
        keyIcon(topRight: .text(text), fixedMode: fixedMode)
    }

    // Значок паузи малюємо як дві вертикальні смуги.
    private static func pauseIcon() -> NSImage {
        keyIcon(topRight: .pause, fixedMode: false)
    }

    private enum TopRight {
        case text(String)
        case pause
    }

    private static func keyIcon(topRight: TopRight, fixedMode: Bool) -> NSImage {

        // РОЗМІР ПОЛОТНА ІКОНКИ: ширина 23 (менша ширина - менші відступи до сусідів), висота 18.
        let size = NSSize(width: 23, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            NSColor.clear.setFill()
            rect.fill()

            // КОНТУР КЛАВІШІ: x: 1 (відступ зліва), y: 1 (відступ знизу), ширина 21, висота 15.
            let key = NSRect(x: 1, y: 1, width: 21, height: 15)
            let keyPath = NSBezierPath(roundedRect: key, xRadius: 2.6, yRadius: 2.6)
            NSColor.black.setStroke()

            // ТОВЩИНА ЛІНІЇ КОНТУРУ КЛАВІШІ (зараз 1.0).
            keyPath.lineWidth = 1.0
            keyPath.stroke()

            // НАЛАШТУВАННЯ СИМВОЛА "⌃" (розмір шрифту, жирність).
            let controlAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8.2, weight: .bold),
                .foregroundColor: NSColor.black,
            ]
            // МАЛЮВАННЯ "⌃": x: 3.2, y: 0.6 (координати лівого нижнього кута символа).
            NSAttributedString(string: "⌃", attributes: controlAttributes).draw(
                at: NSPoint(x: 3.2, y: 0.6))

            switch topRight {
            case .text(let text):

                // НАЛАШТУВАННЯ ТЕКСТУ МОВИ (RU/EN): шрифт, розмір, накреслення.
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 6.8, weight: .heavy),
                    .foregroundColor: NSColor.black,
                ]
                let label = NSAttributedString(string: text, attributes: attributes)
                let textSize = label.size()

                // МАЛЮВАННЯ ТЕКСТУ МОВИ: x: 19.0 - ширина тексту (вирівнювання праворуч), y: 5.8.
                label.draw(at: NSPoint(x: 19.0 - textSize.width, y: 5.8))
            case .pause:
                NSColor.black.setFill()

                // ЛІВА СМУГА ПАУЗИ: x: 13.0, y: 6.0, ширина 2.0, висота 5.6.
                NSBezierPath(
                    roundedRect: NSRect(x: 13.0, y: 6.0, width: 2.0, height: 5.6), xRadius: 0.6,
                    yRadius: 0.6
                ).fill()

                // ПРАВА СМУГА ПАУЗИ: x: 16.0, y: 6.0, ширина 2.0, висота 5.6.
                NSBezierPath(
                    roundedRect: NSRect(x: 16.0, y: 6.0, width: 2.0, height: 5.6), xRadius: 0.6,
                    yRadius: 0.6
                ).fill()
            }

            if fixedMode {
                NSColor.black.setFill()

                // ІНДИКАТОР ФІКСОВАНОГО РЕЖИМУ (коло): x: 3.0, y: 10.5, ширина/висота 2.2 (діаметр).
                NSBezierPath(ovalIn: NSRect(x: 3.0, y: 10.5, width: 2.2, height: 2.2)).fill()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}

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
        case let .language(language, fixedMode):
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
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let key = NSRect(x: 2, y: 2, width: 20, height: 14)
        let keyPath = NSBezierPath(roundedRect: key, xRadius: 2.6, yRadius: 2.6)
        NSColor.black.setStroke()
        keyPath.lineWidth = 1.5
        keyPath.stroke()

        let controlAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.2, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        NSAttributedString(string: "⌃", attributes: controlAttributes).draw(at: NSPoint(x: 4.2, y: 2.6))

        switch topRight {
        case let .text(text):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 6.8, weight: .heavy),
                .foregroundColor: NSColor.black,
                .kern: -0.45
            ]
            let label = NSAttributedString(string: text, attributes: attributes)
            let textSize = label.size()
            label.draw(at: NSPoint(x: 20.0 - textSize.width, y: 8.1))
        case .pause:
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 14.0, y: 8.3, width: 2.0, height: 5.6), xRadius: 0.6, yRadius: 0.6).fill()
            NSBezierPath(roundedRect: NSRect(x: 17.0, y: 8.3, width: 2.0, height: 5.6), xRadius: 0.6, yRadius: 0.6).fill()
        }

        if fixedMode {
            NSBezierPath(ovalIn: NSRect(x: 4.0, y: 12.0, width: 2.2, height: 2.2)).fill()
        }

        image.isTemplate = true
        return image
    }
}

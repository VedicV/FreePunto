import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let icons: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in icons {
    let image = makeIcon(size: size)
    let destination = outputURL.appendingPathComponent(name)
    try writePNG(image, to: destination)
}

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let scale = size / 1024.0
    NSGraphicsContext.current?.imageInterpolation = .high

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let outer = canvas.insetBy(dx: 44 * scale, dy: 44 * scale)
    let radius = 210 * scale
    let outerPath = NSBezierPath(roundedRect: outer, xRadius: radius, yRadius: radius)
    NSGraphicsContext.current?.saveGraphicsState()
    outerPath.addClip()

    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.62, blue: 0.72, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.23, blue: 0.48, alpha: 1),
        NSColor(calibratedRed: 0.43, green: 0.18, blue: 0.62, alpha: 1)
    ])!
    background.draw(in: outer, angle: 315)

    drawLanguageBand(in: outer, scale: scale)
    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor(calibratedWhite: 1, alpha: 0.28).setStroke()
    outerPath.lineWidth = 10 * scale
    outerPath.stroke()

    drawKeycap(in: outer, scale: scale)
    drawMonogram(in: outer, scale: scale)
    drawLanguageDots(in: outer, scale: scale)

    return image
}

func drawLanguageBand(in outer: NSRect, scale: CGFloat) {
    let bandHeight = 250 * scale
    let band = NSRect(x: outer.minX, y: outer.minY, width: outer.width, height: bandHeight)
    NSColor(calibratedRed: 0.03, green: 0.12, blue: 0.22, alpha: 0.24).setFill()
    band.fill()

    for index in 0..<3 {
        let x = outer.minX + CGFloat(170 + index * 230) * scale
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: outer.minY + 96 * scale))
        path.line(to: NSPoint(x: x + 120 * scale, y: outer.minY + 210 * scale))
        path.lineWidth = 14 * scale
        NSColor(calibratedWhite: 1, alpha: 0.26).setStroke()
        path.stroke()
    }
}

func drawKeycap(in outer: NSRect, scale: CGFloat) {
    let key = NSRect(
        x: outer.minX + 185 * scale,
        y: outer.minY + 238 * scale,
        width: 566 * scale,
        height: 566 * scale
    )
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 32 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -16 * scale)
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)

    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()
    let keyPath = NSBezierPath(roundedRect: key, xRadius: 126 * scale, yRadius: 126 * scale)
    NSColor(calibratedWhite: 1, alpha: 0.94).setFill()
    keyPath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor(calibratedRed: 0.13, green: 0.23, blue: 0.48, alpha: 0.16).setStroke()
    keyPath.lineWidth = 8 * scale
    keyPath.stroke()
}

func drawMonogram(in outer: NSRect, scale: CGFloat) {
    let text = "F"
    let fontSize = 420 * scale
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.19, blue: 0.39, alpha: 1),
        .kern: -10 * scale
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributed.size()
    let point = NSPoint(
        x: outer.midX - textSize.width / 2 + 8 * scale,
        y: outer.midY - textSize.height / 2 + 32 * scale
    )
    attributed.draw(at: point)

    let arrowPath = NSBezierPath()
    arrowPath.move(to: NSPoint(x: outer.minX + 448 * scale, y: outer.minY + 326 * scale))
    arrowPath.line(to: NSPoint(x: outer.minX + 574 * scale, y: outer.minY + 326 * scale))
    arrowPath.move(to: NSPoint(x: outer.minX + 538 * scale, y: outer.minY + 360 * scale))
    arrowPath.line(to: NSPoint(x: outer.minX + 574 * scale, y: outer.minY + 326 * scale))
    arrowPath.line(to: NSPoint(x: outer.minX + 538 * scale, y: outer.minY + 292 * scale))
    arrowPath.lineWidth = 24 * scale
    arrowPath.lineCapStyle = .round
    arrowPath.lineJoinStyle = .round
    NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.18, alpha: 1).setStroke()
    arrowPath.stroke()
}

func drawLanguageDots(in outer: NSRect, scale: CGFloat) {
    let colors = [
        NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.18, alpha: 1),
        NSColor(calibratedRed: 0.28, green: 0.82, blue: 0.62, alpha: 1),
        NSColor(calibratedRed: 0.98, green: 0.36, blue: 0.50, alpha: 1)
    ]
    for (index, color) in colors.enumerated() {
        let dot = NSRect(
            x: outer.midX - 106 * scale + CGFloat(index) * 86 * scale,
            y: outer.minY + 122 * scale,
            width: 44 * scale,
            height: 44 * scale
        )
        color.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "FreePuntoIcon", code: 1)
    }

    try png.write(to: url)
}

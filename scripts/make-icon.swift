// Draws the GlassDock app icon into an .iconset folder.
// Usage: swift scripts/make-icon.swift build/AppIcon.iconset
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func draw(_ pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = size * 0.1
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let background = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    // Dusk sky: navy to mauve to peach.
    NSGradient(colors: [
        NSColor(red: 0.98, green: 0.74, blue: 0.60, alpha: 1),
        NSColor(red: 0.62, green: 0.42, blue: 0.68, alpha: 1),
        NSColor(red: 0.12, green: 0.14, blue: 0.34, alpha: 1),
    ])?.draw(in: background, angle: 90)

    // The glass dock bar.
    let bar = NSRect(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.14,
                     width: rect.width * 0.76, height: rect.height * 0.22)
    let barPath = NSBezierPath(roundedRect: bar, xRadius: bar.height * 0.38, yRadius: bar.height * 0.38)
    NSColor(white: 1, alpha: 0.28).setFill()
    barPath.fill()
    NSColor(white: 1, alpha: 0.7).setStroke()
    barPath.lineWidth = max(1, size * 0.006)
    barPath.stroke()

    // Three tiles on the bar.
    let tile = bar.height * 0.64
    let gap = (bar.width - tile * 3) / 4
    let colors = [NSColor.systemPink, NSColor.systemOrange, NSColor.systemTeal]
    for (i, color) in colors.enumerated() {
        let r = NSRect(x: bar.minX + gap + CGFloat(i) * (tile + gap), y: bar.midY - tile / 2, width: tile, height: tile)
        color.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: r, xRadius: tile * 0.26, yRadius: tile * 0.26).fill()
    }

    // The sun.
    let sun = NSRect(x: rect.midX - rect.width * 0.14, y: rect.minY + rect.height * 0.5,
                     width: rect.width * 0.28, height: rect.width * 0.28)
    NSColor(red: 1, green: 0.88, blue: 0.7, alpha: 0.95).setFill()
    NSBezierPath(ovalIn: sun).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        if let data = draw(base * scale) {
            try? data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
        }
    }
}

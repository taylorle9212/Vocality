// Renders the Vocality app icon (sky-blue "speaking cursor") to an .icns file.
// Usage: swift scripts/make-icon.swift <output.icns>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    let s = CGFloat(px) / 1024

    // macOS icon grid: 824pt tile centered on a 1024 canvas.
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)

    let rgb = CGColorSpaceCreateDeviceRGB()
    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
        NSColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a).cgColor
    }
    func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
        CGGradient(colorsSpace: rgb, colors: stops.map { $0.0 } as CFArray, locations: stops.map { $0.1 })!
    }
    let canvas = CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px))

    // Soft neutral drop shadow, kept outside the tile so it never darkens the glass.
    ctx.saveGState()
    ctx.addRect(canvas); ctx.addPath(shape)
    ctx.clip(using: .evenOdd)
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: NSColor(white: 0, alpha: 0.2).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Translucent blue glass body.
    ctx.drawLinearGradient(
        gradient([(color(0x9C, 0xD3, 0xFF, 0.72), 0), (color(0x5A, 0xA6, 0xF8, 0.76), 0.5), (color(0x2F, 0x86, 0xF0, 0.82), 1)]),
        start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

    // Deeper tint toward the bottom for depth.
    ctx.drawLinearGradient(
        gradient([(color(0x0A, 0x3C, 0x96, 0), 0), (color(0x0A, 0x3C, 0x96, 0), 0.45), (color(0x0A, 0x3C, 0x96, 0.28), 1)]),
        start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])

    // Soft elliptical sheen near the top (no hard edge).
    ctx.saveGState()
    ctx.translateBy(x: tile.midX, y: tile.maxY - 90 * s)
    ctx.scaleBy(x: 1.35, y: 0.75)
    ctx.drawRadialGradient(
        gradient([(NSColor(white: 1, alpha: 0.38).cgColor, 0), (NSColor(white: 1, alpha: 0.14).cgColor, 0.5), (NSColor(white: 1, alpha: 0).cgColor, 1)]),
        startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 420 * s, options: [])
    ctx.restoreGState()

    // Inner shadow hugging the lower edge.
    ctx.saveGState()
    ctx.addRect(canvas.insetBy(dx: -200 * s, dy: -200 * s)); ctx.addPath(shape)
    ctx.setShadow(offset: CGSize(width: 0, height: 14 * s), blur: 40 * s, color: color(0x08, 0x2A, 0x70, 0.35))
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
    ctx.restoreGState()

    // Specular rim: bright at top-left, fading out toward bottom-right.
    func rim(width: CGFloat, stops: [(CGColor, CGFloat)]) {
        let inset = tile.insetBy(dx: width / 2, dy: width / 2)
        let path = CGPath(roundedRect: inset, cornerWidth: 185 * s - width / 2, cornerHeight: 185 * s - width / 2, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(width)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(gradient(stops), start: CGPoint(x: tile.minX, y: tile.maxY),
                               end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
        ctx.restoreGState()
    }
    rim(width: 14 * s, stops: [(NSColor(white: 1, alpha: 0.35).cgColor, 0), (NSColor(white: 1, alpha: 0.08).cgColor, 0.45), (NSColor(white: 1, alpha: 0).cgColor, 1)])
    rim(width: 4.5 * s, stops: [(NSColor(white: 1, alpha: 0.95).cgColor, 0), (NSColor(white: 1, alpha: 0.3).cgColor, 0.35), (NSColor(white: 1, alpha: 0.03).cgColor, 1)])

    // Glyph from the 200x200 design, mapped into the tile (y flipped),
    // drawn in one layer with a soft blue glow so it sits above the glass.
    let k = tile.width / 200
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tile.minX + x * k, y: tile.maxY - y * k) }
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 30 * s, color: color(0x0B, 0x4C, 0xC0, 0.55))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(11 * k)
    ctx.move(to: p(86, 56)); ctx.addLine(to: p(114, 56))
    ctx.move(to: p(100, 56)); ctx.addLine(to: p(100, 144))
    ctx.move(to: p(86, 144)); ctx.addLine(to: p(114, 144))
    ctx.strokePath()

    ctx.setLineWidth(8 * k)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.9).cgColor)
    ctx.move(to: p(64, 78)); ctx.addQuadCurve(to: p(64, 122), control: p(54, 100))
    ctx.move(to: p(136, 78)); ctx.addQuadCurve(to: p(136, 122), control: p(146, 100))
    ctx.strokePath()

    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.45).cgColor)
    ctx.move(to: p(44, 66)); ctx.addQuadCurve(to: p(44, 134), control: p(30, 100))
    ctx.move(to: p(156, 66)); ctx.addQuadCurve(to: p(156, 134), control: p(170, 100))
    ctx.strokePath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Vocality-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try! task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "Wrote \(output)" : "iconutil failed")

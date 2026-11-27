// Renders the Vocality app icon (white glass, thermal "speaking cursor") to an .icns file.
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

    // Frosted white glass body, slightly translucent.
    ctx.drawLinearGradient(
        gradient([(color(0xFF, 0xFF, 0xFF, 0.92), 0), (color(0xF6, 0xF6, 0xF8, 0.9), 0.5), (color(0xEC, 0xEC, 0xEF, 0.9), 1)]),
        start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

    // Subtle cool-grey depth toward the bottom.
    ctx.drawLinearGradient(
        gradient([(color(0x8A, 0x90, 0x9C, 0), 0), (color(0x8A, 0x90, 0x9C, 0), 0.5), (color(0x8A, 0x90, 0x9C, 0.12), 1)]),
        start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])

    // Soft elliptical sheen near the top (no hard edge).
    ctx.saveGState()
    ctx.translateBy(x: tile.midX, y: tile.maxY - 90 * s)
    ctx.scaleBy(x: 1.35, y: 0.75)
    ctx.drawRadialGradient(
        gradient([(NSColor(white: 1, alpha: 0.6).cgColor, 0), (NSColor(white: 1, alpha: 0.22).cgColor, 0.5), (NSColor(white: 1, alpha: 0).cgColor, 1)]),
        startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 420 * s, options: [])
    ctx.restoreGState()

    // Faint inner shadow hugging the lower edge.
    ctx.saveGState()
    ctx.addRect(canvas.insetBy(dx: -200 * s, dy: -200 * s)); ctx.addPath(shape)
    ctx.setShadow(offset: CGSize(width: 0, height: 14 * s), blur: 40 * s, color: color(0x5A, 0x60, 0x6E, 0.14))
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
    ctx.restoreGState()

    // Edge strokes on the tile, shaded along a gradient axis.
    func rim(width: CGFloat, from: CGPoint, to: CGPoint, stops: [(CGColor, CGFloat)]) {
        let inset = tile.insetBy(dx: width / 2, dy: width / 2)
        let path = CGPath(roundedRect: inset, cornerWidth: 185 * s - width / 2, cornerHeight: 185 * s - width / 2, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(width)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(gradient(stops), start: from, end: to, options: [])
        ctx.restoreGState()
    }
    let topLeft = CGPoint(x: tile.minX, y: tile.maxY), bottomRight = CGPoint(x: tile.maxX, y: tile.minY)
    // Bright specular rim at top-left.
    rim(width: 4.5 * s, from: topLeft, to: bottomRight,
        stops: [(NSColor(white: 1, alpha: 1).cgColor, 0), (NSColor(white: 1, alpha: 0.4).cgColor, 0.35), (NSColor(white: 1, alpha: 0).cgColor, 0.7)])
    // Faint grey hairline on the lower edge so the tile separates from light Docks.
    rim(width: 2.5 * s, from: CGPoint(x: tile.midX, y: tile.maxY), to: CGPoint(x: tile.midX, y: tile.minY),
        stops: [(color(0, 0, 0, 0), 0), (color(0, 0, 0, 0.02), 0.5), (color(0, 0, 0, 0.08), 1)])

    // Glyph from the 200x200 design, mapped into the tile (y flipped).
    let k = tile.width / 200
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tile.minX + x * k, y: tile.maxY - y * k) }
    func cursor() {
        ctx.move(to: p(86, 56)); ctx.addLine(to: p(114, 56))
        ctx.move(to: p(100, 56)); ctx.addLine(to: p(100, 144))
        ctx.move(to: p(86, 144)); ctx.addLine(to: p(114, 144))
    }
    func innerArcs() {
        ctx.move(to: p(64, 78)); ctx.addQuadCurve(to: p(64, 122), control: p(54, 100))
        ctx.move(to: p(136, 78)); ctx.addQuadCurve(to: p(136, 122), control: p(146, 100))
    }
    func outerArcs() {
        ctx.move(to: p(44, 66)); ctx.addQuadCurve(to: p(44, 134), control: p(30, 100))
        ctx.move(to: p(156, 66)); ctx.addQuadCurve(to: p(156, 134), control: p(170, 100))
    }
    let strokes: [(() -> Void, CGFloat, CGFloat)] = [(cursor, 11, 1), (innerArcs, 8, 0.9), (outerArcs, 8, 0.5)]

    // Thermal ("inferno") gradient, bottom-left to top-right across the glyph.
    let inferno = gradient([
        (color(0x32, 0x0A, 0x5E, 1), 0), (color(0x78, 0x1C, 0x6D, 1), 0.25), (color(0xBC, 0x37, 0x54, 1), 0.5),
        (color(0xED, 0x69, 0x25, 1), 0.75), (color(0xFB, 0xB6, 0x1A, 1), 1)])
    let gStart = p(30, 144), gEnd = p(170, 56)

    // Warm glow beneath the glyph so it reads as lit from within.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 36 * s, color: color(0xED, 0x69, 0x25, 0.25))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setLineCap(.round)
    for (draw, width, alpha) in strokes {
        ctx.saveGState()
        draw()
        ctx.setLineWidth(width * k)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.setAlpha(alpha)
        ctx.drawLinearGradient(inferno, start: gStart, end: gEnd, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
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

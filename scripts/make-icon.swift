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

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 24 * s,
                  color: NSColor(white: 0, alpha: 0.22).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let colors = [
        NSColor(red: 0x8C / 255, green: 0xCB / 255, blue: 1, alpha: 1).cgColor,
        NSColor(red: 0x2F / 255, green: 0x86 / 255, blue: 0xF0 / 255, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    ctx.restoreGState()

    // Glyph from the 200x200 design, mapped into the tile (y flipped).
    let k = tile.width / 200
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tile.minX + x * k, y: tile.maxY - y * k) }
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

// Renders the Vocality README banner (2560x1280, 2x of 1280x640) to a PNG.
// Usage: swift scripts/make-banner.swift <output.png>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "banner.png"
let W = 2560, H = 1280
let w = CGFloat(W), h = CGFloat(H)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.saveGraphicsState()
let gc = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gc
let ctx = gc.cgContext

let rgb = CGColorSpaceCreateDeviceRGB()
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a).cgColor
}
func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: rgb, colors: stops.map { $0.0 } as CFArray, locations: stops.map { $0.1 })!
}
let canvas = CGRect(x: 0, y: 0, width: w, height: h)

// MARK: Background

ctx.setFillColor(color(0x0B0614))
ctx.fill(canvas)

// Large soft glow behind the center-left: violet core fading through indigo to the base.
func glow(center: CGPoint, radius: CGFloat, sx: CGFloat, sy: CGFloat, stops: [(CGColor, CGFloat)]) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.scaleBy(x: sx, y: sy)
    ctx.drawRadialGradient(gradient(stops), startCenter: .zero, startRadius: 0,
                           endCenter: .zero, endRadius: radius, options: [])
    ctx.restoreGState()
}
glow(center: CGPoint(x: w * 0.36, y: h * 0.52), radius: 1100, sx: 1.25, sy: 0.85, stops: [
    (color(0x7C3AED, 0.42), 0), (color(0x6D3FE8, 0.28), 0.3), (color(0x4F46E5, 0.14), 0.6), (color(0x4F46E5, 0), 1),
])
glow(center: CGPoint(x: w * 0.78, y: h * 0.42), radius: 700, sx: 1.2, sy: 0.9, stops: [
    (color(0x4F46E5, 0.16), 0), (color(0x4F46E5, 0), 1),
])

// Faint fine grid, fading out toward the edges.
ctx.saveGState()
let step: CGFloat = 64
let grid = CGMutablePath()
var gx: CGFloat = 0
while gx <= w { grid.move(to: CGPoint(x: gx, y: 0)); grid.addLine(to: CGPoint(x: gx, y: h)); gx += step }
var gy: CGFloat = 0
while gy <= h { grid.move(to: CGPoint(x: 0, y: gy)); grid.addLine(to: CGPoint(x: w, y: gy)); gy += step }
ctx.addPath(grid)
ctx.setLineWidth(1.5)
ctx.replacePathWithStrokedPath()
ctx.clip()
glow(center: CGPoint(x: w * 0.5, y: h * 0.5), radius: 1250, sx: 1.0, sy: 0.6, stops: [
    (NSColor(white: 1, alpha: 0.035).cgColor, 0), (NSColor(white: 1, alpha: 0.018).cgColor, 0.6), (NSColor(white: 1, alpha: 0).cgColor, 1),
])
ctx.restoreGState()

// Vignette to keep the edges deep.
glow(center: CGPoint(x: w / 2, y: h / 2), radius: 1650, sx: 1.0, sy: 0.6, stops: [
    (color(0x0B0614, 0), 0), (color(0x0B0614, 0), 0.62), (color(0x0B0614, 0.85), 1),
])

// MARK: App mark

let markSize: CGFloat = 320
let tile = CGRect(x: 200, y: h / 2 - markSize / 2, width: markSize, height: markSize)
let radius = markSize * 0.225
let shape = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 60, color: color(0x7C3AED, 0.45))
ctx.addPath(shape)
ctx.setFillColor(color(0x4F46E5))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
ctx.drawLinearGradient(gradient([(color(0xA78BFA), 0), (color(0x7C3AED), 0.5), (color(0x4F46E5), 1)]),
                       start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
ctx.drawLinearGradient(gradient([(color(0x2E1065, 0), 0), (color(0x2E1065, 0), 0.45), (color(0x2E1065, 0.28), 1)]),
                       start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])
ctx.saveGState()
ctx.translateBy(x: tile.midX, y: tile.maxY - markSize * 0.11)
ctx.scaleBy(x: 1.35, y: 0.75)
ctx.drawRadialGradient(
    gradient([(NSColor(white: 1, alpha: 0.32).cgColor, 0), (NSColor(white: 1, alpha: 0.1).cgColor, 0.5), (NSColor(white: 1, alpha: 0).cgColor, 1)]),
    startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: markSize * 0.5, options: [])
ctx.restoreGState()
ctx.restoreGState()

// Thin specular rim.
ctx.saveGState()
let rimW: CGFloat = 3
ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: rimW / 2, dy: rimW / 2), cornerWidth: radius - rimW / 2,
                   cornerHeight: radius - rimW / 2, transform: nil))
ctx.setLineWidth(rimW)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(gradient([(NSColor(white: 1, alpha: 0.7).cgColor, 0), (NSColor(white: 1, alpha: 0.15).cgColor, 0.4), (NSColor(white: 1, alpha: 0).cgColor, 1)]),
                       start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
ctx.restoreGState()

// Glyph from the 200x200 design in make-icon.swift (y flipped).
let k = tile.width / 200
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tile.minX + x * k, y: tile.maxY - y * k) }
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: color(0xC4B5FD, 0.6))
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

// MARK: Wordmark

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}
let titleFont = rounded(200, .heavy)
let title = NSAttributedString(string: "Vocality", attributes: [
    .font: titleFont, .foregroundColor: NSColor.white, .kern: -4,
])
let subFont = rounded(60, .medium)
let sub = NSAttributedString(string: "On-device dictation for macOS", attributes: [
    .font: subFont, .foregroundColor: NSColor(white: 1, alpha: 0.6),
])
let textX = tile.maxX + 72
let gap: CGFloat = 44
// Vertically center the cap-height of the title plus the subtitle block on the mark.
let blockH = titleFont.capHeight + gap - subFont.descender + subFont.ascender
let titleBaseline = h / 2 + blockH / 2 - titleFont.capHeight
let subBaseline = titleBaseline - gap - subFont.ascender
title.draw(at: CGPoint(x: textX, y: titleBaseline + titleFont.descender))
sub.draw(at: CGPoint(x: textX, y: subBaseline + subFont.descender))
let textRight = textX + max(title.size().width, sub.size().width)

// MARK: Recorder

let barCount = 18
let barW: CGFloat = 14, barGap: CGFloat = 10
let heights: [CGFloat] = [0.22, 0.38, 0.55, 0.42, 0.7, 0.92, 0.6, 1.0, 0.78, 0.5, 0.86, 0.66, 0.4, 0.58, 0.32, 0.46, 0.26, 0.18]
let capH: CGFloat = 148
let circleD: CGFloat = 100
let pad = (capH - circleD) / 2
let wavesW = CGFloat(barCount) * barW + CGFloat(barCount - 1) * barGap
let capW = pad + circleD + 40 + wavesW + 48
let capRight = w - 200
let cap = CGRect(x: capRight - capW, y: h / 2 - capH / 2, width: capW, height: capH)
assert(cap.minX > textRight + 80, "recorder overlaps text")
let capPath = CGPath(roundedRect: cap, cornerWidth: capH / 2, cornerHeight: capH / 2, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 50, color: NSColor(white: 0, alpha: 0.55).cgColor)
ctx.addPath(capPath)
ctx.setFillColor(NSColor(white: 0, alpha: 0.85).cgColor)
ctx.fillPath()
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: cap.insetBy(dx: 1, dy: 1), cornerWidth: capH / 2 - 1, cornerHeight: capH / 2 - 1, transform: nil))
ctx.setStrokeColor(NSColor(white: 1, alpha: 0.1).cgColor)
ctx.setLineWidth(2)
ctx.strokePath()

// Violet send button with a white up-arrow.
let circle = CGRect(x: cap.minX + pad, y: cap.midY - circleD / 2, width: circleD, height: circleD)
ctx.saveGState()
ctx.addEllipse(in: circle)
ctx.clip()
ctx.drawLinearGradient(gradient([(color(0xA78BFA), 0), (color(0x7C3AED), 1)]),
                       start: CGPoint(x: circle.midX, y: circle.maxY), end: CGPoint(x: circle.midX, y: circle.minY), options: [])
ctx.restoreGState()
ctx.saveGState()
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineWidth(9)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let ac = CGPoint(x: circle.midX, y: circle.midY)
ctx.move(to: CGPoint(x: ac.x, y: ac.y - 24)); ctx.addLine(to: CGPoint(x: ac.x, y: ac.y + 24))
ctx.move(to: CGPoint(x: ac.x - 19, y: ac.y + 5)); ctx.addLine(to: CGPoint(x: ac.x, y: ac.y + 24))
ctx.addLine(to: CGPoint(x: ac.x + 19, y: ac.y + 5))
ctx.strokePath()
ctx.restoreGState()

// Waveform bars.
let maxBar = capH - 52
var bx = circle.maxX + 40
for t in heights {
    let bh = max(barW, maxBar * t)
    let fill: UInt32 = t >= 0.75 ? 0xC4B5FD : (t >= 0.4 ? 0x8B5CF6 : 0x4C3A8F)
    let r = CGRect(x: bx, y: cap.midY - bh / 2, width: barW, height: bh)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
    ctx.setFillColor(color(fill))
    ctx.fillPath()
    bx += barW + barGap
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")

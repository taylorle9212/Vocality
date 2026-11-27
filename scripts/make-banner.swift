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

// Thermal palette, cool to hot. Capped at amber so it reads on white.
let thermal: [UInt32] = [0x320A5E, 0x781C6D, 0xBC3754, 0xED6925, 0xFBB61A]
func thermalStops(_ a: CGFloat = 1) -> [(CGColor, CGFloat)] {
    thermal.enumerated().map { (color($0.element, a), CGFloat($0.offset) / CGFloat(thermal.count - 1)) }
}
func thermalColor(_ t: CGFloat) -> CGColor {
    let x = min(max(t, 0), 1) * CGFloat(thermal.count - 1)
    let i = min(Int(x), thermal.count - 2), f = x - CGFloat(i)
    func ch(_ c: UInt32, _ s: UInt32) -> CGFloat { CGFloat((c >> s) & 0xFF) / 255 }
    let a = thermal[i], b = thermal[i + 1]
    return NSColor(red: ch(a, 16) + (ch(b, 16) - ch(a, 16)) * f, green: ch(a, 8) + (ch(b, 8) - ch(a, 8)) * f,
                   blue: ch(a, 0) + (ch(b, 0) - ch(a, 0)) * f, alpha: 1).cgColor
}

// MARK: Background

ctx.setFillColor(color(0xFAFAFA))
ctx.fill(canvas)

func glow(center: CGPoint, radius: CGFloat, sx: CGFloat, sy: CGFloat, stops: [(CGColor, CGFloat)]) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.scaleBy(x: sx, y: sy)
    ctx.drawRadialGradient(gradient(stops), startCenter: .zero, startRadius: 0,
                           endCenter: .zero, endRadius: radius, options: [])
    ctx.restoreGState()
}
// Warm thermal glow behind the center-left, faint cool glow at far right.
glow(center: CGPoint(x: w * 0.34, y: h * 0.52), radius: 1050, sx: 1.25, sy: 0.8, stops: [
    (color(0xED6925, 0.18), 0), (color(0xBC3754, 0.11), 0.4), (color(0xBC3754, 0.04), 0.7), (color(0xBC3754, 0), 1),
])
glow(center: CGPoint(x: w * 0.95, y: h * 0.45), radius: 800, sx: 1.0, sy: 1.0, stops: [
    (color(0x320A5E, 0.08), 0), (color(0x320A5E, 0.03), 0.5), (color(0x320A5E, 0), 1),
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
    (NSColor(white: 0, alpha: 0.03).cgColor, 0), (NSColor(white: 0, alpha: 0.018).cgColor, 0.6), (NSColor(white: 0, alpha: 0).cgColor, 1),
])
ctx.restoreGState()

// MARK: App mark

let markSize: CGFloat = 320
let tile = CGRect(x: 200, y: h / 2 - markSize / 2, width: markSize, height: markSize)
let radius = markSize * 0.225
let shape = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Frosted white tile with a soft neutral shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 50, color: NSColor(white: 0, alpha: 0.12).cgColor)
ctx.addPath(shape)
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
ctx.drawLinearGradient(gradient([(NSColor(white: 1, alpha: 1).cgColor, 0), (NSColor(white: 0.955, alpha: 1).cgColor, 1)]),
                       start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 1, dy: 1), cornerWidth: radius - 1, cornerHeight: radius - 1, transform: nil))
ctx.setStrokeColor(NSColor(white: 0, alpha: 0.09).cgColor)
ctx.setLineWidth(2)
ctx.strokePath()

// Glyph from the 200x200 design in make-icon.swift (y flipped), filled with the thermal gradient.
let k = tile.width / 200
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tile.minX + x * k, y: tile.maxY - y * k) }
let glyphGrad = gradient(thermalStops())
func thermalStroke(width: CGFloat, alpha: CGFloat, _ build: () -> Void) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setLineCap(.round)
    ctx.setLineWidth(width)
    build()
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(glyphGrad, start: p(36, 150), end: p(164, 50), options: [])
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}
thermalStroke(width: 11 * k, alpha: 1) {
    ctx.move(to: p(86, 56)); ctx.addLine(to: p(114, 56))
    ctx.move(to: p(100, 56)); ctx.addLine(to: p(100, 144))
    ctx.move(to: p(86, 144)); ctx.addLine(to: p(114, 144))
}
thermalStroke(width: 8 * k, alpha: 0.9) {
    ctx.move(to: p(64, 78)); ctx.addQuadCurve(to: p(64, 122), control: p(54, 100))
    ctx.move(to: p(136, 78)); ctx.addQuadCurve(to: p(136, 122), control: p(146, 100))
}
thermalStroke(width: 8 * k, alpha: 0.5) {
    ctx.move(to: p(44, 66)); ctx.addQuadCurve(to: p(44, 134), control: p(30, 100))
    ctx.move(to: p(156, 66)); ctx.addQuadCurve(to: p(156, 134), control: p(170, 100))
}

// MARK: Wordmark

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}
let titleFont = rounded(200, .heavy)
let title = NSAttributedString(string: "Vocality", attributes: [
    .font: titleFont, .foregroundColor: NSColor(cgColor: color(0x111113))!, .kern: -4,
])
let subFont = rounded(60, .medium)
let sub = NSAttributedString(string: "On-device dictation for macOS", attributes: [
    .font: subFont, .foregroundColor: NSColor(cgColor: color(0x6B6B73))!,
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

// Dot-matrix wave: columns of round dots (odd counts, centered on the midline).
let dotCounts = [1, 3, 3, 5, 3, 5, 7, 5, 7, 7, 5, 3, 5, 7, 5, 3, 5, 3, 3, 1, 3, 1]
let dotD: CGFloat = 12, dotPitch: CGFloat = 16, colPitch: CGFloat = 20
let capH: CGFloat = 148
let circleD: CGFloat = 100
let pad = (capH - circleD) / 2
let wavesW = CGFloat(dotCounts.count - 1) * colPitch + dotD
let capW = pad + circleD + 44 + wavesW + 52
let capRight = w - 200
let cap = CGRect(x: capRight - capW, y: h / 2 - capH / 2, width: capW, height: capH)
assert(cap.minX > textRight + 80, "recorder overlaps text")
let capPath = CGPath(roundedRect: cap, cornerWidth: capH / 2, cornerHeight: capH / 2, transform: nil)

// Frosted white glass capsule.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 44, color: NSColor(white: 0, alpha: 0.12).cgColor)
ctx.addPath(capPath)
ctx.setFillColor(NSColor(white: 1, alpha: 0.85).cgColor)
ctx.fillPath()
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: cap.insetBy(dx: 1, dy: 1), cornerWidth: capH / 2 - 1, cornerHeight: capH / 2 - 1, transform: nil))
ctx.setStrokeColor(NSColor(white: 0, alpha: 0.08).cgColor)
ctx.setLineWidth(2)
ctx.strokePath()

// White button with a thermal charge ring and a dark up-arrow.
let circle = CGRect(x: cap.minX + pad, y: cap.midY - circleD / 2, width: circleD, height: circleD)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: NSColor(white: 0, alpha: 0.1).cgColor)
ctx.addEllipse(in: circle)
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillPath()
ctx.restoreGState()
let ringW: CGFloat = 6
let ringR = circleD / 2 - ringW / 2 - 1
let ac = CGPoint(x: circle.midX, y: circle.midY)
ctx.addArc(center: ac, radius: ringR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.setStrokeColor(NSColor(white: 0, alpha: 0.07).cgColor)
ctx.setLineWidth(ringW)
ctx.strokePath()
ctx.saveGState()
ctx.setLineCap(.round)
ctx.setLineWidth(ringW)
ctx.addArc(center: ac, radius: ringR, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 1.55, clockwise: true)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(gradient(thermalStops()), start: CGPoint(x: circle.minX, y: circle.minY),
                       end: CGPoint(x: circle.maxX, y: circle.maxY), options: [])
ctx.restoreGState()
ctx.saveGState()
ctx.setStrokeColor(color(0x111113))
ctx.setLineWidth(8)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: ac.x, y: ac.y - 20)); ctx.addLine(to: CGPoint(x: ac.x, y: ac.y + 20))
ctx.move(to: CGPoint(x: ac.x - 16, y: ac.y + 4)); ctx.addLine(to: CGPoint(x: ac.x, y: ac.y + 20))
ctx.addLine(to: CGPoint(x: ac.x + 16, y: ac.y + 4))
ctx.strokePath()
ctx.restoreGState()

// Taller columns and dots nearer the midline run hotter.
var dx = circle.maxX + 44
for n in dotCounts {
    let level = CGFloat(n) / 7
    for i in 0..<n {
        let off = CGFloat(i - n / 2)
        let t = 0.12 + 0.88 * level - 0.1 * abs(off)
        ctx.addEllipse(in: CGRect(x: dx, y: cap.midY + off * dotPitch - dotD / 2, width: dotD, height: dotD))
        ctx.setFillColor(thermalColor(t))
        ctx.fillPath()
    }
    dx += colPitch
}

NSGraphicsContext.restoreGraphicsState()
// Flatten to opaque RGB (the background is solid) to keep the PNG small.
let opaque = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: rgb,
                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
opaque.draw(rep.cgImage!, in: canvas)
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, opaque.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("Wrote \(output)")

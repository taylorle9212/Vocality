import AppKit
import SwiftUI

/// Light-blue palette that follows the system light/dark appearance.
enum Theme {
    static let background = Color(light: 0xF5F9FF, dark: 0x10151C)
    static let card = Color(light: 0xFFFFFF, dark: 0x18202A)
    static let line = Color(light: 0xD8E6FA, dark: 0x2A3646)
    static let ink = Color(light: 0x0E1A2B, dark: 0xE8EEF6)
    static let slate = Color(light: 0x4A5B73, dark: 0x9AA8BB)
    static let chip = Color(light: 0xE3F0FF, dark: 0x1D2C40)
    static let chipText = Color(light: 0x134C99, dark: 0xA9D2FF)

    static let sky300 = Color(light: 0xA9D2FF, dark: 0x3A6EA8)
    static let sky500 = Color(light: 0x4DA3FF, dark: 0x5DAEFF)
    static let sky600 = Color(light: 0x2F86F0, dark: 0x7CC0FF)
    /// Buttons and switches. White text on it passes 4.5:1 in both appearances.
    static let action = Color(light: 0x1A63C7, dark: 0x2F78D8)
    static let warning = Color(light: 0xC2410C, dark: 0xFB923C)

    static let iconGradient = LinearGradient(
        colors: [Color(hex: 0x8CCBFF), Color(hex: 0x2F86F0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The app mark: a text cursor with sound arcs.
struct LogoMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Theme.iconGradient)
            Canvas { ctx, canvas in
                let s = canvas.width / 200
                func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

                var caret = Path()
                caret.move(to: p(86, 56)); caret.addLine(to: p(114, 56))
                caret.move(to: p(100, 56)); caret.addLine(to: p(100, 144))
                caret.move(to: p(86, 144)); caret.addLine(to: p(114, 144))
                ctx.stroke(caret, with: .color(.white), style: StrokeStyle(lineWidth: 13 * s, lineCap: .round))

                var arcs = Path()
                arcs.move(to: p(62, 78)); arcs.addQuadCurve(to: p(62, 122), control: p(50, 100))
                arcs.move(to: p(138, 78)); arcs.addQuadCurve(to: p(138, 122), control: p(150, 100))
                ctx.stroke(arcs, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

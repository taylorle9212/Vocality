import AppKit
import SwiftUI

/// Tech-purple palette that follows the system light/dark appearance.
enum Theme {
    static let background = Color(light: 0xF7F5FF, dark: 0x07050D)
    static let card = Color(light: 0xFFFFFF, dark: 0x0F0B18, lightAlpha: 0.74, darkAlpha: 0.72)
    static let line = Color(light: 0xE4DCFB, dark: 0x251C3A)
    static let ink = Color(light: 0x1A1030, dark: 0xEEEAF8)
    static let slate = Color(light: 0x5B5274, dark: 0xA79FBF)
    static let chip = Color(light: 0xEEE8FF, dark: 0x22163D)
    static let chipText = Color(light: 0x4C1D95, dark: 0xD8CCFF)

    static let accent300 = Color(light: 0xC4B5FD, dark: 0x5B3FA6)
    static let accent500 = Color(light: 0x8B5CF6, dark: 0xA78BFA)
    static let accent600 = Color(light: 0x7C3AED, dark: 0xC4B5FD)
    /// Buttons and switches. White text on it passes 4.5:1 in both appearances.
    static let action = Color(light: 0x6D28D9, dark: 0x7C3AED)
    static let warning = Color(light: 0xC2410C, dark: 0xFB923C)

    /// Violet to indigo, for the logo and brand surfaces.
    static let iconGradient = LinearGradient(
        colors: [Color(hex: 0xA78BFA), Color(hex: 0x7C3AED), Color(hex: 0x4F46E5)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// The window backdrop: a soft purple gradient over the translucent window material.
struct WindowBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(light: 0xEFE7FF, dark: 0x0B0716, lightAlpha: 0.82, darkAlpha: 0.9),
                    Color(light: 0xF7F5FF, dark: 0x05040A, lightAlpha: 0.82, darkAlpha: 0.92),
                ],
                startPoint: .top,
                endPoint: .bottom)
            RadialGradient(
                colors: [Color(light: 0xA78BFA, dark: 0x7C3AED, lightAlpha: 0.32, darkAlpha: 0.34), .clear],
                center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(
                colors: [Color(light: 0x818CF8, dark: 0x4F46E5, lightAlpha: 0.2, darkAlpha: 0.22), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark).withAlphaComponent(darkAlpha)
                : NSColor(hex: light).withAlphaComponent(lightAlpha)
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

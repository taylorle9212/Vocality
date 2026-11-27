import AppKit
import SwiftUI

/// White and graphite with a thermal-gradient accent. Follows the system light/dark appearance.
enum Theme {
    static let background = Color(light: 0xFAFAFA, dark: 0x0A0A0B)
    static let card = Color(light: 0xFFFFFF, dark: 0x141416, lightAlpha: 0.82, darkAlpha: 0.78)
    /// Tint for glass cards over the thermal backdrop: white in light mode, graphite in dark.
    static let glassTint = Color(light: 0xFFFFFF, dark: 0x111113, lightAlpha: 0.62, darkAlpha: 0.55)
    static let line = Color(light: 0xE7E7EA, dark: 0x2A2A2F)
    static let ink = Color(light: 0x111113, dark: 0xF4F4F5)
    static let slate = Color(light: 0x5F5F68, dark: 0xA1A1AA)
    static let chip = Color(light: 0xF2F2F4, dark: 0x232327)
    static let chipText = Color(light: 0x27272A, dark: 0xE4E4E7)

    static let accent300 = Color(light: 0xD4D4D8, dark: 0x52525B)
    /// Warm thermal accent for small highlights (status dot, checks).
    static let accent500 = Color(light: 0xE0582A, dark: 0xF47A3D)
    static let accent600 = Color(light: 0xD04A22, dark: 0xFB923C)
    /// Buttons and switches: graphite, with white text at more than 7:1.
    static let action = Color(light: 0x18181B, dark: 0x3F3F46)
    static let warning = Color(light: 0xC2410C, dark: 0xFB923C)

    /// The brand gradient, thermal from deep violet to amber.
    static let thermal: [Color] = [
        Color(hex: 0x320A5E), Color(hex: 0x781C6D), Color(hex: 0xBC3754), Color(hex: 0xED6925), Color(hex: 0xFBB61A),
    ]
    static let iconGradient = LinearGradient(colors: thermal, startPoint: .bottomLeading, endPoint: .topTrailing)
}

/// The window backdrop: a soft thermal mesh gradient under the white glass cards.
struct WindowBackdrop: View {
    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.55, 0.45], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    Color(light: 0xFFD27A, dark: 0x7A3A10), Color(light: 0xFFB088, dark: 0x6E2418), Color(light: 0xF5A3B5, dark: 0x4A1236),
                    Color(light: 0xFFA36B, dark: 0x6A2A12), Color(light: 0xF08A9A, dark: 0x4E1530), Color(light: 0xC9A3E8, dark: 0x2A0E45),
                    Color(light: 0xF48FA8, dark: 0x45122E), Color(light: 0xC6A0E6, dark: 0x2A0C44), Color(light: 0xA99BE0, dark: 0x170733),
                ])
            // Wash so the gradient stays soft behind text.
            Color(light: 0xFFFFFF, dark: 0x050506, lightAlpha: 0.42, darkAlpha: 0.38)
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

/// The app mark: a white tile with a thermal text cursor and sound arcs, matching the app icon.
struct LogoMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(.white)
                .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).stroke(.black.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            Canvas { ctx, canvas in
                let s = canvas.width / 200
                func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
                let heat = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: Theme.thermal), startPoint: p(40, 160), endPoint: p(160, 40))

                var caret = Path()
                caret.move(to: p(86, 56)); caret.addLine(to: p(114, 56))
                caret.move(to: p(100, 56)); caret.addLine(to: p(100, 144))
                caret.move(to: p(86, 144)); caret.addLine(to: p(114, 144))
                ctx.stroke(caret, with: heat, style: StrokeStyle(lineWidth: 13 * s, lineCap: .round))

                var arcs = Path()
                arcs.move(to: p(62, 78)); arcs.addQuadCurve(to: p(62, 122), control: p(50, 100))
                arcs.move(to: p(138, 78)); arcs.addQuadCurve(to: p(138, 122), control: p(150, 100))
                ctx.stroke(arcs, with: heat, style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

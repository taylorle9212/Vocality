import SwiftUI

/// Liquid Glass on macOS 26 and later, a frosted material before that.
enum GlassSupport {
    /// Offscreen snapshots can't sample the desktop behind glass, so they draw the fallback.
    static var forceFallback = false

    static var isAvailable: Bool {
        if forceFallback { return false }
        if #available(macOS 26, *) { return true }
        return false
    }
}

extension View {
    /// A glass surface in `shape`, optionally tinted. Used for floating controls only.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *), GlassSupport.isAvailable {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(
                shape.fill(.regularMaterial)
                    .overlay(shape.fill(tint ?? Theme.card.opacity(0.55)))
                    .overlay(shape.stroke(Theme.line, lineWidth: 1))
            )
        }
    }

    /// Groups nearby glass shapes so they blend and morph together on macOS 26.
    @ViewBuilder
    func glassGroup(spacing: CGFloat) -> some View {
        if #available(macOS 26, *), GlassSupport.isAvailable {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// Prominent glass buttons on macOS 26, bordered prominent before.
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(macOS 26, *), GlassSupport.isAvailable {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Light effects

/// An iridescent edge, like light splitting at the rim of glass. Rotates slowly when `animated`.
struct IridescentRim<S: InsettableShape>: View {
    let shape: S
    var lineWidth: CGFloat = 1.2
    var opacity: Double = 0.55
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var colors: [Color] {
        [Color(hex: 0xA78BFA), Color(hex: 0x67E8F9), Color(hex: 0xF0ABFC), Color(hex: 0x818CF8), Color(hex: 0xA78BFA)]
    }

    var body: some View {
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                rim(angle: .degrees(context.date.timeIntervalSinceReferenceDate * 40))
            }
        } else {
            rim(angle: .degrees(-30))
        }
    }

    private func rim(angle: Angle) -> some View {
        shape
            .strokeBorder(
                AngularGradient(colors: Self.colors, center: .center, angle: angle),
                lineWidth: lineWidth)
            .opacity(opacity)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}

/// A bright band of light that sweeps across a surface whenever `trigger` changes.
struct SheenSweep<S: Shape, T: Equatable>: View {
    let shape: S
    let trigger: T
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, .white.opacity(0.28), .white.opacity(0.06), .clear],
                startPoint: .leading,
                endPoint: .trailing)
                .frame(width: geo.size.width * 0.45)
                .rotationEffect(.degrees(18))
                .offset(x: phase * geo.size.width * 1.2)
        }
        .mask(shape)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in sweep() }
        .onAppear { sweep() }
    }

    private func sweep() {
        guard !reduceMotion else { return }
        phase = -0.6
        withAnimation(.easeInOut(duration: 0.9)) { phase = 1.1 }
    }
}

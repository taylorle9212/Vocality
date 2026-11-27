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

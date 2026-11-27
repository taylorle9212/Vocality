import AppKit
import SwiftUI

/// The recorder: a black glass "island" at the bottom of the screen.
/// It glides up from the bottom of the screen and glides back down when done.
/// Click-through and non-activating, so it never takes focus from the app being typed into.
@MainActor
final class RecorderOverlay {
    enum Mode: Equatable {
        case recording
        case transcribing
        /// Send key glyph, plus the app the text went to.
        case sent(String, app: String? = nil, iconPath: String? = nil)
        case pasted
        case error(String)
    }

    final class Model: ObservableObject {
        @Published var mode: Mode = .recording
        @Published var visible = false
        @Published var autoSend = true
        @Published var levels: [CGFloat] = Array(repeating: 0, count: 22)
        /// 0...1: recording time used out of the maximum length.
        @Published var charge: CGFloat = 0
        /// For offscreen snapshots: draw each state's end frame instead of animating into it.
        var settled = false
        private var smoothed: CGFloat = 0

        var lastLevel: CGFloat { levels.last ?? 0 }

        /// Slow volume envelope (0...1, from decibels): rises quickly, falls slowly.
        @Published var volume: CGFloat = 0

        func push(level: Float) {
            smoothed = smoothed * 0.55 + CGFloat(level) * 0.45
            levels.removeFirst()
            levels.append(smoothed)
            let target = CGFloat(level)
            volume += (target - volume) * (target > volume ? 0.2 : 0.06)
        }

        func reset() {
            levels = Array(repeating: 0, count: levels.count)
            charge = 0
            smoothed = 0
            volume = 0
        }
    }

    private let model = Model()
    private var panel: NSPanel?
    private var task: Task<Void, Never>?
    private let size = NSSize(width: 380, height: 120)

    func show(_ mode: Mode, autoSend: Bool = Settings.autoEnter) {
        task?.cancel()
        if mode == .recording { model.reset() }
        model.autoSend = autoSend
        model.mode = mode
        present()
    }

    func update(level: Float) {
        guard model.mode == .recording else { return }
        model.push(level: level)
    }

    /// Recording time used, 0...1 of the maximum length. Drawn as the ring around the send button.
    func update(progress: Double) {
        guard model.mode == .recording else { return }
        model.charge = CGFloat(min(1, max(0, progress)))
    }

    /// Shows a final state briefly, then folds the island away.
    func flash(_ mode: Mode) {
        task?.cancel()
        model.mode = mode
        present()
        let linger: Int = {
            switch mode {
            case .sent: return 1250
            case .pasted: return 850
            default: return 1800
            }
        }()
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(linger))
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    /// Folds the island back to a capsule, then fades it out.
    /// Glides the island down and out.
    func hide() {
        task?.cancel()
        model.visible = false
        let panel = self.panel
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, !self.model.visible else { return }
            panel?.orderOut(nil)
        }
    }

    private func present() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let appearing = !model.visible
        if !panel.isVisible {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrame(
                    NSRect(x: frame.midX - size.width / 2, y: frame.minY + 14, width: size.width, height: size.height),
                    display: false)
            }
            panel.orderFrontRegardless()
        }
        if appearing { model.visible = true }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        return panel
    }
}

// MARK: - Views

/// Island colors are fixed: frosted white glass in both light and dark mode.
private enum Island {
    static let tint = Color.white.opacity(0.55)
    static let text = Color(hex: 0x111113)
    static let secondary = Color(hex: 0x5F5F68)
    static let edge = Color.black.opacity(0.07)
    static let track = Color.black.opacity(0.08)
    static let mid = Color(hex: 0xED6925)
    static let high = Color(hex: 0x111113)
    static let send = Color(hex: 0x18181B)
}

/// Smooth, unbouncy motion for the island gliding in and out.
private let glide = Animation.smooth(duration: 0.4)
private let contentSpring = Animation.spring(response: 0.36, dampingFraction: 0.86)

private struct OverlayView: View {
    @ObservedObject var model: RecorderOverlay.Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.visible {
                IslandView(model: model)
                    .transition(reduceMotion ? .opacity : .offset(y: 44).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 10)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : glide, value: model.visible)
    }
}

private struct IslandView: View {
    @ObservedObject var model: RecorderOverlay.Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            LaunchPad(model: model)
            content
                .shadow(color: .white.opacity(0.7), radius: 2)
                .fixedSize()
                .transition(.opacity)
                .id(contentID)
        }
        .padding(.leading, 8)
        .padding(.trailing, 18)
        .frame(height: 52)
        .glassSurface(Capsule(style: .continuous), tint: Island.tint, clear: true)
        .overlay(Capsule(style: .continuous).strokeBorder(Island.edge, lineWidth: 1))
        .overlay(IridescentRim(shape: Capsule(style: .continuous), lineWidth: 1, opacity: 0.45, animated: !model.settled))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
        .glassGroup(spacing: 12)
        // Width eases as the content changes; no bounce.
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: contentID)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var contentID: String {
        switch model.mode {
        case .recording: return "rec"
        case .transcribing: return "busy"
        case .sent: return "sent"
        case .pasted: return "pasted"
        case .error: return "error"
        }
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .recording:
            ParticleField(volume: model.volume, animated: !model.settled)
        case .transcribing:
            Text("Transcribing").font(.system(size: 13, weight: .semibold)).foregroundStyle(Island.text)
        case .sent(let glyph, let app, let iconPath):
            HStack(spacing: 7) {
                if let iconPath {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: iconPath))
                        .resizable()
                        .frame(width: 18, height: 18)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(app.map { "Sent to \($0)" } ?? "Sent")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Island.text)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
                Text(glyph)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.14)))
                    .foregroundStyle(Island.high)
            }
        case .pasted:
            Text("Pasted").font(.system(size: 14, weight: .semibold)).foregroundStyle(Island.text)
        case .error(let message):
            Text(message).font(.system(size: 12, weight: .medium)).foregroundStyle(Island.text)
                .lineLimit(2).frame(maxWidth: 240, alignment: .leading)
        }
    }

    private var accessibilityText: String {
        switch model.mode {
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .sent: return "Sent"
        case .pasted: return "Pasted"
        case .error(let message): return message
        }
    }
}

/// The glass button on the left: an arrow that charges while you talk and launches on send.
private struct LaunchPad: View {
    @ObservedObject var model: RecorderOverlay.Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var launched = false
    @State private var showCheck = false
    @State private var spin = false

    private let diameter: CGFloat = 36

    var body: some View {
        ZStack {
            Color.clear
                .glassSurface(Circle(), tint: padTint, interactive: true)
                .animation(contentSpring, value: padTint)
            IridescentRim(shape: Circle(), lineWidth: 1, opacity: 0.55)

            // Charge ring: fills as you speak, spins while transcribing.
            Circle().stroke(Island.track, lineWidth: 3)
            Circle()
                .trim(from: 0, to: ringTrim)
                .stroke(model.mode == .recording ? Thermal.color(0.35 + model.charge * 0.5) : Island.mid, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(spin ? 270 : -90))
                .animation(.easeOut(duration: 0.12), value: model.charge)

            if isError {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFB923C))
            } else if !model.autoSend && (model.mode == .recording || model.mode == .transcribing) {
                Circle().fill(Island.mid).frame(width: 10, height: 10)
                    .scaleEffect(model.mode == .recording ? 1 + min(0.5, model.lastLevel * 0.8) : 1)
                    .animation(.easeOut(duration: 0.1), value: model.lastLevel)
            } else {
                arrow
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .scaleEffect(isChecked ? 1 : 0.3)
                    .opacity(isChecked ? 1 : 0)
            }
        }
        .frame(width: diameter, height: diameter)
        .onChange(of: model.mode) { _, mode in react(to: mode) }
        .onAppear { react(to: model.mode) }
    }

    private var arrow: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(isSent ? .white : Island.high)
            .offset(y: isLaunched ? -40 : 0)
            .scaleEffect(isLaunched ? 0.6 : 1)
            .opacity(isLaunched || isChecked ? 0 : 1)
            // Idle "ready to launch" bob while recording or transcribing.
            .phaseAnimator(bobPhases) { view, phase in
                view.offset(y: phase)
            } animation: { _ in .easeInOut(duration: 0.75) }
    }

    private var bobPhases: [CGFloat] {
        guard !reduceMotion, !launched, model.mode == .recording || model.mode == .transcribing else { return [0] }
        return [0, -2.5]
    }

    private var isLaunched: Bool { launched || (model.settled && isSent) }

    private var isChecked: Bool {
        showCheck || (model.settled && (isSent || model.mode == .pasted))
    }

    private var isSent: Bool {
        if case .sent = model.mode { return true }
        return false
    }

    private var isError: Bool {
        if case .error = model.mode { return true }
        return false
    }

    /// Faint violet glass while armed; solid violet once sent.
    private var padTint: Color {
        if isSent || isChecked { return Island.send }
        if isError { return Color(hex: 0xFB923C).opacity(0.2) }
        return Color.white.opacity(0.7)
    }

    private var ringTrim: CGFloat {
        switch model.mode {
        case .recording: return model.charge
        case .transcribing: return 0.3
        default: return 0
        }
    }

    private func react(to mode: RecorderOverlay.Mode) {
        switch mode {
        case .recording:
            launched = false
            showCheck = false
            spin = false
        case .transcribing:
            spin = false
            if !reduceMotion {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
            }
        case .sent:
            spin = false
            if reduceMotion {
                showCheck = true
                return
            }
            withAnimation(.easeIn(duration: 0.28)) { launched = true }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.22)) { showCheck = true }
        case .pasted:
            spin = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { showCheck = true }
        case .error:
            spin = false
        }
    }
}

/// Thermal ("inferno") palette: deep violet → magenta → red-orange → amber → white-hot.
enum Thermal {
    private static let stops: [(CGFloat, (Double, Double, Double))] = [
        (0.0, (0.20, 0.04, 0.37)),   // #320A5E
        (0.3, (0.47, 0.11, 0.43)),   // #781C6D
        (0.55, (0.74, 0.22, 0.33)),  // #BC3754
        (0.75, (0.93, 0.41, 0.15)),  // #ED6925
        (0.9, (0.98, 0.71, 0.10)),   // #FBB61A
        (1.0, (0.99, 1.0, 0.64)),    // #FCFFA4
    ]

    static func color(_ value: CGFloat) -> Color {
        let t = max(0, min(1, value))
        for i in 1..<stops.count where t <= stops[i].0 {
            let (t0, a) = stops[i - 1]
            let (t1, b) = stops[i]
            let f = Double((t - t0) / (t1 - t0))
            return Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
        }
        return Color(red: 0.99, green: 1.0, blue: 0.64)
    }
}

/// A field of tiny round dots driven by volume.
/// Each dot has a fixed home, size and drift path. Louder speech shows more dots (in a fixed
/// order, each fading in) and makes every dot drift further. Drawn on the GPU every frame.
private struct ParticleField: View {
    let volume: CGFloat
    var animated = true

    private struct Particle {
        let x: CGFloat, y: CGFloat      // home, 0...1
        let size: CGFloat
        let phaseX: Double, phaseY: Double
        let speedX: Double, speedY: Double
        let warmth: CGFloat             // small per-dot color variation
    }

    private static let count = 90
    /// Minimum dots shown while listening in silence.
    private static let resting = 5

    /// Deterministic, evenly spread particles (a jittered grid, shuffled into a fixed reveal order).
    private static let particles: [Particle] = {
        var rng = SeededGenerator(seed: 0x5EED)
        let cols = 18, rows = 5
        var list: [Particle] = []
        for r in 0..<rows {
            for c in 0..<cols {
                list.append(Particle(
                    x: (CGFloat(c) + 0.5 + CGFloat.random(in: -0.35...0.35, using: &rng)) / CGFloat(cols),
                    y: (CGFloat(r) + 0.5 + CGFloat.random(in: -0.35...0.35, using: &rng)) / CGFloat(rows),
                    size: CGFloat.random(in: 1.6...2.8, using: &rng),
                    phaseX: Double.random(in: 0...(2 * .pi), using: &rng),
                    phaseY: Double.random(in: 0...(2 * .pi), using: &rng),
                    speedX: Double.random(in: 0.5...1.3, using: &rng),
                    speedY: Double.random(in: 0.5...1.3, using: &rng),
                    warmth: CGFloat.random(in: -0.08...0.08, using: &rng)))
            }
        }
        list.shuffle(using: &rng)
        return list
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !animated)) { context in
            let time = animated ? context.date.timeIntervalSinceReferenceDate : 3.0
            Canvas { gc, size in draw(in: &gc, size: size, time: time) }
        }
        .frame(width: 190, height: 36)
        .drawingGroup()
        .accessibilityHidden(true)
    }

    private func draw(in gc: inout GraphicsContext, size: CGSize, time: Double) {
        let v = max(0, min(1, volume))
        // Map volume to how many dots are visible; the last one fades in.
        let visible = CGFloat(Self.resting) + CGFloat(Self.count - Self.resting) * pow(v, 0.85)
        // Drift grows with volume: nearly still when quiet, lively when loud.
        let drift = 0.8 + 6.5 * v
        let heatBase = 0.3 + 0.5 * v

        for (i, p) in Self.particles.enumerated() {
            let reveal = min(1, max(0, visible - CGFloat(i)))
            guard reveal > 0.01 else { break }
            let dx = CGFloat(sin(time * p.speedX + p.phaseX)) * drift
            let dy = CGFloat(cos(time * p.speedY + p.phaseY)) * drift * 0.6
            let x = p.x * size.width + dx
            let y = p.y * size.height + dy
            let s = p.size * (0.85 + 0.3 * v)
            let rect = CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
            let heat = min(0.86, max(0.1, heatBase + p.warmth))
            gc.fill(Path(ellipseIn: rect), with: .color(Thermal.color(heat).opacity(Double(reveal) * 0.92)))
        }
    }
}

/// Small deterministic RNG so the dot layout is the same every launch.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Snapshots

extension RecorderOverlay {
    /// A settled island for offscreen rendering.
    static func snapshotView(
        _ mode: Mode, autoSend: Bool = true, levels: [CGFloat] = [], charge: CGFloat = 0
    ) -> some View {
        let model = Model()
        model.mode = mode
        model.autoSend = autoSend
        model.settled = true
        model.visible = true
        if !levels.isEmpty {
            model.levels = levels
            model.volume = levels.reduce(0, +) / CGFloat(levels.count)
        }
        model.charge = charge
        return IslandView(model: model).padding(20)
    }
}

import AppKit
import SwiftUI

/// The recorder: a black glass "island" at the bottom of the screen.
/// It appears as a small capsule, springs open while you talk, and folds back up before it goes away.
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
        /// Collapsed is the small resting capsule; expanded shows the full island.
        @Published var expanded = false
        @Published var autoSend = true
        @Published var levels: [CGFloat] = Array(repeating: 0, count: 22)
        /// 0...1, fills while you speak: the "charge" of the send arrow.
        @Published var charge: CGFloat = 0
        /// For offscreen snapshots: draw each state's end frame instead of animating into it.
        var settled = false
        private var smoothed: CGFloat = 0

        var lastLevel: CGFloat { levels.last ?? 0 }

        func push(level: Float) {
            smoothed = smoothed * 0.55 + CGFloat(level) * 0.45
            levels.removeFirst()
            levels.append(smoothed)
            charge = min(1, charge + 0.004 + smoothed * 0.02)
        }

        func reset() {
            levels = Array(repeating: 0, count: levels.count)
            charge = 0
            smoothed = 0
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
    func hide() {
        task?.cancel()
        model.expanded = false
        let panel = self.panel
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            self.model.visible = false
            try? await Task.sleep(for: .milliseconds(260))
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
        if appearing {
            model.expanded = false
            model.visible = true
            // Let the capsule land first, then open it.
            task = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(70))
                guard !Task.isCancelled else { return }
                self.model.expanded = true
            }
        } else {
            model.expanded = true
        }
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

/// Island colors are fixed: the island is black in both light and dark mode.
private enum Island {
    static let tint = Color.black.opacity(0.84)
    static let text = Color.white
    static let secondary = Color.white.opacity(0.6)
    static let edge = Color.white.opacity(0.09)
    static let low = Color(hex: 0x4C3A8F)
    static let mid = Color(hex: 0x8B5CF6)
    static let high = Color(hex: 0xC4B5FD)
    static let send = Color(hex: 0x7C3AED)
}

/// Bouncy, like Dynamic Island.
private let islandSpring = Animation.spring(response: 0.48, dampingFraction: 0.7)
private let contentSpring = Animation.spring(response: 0.36, dampingFraction: 0.86)

private struct OverlayView: View {
    @ObservedObject var model: RecorderOverlay.Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.visible {
                IslandView(model: model)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 10)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : islandSpring, value: model.visible)
    }
}

private struct IslandView: View {
    @ObservedObject var model: RecorderOverlay.Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let open = model.expanded
        HStack(spacing: open ? 12 : 0) {
            LaunchPad(model: model)
                .scaleEffect(open ? 1 : 0.5)
                .opacity(open ? 1 : 0)
            content
                .fixedSize()
                .transition(.blurReplace.combined(with: .opacity))
                .id(contentID)
                .frame(width: open ? nil : 0, alignment: .leading)
                .opacity(open ? 1 : 0)
                .clipped()
        }
        .padding(.leading, open ? 8 : 0)
        .padding(.trailing, open ? 18 : 0)
        .frame(minWidth: open ? nil : 72, minHeight: open ? 52 : 28, maxHeight: open ? 52 : 28)
        .glassSurface(Capsule(style: .continuous), tint: Island.tint)
        .overlay(Capsule(style: .continuous).strokeBorder(Island.edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: open ? 18 : 8, y: open ? 10 : 4)
        // A slight swell with your voice while recording.
        .scaleEffect(breathe)
        .glassGroup(spacing: 12)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : islandSpring, value: model.expanded)
        .animation(contentSpring, value: contentID)
        .animation(.easeOut(duration: 0.12), value: model.lastLevel)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var breathe: CGFloat {
        guard !reduceMotion, model.expanded, model.mode == .recording else { return 1 }
        return 1 + min(0.025, model.lastLevel * 0.03)
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
            Waveform(levels: model.levels)
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
    @State private var sparksOut = false

    private let diameter: CGFloat = 36

    var body: some View {
        ZStack {
            Color.clear
                .glassSurface(Circle(), tint: padTint, interactive: true)
                .animation(contentSpring, value: padTint)

            // Charge ring: fills as you speak, spins while transcribing.
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: ringTrim)
                .stroke(Island.mid, style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
                // Trail left behind by the launch.
                Capsule()
                    .fill(LinearGradient(colors: [Island.mid.opacity(0), Island.high.opacity(0.8)], startPoint: .bottom, endPoint: .top))
                    .frame(width: 3, height: isLaunched ? 26 : 0)
                    .offset(y: isLaunched ? -14 : 0)
                    .opacity(isLaunched && !isChecked ? 1 : 0)
                sparks
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

    /// A small burst from the button as the arrow launches.
    private var sparks: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 2 * .pi - .pi / 2
                let radius: CGFloat = sparksOut ? 30 : 10
                Capsule()
                    .fill(i.isMultiple(of: 2) ? Island.high : Island.mid)
                    .frame(width: 2.5, height: sparksOut ? 3 : 7)
                    .rotationEffect(.radians(angle + .pi / 2))
                    .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            }
        }
        .opacity(launched && !sparksOut ? 1 : 0)
        .allowsHitTesting(false)
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
        return Island.mid.opacity(0.22)
    }

    private var ringTrim: CGFloat {
        switch model.mode {
        case .recording: return max(0.04, model.charge)
        case .transcribing: return 0.3
        default: return 0
        }
    }

    private func react(to mode: RecorderOverlay.Mode) {
        switch mode {
        case .recording:
            launched = false
            showCheck = false
            sparksOut = false
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
            sparksOut = false
            withAnimation(.easeIn(duration: 0.28)) { launched = true }
            withAnimation(.easeOut(duration: 0.55).delay(0.16)) { sparksOut = true }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.22)) { showCheck = true }
        case .pasted:
            spin = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { showCheck = true }
        case .error:
            spin = false
        }
    }
}

private struct Waveform: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(color(for: levels[i]))
                    .frame(width: 3, height: 4 + levels[i] * 24)
            }
        }
        .frame(height: 30)
        .animation(.interpolatingSpring(stiffness: 260, damping: 22), value: levels)
    }

    private func color(for level: CGFloat) -> Color {
        level > 0.55 ? Island.high : (level > 0.2 ? Island.mid : Island.low)
    }
}

// MARK: - Snapshots

extension RecorderOverlay {
    /// A settled island for offscreen rendering. `expanded: false` draws the resting capsule.
    static func snapshotView(
        _ mode: Mode, autoSend: Bool = true, levels: [CGFloat] = [], charge: CGFloat = 0, expanded: Bool = true
    ) -> some View {
        let model = Model()
        model.mode = mode
        model.autoSend = autoSend
        model.settled = true
        model.visible = true
        model.expanded = expanded
        if !levels.isEmpty { model.levels = levels }
        model.charge = charge
        return IslandView(model: model).padding(20)
    }
}

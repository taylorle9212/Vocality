import AppKit
import SwiftUI

/// The floating pill near the bottom of the screen. It stays up from fn-press to send and
/// animates between states: recording (send arrow charging) → transcribing → sent (arrow launches).
/// Click-through and non-activating, so it never takes focus from the app being typed into.
@MainActor
final class RecorderOverlay {
    enum Mode: Equatable {
        case recording
        case transcribing
        case sent(String)
        case pasted
        case error(String)
    }

    final class Model: ObservableObject {
        @Published var mode: Mode = .recording
        @Published var visible = false
        @Published var autoSend = true
        @Published var levels: [CGFloat] = Array(repeating: 0, count: 22)
        /// 0...1, fills while you speak: the "charge" of the send arrow.
        @Published var charge: CGFloat = 0
        /// For offscreen snapshots: draw each state's end frame instead of animating into it.
        var settled = false
        private var smoothed: CGFloat = 0

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
    private var hideTask: Task<Void, Never>?
    private let size = NSSize(width: 360, height: 120)

    func show(_ mode: Mode, autoSend: Bool = Settings.autoEnter) {
        hideTask?.cancel()
        if mode == .recording { model.reset() }
        model.autoSend = autoSend
        model.mode = mode
        present()
    }

    func update(level: Float) {
        guard model.mode == .recording else { return }
        model.push(level: level)
    }

    /// Shows a final state briefly, then hides.
    func flash(_ mode: Mode) {
        hideTask?.cancel()
        model.mode = mode
        present()
        let linger: Int = {
            switch mode {
            case .sent: return 1300
            case .pasted: return 900
            default: return 1800
            }
        }()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(linger))
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        model.visible = false
        let panel = self.panel
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !self.model.visible else { return }
            panel?.orderOut(nil)
        }
    }

    private func present() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrame(
                    NSRect(x: frame.midX - size.width / 2, y: frame.minY + 16, width: size.width, height: size.height),
                    display: false)
            }
            panel.orderFrontRegardless()
        }
        model.visible = true
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

private let pillSpring = Animation.spring(response: 0.42, dampingFraction: 0.86)

private struct OverlayView: View {
    @ObservedObject var model: RecorderOverlay.Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.visible {
                Pill(model: model)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .offset(y: 24).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .bottom)),
                                removal: .offset(y: 12).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .bottom))))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 10)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : pillSpring, value: model.visible)
    }
}

private struct Pill: View {
    @ObservedObject var model: RecorderOverlay.Model

    var body: some View {
        HStack(spacing: 12) {
            LaunchPad(model: model)
            content
                .transition(.opacity.combined(with: .offset(x: 6)))
                .id(contentID)
        }
        .padding(.leading, 8)
        .padding(.trailing, 18)
        .frame(height: 52)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay(Capsule(style: .continuous).fill(Theme.card.opacity(0.55)))
                .overlay(Capsule(style: .continuous).stroke(Theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        )
        .animation(pillSpring, value: contentID)
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
            Waveform(levels: model.levels)
        case .transcribing:
            Text("Transcribing").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
        case .sent(let glyph):
            HStack(spacing: 6) {
                Text("Sent").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(glyph)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.chip))
                    .foregroundStyle(Theme.chipText)
            }
        case .pasted:
            Text("Pasted").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
        case .error(let message):
            Text(message).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(2)
                .frame(maxWidth: 240, alignment: .leading)
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

/// The circular badge on the left: an arrow that charges while you talk and launches on send.
private struct LaunchPad: View {
    @ObservedObject var model: RecorderOverlay.Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var launched = false
    @State private var showCheck = false
    @State private var spin = false

    private let diameter: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(padFill)

            // Charge ring: fills as you speak, spins while transcribing.
            Circle()
                .stroke(Theme.sky300.opacity(0.35), lineWidth: 3)
            Circle()
                .trim(from: 0, to: ringTrim)
                .stroke(Theme.sky500, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(spin ? 270 : -90))
                .animation(.easeOut(duration: 0.12), value: model.charge)

            if isError {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.warning)
            } else if !model.autoSend && (model.mode == .recording || model.mode == .transcribing) {
                Circle().fill(Theme.sky600).frame(width: 10, height: 10)
                    .scaleEffect(model.mode == .recording ? 1 + min(0.5, (model.levels.last ?? 0) * 0.8) : 1)
                    .animation(.easeOut(duration: 0.1), value: model.levels.last)
            } else {
                arrow
                // Trail left behind by the launch.
                Capsule()
                    .fill(LinearGradient(colors: [Theme.sky500.opacity(0), Theme.sky500.opacity(0.7)], startPoint: .bottom, endPoint: .top))
                    .frame(width: 3, height: isLaunched ? 26 : 0)
                    .offset(y: isLaunched ? -14 : 0)
                    .opacity(isLaunched && !isChecked ? 1 : 0)
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
            .foregroundStyle(isSent ? .white : Theme.sky600)
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

    private var padFill: Color {
        if isSent || isChecked { return Theme.action }
        return Theme.chip
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
        level > 0.55 ? Theme.sky600 : (level > 0.2 ? Theme.sky500 : Theme.sky300)
    }
}

// MARK: - Snapshots

extension RecorderOverlay {
    /// A settled, non-animating pill for offscreen rendering.
    static func snapshotView(_ mode: Mode, autoSend: Bool = true, levels: [CGFloat] = [], charge: CGFloat = 0) -> some View {
        let model = Model()
        model.mode = mode
        model.autoSend = autoSend
        model.settled = true
        if !levels.isEmpty { model.levels = levels }
        model.charge = charge
        return Pill(model: model).padding(20)
    }
}

import AppKit

/// Watches the Fn (🌐) key system-wide.
/// Hold Fn to talk and release to finish. A quick tap locks recording on until the next tap.
/// Esc cancels. Needs Accessibility permission to see keys in other apps.
final class HotkeyMonitor {
    enum Event {
        case start
        case finish
        case cancel
    }

    var onEvent: ((Event) -> Void)?
    /// Whether a recording is in progress, so Fn and Esc act on it.
    var isRecording: () -> Bool = { false }

    private var monitors: [Any] = []
    private var fnDown = false
    private var pressedAt = Date.distantPast
    private var locked = false

    private static let fnKeyCode: UInt16 = 63
    private static let escKeyCode: UInt16 = 53
    private static let tapThreshold: TimeInterval = 0.3

    func start() {
        stop()
        let flags: (NSEvent) -> Void = { [weak self] in self?.handleFlags($0) }
        let keys: (NSEvent) -> Void = { [weak self] in self?.handleKey($0) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keys) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { keys($0); return $0 }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handleFlags(_ event: NSEvent) {
        guard event.keyCode == Self.fnKeyCode else { return }
        let isDown = event.modifierFlags.contains(.function)
        guard isDown != fnDown else { return }
        fnDown = isDown

        if isDown {
            if isRecording() {
                // A tap while locked (or any press while recording) finishes.
                locked = false
                onEvent?(.finish)
                pressedAt = .distantPast
            } else {
                pressedAt = Date()
                onEvent?(.start)
            }
        } else {
            guard pressedAt != .distantPast else { return }
            let held = Date().timeIntervalSince(pressedAt)
            pressedAt = .distantPast
            if held < Self.tapThreshold {
                locked = true  // quick tap: keep listening hands-free
            } else if isRecording() {
                onEvent?(.finish)
            }
        }
    }

    private func handleKey(_ event: NSEvent) {
        guard event.keyCode == Self.escKeyCode, isRecording() else { return }
        locked = false
        onEvent?(.cancel)
    }
}

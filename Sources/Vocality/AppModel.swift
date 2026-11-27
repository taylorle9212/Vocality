import AVFoundation
import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

struct HistoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date: Date
    var sent: Bool
}

/// Ties together the hotkey, microphone, speech model and paste.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var modelState: Transcriber.State = .notDownloaded
    @Published private(set) var level: Float = 0
    @Published private(set) var history: [HistoryItem] = []
    @Published private(set) var micGranted = false
    @Published private(set) var accessibilityGranted = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { setLaunchAtLogin(launchAtLogin) }
    }

    let overlay = RecorderOverlay()
    private let transcriber = Transcriber()
    private let capture = AudioCapture()
    private let hotkey = HotkeyMonitor()
    private var permissionTimer: Timer?

    var isReady: Bool { modelState == .ready && micGranted && accessibilityGranted }

    /// `snapshot: true` builds a passive model for offscreen rendering: no hotkey, mic or model loading.
    init(snapshot: Bool = false) {
        Settings.registerDefaults()
        loadHistory()
        refreshPermissions()
        if snapshot {
            modelState = .ready
            return
        }

        capture.onLevel = { [weak self] level in
            guard let self else { return }
            self.level = level
            self.overlay.update(level: level)
        }
        hotkey.isRecording = { [weak self] in self?.phase == .recording }
        hotkey.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        hotkey.start()

        // Permissions can be granted while the app runs; keep the checklist fresh.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }

        Task { await prepareModel() }
    }

    // MARK: - Model

    func prepareModel() async {
        await transcriber.prepare { [weak self] state in
            Task { @MainActor in self?.modelState = state }
        }
    }

    // MARK: - Permissions

    func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let trusted = AXIsProcessTrusted()
        if trusted && !accessibilityGranted { hotkey.start() }  // monitors need re-adding after trust
        accessibilityGranted = trusted
    }

    func requestMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in self.refreshPermissions() }
            }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    // MARK: - Recording flow

    func toggleRecording() {
        handle(phase == .recording ? .finish : .start)
    }

    private func handle(_ event: HotkeyMonitor.Event) {
        switch event {
        case .start: startRecording()
        case .finish: finishRecording()
        case .cancel: cancelRecording()
        }
    }

    private func startRecording() {
        guard phase == .idle else { return }
        guard micGranted else {
            requestMicrophone()
            return
        }
        do {
            try capture.start()
            phase = .recording
            Sounds.start()
            overlay.show(.recording)
        } catch {
            overlay.flash(.error(error.localizedDescription))
        }
    }

    private func finishRecording() {
        guard phase == .recording else { return }
        let samples: [Float]
        do {
            samples = try capture.stop()
        } catch {
            phase = .idle
            overlay.flash(.error(error.localizedDescription))
            return
        }
        Sounds.stop()

        // Ignore accidental taps with almost no audio.
        guard samples.count > 16_000 / 4 else {
            phase = .idle
            overlay.hide()
            return
        }

        phase = .transcribing
        overlay.show(.transcribing)

        Task {
            do {
                var text = TextCleanup.apply(try await transcriber.transcribe(samples))
                guard !text.isEmpty else {
                    phase = .idle
                    overlay.hide()
                    return
                }
                if Settings.trailingSpace { text += " " }
                // The overlay is click-through and non-activating, so it can stay up while pasting.
                let sent = await Paster.paste(text)
                addHistory(text, sent: sent)
                phase = .idle
                if !Settings.showSentBadge {
                    overlay.hide()
                } else if sent {
                    overlay.flash(.sent(Settings.enterKey.glyph))
                } else {
                    overlay.flash(.pasted)
                }
            } catch {
                phase = .idle
                overlay.flash(.error(error.localizedDescription))
            }
        }
    }

    private func cancelRecording() {
        guard phase == .recording else { return }
        capture.cancel()
        phase = .idle
        overlay.hide()
    }

    // MARK: - History

    func copy(_ item: HistoryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    private func addHistory(_ text: String, sent: Bool) {
        history.insert(HistoryItem(text: text, date: Date(), sent: sent), at: 0)
        if history.count > 50 { history.removeLast(history.count - 50) }
        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.history),
            let items = try? JSONDecoder().decode([HistoryItem].self, from: data)
        else { return }
        history = items
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: SettingsKey.history)
        }
    }

    // MARK: - Launch at login

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Vocality: launch at login failed: \(error.localizedDescription)")
        }
    }
}

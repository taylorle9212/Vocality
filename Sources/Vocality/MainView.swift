import SwiftUI

struct MainView: View {
    var body: some View {
        ScrollView { Content() }
            .scrollContentBackground(.hidden)
            .background(WindowBackdrop())
            .frame(minWidth: 460, minHeight: 480)
    }
}

extension MainView {
    struct Content: View {
        @EnvironmentObject private var app: AppModel
        @AppStorage(SettingsKey.autoEnter) private var autoEnter = true
        @AppStorage(SettingsKey.enterKey) private var enterKey = EnterKey.enter.rawValue
        @AppStorage(SettingsKey.showSentBadge) private var showSentBadge = true
        @AppStorage(SettingsKey.playSounds) private var playSounds = true
        @AppStorage(SettingsKey.trailingSpace) private var trailingSpace = false
        @AppStorage(SettingsKey.restoreClipboard) private var restoreClipboard = true

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !app.isReady { setupCard }
                shortcutsCard
                settingsCard
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .foregroundStyle(Theme.ink)
        }

        // MARK: Header

        private var header: some View {
            HStack(spacing: 12) {
                LogoMark(size: 36)
                Text("Vocality").font(.system(size: 22, weight: .heavy, design: .rounded))
                Spacer()
                statusChip
            }
        }

        private var statusChip: some View {
            let (text, color): (String, Color) = {
                switch app.modelState {
                case .ready: return app.isReady ? ("Ready", Theme.accent600) : ("Setup needed", Theme.warning)
                case .downloading(let p): return ("Downloading \(Int(p * 100))%", Theme.accent500)
                case .loading: return ("Loading", Theme.accent500)
                case .notDownloaded: return ("Starting", Theme.accent500)
                case .failed: return ("Model error", Theme.warning)
                }
            }()
            return HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.chipText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassSurface(Capsule(), tint: Theme.accent500.opacity(0.18))
        }

        // MARK: Setup

        private var setupCard: some View {
            Card(title: "Setup") {
                SetupRow(title: "Speech model", detail: modelDetail, done: app.modelState == .ready, action: modelAction)
                Divider().overlay(Theme.line)
                SetupRow(
                    title: "Microphone", detail: "Required to record.", done: app.micGranted,
                    action: ("Allow", { app.requestMicrophone() }))
                Divider().overlay(Theme.line)
                SetupRow(
                    title: "Accessibility", detail: "Required for the fn shortcut and pasting.",
                    done: app.accessibilityGranted,
                    action: ("Open Settings", { app.requestAccessibility() }))
            }
        }

        private var modelDetail: String {
            switch app.modelState {
            case .ready: return "Parakeet V3, on device"
            case .downloading(let p): return "Parakeet V3, 450 MB · \(Int(p * 100))%"
            case .loading: return "Parakeet V3 · loading"
            case .notDownloaded: return "Parakeet V3, 450 MB"
            case .failed(let message): return message
            }
        }

        private var modelAction: (String, () -> Void)? {
            if case .failed = app.modelState { return ("Retry", { Task { await app.prepareModel() } }) }
            return nil
        }

        // MARK: Shortcuts

        private var shortcutsCard: some View {
            Card(title: "Shortcuts") {
                KeyRow(keys: "fn", text: "Hold to record, release to paste")
                KeyRow(keys: "fn  fn", text: "Tap to start, tap again to stop")
                KeyRow(keys: "esc", text: "Cancel")
                Text("If fn opens the emoji picker: System Settings › Keyboard › Press 🌐 key to › Do Nothing.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // MARK: Settings

        private var settingsCard: some View {
            Card(title: "Settings") {
                SettingToggle("Press Return after pasting", isOn: $autoEnter)
                if autoEnter {
                    Picker("Key", selection: $enterKey) {
                        ForEach(EnterKey.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    SettingToggle("Send animation", isOn: $showSentBadge)
                }
                Divider().overlay(Theme.line)
                SettingToggle("Sounds", isOn: $playSounds)
                SettingToggle("Trailing space", isOn: $trailingSpace)
                SettingToggle("Restore clipboard", isOn: $restoreClipboard)
                SettingToggle("Launch at login", isOn: $app.launchAtLogin)
            }
            .tint(Theme.action)
        }
    }
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    let title: String
    var trailing: (String, () -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.slate)
                Spacer()
                if let trailing {
                    Button(trailing.0, action: trailing.1).buttonStyle(.borderless).foregroundStyle(Theme.accent600)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
        )
    }
}

private struct SetupRow: View {
    let title: String
    let detail: String
    let done: Bool
    var action: (String, () -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(done ? Theme.accent600 : Theme.accent300)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.slate)
            }
            Spacer()
            if !done, let action {
                Button(action.0, action: action.1)
                    .glassProminentButton()
                    .tint(Theme.action)
                    .controlSize(.small)
            }
        }
    }
}

private struct KeyRow: View {
    let keys: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: 64)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.chip))
                .foregroundStyle(Theme.chipText)
            Text(text).font(.system(size: 13))
        }
    }
}

private struct SettingToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.action)
        }
    }
}

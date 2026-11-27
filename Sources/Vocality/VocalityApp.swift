import FluidAudio
import SwiftUI

@main
enum Entry {
    static func main() {
        // `Vocality --transcribe <audio-file>` prints a transcript and exits (for testing the pipeline).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--transcribe"), i + 1 < args.count {
            let url = URL(fileURLWithPath: args[i + 1])
            let done = DispatchSemaphore(value: 0)
            // Detached: main() blocks the main thread on the semaphore below.
            Task.detached {
                let transcriber = Transcriber()
                await transcriber.prepare { state in
                    if case .failed(let message) = state { print("error: \(message)") }
                }
                do {
                    let samples = try AudioConverter().resampleAudioFile(url)
                    print(TextCleanup.apply(try await transcriber.transcribe(samples)))
                } catch {
                    print("error: \(error.localizedDescription)")
                }
                done.signal()
            }
            done.wait()
            return
        }
        // `Vocality --snapshot <dir>` renders the UI in light and dark to PNGs (see scripts/validate.sh).
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated {
                Snapshot.run(outputDirectory: URL(fileURLWithPath: args[i + 1]))
            }
            return
        }
        VocalityApp.main()
    }
}

struct VocalityApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        Window("Vocality", id: "main") {
            MainView()
                .environmentObject(app)
                .containerBackground(Color.clear, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 540, height: 620)

        MenuBarExtra {
            MenuContent()
                .environmentObject(app)
        } label: {
            Image(systemName: app.phase == .recording ? "waveform.circle.fill" : "waveform")
        }
    }
}

private struct MenuContent: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.autoEnter) private var autoEnter = true

    var body: some View {
        Button(app.phase == .recording ? "Stop Dictation" : "Start Dictation") { app.toggleRecording() }
            .disabled(!app.isReady)
        Toggle("Auto-Enter After Dictation", isOn: $autoEnter)
            .keyboardShortcut("e", modifiers: [.command, .shift])
        if app.lastText != nil {
            Button("Copy Last Dictation") { app.copyLast() }
        }
        Divider()
        Button("Open Vocality") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Vocality") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

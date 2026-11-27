import AppKit
import SwiftUI

/// Renders the settings window and every recorder state, in light and dark, to PNGs.
/// Also writes the start/stop sounds as WAVs. Used by scripts/validate.sh.
@MainActor
enum Snapshot {
    static func run(outputDirectory: URL) {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        GlassSupport.forceFallback = true
        let model = AppModel(snapshot: true)
        let wave: [CGFloat] = (0..<22).map { (i: Int) -> CGFloat in
            let shape: Double = abs(sin(Double(i) * 0.7))
            let variation: Double = 0.4 + 0.6 * Double(i % 5) / 4
            return CGFloat(0.15 + 0.7 * shape * variation)
        }

        // Any installed app works as the sample "sent to" target.
        let sampleAppIcon = ["/Applications/T3 Code (Beta).app", "/System/Applications/Notes.app"]
            .first { FileManager.default.fileExists(atPath: $0) }
        let overlays: [(String, AnyView)] = [
            ("overlay-recording", AnyView(RecorderOverlay.snapshotView(.recording, levels: wave, charge: 0.65))),
            ("overlay-recording-noautosend", AnyView(RecorderOverlay.snapshotView(.recording, autoSend: false, levels: wave))),
            ("overlay-transcribing", AnyView(RecorderOverlay.snapshotView(.transcribing))),
            ("overlay-sent", AnyView(RecorderOverlay.snapshotView(.sent("⏎", app: "T3 Code", iconPath: sampleAppIcon)))),
            ("overlay-pasted", AnyView(RecorderOverlay.snapshotView(.pasted, autoSend: false))),
            ("overlay-error", AnyView(RecorderOverlay.snapshotView(.error("No microphone input is available.")))),
        ]

        for (scheme, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let colorScheme: ColorScheme = scheme == "dark" ? .dark : .light
            NSAppearance(named: appearanceName)!.performAsCurrentDrawingAppearance {
                let backdrop = scheme == "dark" ? Color(hex: 0x07050D) : Color(hex: 0xF7F5FF)
                let window = MainView.Content()
                    .environmentObject(model)
                    .frame(width: 560)
                    .background(ZStack { backdrop; WindowBackdrop() })
                    .environment(\.colorScheme, colorScheme)
                write(window, to: outputDirectory.appendingPathComponent("window-\(scheme).png"))

                for (name, view) in overlays {
                    let framed = view
                        .environment(\.colorScheme, colorScheme)
                        .background(backdrop)
                    write(framed, to: outputDirectory.appendingPathComponent("\(name)-\(scheme).png"))
                }
            }
        }

        try? Sounds.wav(Sounds.thunk(pitch: 1.0, gain: 0.55))
            .write(to: outputDirectory.appendingPathComponent("sound-start.wav"))
        let stop = Sounds.thunk(pitch: 1.0, gain: 0.5) + [Float](repeating: 0, count: 2_425) + Sounds.thunk(pitch: 0.9, gain: 0.42)
        try? Sounds.wav(stop).write(to: outputDirectory.appendingPathComponent("sound-stop.wav"))
    }

    private static func write<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else {
            print("snapshot failed: \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
    }
}

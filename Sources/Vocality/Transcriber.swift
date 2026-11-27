import AVFoundation
import FluidAudio
import Foundation

/// On-device speech recognition with NVIDIA Parakeet TDT 0.6B v3 (CoreML, via FluidAudio).
actor Transcriber {
    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    private let version: AsrModelVersion = .v3
    private var manager: AsrManager?

    private var cacheDirectory: URL { AsrModels.defaultCacheDirectory(for: version) }

    nonisolated var isDownloaded: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
    }

    /// Downloads (if needed) and loads the model. Progress is reported in [0, 1].
    func prepare(progress: @escaping @Sendable (State) -> Void) async {
        if manager != nil {
            progress(.ready)
            return
        }
        do {
            if !isDownloaded {
                progress(.downloading(0))
                try await ModelHub.download(
                    .parakeetV3,
                    to: cacheDirectory.deletingLastPathComponent(),
                    variant: ParakeetEncoderPrecision.int8.rawValue,
                    additionalModelNames: [ModelNames.ASR.vocabularyFile],
                    progressHandler: { p in progress(.downloading(p.fractionCompleted)) }
                )
            }
            progress(.loading)
            let models = try await AsrModels.load(from: cacheDirectory, version: version, encoderPrecision: .int8)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            self.manager = manager
            progress(.ready)
        } catch {
            progress(.failed(error.localizedDescription))
        }
    }

    /// Transcribes 16 kHz mono samples.
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager else { throw TranscriberError.notReady }
        // Parakeet needs about a second of audio; pad short clips with silence.
        var audio = samples
        if audio.count < 16_000 { audio += [Float](repeating: 0, count: 16_000 - audio.count) }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(audio, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranscriberError: LocalizedError {
    case notReady
    var errorDescription: String? { "The speech model is still loading." }
}

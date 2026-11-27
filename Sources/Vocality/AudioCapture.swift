import AVFoundation
import FluidAudio

/// Captures microphone audio in memory and returns it as 16 kHz mono samples.
final class AudioCapture {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var format: AVAudioFormat?
    private(set) var isRunning = false

    /// Called on the main queue with a 0...1 input level, about 20 times a second.
    var onLevel: ((Float) -> Void)?

    func start() throws {
        guard !isRunning else { return }
        lock.withLock { samples.removeAll(keepingCapacity: true) }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInput }
        self.format = format

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            let chunk = Array(UnsafeBufferPointer(start: channel, count: count))
            self.lock.withLock { self.samples.append(contentsOf: chunk) }

            var sum: Float = 0
            for s in chunk { sum += s * s }
            let rms = sqrt(sum / Float(max(count, 1)))
            let level = min(1, max(0, (20 * log10(max(rms, 1e-6)) + 50) / 45))
            DispatchQueue.main.async { self.onLevel?(level) }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Stops capturing and returns the recording resampled to 16 kHz mono.
    func stop() throws -> [Float] {
        guard isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        let captured = lock.withLock { samples }
        guard let format, !captured.isEmpty,
            let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(captured.count))
        else { return [] }

        buffer.frameLength = AVAudioFrameCount(captured.count)
        captured.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: captured.count)
        }
        return try AudioConverter().resampleBuffer(buffer)
    }

    func cancel() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        lock.withLock { samples.removeAll() }
    }
}

enum CaptureError: LocalizedError {
    case noInput
    var errorDescription: String? { "No microphone input is available." }
}

import AppKit

/// Synthesized "linear switch" clicks: a soft, deep thunk to start and a double thunk to stop.
/// Generated in memory, so there are no audio files to ship.
enum Sounds {
    static func start() { play(startSound) }
    static func stop() { play(stopSound) }

    private static let sampleRate = 44_100.0

    private static let startSound = NSSound(data: wav(thunk(pitch: 1.0, gain: 0.55)))
    private static let stopSound = NSSound(data: wav(
        thunk(pitch: 1.0, gain: 0.5) + silence(0.055) + thunk(pitch: 0.9, gain: 0.42)))

    private static func play(_ sound: NSSound?) {
        guard Settings.playSounds, let sound else { return }
        sound.stop()
        sound.play()
    }

    /// One keystroke: a low, quickly damped body with a short, muffled keycap tick on top.
    static func thunk(pitch: Double, gain: Double) -> [Float] {
        let duration = 0.07
        let count = Int(sampleRate * duration)
        var out = [Float](repeating: 0, count: count)
        var phaseBody = 0.0
        var phaseTock = 0.0
        var noiseLP = 0.0
        var rng = SystemRandomNumberGenerator()

        for i in 0..<count {
            let t = Double(i) / sampleRate
            // Body: a pitch drop from 170 Hz to 85 Hz gives the deep "thunk".
            let fBody = (85 + 85 * exp(-t / 0.012)) * pitch
            phaseBody += 2 * .pi * fBody / sampleRate
            let body = sin(phaseBody) * exp(-t / 0.016)

            // Keycap "tock": a short resonance around 300 Hz.
            phaseTock += 2 * .pi * 300 * pitch / sampleRate
            let tock = sin(phaseTock) * exp(-t / 0.006) * 0.35

            // Contact: a 2 ms burst of low-passed noise, kept soft so it isn't clicky.
            let white = Double.random(in: -1...1, using: &rng)
            noiseLP += 0.18 * (white - noiseLP)
            let contact = noiseLP * exp(-t / 0.0018) * 0.5

            // 1.5 ms fade-in avoids a hard edge.
            let attack = min(1, t / 0.0015)
            out[i] = Float((body + tock + contact) * gain * attack)
        }
        return out
    }

    private static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(sampleRate * seconds))
    }

    /// 16-bit mono PCM WAV.
    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        for s in samples { append(Int16(max(-1, min(1, s)) * Float(Int16.max))) }
        return data
    }
}

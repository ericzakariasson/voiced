import Foundation

/// Deterministic 16 kHz, 16-bit audio at chosen loudness, for testing level handling.
enum SyntheticAudio {
    static let sampleRate = 16_000

    private struct Generator {
        var state: UInt64

        /// Uniform in -1...1.
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 52) - 1
        }
    }

    private static func amplitude(decibels: Double) -> Double {
        pow(10, decibels / 20) * Double(Int16.max)
    }

    private static func data(_ samples: [Double]) -> Data {
        let clipped = samples.map { Int16(max(-32_767, min(32_767, $0.rounded()))) }
        return clipped.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// White noise with the given RMS, in dBFS: a room, a fan, a hiss.
    static func noise(decibels: Double, seconds: Double, seed: UInt64 = 1) -> Data {
        var generator = Generator(state: seed)
        // Uniform noise in -a...a has an RMS of a / √3.
        let peak = amplitude(decibels: decibels) * 3.0.squareRoot()
        return data((0..<Int(seconds * Double(sampleRate))).map { _ in generator.next() * peak })
    }

    /// Something shaped like speech over room noise: a voiced tone in syllables about four to a
    /// second, each a little louder or softer than the last, with a longer pause after every few.
    ///
    /// - Parameters:
    ///   - decibels: RMS of the loudest syllables at their middle, in dBFS.
    ///   - leadIn: Seconds of room noise before the first syllable. The microphone opens when the
    ///     hotkey goes down, a moment before anyone speaks.
    static func speech(decibels: Double, room: Double = -62, seconds: Double, leadIn: Double = 0.3, seed: UInt64 = 7) -> Data {
        var generator = Generator(state: seed)
        let count = Int(seconds * Double(sampleRate))
        let roomPeak = amplitude(decibels: room) * 3.0.squareRoot()
        // Ten harmonics of 120 Hz falling off as 1/k; this is the RMS of that sum at unit scale.
        let harmonics = 1...10
        let carrierRMS = (harmonics.reduce(0.0) { $0 + 1 / Double($1 * $1) } / 2).squareRoot()
        let scale = amplitude(decibels: decibels) / carrierRMS

        let syllable = Int(0.18 * Double(sampleRate))
        let gap = Int(0.07 * Double(sampleRate))
        let pause = Int(0.40 * Double(sampleRate))

        var samples = [Double](repeating: 0, count: count)
        var position = Int(leadIn * Double(sampleRate))
        var syllablesInPhrase = 0
        while position < count {
            // Between 0 and 14 dB below the loudest: stressed and unstressed syllables.
            let gain = pow(10, -7 * (generator.next() + 1) / 20)
            for offset in 0..<syllable where position + offset < count {
                let time = Double(position + offset) / Double(sampleRate)
                let window = 0.5 - 0.5 * cos(2 * .pi * Double(offset) / Double(syllable))
                let carrier = harmonics.reduce(0.0) { $0 + sin(2 * .pi * 120 * Double($1) * time) / Double($1) }
                samples[position + offset] = carrier * scale * gain * window.squareRoot()
            }
            position += syllable + gap
            syllablesInPhrase += 1
            if syllablesInPhrase == 6 {
                syllablesInPhrase = 0
                position += pause
            }
        }
        return data(samples.map { $0 + generator.next() * roomPeak })
    }

    /// Splits audio the way the microphone delivers it: 100 ms at a time.
    static func chunks(_ audio: Data, seconds: Double = 0.1) -> [Data] {
        let size = Int(seconds * Double(sampleRate)) * MemoryLayout<Int16>.size
        return stride(from: 0, to: audio.count, by: size).map { audio.subdata(in: $0..<min($0 + size, audio.count)) }
    }
}

import AVFoundation
import Synchronization

/// Converts microphone buffers to mono signed 16-bit little-endian PCM at the streaming sample rate.
///
/// It goes by the format each buffer says it is in, and by no reading taken beforehand. A
/// device can change its rate between the moment it is asked and the moment it records, as a
/// Bluetooth microphone can, and audio converted from the wrong rate comes out slowed or sped
/// up. So the converter is built at the first buffer, from that buffer, and built again when
/// a later buffer is in another format.
///
/// Not thread-safe: use one converter from one thread, in practice the audio tap's.
public final class PCM16Converter {
    public let outputFormat: AVAudioFormat
    /// The format of the latest buffer; `nil` before the first.
    public private(set) var inputFormat: AVAudioFormat?
    /// How many times a buffer came in another format than the one before it.
    public private(set) var formatChanges = 0
    /// Buffers left out because their format cannot be converted.
    public private(set) var unconvertibleBuffers = 0
    private var converter: AVAudioConverter?

    public init?(sampleRate: Double) {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            return nil
        }
        self.outputFormat = outputFormat
    }

    /// Whether audio in this format can be converted. A Mac with no input device reports a
    /// format with no channels.
    public func canConvert(_ format: AVAudioFormat) -> Bool {
        makeConverter(from: format) != nil
    }

    private func makeConverter(from format: AVAudioFormat) -> AVAudioConverter? {
        guard format.sampleRate > 0, format.channelCount > 0 else { return nil }
        return AVAudioConverter(from: format, to: outputFormat)
    }

    /// Whether two formats hold their samples the same way: the same rate, channels and sample
    /// type. Two format objects that describe the same audio count as the same.
    public static func isSameAudio(_ one: AVAudioFormat, _ other: AVAudioFormat) -> Bool {
        let a = one.streamDescription.pointee
        let b = other.streamDescription.pointee
        return a.mSampleRate == b.mSampleRate
            && a.mChannelsPerFrame == b.mChannelsPerFrame
            && a.mFormatID == b.mFormatID
            && a.mFormatFlags == b.mFormatFlags
            && a.mBitsPerChannel == b.mBitsPerChannel
            && a.mBytesPerFrame == b.mBytesPerFrame
    }

    public func convert(_ buffer: AVAudioPCMBuffer) -> Data {
        guard buffer.frameLength > 0 else { return Data() }
        var pcm = Data()
        if let inputFormat {
            if !Self.isSameAudio(inputFormat, buffer.format) {
                // What the old converter still holds belongs before this buffer.
                pcm = finish()
                formatChanges += 1
                adopt(buffer.format)
            }
        } else {
            adopt(buffer.format)
        }
        guard let converter, let inputFormat else {
            unconvertibleBuffers += 1
            return pcm
        }
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return pcm
        }

        // The SDK types the converter's input block as `@Sendable`, and `AVAudioPCMBuffer` is not
        // Sendable. So the block gets a copy of the samples, which is, and builds its own buffer.
        let format = buffer.format
        let input = OneShot(PCMSamples(copying: buffer))
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            // The converter may ask again once it has used what it was given.
            guard let buffer = input.take()?.makeBuffer(format: format) else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return buffer
        }
        pcm.append(Self.data(in: output, status: status))
        return pcm
    }

    private func adopt(_ format: AVAudioFormat) {
        inputFormat = format
        converter = makeConverter(from: format)
    }

    /// Returns the audio the resampler is still holding. Call once, after the last `convert`.
    ///
    /// The resampler keeps up to about 80 ms of input back between calls; without this the end
    /// of a recording would be clipped.
    public func finish() -> Data {
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 16_384) else {
            return Data()
        }
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            inputStatus.pointee = .endOfStream
            return nil
        }
        converter.reset()
        return Self.data(in: output, status: status)
    }

    private static func data(in output: AVAudioPCMBuffer, status: AVAudioConverterOutputStatus) -> Data {
        guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData else {
            return Data()
        }
        return Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }
}

/// Counts the buffers of one recording against the clock, so the log can say whether they
/// came at the rate they claimed. Audio labelled with the wrong rate has the right number of
/// frames in each buffer and the wrong number of buffers per second.
public struct BufferTally: Sendable, Equatable {
    public private(set) var buffers = 0
    public private(set) var frames = 0
    private var framesAfterTheFirst = 0
    private var first: ContinuousClock.Instant?
    private var last: ContinuousClock.Instant?

    public init() {}

    public mutating func add(frames count: Int, at instant: ContinuousClock.Instant) {
        if first == nil {
            first = instant
        } else {
            framesAfterTheFirst += count
        }
        last = instant
        buffers += 1
        frames += count
    }

    /// From the arrival of the first buffer to that of the last.
    public var span: Duration {
        guard let first, let last else { return .zero }
        return last - first
    }

    /// Frames per second by the clock: those that arrived after the first buffer, over the
    /// time since it. `nil` until two buffers have arrived at different times.
    public var measuredFramesPerSecond: Int? {
        let seconds = Double(span.components.seconds) + Double(span.components.attoseconds) / 1e18
        guard buffers > 1, seconds > 0 else { return nil }
        return Int((Double(framesAfterTheFirst) / seconds).rounded())
    }
}

/// The samples of one `AVAudioPCMBuffer` as plain bytes, which can cross into a `@Sendable` closure.
struct PCMSamples: Sendable {
    let frameLength: AVAudioFrameCount
    /// One entry per buffer in the audio buffer list: one per channel, or a single one when the
    /// format is interleaved.
    let planes: [Data]

    init(copying buffer: AVAudioPCMBuffer) {
        frameLength = buffer.frameLength
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        planes = list.map { plane in
            guard let bytes = plane.mData else { return Data() }
            return Data(bytes: bytes, count: Int(plane.mDataByteSize))
        }
    }

    /// Returns a new buffer holding the samples, or `nil` when they do not fit `format`.
    func makeBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard frameLength > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        buffer.frameLength = frameLength
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard list.count == planes.count else { return nil }
        for (plane, bytes) in zip(list, planes) {
            guard let target = plane.mData else { return nil }
            let count = min(bytes.count, Int(plane.mDataByteSize))
            bytes.copyBytes(to: target.assumingMemoryBound(to: UInt8.self), count: count)
        }
        return buffer
    }
}

/// Hands its value out once, to whichever caller asks first.
private final class OneShot<Value: Sendable>: Sendable {
    private let value: Mutex<Value?>

    init(_ value: Value) {
        self.value = Mutex(value)
    }

    func take() -> Value? {
        value.withLock { held in
            let taken = held
            held = nil
            return taken
        }
    }
}

public enum AudioLevel {
    /// What digital silence is reported as, in dBFS.
    public static let silence = -100.0

    /// Loudness of 16-bit PCM: its RMS in decibels relative to full scale, from `silence` up to 0.
    public static func decibels(pcm16 data: Data) -> Double {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return silence }
        let sumOfSquares = data.withUnsafeBytes { raw -> Double in
            var sum = 0.0
            for index in 0..<sampleCount {
                let sample = Double(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)))
                sum += sample * sample
            }
            return sum
        }
        let rms = (sumOfSquares / Double(sampleCount)).squareRoot() / Double(Int16.max)
        guard rms > 0 else { return silence }
        return min(0, max(silence, 20 * log10(rms)))
    }
}

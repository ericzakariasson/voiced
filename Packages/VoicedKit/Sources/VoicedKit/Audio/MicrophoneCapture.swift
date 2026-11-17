import AVFoundation
import Synchronization

/// A slice of captured audio, already converted for streaming.
public struct AudioChunk: Sendable, Equatable {
    /// Mono signed 16-bit little-endian PCM at 16 kHz.
    public var pcm: Data

    public init(pcm: Data) {
        self.pcm = pcm
    }
}

public enum AudioCaptureError: Error, Equatable, LocalizedError, Sendable {
    case noInputDevice
    case engineFailed(description: String)

    public var errorDescription: String? {
        switch self {
        case .noInputDevice:
            "No microphone is available."
        case let .engineFailed(description):
            "Could not start recording: \(description)"
        }
    }
}

@MainActor
public protocol AudioCapturing: AnyObject {
    /// Starts recording and returns at once, without waiting for the audio engine.
    ///
    /// The stream ends when `stop()` is called, and throws if recording could not start.
    func start() -> AsyncThrowingStream<AudioChunk, any Error>
    func stop()
}

/// An audio engine as `MicrophoneCapture` drives it. Its methods are called on the capture queue,
/// one at a time, and never on the main thread.
protocol CaptureEngine: AnyObject {
    /// Finds the input device and its format, which is the first thing `start` does, and stops
    /// there: nothing is recorded and the device is not started.
    func findInput() throws
    /// Starts recording. `onAudio` gets mono 16-bit PCM on an audio thread until `stop()` returns.
    func start(onAudio: @escaping @Sendable (Data) -> Void) throws
    /// Stops recording and returns the audio that was still held back.
    func stop() -> Data
}

/// Records the default input device.
///
/// Starting an audio engine can take hundreds of milliseconds, longer with a Bluetooth microphone.
/// The hotkey's event tap lives on the main run loop, so anything slow there holds up every key
/// press in every app. The engine is therefore started and stopped on a queue of its own.
@MainActor
public final class MicrophoneCapture: AudioCapturing {
    /// One queue for every recording, so an engine has stopped before the next one starts.
    private static let queue = DispatchSerialQueue(label: "com.ericzakariasson.Voiced.capture", qos: .userInitiated)

    private let makeEngine: @Sendable () -> any CaptureEngine
    private var recording: Recording?

    public convenience init(sampleRate: Double) {
        self.init(makeEngine: { AVAudioCaptureEngine(sampleRate: sampleRate) })
    }

    init(makeEngine: @escaping @Sendable () -> any CaptureEngine) {
        self.makeEngine = makeEngine
    }

    public func start() -> AsyncThrowingStream<AudioChunk, any Error> {
        stop()
        let (stream, continuation) = AsyncThrowingStream<AudioChunk, any Error>.makeStream()
        let recording = Recording(queue: Self.queue, makeEngine: makeEngine, continuation: continuation)
        self.recording = recording
        recording.start()
        return stream
    }

    public func stop() {
        recording?.stop()
        recording = nil
    }

    /// Finds the input device ahead of a hold, so that the hold's own start does not have to
    /// wait for it, and reports whether the device was running before and after.
    ///
    /// Finding the input is the first thing a start does. It once took two seconds of a start
    /// that otherwise takes 90 ms: the first start of that process, after the screen had been
    /// locked. The next one found it in 38 ms. This does that part and nothing more: no tap is
    /// installed and no engine is started, so the microphone is meant to stay off and the orange
    /// dot dark. `make microphone-check` measures that, and every preparation logs the device's
    /// state before and after.
    ///
    /// It does nothing at all, not even look at the device, unless the Microphone has been
    /// granted, and it leaves alone an input it might disturb: see `MicrophonePreparation.run`.
    ///
    /// It takes its turn on the capture queue, so a hold that begins meanwhile waits for it
    /// rather than doing the same work twice.
    public func prepare(
        after reason: MicrophonePreparation.Reason,
        authorization: @escaping @Sendable () -> MicrophoneAuthorization = MicrophoneAuthorization.current,
        status: @escaping @Sendable () -> InputDeviceStatus? = InputDeviceStatus.current
    ) async -> MicrophonePreparation {
        let makeEngine = makeEngine
        return await withCheckedContinuation { continuation in
            Self.queue.async {
                let preparation = MicrophonePreparation.run(
                    after: reason,
                    authorization: authorization,
                    status: status,
                    findInput: { try makeEngine().findInput() }
                )
                continuation.resume(returning: preparation)
            }
        }
    }
}

/// One recording. It owns the engine and touches it only on the capture queue, which is this
/// actor's executor.
private actor Recording {
    private let queue: DispatchSerialQueue
    private let makeEngine: @Sendable () -> any CaptureEngine
    private let continuation: AsyncThrowingStream<AudioChunk, any Error>.Continuation
    /// Set the moment `stop()` is called, so a start that has not had its turn yet is skipped.
    private let stopRequested = Atomic<Bool>(false)
    /// When the hotkey asked for this recording, to tell a wait for the queue from a slow engine.
    private let requested = ContinuousClock.now
    private var engine: (any CaptureEngine)?

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    init(
        queue: DispatchSerialQueue,
        makeEngine: @escaping @Sendable () -> any CaptureEngine,
        continuation: AsyncThrowingStream<AudioChunk, any Error>.Continuation
    ) {
        self.queue = queue
        self.makeEngine = makeEngine
        self.continuation = continuation
    }

    // `queue.async` rather than a task per call: the queue runs these in the order they were made.
    nonisolated func start() {
        queue.async {
            self.assumeIsolated { $0.startEngine() }
        }
    }

    nonisolated func stop() {
        stopRequested.store(true, ordering: .relaxed)
        queue.async {
            self.assumeIsolated { $0.stopEngine() }
        }
    }

    private func startEngine() {
        guard !stopRequested.load(ordering: .relaxed) else {
            VoicedLog.capture.notice("start skipped: the hotkey was released before the engine's turn came")
            return
        }
        let engine = makeEngine()
        let continuation = continuation
        let began = ContinuousClock.now
        let queued = Int((began - requested) / .milliseconds(1))
        do {
            try engine.start { pcm in
                Self.emit(pcm, to: continuation)
            }
            self.engine = engine
            VoicedLog.capture.notice("engine started in \(VoicedLog.milliseconds(since: began)) ms, after \(queued) ms waiting for the capture queue")
        } catch {
            VoicedLog.capture.error("engine failed to start after \(VoicedLog.milliseconds(since: began)) ms: \(VoicedLog.describe(error), privacy: .public)")
            continuation.finish(throwing: error)
        }
    }

    private func stopEngine() {
        if let engine {
            self.engine = nil
            let tail = engine.stop()
            VoicedLog.capture.notice("engine stopped, converter tail bytes=\(tail.count)")
            Self.emit(tail, to: continuation)
        }
        continuation.finish()
    }

    private static func emit(_ pcm: Data, to continuation: AsyncThrowingStream<AudioChunk, any Error>.Continuation) {
        guard !pcm.isEmpty else { return }
        continuation.yield(AudioChunk(pcm: pcm))
    }
}

/// Records the default input device with `AVAudioEngine`.
final class AVAudioCaptureEngine: CaptureEngine {
    private let sampleRate: Double
    private var engine: AVAudioEngine?
    private var tapState: TapState?

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// A fresh engine each time picks up whichever input device is current. This is where a
    /// first start once spent two seconds, and it is all that `findInput` does.
    private func inputOfNewEngine() throws -> (engine: AVAudioEngine, input: AVAudioInputNode, format: AVAudioFormat, converter: PCM16Converter) {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        VoicedLog.capture.notice("input format: sampleRate=\(Int(format.sampleRate)) channels=\(format.channelCount)")
        // The reading only says whether there is an input at all. The converter goes by the
        // buffers themselves, which may not come in the format read here.
        guard let converter = PCM16Converter(sampleRate: sampleRate), converter.canConvert(format) else {
            throw AudioCaptureError.noInputDevice
        }
        return (engine, input, format, converter)
    }

    func findInput() throws {
        // The engine is let go again: one that is kept across sleep or a change of device goes stale.
        _ = try inputOfNewEngine()
    }

    func start(onAudio: @escaping @Sendable (Data) -> Void) throws {
        let began = ContinuousClock.now
        let (engine, input, format, converter) = try inputOfNewEngine()
        let inputFound = ContinuousClock.now

        let tapState = TapState(converter: converter, read: format, onAudio: onAudio, began: began)
        // 100 ms is the smallest buffer a tap supports, and matches the streaming chunk size.
        // This call is deprecated in macOS 27, but the SDK exposes its throwing replacement to
        // Swift only as the underscored `__installTap(onBus:bufferSize:format:error:block:)`.
        //
        // No format is given: the tap then takes whichever format the input has when it is
        // installed. A format of our own that the device has moved away from since it was read
        // can be refused with an exception that Swift cannot catch.
        let bufferSize = AVAudioFrameCount(format.sampleRate / 10)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { buffer, _ in
            tapState.convert(buffer)
        }

        engine.prepare()
        let prepared = ContinuousClock.now
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioCaptureError.engineFailed(description: error.localizedDescription)
        }
        // Which part of a slow start was slow: finding the input device, or the device itself
        // beginning to record. Only the first can be done before the hotkey goes down.
        func milliseconds(_ duration: Duration) -> Int { Int(duration / .milliseconds(1)) }
        VoicedLog.capture.notice("""
            start stages: input found in \(milliseconds(inputFound - began)) ms, \
            tap and prepare \(milliseconds(prepared - inputFound)) ms, \
            device started in \(milliseconds(ContinuousClock.now - prepared)) ms; \
            device now: \(InputDeviceStatus.current()?.logDescription ?? "none", privacy: .public)
            """)

        self.engine = engine
        self.tapState = tapState
    }

    func stop() -> Data {
        guard let engine, let tapState else { return Data() }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.tapState = nil
        tapState.logTally()
        return tapState.converter.finish()
    }

    /// The converter is touched from the tap's serial callback, and once more from `stop()` after
    /// the tap has been removed.
    private final class TapState: @unchecked Sendable {
        let converter: PCM16Converter
        /// The format read before the start, kept only to say in the log when the buffers differ.
        private let read: AVAudioFormat
        private let onAudio: @Sendable (Data) -> Void
        private let began: ContinuousClock.Instant
        private var tally = BufferTally()
        /// A device that keeps changing its format must not fill the log.
        private static let mostChangesLogged = 3

        init(converter: PCM16Converter, read: AVAudioFormat, onAudio: @escaping @Sendable (Data) -> Void, began: ContinuousClock.Instant) {
            self.converter = converter
            self.read = read
            self.onAudio = onAudio
            self.began = began
        }

        func convert(_ buffer: AVAudioPCMBuffer) {
            let format = buffer.format
            let previous = converter.inputFormat
            let changesBefore = converter.formatChanges
            let pcm = converter.convert(buffer)

            if tally.buffers == 0 {
                VoicedLog.capture.notice("first buffer \(VoicedLog.milliseconds(since: self.began)) ms after the start began: frames=\(buffer.frameLength) sampleRate=\(Int(format.sampleRate)) channels=\(format.channelCount)")
                if !PCM16Converter.isSameAudio(read, format) {
                    VoicedLog.capture.notice("the first buffer is not in the format read before the start: read sampleRate=\(Int(self.read.sampleRate)) channels=\(self.read.channelCount), buffer sampleRate=\(Int(format.sampleRate)) channels=\(format.channelCount); converting from the buffer's")
                }
            } else if converter.formatChanges != changesBefore, converter.formatChanges <= Self.mostChangesLogged, let previous {
                VoicedLog.capture.notice("input format changed after buffers=\(self.tally.buffers): sampleRate=\(Int(previous.sampleRate)) channels=\(previous.channelCount) -> sampleRate=\(Int(format.sampleRate)) channels=\(format.channelCount); converter rebuilt")
            }
            tally.add(frames: Int(buffer.frameLength), at: .now)

            guard !pcm.isEmpty else { return }
            onAudio(pcm)
        }

        /// One line when the recording stops, to check the rate the buffers claimed against
        /// the clock. Call once the tap has been removed.
        func logTally() {
            let format = converter.inputFormat
            let measured = tally.measuredFramesPerSecond.map(String.init) ?? "-"
            VoicedLog.capture.notice("""
                buffers=\(self.tally.buffers) frames=\(self.tally.frames) \
                claiming sampleRate=\(Int(format?.sampleRate ?? 0)) channels=\(format?.channelCount ?? 0); \
                measured \(measured, privacy: .public) frames per second over \(Int(self.tally.span / .milliseconds(1))) ms; \
                format changes=\(self.converter.formatChanges) unconvertible buffers=\(self.converter.unconvertibleBuffers)
                """)
        }
    }
}

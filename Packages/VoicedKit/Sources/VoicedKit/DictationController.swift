import Foundation
import Observation

private let log = VoicedLog.dictation

/// Runs the dictation loop: record while the hotkey is held, transcribe, clean up, insert.
@MainActor
@Observable
public final class DictationController {
    public enum Phase: Equatable, Sendable {
        case idle
        /// The hotkey is down but has not been held for `minimumHold` yet. The microphone has
        /// already been asked to start so as little speech as possible is lost, but nothing is
        /// shown and xAI is not contacted: if this turns out to be a tap, or the hotkey typing a
        /// character, it ends without a trace.
        case starting
        /// The hold is confirmed and the dictation is under way. Whether audio is arriving yet
        /// is told by `microphone`.
        case recording
        case transcribing
        case cleaning
        case inserting
    }

    /// What the microphone has delivered to the hold in progress.
    public enum Microphone: Equatable, Sendable {
        /// No hold is being recorded.
        case off
        /// Asked to start, and no audio has arrived yet. Every hold begins like this, and a
        /// usual one leaves it before there is anything to show.
        case starting
        /// Still no audio after `microphoneStartAllowance`: what is said now is not recorded.
        case startingSlowly
        /// Audio is arriving, and has been since this moment.
        case listening(since: Date)
    }

    public struct Notice: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case warning
            case error
        }

        public var kind: Kind
        public var message: String
        /// Distinguishes a repeated notice from the one before it.
        public var sequence: Int
    }

    @MainActor
    public struct Dependencies {
        public var apiKey: () -> String?
        public var makeCapture: () -> any AudioCapturing
        public var makeTranscription: (_ apiKey: String) -> any TranscriptionSession
        public var makeCleaner: (_ apiKey: String) -> any TextCleaning
        /// Whether a dictation is cleaned up before it is inserted. Asked once per dictation,
        /// when the hotkey goes down, so a hold ends by the choice it began with.
        public var cleanupIsOn: () -> Bool
        public var inserter: any TextInserting
        /// Holds shorter than this are treated as an accidental tap, or as the hotkey being used
        /// to type a character, and leave no trace.
        public var minimumHold: Duration
        /// Recording continues this long after release, so the last word is not clipped by a
        /// finger that lets go a moment early or by audio still in the capture buffer.
        public var releaseTail: Duration
        /// How long after the hotkey goes down the first audio may take before the microphone
        /// counts as slow to start. A usual start delivers in 200 to 300 ms, so a usual hold
        /// never gets there.
        public var microphoneStartAllowance: Duration
        public var clock: any DictationClock

        public init(
            apiKey: @escaping () -> String?,
            makeCapture: @escaping () -> any AudioCapturing,
            makeTranscription: @escaping (_ apiKey: String) -> any TranscriptionSession,
            makeCleaner: @escaping (_ apiKey: String) -> any TextCleaning,
            cleanupIsOn: @escaping () -> Bool = { true },
            inserter: any TextInserting,
            minimumHold: Duration = DictationController.defaultMinimumHold,
            releaseTail: Duration = .milliseconds(150),
            microphoneStartAllowance: Duration = .milliseconds(500),
            clock: any DictationClock = SystemDictationClock()
        ) {
            self.apiKey = apiKey
            self.makeCapture = makeCapture
            self.makeTranscription = makeTranscription
            self.makeCleaner = makeCleaner
            self.cleanupIsOn = cleanupIsOn
            self.inserter = inserter
            self.minimumHold = minimumHold
            self.releaseTail = releaseTail
            self.microphoneStartAllowance = microphoneStartAllowance
            self.clock = clock
        }
    }

    public static let defaultMinimumHold: Duration = .milliseconds(250)

    public private(set) var phase: Phase = .idle
    /// Microphone loudness on a 0...1 scale while recording, fitted to the speaker by `LevelMeter`.
    public private(set) var level: Float = 0
    /// Whether the hold in progress is being recorded yet. The microphone is asked to start the
    /// moment the hotkey goes down, and audio follows when the audio engine is running.
    public private(set) var microphone: Microphone = .off
    /// A confirmed hold whose audio is arriving: the one state that may be shown as listening.
    public var isListening: Bool {
        guard phase == .recording, case .listening = microphone else { return false }
        return true
    }
    /// The words are with the cleanup pass, or are back from it and being inserted: the one
    /// stretch that may be shown as polishing. A dictation whose cleanup is switched off never
    /// gets there: it is shown as transcribing until its text has landed.
    public var isPolishing: Bool {
        switch phase {
        case .cleaning: true
        case .inserting: current?.cleansUp ?? false
        case .idle, .starting, .recording, .transcribing: false
        }
    }
    public private(set) var notice: Notice?

    private struct Dictation {
        var id: Int
        var apiKey: String
        /// Whether cleanup was on when the hotkey went down. A change made later is for the
        /// next dictation.
        var cleansUp: Bool
        var capture: any AudioCapturing
        var session: any TranscriptionSession
        var pump: Task<Void, Never>
        var startedAt: ContinuousClock.Instant
        /// Waits out `minimumHold`, then confirms the hold.
        var confirmation: Task<Void, Never>?
        /// Opens the transcription connection once the hold is confirmed.
        var connection: Task<Void, Never>?
        /// A microphone failure that arrived before the hold was confirmed.
        var captureError: (any Error)?
        /// Waits out `microphoneStartAllowance`, then says the microphone is slow to start.
        var slowStart: Task<Void, Never>?
        /// How long after the hotkey went down the first audio arrived; `nil` until it does.
        var firstAudioAfter: Duration?
        /// The hold was shown as waiting for the microphone, so its beginning may be missing.
        var microphoneWasSlow = false
    }

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private let clock: any DictationClock
    @ObservationIgnored private var current: Dictation?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var nextDictationID = 0
    @ObservationIgnored private var noticeSequence = 0

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
        clock = dependencies.clock
    }

    /// The hotkey went down.
    public func begin() {
        guard phase == .idle else {
            log.notice("hotkey down ignored: the previous dictation is still \(String(describing: self.phase), privacy: .public)")
            return
        }
        guard let apiKey = dependencies.apiKey(), !apiKey.isEmpty else {
            log.notice("hotkey down, but no API key is saved")
            post(.error, "Add your Grok API Key in Settings to start dictating.")
            return
        }

        let startedAt = clock.now
        let capture = dependencies.makeCapture()
        // Returns at once. The audio engine starts in the background, so a slow start cannot hold
        // up the main thread and with it the hotkey's event tap; a failure arrives through the stream.
        let audio = capture.start()

        let session = dependencies.makeTranscription(apiKey)
        nextDictationID += 1
        let id = nextDictationID
        // One task forwards the audio, so chunks reach the session in the order they were captured.
        // The session queues them until it is connected, which waits for the hold to be confirmed.
        let pump = Task { [weak self] in
            var chunks = 0
            var bytes = 0
            var meter = LevelMeter()
            do {
                for try await chunk in audio {
                    if chunks == 0 {
                        self?.audioBegan(dictationID: id)
                    }
                    chunks += 1
                    bytes += chunk.pcm.count
                    self?.level = meter.level(forPCM16: chunk.pcm)
                    await session.send(audio: chunk.pcm)
                }
                log.notice("#\(id): capture ended: chunks=\(chunks) bytes=\(bytes)")
                Self.logLevels(meter.statistics, dictationID: id)
            } catch {
                log.error("#\(id): capture failed after chunks=\(chunks): \(VoicedLog.describe(error), privacy: .public)")
                self?.captureFailed(dictationID: id, error: error)
            }
        }

        current = Dictation(
            id: id,
            apiKey: apiKey,
            cleansUp: dependencies.cleanupIsOn(),
            capture: capture,
            session: session,
            pump: pump,
            startedAt: startedAt
        )
        level = 0
        microphone = .starting
        phase = .starting
        log.notice("#\(id): hotkey down, microphone requested")

        // Both waits end at a moment fixed now, not after however long their tasks take to start.
        let clock = clock
        let slowStart = startedAt + dependencies.microphoneStartAllowance
        current?.slowStart = Task { [weak self] in
            try? await clock.sleep(until: slowStart)
            guard !Task.isCancelled else { return }
            self?.microphoneIsSlow(dictationID: id)
        }

        let minimumHold = dependencies.minimumHold
        if minimumHold <= .zero {
            confirmHold(dictationID: id)
        } else {
            let confirmation = startedAt + minimumHold
            current?.confirmation = Task { [weak self] in
                try? await clock.sleep(until: confirmation)
                guard !Task.isCancelled else { return }
                self?.confirmHold(dictationID: id)
            }
        }
    }

    /// The first audio of the hold has arrived: from here on, what is said is recorded.
    private func audioBegan(dictationID: Int) {
        guard let dictation = current, dictation.id == dictationID else { return }
        let waited = clock.now - dictation.startedAt
        current?.firstAudioAfter = waited
        dictation.slowStart?.cancel()
        log.notice("#\(dictationID): first audio \(Self.milliseconds(waited)) ms after hotkey down")
        // After release the pill has moved on, and audio from the release tail changes nothing on it.
        guard phase == .starting || phase == .recording else { return }
        microphone = .listening(since: Date())
    }

    /// The microphone has had `microphoneStartAllowance` and delivered nothing.
    private func microphoneIsSlow(dictationID: Int) {
        guard let dictation = current, dictation.id == dictationID, dictation.firstAudioAfter == nil else { return }
        guard phase == .starting || phase == .recording else { return }
        log.notice("#\(dictationID): no audio \(self.milliseconds(since: dictation.startedAt)) ms after hotkey down: showing that the microphone is still starting")
        current?.microphoneWasSlow = true
        microphone = .startingSlowly
    }

    /// The hotkey has been held long enough to mean dictation: show it and connect to xAI.
    private func confirmHold(dictationID: Int) {
        guard phase == .starting, let dictation = current, dictation.id == dictationID else { return }
        let held = milliseconds(since: dictation.startedAt)
        if let error = dictation.captureError {
            log.error("#\(dictationID): hold confirmed after \(held) ms, but the microphone had failed: \(VoicedLog.describe(error), privacy: .public)")
            dictation.capture.stop()
            discard(dictation)
            post(.error, Self.describe(error))
            return
        }
        log.notice("#\(dictationID): hold confirmed after \(held) ms, connecting to xAI")
        let session = dictation.session
        current?.connection = Task { await session.start() }
        notice = nil
        phase = .recording
    }

    /// The hotkey was released.
    public func end() {
        if phase == .starting, let dictation = current {
            guard clock.now - dictation.startedAt >= dependencies.minimumHold else {
                // A quick tap. Nothing was shown and nothing was sent.
                log.notice("#\(dictation.id): hotkey up after \(self.milliseconds(since: dictation.startedAt)) ms, under the minimum hold: dropped silently")
                dictation.capture.stop()
                discard(dictation)
                return
            }
            // Held long enough, though the confirmation has not had its turn yet.
            confirmHold(dictationID: dictation.id)
        }
        guard phase == .recording, let dictation = current else { return }
        level = 0
        let held = milliseconds(since: dictation.startedAt)
        if microphone == .startingSlowly {
            // The pill was still saying so. There is no audio, and none worth waiting for.
            log.notice("#\(dictation.id): hotkey up after \(held) ms, before any audio had arrived: nothing was recorded")
            dictation.capture.stop()
            discard(dictation)
            post(.warning, Self.nothingRecordedWarning)
            return
        }
        microphone = .off
        let firstAudio = dictation.firstAudioAfter.map { "\(Self.milliseconds($0)) ms" } ?? "none yet"
        log.notice("#\(dictation.id): hotkey up after \(held) ms, first audio after \(firstAudio, privacy: .public)")

        phase = .transcribing
        let released = clock.now
        processingTask = Task { [weak self] in
            await self?.process(dictation, released: released)
        }
    }

    /// Drops the dictation in progress, whether it is still recording or already being processed.
    /// Says nothing: this is also what happens when the hotkey turns out to be typing a character.
    public func cancel() {
        guard let dictation = current else { return }
        log.notice("#\(dictation.id): cancelled while \(String(describing: self.phase), privacy: .public)")
        dictation.capture.stop()
        discard(dictation)
    }

    /// The microphone could not start, which is only known some time after `begin()` returned.
    private func captureFailed(dictationID: Int, error: any Error) {
        guard let dictation = current, dictation.id == dictationID else { return }
        guard phase != .starting else {
            // Not yet known to be a dictation. Keep quiet unless the hold is confirmed.
            log.notice("#\(dictationID): microphone failure held back until the hold is confirmed")
            current?.captureError = error
            return
        }
        dictation.capture.stop()
        discard(dictation)
        post(.error, Self.describe(error))
    }

    private func discard(_ dictation: Dictation) {
        current = nil
        processingTask?.cancel()
        processingTask = nil
        dictation.confirmation?.cancel()
        dictation.slowStart?.cancel()
        dictation.connection?.cancel()
        dictation.pump.cancel()
        Task { await dictation.session.cancel() }
        level = 0
        microphone = .off
        phase = .idle
    }

    private func isCurrent(_ dictation: Dictation) -> Bool {
        current?.id == dictation.id
    }

    /// Returns once the capture's stream has ended and everything in it has been dealt with.
    /// For tests, which must know that a microphone failure has arrived before they go on.
    func captureEnded() async {
        await current?.pump.value
    }

    private func process(_ dictation: Dictation, released: ContinuousClock.Instant) async {
        defer {
            if isCurrent(dictation) {
                current = nil
                processingTask = nil
                phase = .idle
            }
        }

        let id = dictation.id
        try? await clock.sleep(until: released + dependencies.releaseTail)
        guard isCurrent(dictation) else { return }
        dictation.capture.stop()
        await dictation.pump.value
        // `dictation` is as it was at release; what the capture delivered since is in `current`.
        guard let recorded = current, recorded.id == id else { return }
        guard recorded.firstAudioAfter != nil else {
            // Released before the audio engine delivered anything. Sending xAI nothing would
            // end in "Didn't catch that", which blames the speaker.
            log.notice("#\(id): the microphone delivered no audio before it was stopped: nothing to transcribe")
            dictation.connection?.cancel()
            await dictation.session.cancel()
            post(.warning, Self.nothingRecordedWarning)
            return
        }
        let slowStart = recorded.microphoneWasSlow ? Self.slowStartWarning : nil
        await dictation.connection?.value

        let transcription: TranscriptionResult
        do {
            transcription = try await dictation.session.finish()
        } catch {
            if isCurrent(dictation) {
                log.error("#\(id): transcription failed \(self.milliseconds(since: released)) ms after release: \(VoicedLog.describe(error), privacy: .public)")
                post(.error, Self.describe(error))
            }
            return
        }
        guard isCurrent(dictation) else { return }

        let raw = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        log.notice("#\(id): transcript received \(self.milliseconds(since: released)) ms after release: chars=\(raw.count) complete=\(transcription.isComplete)")
        guard !raw.isEmpty else {
            post(.warning, slowStart == nil ? "Didn't catch that. Hold the hotkey while you speak." : Self.nothingRecordedWarning)
            return
        }

        var text = raw
        var warning = transcription.isComplete ? nil : "xAI was slow to finish; the end of the dictation may be missing."
        if dictation.cleansUp {
            phase = .cleaning
            do {
                let cleaned = try await dependencies.makeCleaner(dictation.apiKey).clean(raw)
                if let accepted = CleanupGuard.accept(cleaned: cleaned, raw: raw) {
                    log.notice("#\(id): cleanup accepted: chars \(raw.count) -> \(accepted.count)")
                    text = accepted
                } else {
                    log.error("#\(id): cleanup result rejected as implausible: chars \(raw.count) -> \(cleaned.count); using the raw transcript")
                    warning = "Cleanup gave an unexpected result. Inserted the raw transcript."
                }
            } catch {
                log.error("#\(id): cleanup failed: \(VoicedLog.describe(error), privacy: .public); using the raw transcript")
                warning = "Cleanup failed, inserted the raw transcript. \(Self.describe(error))"
            }
            guard isCurrent(dictation) else { return }
        } else {
            // No cleaner is made and nothing is sent: the transcript goes in as it came.
            log.notice("#\(id): cleanup skipped, the setting was off when the hotkey went down: chars=\(raw.count)")
        }

        phase = .inserting
        do {
            try await dependencies.inserter.insert(text)
        } catch {
            log.error("#\(id): insertion failed: \(VoicedLog.describe(error), privacy: .public)")
            post(.error, Self.describe(error))
            return
        }
        log.notice("#\(id): inserted chars=\(text.count), done \(self.milliseconds(since: released)) ms after release")
        // The pill has room for one warning. Words that were never recorded come first: nothing
        // else on screen shows them missing, while a failed cleanup shows in the text itself.
        if let warning = slowStart ?? warning {
            post(.warning, warning)
        }
    }

    private static let slowStartWarning = "The microphone was slow to start. The beginning of the dictation may be missing."
    private static let nothingRecordedWarning = "The microphone did not start in time. Nothing was recorded."

    /// Whole milliseconds from `start` to now, by the loop's own clock.
    private func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Self.milliseconds(clock.now - start)
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration / .milliseconds(1))
    }

    /// One line of numbers per dictation, so the meter can be checked against a real microphone.
    private static func logLevels(_ levels: LevelMeter.Statistics, dictationID id: Int) {
        func decibels(_ value: Double) -> String { String(format: "%.1f", value) }
        func shown(_ value: Float) -> String { String(format: "%.2f", value) }
        log.notice("""
            #\(id): levels: chunks=\(levels.chunks) audible=\(levels.audibleChunks) \
            silent=\(levels.silentChunks) leading silent=\(levels.leadingSilentChunks) \
            (\(Int((levels.leadingSilentSeconds * 1000).rounded())) ms); \
            input dBFS min=\(decibels(levels.quietestInput), privacy: .public) \
            median=\(decibels(levels.medianInput), privacy: .public) \
            p90=\(decibels(levels.ninetiethPercentileInput), privacy: .public) \
            max=\(decibels(levels.loudestInput), privacy: .public); \
            meter floor=\(decibels(levels.floor), privacy: .public) \
            ceiling=\(decibels(levels.ceiling), privacy: .public); \
            shown median=\(shown(levels.medianShown), privacy: .public) \
            p90=\(shown(levels.ninetiethPercentileShown), privacy: .public) \
            max=\(shown(levels.highestShown), privacy: .public)
            """)
    }

    private func post(_ kind: Notice.Kind, _ message: String) {
        // The message is not logged: it can carry text from the server.
        log.notice("notice shown: \(kind == .error ? "error" : "warning", privacy: .public)")
        noticeSequence += 1
        notice = Notice(kind: kind, message: message, sequence: noticeSequence)
    }

    private static func describe(_ error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

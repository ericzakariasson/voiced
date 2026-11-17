import Foundation
import Synchronization
import Testing
@testable import VoicedKit

/// A clock that stands still until the test moves it, so a test decides when a hold is confirmed,
/// when the release tail is over and when the microphone counts as slow, instead of racing a real
/// clock on a busy machine.
private final class ManualClock: DictationClock {
    private struct Sleeper: Sendable {
        var id: Int
        var deadline: ContinuousClock.Instant
        var continuation: CheckedContinuation<Void, any Error>
    }

    private struct State: Sendable {
        var now = ContinuousClock.now
        var sleepers: [Sleeper] = []
        var lastID = 0
    }

    private let state = Mutex(State())

    var now: ContinuousClock.Instant {
        state.withLock { $0.now }
    }

    func advance(by duration: Duration) {
        let due: [Sleeper] = state.withLock { state in
            state.now += duration
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }

    func sleep(until deadline: ContinuousClock.Instant) async throws {
        let id: Int = state.withLock { state in
            state.lastID += 1
            return state.lastID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let outcome: Result<Void, any Error>? = state.withLock { state in
                    // Checked under the lock: a cancellation is either seen here, or finds the sleeper below.
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if deadline <= state.now { return .success(()) }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return nil
                }
                if let outcome {
                    continuation.resume(with: outcome)
                }
            }
        } onCancel: {
            let cancelled: Sleeper? = state.withLock { state in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return state.sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }
}

@MainActor
private final class FakeCapture: AudioCapturing {
    /// What the microphone hears once it has started.
    var chunks = [AudioChunk(pcm: Data([7, 7]))]
    /// Like the real microphone, a failed start is reported through the stream, after `start()` returned.
    var startError: (any Error)?
    /// When set, the stream stays silent until `engineStarts()` or `engineFails(_:)`: a slow engine.
    var holdsStart = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var continuation: AsyncThrowingStream<AudioChunk, any Error>.Continuation?

    func start() -> AsyncThrowingStream<AudioChunk, any Error> {
        startCount += 1
        let (stream, continuation) = AsyncThrowingStream<AudioChunk, any Error>.makeStream()
        self.continuation = continuation
        if !holdsStart {
            engineStarts()
        }
        return stream
    }

    func engineStarts() {
        if let startError {
            continuation?.finish(throwing: startError)
        } else {
            chunks.forEach { continuation?.yield($0) }
        }
    }

    func engineFails(_ error: any Error) {
        continuation?.finish(throwing: error)
    }

    func stop() {
        stopCount += 1
        continuation?.finish()
    }
}

private actor FakeSession: TranscriptionSession {
    enum Reply {
        case result(TranscriptionResult)
        case failure(XAIError)
    }

    private let reply: Reply
    private(set) var started = false
    private(set) var received = Data()
    private(set) var finishCount = 0
    private(set) var cancelled = false
    private var cancelWaiter: CheckedContinuation<Void, Never>?
    private let holdsFinishUntilCancelled: Bool

    init(_ reply: Reply, holdsFinishUntilCancelled: Bool = false) {
        self.reply = reply
        self.holdsFinishUntilCancelled = holdsFinishUntilCancelled
    }

    func start() {
        started = true
    }

    func send(audio: Data) {
        received.append(audio)
    }

    func finish() async throws -> TranscriptionResult {
        finishCount += 1
        if holdsFinishUntilCancelled {
            if !cancelled {
                await withCheckedContinuation { cancelWaiter = $0 }
            }
            throw CancellationError()
        }
        switch reply {
        case let .result(result): return result
        case let .failure(error): throw error
        }
    }

    func cancel() {
        cancelled = true
        cancelWaiter?.resume()
        cancelWaiter = nil
    }
}

private struct FakeCleaner: TextCleaning {
    enum Reply {
        case text(String)
        case failure(XAIError)
    }

    var reply: Reply
    var onClean: @Sendable (String) async -> Void = { _ in }

    func clean(_ transcript: String) async throws -> String {
        await onClean(transcript)
        switch reply {
        case let .text(text): return text
        case let .failure(error): throw error
        }
    }
}

@MainActor
private final class FakeInserter: TextInserting {
    private(set) var inserted: [String] = []
    var error: (any Error)?
    var onInsert: () -> Void = {}

    func insert(_ text: String) async throws {
        onInsert()
        if let error { throw error }
        inserted.append(text)
    }
}

@MainActor
private final class Harness {
    var apiKey: String? = "test-key"
    let capture = FakeCapture()
    let inserter = FakeInserter()
    var session: FakeSession
    var cleaner: FakeCleaner
    /// The Cleanup setting, as it stands when the controller asks.
    var cleanupIsOn = true
    var minimumHold: Duration = .zero
    var releaseTail: Duration = .zero
    var microphoneStartAllowance: Duration = .milliseconds(500)
    /// Time passes only when a test says so.
    let clock = ManualClock()
    private(set) var keysUsed: [String] = []
    private(set) var cleanersMade = 0
    private(set) var phases: [DictationController.Phase] = []
    /// Whether the controller said it was polishing, each time a phase was recorded.
    private(set) var polishing: [Bool] = []

    private(set) lazy var controller = DictationController(dependencies: .init(
        apiKey: { [unowned self] in apiKey },
        makeCapture: { [unowned self] in capture },
        makeTranscription: { [unowned self] key in
            keysUsed.append(key)
            return session
        },
        makeCleaner: { [unowned self] key in
            keysUsed.append(key)
            cleanersMade += 1
            return cleaner
        },
        cleanupIsOn: { [unowned self] in cleanupIsOn },
        inserter: inserter,
        minimumHold: minimumHold,
        releaseTail: releaseTail,
        microphoneStartAllowance: microphoneStartAllowance,
        clock: clock
    ))

    init(
        transcript: FakeSession.Reply = .result(.init(text: "um hello world", isComplete: true)),
        cleaned: FakeCleaner.Reply = .text("Hello, world.")
    ) {
        session = FakeSession(transcript)
        cleaner = FakeCleaner(reply: cleaned)
        cleaner.onClean = { [weak self] _ in await self?.recordPhase() }
        inserter.onInsert = { [weak self] in self?.recordPhase() }
    }

    func recordPhase() {
        phases.append(controller.phase)
        polishing.append(controller.isPolishing)
    }

    func dictate() async throws {
        controller.begin()
        controller.end()
        try await waitUntil { self.controller.phase == .idle }
    }
}

@MainActor
@Suite struct DictationControllerTests {
    @Test func recordsTranscribesCleansAndInserts() async throws {
        let harness = Harness()
        harness.capture.chunks = [
            AudioChunk(pcm: Data([1, 2])),
            AudioChunk(pcm: Data([3, 4])),
        ]

        harness.controller.begin()
        #expect(harness.controller.phase == .recording)
        #expect(harness.capture.startCount == 1)

        harness.controller.end()
        #expect(harness.controller.phase == .transcribing)

        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.capture.stopCount == 1)
        #expect(harness.inserter.inserted == ["Hello, world."])
        #expect(harness.phases == [.cleaning, .inserting])
        #expect(harness.polishing == [true, true])
        #expect(!harness.controller.isPolishing)
        #expect(harness.controller.notice == nil)
        #expect(harness.keysUsed == ["test-key", "test-key"])
        #expect(await harness.session.started)
        #expect(await harness.session.received == Data([1, 2, 3, 4]))
        #expect(await harness.session.finishCount == 1)
    }

    @Test func reportsTheMicrophoneLevelWhileRecording() async throws {
        let harness = Harness()
        // A quiet room, then someone speaking: the meter needs the first to judge the second.
        harness.capture.chunks = [
            AudioChunk(pcm: SyntheticAudio.noise(decibels: -62, seconds: 0.1)),
            AudioChunk(pcm: SyntheticAudio.noise(decibels: -28, seconds: 0.1)),
        ]

        harness.controller.begin()

        try await waitUntil { harness.controller.level > 0.5 }
        harness.controller.cancel()
        #expect(harness.controller.level == 0)
    }

    @Test func theRecordingClockStartsWhenAudioArrivesAndNotBefore() async throws {
        let harness = Harness()
        harness.capture.holdsStart = true
        #expect(harness.controller.microphone == .off)

        harness.controller.begin()
        // Asked to start, and nothing has arrived: there is no time to count from yet.
        #expect(harness.controller.microphone == .starting)

        let audioBegan = Date()
        harness.capture.engineStarts()
        try await waitUntil { harness.controller.microphone != .starting }
        guard case let .listening(since) = harness.controller.microphone else {
            Issue.record("Expected to be listening, but the microphone is \(harness.controller.microphone)")
            return
        }
        #expect(since >= audioBegan && since <= Date())

        harness.controller.end()
        #expect(harness.controller.microphone == .off)
        try await waitUntil { harness.controller.phase == .idle }

        harness.capture.holdsStart = false
        harness.controller.begin()
        try await waitUntil { harness.controller.microphone != .starting }
        harness.controller.cancel()
        #expect(harness.controller.microphone == .off)
    }

    @Test func aMicrophoneThatTakesTwoSecondsIsShownAsStartingUntilItsAudioArrives() async throws {
        let harness = Harness()
        harness.capture.holdsStart = true
        harness.capture.chunks = [AudioChunk(pcm: Data([1, 2]))]

        harness.controller.begin()
        #expect(harness.controller.phase == .recording)
        #expect(harness.controller.microphone == .starting)

        // Half a second in, still nothing: the hold is shown as waiting for the microphone.
        harness.clock.advance(by: .milliseconds(500))
        try await waitUntil { harness.controller.microphone == .startingSlowly }

        // The engine comes up two seconds after the hotkey went down. Until its audio arrives
        // the hold is not shown as listening.
        harness.clock.advance(by: .milliseconds(1500))
        #expect(harness.controller.microphone == .startingSlowly)
        harness.capture.engineStarts()
        try await waitUntil { harness.controller.microphone != .startingSlowly }
        guard case .listening = harness.controller.microphone else {
            Issue.record("Expected to be listening, but the microphone is \(harness.controller.microphone)")
            return
        }

        // What was said after that is transcribed, with a warning about what was said before.
        harness.controller.end()
        try await waitUntil { harness.controller.phase == .idle }
        #expect(await harness.session.received == Data([1, 2]))
        #expect(harness.inserter.inserted == ["Hello, world."])
        #expect(harness.controller.notice?.kind == .warning)
        #expect(harness.controller.notice?.message == "The microphone was slow to start. The beginning of the dictation may be missing.")
    }

    @Test func aMicrophoneThatStartsAsUsualIsNeverShownAsStarting() async throws {
        let harness = Harness()

        harness.controller.begin()
        try await waitUntil { harness.controller.microphone != .starting }
        guard case .listening = harness.controller.microphone else {
            Issue.record("Expected to be listening, but the microphone is \(harness.controller.microphone)")
            return
        }

        // Long after the allowance has run out, it is still simply listening.
        harness.clock.advance(by: .seconds(2))
        harness.controller.end()
        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.inserter.inserted == ["Hello, world."])
        // The warning follows any hold that was shown as starting, so there was none.
        #expect(harness.controller.notice == nil)
    }

    @Test func releasingWhileTheMicrophoneIsStillStartingSaysThatNothingWasRecorded() async throws {
        let harness = Harness()
        harness.capture.holdsStart = true

        harness.controller.begin()
        harness.clock.advance(by: .seconds(1))
        try await waitUntil { harness.controller.microphone == .startingSlowly }
        harness.controller.end()

        #expect(harness.controller.phase == .idle)
        #expect(harness.controller.microphone == .off)
        #expect(harness.capture.stopCount == 1)
        #expect(harness.controller.notice?.kind == .warning)
        #expect(harness.controller.notice?.message == "The microphone did not start in time. Nothing was recorded.")
        try await waitUntil { await harness.session.cancelled }
        #expect(await harness.session.finishCount == 0)
        #expect(harness.inserter.inserted.isEmpty)
    }

    @Test func aHoldThatEndsBeforeAnyAudioArrivesIsNotSentForTranscription() async throws {
        let harness = Harness()
        // A short hold: released inside the allowance, with the engine not yet delivering.
        harness.capture.chunks = []

        harness.controller.begin()
        harness.controller.end()
        #expect(harness.controller.phase == .transcribing)

        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.controller.notice?.kind == .warning)
        #expect(harness.controller.notice?.message == "The microphone did not start in time. Nothing was recorded.")
        #expect(await harness.session.cancelled)
        #expect(await harness.session.finishCount == 0)
        #expect(harness.inserter.inserted.isEmpty)
    }

    @Test func silenceAfterASlowStartIsBlamedOnTheMicrophoneNotTheSpeaker() async throws {
        let harness = Harness(transcript: .result(.init(text: "", isComplete: true)))
        harness.capture.holdsStart = true

        harness.controller.begin()
        harness.clock.advance(by: .seconds(2))
        try await waitUntil { harness.controller.microphone == .startingSlowly }
        harness.capture.engineStarts()
        try await waitUntil { harness.controller.microphone != .startingSlowly }
        harness.controller.end()

        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.controller.notice?.message == "The microphone did not start in time. Nothing was recorded.")
        #expect(harness.inserter.inserted.isEmpty)
    }

    @Test func aSlowStartIsTheWarningShownWhenCleanupFailsToo() async throws {
        let harness = Harness(cleaned: .failure(.rateLimited))
        harness.capture.holdsStart = true

        harness.controller.begin()
        harness.clock.advance(by: .seconds(2))
        try await waitUntil { harness.controller.microphone == .startingSlowly }
        harness.capture.engineStarts()
        try await waitUntil { harness.controller.microphone != .startingSlowly }
        harness.controller.end()

        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.inserter.inserted == ["um hello world"])
        #expect(harness.controller.notice?.message == "The microphone was slow to start. The beginning of the dictation may be missing.")
    }

    @Test func aTapWhileTheMicrophoneIsSlowStillLeavesNoTrace() async throws {
        let harness = Harness()
        harness.minimumHold = .seconds(60)
        harness.capture.holdsStart = true

        harness.controller.begin()
        harness.clock.advance(by: .seconds(1))
        try await waitUntil { harness.controller.microphone == .startingSlowly }
        // Not yet known to be a dictation, so nothing is said about it.
        #expect(harness.controller.phase == .starting)
        harness.controller.cancel()

        #expect(harness.controller.phase == .idle)
        #expect(harness.controller.microphone == .off)
        #expect(harness.controller.notice == nil)
    }

    @Test func keepsRecordingBrieflyAfterRelease() async throws {
        let harness = Harness()
        harness.releaseTail = .milliseconds(80)
        harness.capture.chunks = [AudioChunk(pcm: Data([1, 2]))]

        harness.controller.begin()
        harness.controller.end()
        // The key is up and what was captured has gone on, yet the microphone stays on for the tail.
        try await waitUntil { await harness.session.received == Data([1, 2]) }
        #expect(harness.capture.stopCount == 0)

        harness.clock.advance(by: .milliseconds(80))
        try await waitUntil { harness.capture.stopCount == 1 }
        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.inserter.inserted == ["Hello, world."])
    }

    @Test func withoutAKeyItAsksForOneAndRecordsNothing() {
        let harness = Harness()
        harness.apiKey = nil

        harness.controller.begin()

        #expect(harness.controller.phase == .idle)
        #expect(harness.capture.startCount == 0)
        #expect(harness.controller.notice?.kind == .error)
        #expect(harness.controller.notice?.message.contains("Grok API Key") == true)
    }

    @Test func aMicrophoneFailureIsReported() async throws {
        let harness = Harness()
        harness.capture.startError = AudioCaptureError.noInputDevice

        harness.controller.begin()

        try await waitUntil { harness.controller.notice != nil }
        #expect(harness.controller.phase == .idle)
        #expect(harness.controller.notice?.kind == .error)
        #expect(harness.controller.notice?.message == "No microphone is available.")
        #expect(harness.capture.stopCount == 1)
        try await waitUntil { await harness.session.cancelled }
        #expect(harness.inserter.inserted.isEmpty)
    }

    @Test func beginDoesNotWaitForTheMicrophoneToStart() async throws {
        let harness = Harness()
        harness.capture.holdsStart = true
        harness.capture.chunks = [AudioChunk(pcm: Data([1, 2]))]

        harness.controller.begin()

        // The engine has not started, yet the hold is already under way.
        #expect(harness.controller.phase == .recording)
        #expect(harness.capture.startCount == 1)

        harness.capture.engineStarts()
        harness.controller.end()
        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.inserter.inserted == ["Hello, world."])
        #expect(await harness.session.received == Data([1, 2]))
    }

    @Test func aMicrophoneThatFailsAfterTheKeyWasReleasedIsReported() async throws {
        let harness = Harness()
        harness.capture.holdsStart = true
        harness.releaseTail = .milliseconds(200)

        harness.controller.begin()
        harness.controller.end()
        #expect(harness.controller.phase == .transcribing)
        harness.capture.engineFails(AudioCaptureError.engineFailed(description: "device busy"))

        try await waitUntil { harness.controller.notice != nil }
        #expect(harness.controller.phase == .idle)
        #expect(harness.controller.notice?.message == "Could not start recording: device busy")
        #expect(await harness.session.finishCount == 0)
        #expect(harness.inserter.inserted.isEmpty)

        // The failure leaves nothing behind: the next dictation works.
        harness.capture.holdsStart = false
        harness.session = FakeSession(.result(.init(text: "second try", isComplete: true)))
        harness.cleaner.reply = .text("Second try.")
        harness.controller.begin()
        harness.controller.end()
        harness.clock.advance(by: .milliseconds(200))
        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.inserter.inserted == ["Second try."])
    }

    @Test func aQuickTapIsDiscarded() async throws {
        let harness = Harness()
        harness.minimumHold = .seconds(60)

        harness.controller.begin()
        #expect(harness.controller.phase == .starting)
        harness.controller.end()

        #expect(harness.controller.phase == .idle)
        #expect(harness.capture.stopCount == 1)
        try await waitUntil { await harness.session.cancelled }
        #expect(await !harness.session.started)
        #expect(await harness.session.finishCount == 0)
        #expect(harness.inserter.inserted.isEmpty)
        #expect(harness.controller.notice == nil)
    }

    @Test func aHoldShowsNothingAndContactsNobodyUntilItOutlastsAQuickTap() async throws {
        let harness = Harness()
        harness.minimumHold = .milliseconds(200)

        harness.controller.begin()

        // The microphone is asked to start at the first moment, so as little speech as possible is lost.
        #expect(harness.controller.phase == .starting)
        #expect(harness.capture.startCount == 1)
        #expect(await !harness.session.started)
        #expect(harness.controller.phase == .starting)

        harness.clock.advance(by: .milliseconds(200))
        try await waitUntil { harness.controller.phase == .recording }
        try await waitUntil { await harness.session.started }

        harness.controller.end()
        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.inserter.inserted == ["Hello, world."])
    }

    @Test func audioCapturedBeforeTheHoldIsConfirmedIsNotLost() async throws {
        let harness = Harness()
        harness.minimumHold = .seconds(1)
        harness.capture.chunks = [AudioChunk(pcm: Data([1, 2]))]

        // However long the audio takes to arrive, the hold is not confirmed until the test says
        // that the second has passed.
        harness.controller.begin()
        try await waitUntil { await harness.session.received == Data([1, 2]) }
        #expect(harness.controller.phase == .starting)

        harness.clock.advance(by: .seconds(1))
        try await waitUntil { harness.controller.phase == .recording }
        harness.controller.end()
        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.inserter.inserted == ["Hello, world."])
    }

    @Test func typingACharacterWithTheHotkeyLeavesNoTrace() async throws {
        let harness = Harness()
        harness.minimumHold = .seconds(60)
        harness.capture.chunks = [AudioChunk(pcm: Data([1, 2]))]

        // The hotkey goes down, then another key: the state machine cancels.
        harness.controller.begin()
        #expect(harness.controller.phase == .starting)
        harness.controller.cancel()

        #expect(harness.controller.phase == .idle)
        #expect(harness.controller.notice == nil)
        #expect(harness.capture.stopCount == 1)
        try await waitUntil { await harness.session.cancelled }
        #expect(await !harness.session.started)
        #expect(await harness.session.finishCount == 0)
        #expect(harness.inserter.inserted.isEmpty)
    }

    @Test func aNoticeOnScreenSurvivesATypedCharacter() {
        let harness = Harness()
        harness.minimumHold = .seconds(60)
        harness.apiKey = nil
        harness.controller.begin()
        let notice = harness.controller.notice
        #expect(notice != nil)

        harness.apiKey = "test-key"
        harness.controller.begin()
        harness.controller.cancel()

        #expect(harness.controller.notice == notice)
    }

    @Test func releasingAfterTheMinimumDictatesEvenIfTheConfirmationHasNotRunYet() async throws {
        let harness = Harness()
        harness.minimumHold = .milliseconds(20)

        harness.controller.begin()
        #expect(harness.controller.phase == .starting)
        // The minimum hold passes while the main actor is busy, so the confirmation cannot run.
        harness.clock.advance(by: .milliseconds(20))
        harness.controller.end()

        #expect(harness.controller.phase == .transcribing)
        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.inserter.inserted == ["Hello, world."])
        #expect(await harness.session.started)
    }

    @Test func aMicrophoneFailureDuringATapStaysQuiet() async throws {
        let harness = Harness()
        harness.minimumHold = .seconds(60)
        harness.capture.startError = AudioCaptureError.noInputDevice

        harness.controller.begin()
        await harness.controller.captureEnded()
        #expect(harness.controller.phase == .starting)
        #expect(harness.controller.notice == nil)

        harness.controller.end()
        #expect(harness.controller.phase == .idle)
        #expect(harness.controller.notice == nil)
    }

    @Test func aMicrophoneFailureBeforeTheHoldIsConfirmedIsReportedOnceItIs() async throws {
        let harness = Harness()
        harness.minimumHold = .milliseconds(100)
        harness.capture.startError = AudioCaptureError.noInputDevice

        harness.controller.begin()
        // The failure has arrived, and is held back while this could still be a tap.
        await harness.controller.captureEnded()
        #expect(harness.controller.phase == .starting)
        #expect(harness.controller.notice == nil)

        harness.clock.advance(by: .milliseconds(100))
        try await waitUntil { harness.controller.notice != nil }
        #expect(harness.controller.phase == .idle)
        #expect(harness.controller.notice?.message == "No microphone is available.")
        #expect(await !harness.session.started)
    }

    @Test func cancellingWhileRecordingInsertsNothing() async throws {
        let harness = Harness()

        harness.controller.begin()
        harness.controller.cancel()

        #expect(harness.controller.phase == .idle)
        #expect(harness.capture.stopCount == 1)
        try await waitUntil { await harness.session.cancelled }
        #expect(harness.inserter.inserted.isEmpty)
    }

    @Test func cancellingWhileTranscribingInsertsNothingAndAllowsANewDictation() async throws {
        let harness = Harness()
        harness.session = FakeSession(.result(.init(text: "ignored", isComplete: true)), holdsFinishUntilCancelled: true)

        harness.controller.begin()
        harness.controller.end()
        let stuckSession = harness.session
        try await waitUntil { await stuckSession.finishCount == 1 }
        harness.controller.cancel()
        #expect(harness.controller.phase == .idle)

        harness.session = FakeSession(.result(.init(text: "second try", isComplete: true)))
        harness.cleaner.reply = .text("Second try.")
        try await harness.dictate()

        #expect(harness.inserter.inserted == ["Second try."])
        #expect(harness.controller.notice == nil)
    }

    @Test func aFailedCleanupInsertsTheRawTranscriptWithAWarning() async throws {
        let harness = Harness(cleaned: .failure(.server(status: 400, message: "Unsupported reasoning effort")))

        try await harness.dictate()

        #expect(harness.inserter.inserted == ["um hello world"])
        #expect(harness.controller.notice?.kind == .warning)
        #expect(harness.controller.notice?.message.contains("inserted the raw transcript") == true)
        #expect(harness.controller.notice?.message.contains("Unsupported reasoning effort") == true)
    }

    @Test func anImplausibleCleanupInsertsTheRawTranscriptWithAWarning() async throws {
        let answer = String(repeating: "Here is a long answer to your question. ", count: 5)
        let harness = Harness(cleaned: .text(answer))

        try await harness.dictate()

        #expect(harness.inserter.inserted == ["um hello world"])
        #expect(harness.controller.notice?.kind == .warning)
    }

    @Test func withCleanupOffTheTranscriptIsInsertedAsItCameAndNoCleanerIsMade() async throws {
        // Nothing but the white space around it is taken off, as it is before a cleanup too.
        let harness = Harness(transcript: .result(.init(text: "  um hello world, i i mean hi \n", isComplete: true)))
        harness.cleanupIsOn = false

        try await harness.dictate()

        #expect(harness.inserter.inserted == ["um hello world, i i mean hi"])
        #expect(harness.cleanersMade == 0)
        // The key went to the transcription and nowhere else.
        #expect(harness.keysUsed == ["test-key"])
        #expect(harness.controller.notice == nil)
        #expect(await harness.session.finishCount == 1)
    }

    @Test func withCleanupOffADictationIsNeverShownAsPolishing() async throws {
        let harness = Harness()
        harness.cleanupIsOn = false

        harness.controller.begin()
        #expect(!harness.controller.isPolishing)
        harness.controller.end()
        #expect(harness.controller.phase == .transcribing)
        #expect(!harness.controller.isPolishing)

        try await waitUntil { harness.controller.phase == .idle }
        // The one phase recorded is the insertion: there was no cleaning to record.
        #expect(harness.phases == [.inserting])
        #expect(harness.polishing == [false])
        #expect(harness.inserter.inserted == ["um hello world"])
    }

    @Test func cleanupIsOnWhereNothingSaysOtherwise() async throws {
        let capture = FakeCapture()
        let inserter = FakeInserter()
        let session = FakeSession(.result(.init(text: "um hello world", isComplete: true)))
        // The dependencies as every caller that says nothing about cleanup makes them.
        let controller = DictationController(dependencies: .init(
            apiKey: { "test-key" },
            makeCapture: { capture },
            makeTranscription: { _ in session },
            makeCleaner: { _ in FakeCleaner(reply: .text("Hello, world.")) },
            inserter: inserter,
            minimumHold: .zero,
            releaseTail: .zero,
            clock: ManualClock()
        ))

        controller.begin()
        controller.end()
        try await waitUntil { controller.phase == .idle }

        #expect(inserter.inserted == ["Hello, world."])
    }

    @Test func aChangeToCleanupDuringAHoldAppliesFromTheNextHold() async throws {
        let harness = Harness()

        // Switched off while the hotkey is down: this hold began with cleanup on, and ends so.
        harness.controller.begin()
        harness.cleanupIsOn = false
        harness.controller.end()
        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.inserter.inserted == ["Hello, world."])
        #expect(harness.cleanersMade == 1)

        // The next hold begins with it off. Switching it back on before the transcript has
        // arrived changes nothing for this one either.
        harness.session = FakeSession(.result(.init(text: "second try", isComplete: true)))
        harness.cleaner.reply = .text("Second try.")
        harness.controller.begin()
        harness.controller.end()
        #expect(harness.controller.phase == .transcribing)
        harness.cleanupIsOn = true
        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.inserter.inserted == ["Hello, world.", "second try"])
        #expect(harness.cleanersMade == 1)

        // And the one after that is cleaned up again.
        harness.session = FakeSession(.result(.init(text: "third try", isComplete: true)))
        harness.cleaner.reply = .text("Third try.")
        try await harness.dictate()
        #expect(harness.inserter.inserted == ["Hello, world.", "second try", "Third try."])
        #expect(harness.cleanersMade == 2)
    }

    @Test func anIncompleteTranscriptWithCleanupOffIsInsertedAsItCameWithAWarning() async throws {
        let harness = Harness(transcript: .result(.init(text: "um hello world", isComplete: false)))
        harness.cleanupIsOn = false

        try await harness.dictate()

        #expect(harness.inserter.inserted == ["um hello world"])
        #expect(harness.cleanersMade == 0)
        #expect(harness.controller.notice?.kind == .warning)
        #expect(harness.controller.notice?.message.contains("may be missing") == true)
    }

    @Test func anIncompleteTranscriptIsInsertedWithAWarning() async throws {
        let harness = Harness(transcript: .result(.init(text: "um hello world", isComplete: false)))

        try await harness.dictate()

        #expect(harness.inserter.inserted == ["Hello, world."])
        #expect(harness.controller.notice?.kind == .warning)
        #expect(harness.controller.notice?.message.contains("may be missing") == true)
    }

    @Test func aTranscriptionFailureIsReportedAndNothingIsInserted() async throws {
        let harness = Harness(transcript: .failure(.invalidAPIKey))

        try await harness.dictate()

        #expect(harness.inserter.inserted.isEmpty)
        #expect(harness.controller.notice?.kind == .error)
        #expect(harness.controller.notice?.message == "The Grok API Key was rejected. Check it in Settings.")
        #expect(harness.phases.isEmpty)
    }

    @Test func silenceInsertsNothing() async throws {
        let harness = Harness(transcript: .result(.init(text: "  ", isComplete: true)))

        try await harness.dictate()

        #expect(harness.inserter.inserted.isEmpty)
        #expect(harness.controller.notice?.kind == .warning)
        #expect(harness.phases.isEmpty)
    }

    @Test func anInsertionFailureIsReported() async throws {
        let harness = Harness()
        harness.inserter.error = TextInsertionError.accessibilityNotGranted

        try await harness.dictate()

        #expect(harness.controller.notice?.kind == .error)
        #expect(harness.controller.notice?.message.contains("Accessibility") == true)
    }

    @Test func aSecondPressWhileProcessingIsIgnored() async throws {
        let harness = Harness()

        harness.controller.begin()
        harness.controller.end()
        harness.controller.begin()

        #expect(harness.controller.phase == .transcribing)
        #expect(harness.capture.startCount == 1)
        try await waitUntil { harness.controller.phase == .idle }
        #expect(harness.inserter.inserted == ["Hello, world."])
    }

    @Test func repeatedNoticesAreDistinguishable() {
        let harness = Harness()
        harness.apiKey = nil

        harness.controller.begin()
        let first = harness.controller.notice
        harness.controller.begin()

        #expect(harness.controller.notice != first)
        #expect(harness.controller.notice?.message == first?.message)
    }
}

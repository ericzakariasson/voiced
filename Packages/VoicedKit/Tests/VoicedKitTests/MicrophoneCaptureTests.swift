import Foundation
import Synchronization
import Testing
@testable import VoicedKit

/// What a test tells its stand-in engine to do, and what the engine saw.
private final class EngineScript: Sendable {
    struct Observed {
        var enginesMade = 0
        var inputsFound = 0
        var statusReads = 0
        var startsEntered = 0
        var startsFinished = 0
        var stops = 0
        var ranOnMainThread = false
        var onAudio: (@Sendable (Data) -> Void)?
    }

    let observed = Mutex(Observed())
    /// An engine that is slow to start waits here until the test signals.
    let gate = DispatchSemaphore(value: 0)
    let isSlowToStart: Bool
    /// Finding the input waits at the gate too: the two seconds a real first start once took.
    let isSlowToFindInput: Bool
    let hasNoInput: Bool
    let startError: AudioCaptureError?
    let tail: Data

    init(
        isSlowToStart: Bool = false, isSlowToFindInput: Bool = false, hasNoInput: Bool = false,
        startError: AudioCaptureError? = nil, tail: Data = Data()
    ) {
        self.isSlowToStart = isSlowToStart
        self.isSlowToFindInput = isSlowToFindInput
        self.hasNoInput = hasNoInput
        self.startError = startError
        self.tail = tail
    }

    var snapshot: Observed {
        observed.withLock { $0 }
    }

    func microphoneHears(_ pcm: Data) {
        observed.withLock { $0.onAudio }?(pcm)
    }

    /// Reports `status` as the input device's state, and counts how often it was asked.
    func reading(_ status: InputDeviceStatus?) -> @Sendable () -> InputDeviceStatus? {
        {
            self.observed.withLock { $0.statusReads += 1 }
            return status
        }
    }
}

private final class FakeEngine: CaptureEngine {
    private let script: EngineScript

    init(_ script: EngineScript) {
        self.script = script
        script.observed.withLock { $0.enginesMade += 1 }
    }

    func findInput() throws {
        script.observed.withLock {
            $0.inputsFound += 1
            $0.ranOnMainThread = $0.ranOnMainThread || Thread.isMainThread
        }
        if script.isSlowToFindInput {
            script.gate.wait()
        }
        if script.hasNoInput {
            throw AudioCaptureError.noInputDevice
        }
    }

    func start(onAudio: @escaping @Sendable (Data) -> Void) throws {
        script.observed.withLock {
            $0.startsEntered += 1
            $0.ranOnMainThread = $0.ranOnMainThread || Thread.isMainThread
        }
        if script.isSlowToStart {
            script.gate.wait()
        }
        if let error = script.startError {
            throw error
        }
        script.observed.withLock {
            $0.onAudio = onAudio
            $0.startsFinished += 1
        }
    }

    func stop() -> Data {
        script.observed.withLock {
            $0.stops += 1
            $0.ranOnMainThread = $0.ranOnMainThread || Thread.isMainThread
            $0.onAudio = nil
        }
        return script.tail
    }
}

private func collect(_ audio: AsyncThrowingStream<AudioChunk, any Error>) async throws -> [Data] {
    var received: [Data] = []
    for try await chunk in audio {
        received.append(chunk.pcm)
    }
    return received
}

/// The input device as a preparation may find it: nobody using it, or this process recording from it.
private let idle = InputDeviceStatus(id: 7, isRunningSomewhere: false, isRunningHere: false, transport: .builtIn, sampleRate: 48_000)
private let recording = InputDeviceStatus(id: 7, isRunningSomewhere: true, isRunningHere: true, transport: .builtIn, sampleRate: 48_000)

/// `MicrophoneCapture` with a stand-in for `AVAudioEngine`. The tests run on the main actor, as the
/// app's hotkey handling does; they share the capture queue, so they run one at a time.
@MainActor
@Suite(.serialized) struct MicrophoneCaptureTests {
    @Test func startReturnsWhileTheEngineIsStillStarting() async throws {
        let script = EngineScript(isSlowToStart: true, tail: Data([9, 9]))
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })

        // If this waited for the engine it would never return: the engine waits for the signal below.
        let audio = capture.start()

        try await waitUntil { script.snapshot.startsEntered == 1 }
        #expect(script.snapshot.startsFinished == 0)

        script.gate.signal()
        try await waitUntil { script.snapshot.startsFinished == 1 }
        script.microphoneHears(Data([1, 0, 2, 0]))
        capture.stop()

        // What the microphone heard, then the audio the converter was still holding.
        #expect(try await collect(audio) == [Data([1, 0, 2, 0]), Data([9, 9])])
        #expect(script.snapshot.stops == 1)
        #expect(!script.snapshot.ranOnMainThread)
    }

    @Test func releasingBeforeTheEngineHasStartedStillStopsIt() async throws {
        let script = EngineScript(isSlowToStart: true)
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })

        let audio = capture.start()
        try await waitUntil { script.snapshot.startsEntered == 1 }
        capture.stop()
        script.gate.signal()

        #expect(try await collect(audio).isEmpty)
        #expect(script.snapshot.startsFinished == 1)
        #expect(script.snapshot.stops == 1)
    }

    @Test func aStartStillWaitingItsTurnWhenStopArrivesIsSkipped() async throws {
        let slow = EngineScript(isSlowToStart: true)
        let first = MicrophoneCapture(makeEngine: { FakeEngine(slow) })
        let firstAudio = first.start()
        try await waitUntil { slow.snapshot.startsEntered == 1 }

        // A second press and release while the first engine is still starting.
        let script = EngineScript()
        let second = MicrophoneCapture(makeEngine: { FakeEngine(script) })
        let secondAudio = second.start()
        second.stop()

        first.stop()
        slow.gate.signal()

        #expect(try await collect(firstAudio).isEmpty)
        #expect(try await collect(secondAudio).isEmpty)
        #expect(slow.snapshot.stops == 1)
        #expect(script.snapshot.enginesMade == 0)
    }

    @Test func aFailedStartEndsTheStreamWithTheError() async throws {
        let script = EngineScript(startError: .engineFailed(description: "device busy"))
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })

        let audio = capture.start()

        await #expect(throws: AudioCaptureError.engineFailed(description: "device busy")) {
            _ = try await collect(audio)
        }
        capture.stop()
        #expect(script.snapshot.stops == 0)
    }

    @Test func preparingFindsTheInputAndStartsNothing() async throws {
        let script = EngineScript()
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })

        let preparation = await capture.prepare(after: .screenUnlocked, authorization: { .granted }, status: { idle })

        #expect(preparation.outcome == .found)
        #expect(preparation.before == idle)
        #expect(preparation.after == idle)
        #expect(!preparation.startedInput)
        #expect(script.snapshot.inputsFound == 1)
        #expect(script.snapshot.startsEntered == 0)
        #expect(script.snapshot.stops == 0)
        #expect(!script.snapshot.ranOnMainThread)
    }

    @Test(arguments: [MicrophoneAuthorization.notDetermined, .denied])
    func withoutTheGrantAPreparationTouchesNothingOfAudio(authorization: MicrophoneAuthorization) async throws {
        let script = EngineScript()
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })

        let preparation = await capture.prepare(after: .launch, authorization: { authorization }, status: script.reading(idle))

        // No engine was made, which is what would raise the system's prompt, and the device's
        // state was not even read.
        #expect(preparation.outcome == .skipped(.microphoneNotGranted))
        #expect(script.snapshot.enginesMade == 0)
        #expect(script.snapshot.inputsFound == 0)
        #expect(script.snapshot.statusReads == 0)
        #expect(preparation.before == nil)
        #expect(preparation.after == nil)
        #expect(!preparation.startedInput)
    }

    @Test(arguments: [InputDeviceStatus.Transport.bluetooth, .aggregate, .virtual, .other(0x61697270)])
    func anInputThatMightBeDisturbedIsNotLookedFor(transport: InputDeviceStatus.Transport) async throws {
        let script = EngineScript()
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })
        let headset = InputDeviceStatus(id: 9, isRunningSomewhere: false, isRunningHere: false, transport: transport, sampleRate: 24_000)

        let preparation = await capture.prepare(after: .screenUnlocked, authorization: { .granted }, status: { headset })

        #expect(preparation.outcome == .skipped(.inputKind(transport)))
        #expect(script.snapshot.enginesMade == 0)
        #expect(!preparation.startedInput)
    }

    @Test func aHoldThatBeginsDuringAPreparationWaitsItsTurnAndThenRecords() async throws {
        let slow = EngineScript(isSlowToFindInput: true)
        let preparing = MicrophoneCapture(makeEngine: { FakeEngine(slow) })
        let preparation = Task {
            await preparing.prepare(after: .systemWoke, authorization: { .granted }, status: { idle })
        }
        try await waitUntil { slow.snapshot.inputsFound == 1 }

        // The hotkey goes down while the input is still being found.
        let script = EngineScript()
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })
        let audio = capture.start()
        #expect(script.snapshot.enginesMade == 0)

        slow.gate.signal()
        #expect(await preparation.value.outcome == .found)
        try await waitUntil { script.snapshot.startsFinished == 1 }
        script.microphoneHears(Data([3, 0]))
        capture.stop()

        #expect(try await collect(audio) == [Data([3, 0])])
        #expect(slow.snapshot.startsEntered == 0)
    }

    @Test func preparingWhileRecordingIsSkipped() async throws {
        let script = EngineScript()
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })

        let preparation = await capture.prepare(after: .inputDeviceChanged, authorization: { .granted }, status: { recording })

        #expect(preparation.outcome == .skipped(.recording))
        #expect(!preparation.startedInput)
        #expect(script.snapshot.enginesMade == 0)
    }

    @Test func aPreparationThatLeavesTheInputRunningIsReported() async throws {
        let script = EngineScript()
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })

        // Idle when the preparation begins, running in this process once the input has been found.
        let preparation = await capture.prepare(after: .launch, authorization: { .granted }) {
            script.snapshot.inputsFound == 0 ? idle : recording
        }

        #expect(preparation.outcome == .found)
        #expect(preparation.startedInput)
    }

    @Test func aMicrophoneAnotherAppIsUsingIsLeftToThatApp() async throws {
        let script = EngineScript()
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })
        // Someone is on a call.
        let elsewhere = InputDeviceStatus(id: 7, isRunningSomewhere: true, isRunningHere: false, transport: .builtIn, sampleRate: 48_000)

        let preparation = await capture.prepare(after: .screenUnlocked, authorization: { .granted }, status: { elsewhere })

        #expect(preparation.outcome == .skipped(.inUseElsewhere))
        #expect(!preparation.startedInput)
        #expect(script.snapshot.enginesMade == 0)
    }

    @Test func anInputRunningAfterwardsCountsAgainstThePreparationEvenIfThisProcessIsNotNamed() async throws {
        let script = EngineScript()
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })
        // What a Mac reported while Voiced itself was recording: running, but not "here".
        let runningUnattributed = InputDeviceStatus(id: 7, isRunningSomewhere: true, isRunningHere: false, transport: .builtIn, sampleRate: 48_000)

        // Idle when the preparation begins, running once the input has been found. Whether the
        // preparation started it or a call began in the same moment cannot be told, so it counts.
        let preparation = await capture.prepare(after: .launch, authorization: { .granted }) {
            script.snapshot.inputsFound == 0 ? idle : runningUnattributed
        }

        #expect(preparation.outcome == .found)
        #expect(preparation.startedInput)
    }

    @Test func withNoInputDeviceThereIsNothingToLookFor() async throws {
        let script = EngineScript()
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })

        let preparation = await capture.prepare(after: .launch, authorization: { .granted }, status: { nil })

        #expect(preparation.outcome == .skipped(.noInputDevice))
        #expect(script.snapshot.enginesMade == 0)
    }

    @Test func aLookupTheAudioSystemRefusesIsReportedAndStartsNothing() async throws {
        let script = EngineScript(hasNoInput: true)
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })

        let preparation = await capture.prepare(after: .launch, authorization: { .granted }, status: { idle })

        #expect(preparation.outcome == .failed("capture.noInputDevice"))
        #expect(!preparation.startedInput)
        #expect(script.snapshot.startsEntered == 0)
    }

    @Test func aPreparationIsDescribedInNumbersAndStates() {
        let found = MicrophonePreparation(outcome: .found, duration: .milliseconds(1890), before: idle, after: idle)
        #expect(found.logDescription == """
            input found in 1890 ms; \
            device before: id=7 transport=builtIn sampleRate=48000 running here=0 somewhere=0; \
            after: id=7 transport=builtIn sampleRate=48000 running here=0 somewhere=0
            """)

        let notGranted = MicrophonePreparation(outcome: .skipped(.microphoneNotGranted), duration: .zero, before: nil, after: nil)
        #expect(notGranted.logDescription == "skipped, microphone not granted in 0 ms; device before: none; after: none")

        let headset = MicrophonePreparation(outcome: .skipped(.inputKind(.bluetooth)), duration: .zero, before: nil, after: nil)
        #expect(headset.logDescription.hasPrefix("skipped, bluetooth input in 0 ms"))
    }

    @Test func startingAgainStopsThePreviousRecording() async throws {
        let script = EngineScript()
        let capture = MicrophoneCapture(makeEngine: { FakeEngine(script) })

        let firstAudio = capture.start()
        try await waitUntil { script.snapshot.startsFinished == 1 }
        let secondAudio = capture.start()
        #expect(try await collect(firstAudio).isEmpty)
        try await waitUntil { script.snapshot.startsFinished == 2 }
        script.microphoneHears(Data([5, 0]))
        capture.stop()

        #expect(try await collect(secondAudio) == [Data([5, 0])])
        #expect(script.snapshot.stops == 2)
    }
}

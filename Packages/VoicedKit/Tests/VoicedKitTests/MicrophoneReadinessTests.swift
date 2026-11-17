import Foundation
import Testing
@testable import VoicedKit

/// `MicrophoneReadiness` with stand-ins for everything that touches audio, which record whether
/// they were touched.
@MainActor
private final class Scene {
    var authorization = MicrophoneAuthorization.granted
    /// The reason of every preparation that was begun.
    private(set) var prepared: [MicrophonePreparation.Reason] = []
    private(set) var inputWatches = 0
    private(set) var inputChanged: (@MainActor () -> Void)?
    /// When set, a preparation does not finish until `finishPreparation()`.
    var holdsPreparations = false
    var nextPreparation = MicrophonePreparation(outcome: .found, duration: .milliseconds(40), before: nil, after: nil)
    private var held: [CheckedContinuation<Void, Never>] = []

    // Weak, because a preparation can still be finishing when its test is over.
    private(set) lazy var readiness = MicrophoneReadiness(
        authorization: { [weak self] in self?.authorization ?? .denied },
        prepare: { [weak self] reason in
            await self?.prepare(after: reason) ?? MicrophonePreparation(outcome: .skipped(.noInputDevice), duration: .zero, before: nil, after: nil)
        },
        watchInputDevice: { [weak self] onChange in
            self?.inputWatches += 1
            self?.inputChanged = onChange
        }
    )

    private func prepare(after reason: MicrophonePreparation.Reason) async -> MicrophonePreparation {
        prepared.append(reason)
        if holdsPreparations {
            await withCheckedContinuation { held.append($0) }
        }
        return nextPreparation
    }

    /// Whether `readiness` has taken in a preparation that lasted `milliseconds`.
    func hasRecordedPreparation(lasting milliseconds: Int) -> Bool {
        readiness.history.summary.contains("a preparation that took \(milliseconds) ms")
    }

    var preparationsHeld: Int { held.count }

    func finishPreparation() {
        held.removeFirst().resume()
    }

    /// Everything that can happen to the Mac.
    func everythingHappens() {
        readiness.permissionsChanged()
        readiness.record(.systemWillSleep)
        readiness.record(.systemDidWake)
        readiness.record(.displaysDidSleep)
        readiness.record(.displaysDidWake)
        readiness.record(.screenLocked)
        readiness.record(.screenUnlocked)
        readiness.record(.inputDeviceChanged)
        readiness.holdBegan()
    }
}

@MainActor
@Suite struct MicrophoneReadinessTests {
    @Test(arguments: [MicrophoneAuthorization.notDetermined, .denied])
    func withoutTheGrantNothingOfAudioIsTouchedWhateverHappens(authorization: MicrophoneAuthorization) async throws {
        let scene = Scene()
        scene.authorization = authorization

        scene.readiness.start()
        scene.everythingHappens()

        // A preparation is begun in the same turn as the event that calls for it, so there is
        // nothing to wait for: none was begun, and the input device is not being watched.
        #expect(scene.prepared.isEmpty)
        #expect(scene.inputWatches == 0)
    }

    @Test func aFreshInstallPreparesOnlyOnceTheMicrophoneIsGranted() async throws {
        let scene = Scene()
        scene.authorization = .notDetermined
        scene.readiness.start()
        scene.readiness.record(.screenUnlocked)
        #expect(scene.prepared.isEmpty)

        // The setup window's Allow button, and the system's prompt answered.
        scene.authorization = .granted
        scene.readiness.permissionsChanged()

        #expect(scene.inputWatches == 1)
        try await waitUntil { scene.prepared == [.microphoneGranted] }

        // Another permission changing later is not a reason to prepare again.
        scene.readiness.permissionsChanged()
        #expect(scene.prepared == [.microphoneGranted])
    }

    @Test func aMicrophoneTakenAwayAgainStopsThePreparations() async throws {
        let scene = Scene()
        scene.readiness.start()
        try await waitUntil { scene.prepared == [.launch] }

        scene.authorization = .denied
        scene.readiness.permissionsChanged()
        scene.readiness.record(.systemDidWake)
        scene.readiness.record(.screenUnlocked)

        #expect(scene.prepared == [.launch])
    }

    @Test func launchWakeUnlockAndAChangeOfInputEachPrepare() async throws {
        let scene = Scene()

        scene.readiness.start()
        try await waitUntil { scene.prepared == [.launch] }
        #expect(scene.inputWatches == 1)

        scene.readiness.record(.systemDidWake)
        try await waitUntil { scene.prepared == [.launch, .systemWoke] }
        scene.readiness.record(.displaysDidWake)
        try await waitUntil { scene.prepared == [.launch, .systemWoke, .displaysWoke] }
        scene.readiness.record(.screenUnlocked)
        try await waitUntil { scene.prepared == [.launch, .systemWoke, .displaysWoke, .screenUnlocked] }

        // The system says the default input device changed.
        let inputChanged = try #require(scene.inputChanged)
        inputChanged()
        try await waitUntil { scene.prepared.last == .inputDeviceChanged }
        #expect(scene.prepared.count == 5)
        #expect(scene.inputWatches == 1)
    }

    @Test func goingToSleepAndLockingDoNotPrepare() async throws {
        let scene = Scene()
        scene.readiness.start()
        try await waitUntil { scene.prepared == [.launch] }

        scene.readiness.record(.systemWillSleep)
        scene.readiness.record(.displaysDidSleep)
        scene.readiness.record(.screenLocked)
        scene.readiness.holdBegan()

        #expect(scene.prepared == [.launch])
    }

    @Test func preparationsRunOneAtATimeAndTheLatestReasonGetsItsTurn() async throws {
        let scene = Scene()
        scene.holdsPreparations = true

        scene.readiness.start()
        try await waitUntil { scene.preparationsHeld == 1 }
        // The Mac wakes and is unlocked while the first is still finding the input.
        scene.readiness.record(.systemDidWake)
        scene.readiness.record(.displaysDidWake)
        scene.readiness.record(.screenUnlocked)
        #expect(scene.prepared == [.launch])

        scene.finishPreparation()
        try await waitUntil { scene.preparationsHeld == 1 && scene.prepared.count == 2 }
        #expect(scene.prepared == [.launch, .screenUnlocked])

        // The second one ends with nothing waiting, so there is no third.
        scene.nextPreparation.duration = .milliseconds(41)
        scene.finishPreparation()
        try await waitUntil { scene.hasRecordedPreparation(lasting: 41) }
        #expect(scene.prepared == [.launch, .screenUnlocked])
    }

    @Test func aPreparationThatLeftTheInputRunningIsTheLast() async throws {
        let scene = Scene()
        // Running, though not reported as running in this process: how a real Mac reports it.
        let running = InputDeviceStatus(id: 7, isRunningSomewhere: true, isRunningHere: false, transport: .builtIn, sampleRate: 48_000)
        scene.nextPreparation = MicrophonePreparation(outcome: .found, duration: .milliseconds(40), before: nil, after: running)
        scene.holdsPreparations = true

        scene.readiness.start()
        try await waitUntil { scene.preparationsHeld == 1 }
        scene.readiness.record(.screenUnlocked)
        scene.finishPreparation()
        try await waitUntil { scene.hasRecordedPreparation(lasting: 40) }

        // Neither the unlock that was waiting nor anything after it prepares again.
        scene.readiness.record(.systemDidWake)
        scene.readiness.record(.inputDeviceChanged)
        #expect(scene.prepared == [.launch])
    }
}

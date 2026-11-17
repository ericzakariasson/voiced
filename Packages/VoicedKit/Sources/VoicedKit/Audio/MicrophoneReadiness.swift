import Foundation

/// Decides when the input device is found ahead of a hold: at launch, when the Microphone is
/// granted, and when the Mac wakes, is unlocked or changes input device.
///
/// Until the Microphone is granted it does nothing with audio: no preparation, and no watch on
/// the input device. On a fresh install the system's microphone prompt therefore appears when
/// the setup window's Allow button is pressed and at no other time.
@MainActor
public final class MicrophoneReadiness {
    public typealias Prepare = @MainActor (MicrophonePreparation.Reason) async -> MicrophonePreparation

    public let history: MicrophoneHistory
    private let authorization: () -> MicrophoneAuthorization
    private let prepareInput: Prepare
    private let watchInputDevice: (@escaping @MainActor () -> Void) -> Void
    private var isWatchingInputDevice = false
    private var wasGranted = false
    private var isPreparing = false
    private var reasonWaiting: MicrophonePreparation.Reason?
    private var hasGivenUp = false

    /// - Parameters:
    ///   - prepare: Finds the input, as `MicrophoneCapture.prepare(after:)` does.
    ///   - watchInputDevice: Starts calling its argument whenever the default input device
    ///     changes. Called at most once, and only once the Microphone is granted.
    public init(
        authorization: @escaping () -> MicrophoneAuthorization = MicrophoneAuthorization.current,
        prepare: @escaping Prepare,
        watchInputDevice: @escaping (@escaping @MainActor () -> Void) -> Void
    ) {
        history = MicrophoneHistory()
        self.authorization = authorization
        prepareInput = prepare
        self.watchInputDevice = watchInputDevice
    }

    /// Call once, at launch.
    public func start() {
        wasGranted = authorization() == .granted
        prepare(after: .launch)
    }

    /// A permission changed. The first preparation waits for the Microphone to be granted.
    public func permissionsChanged() {
        let isGranted = authorization() == .granted
        if isGranted, !wasGranted {
            prepare(after: .microphoneGranted)
        }
        wasGranted = isGranted
    }

    /// Something happened to the Mac. It is written down, and a wake or an unlock is followed by
    /// a preparation.
    public func record(_ event: MicrophoneHistory.Event) {
        history.record(event)
        switch event {
        case .systemDidWake:
            prepare(after: .systemWoke)
        case .displaysDidWake:
            // The displays wake before the screen is unlocked, which gives a head start.
            prepare(after: .displaysWoke)
        case .screenUnlocked:
            prepare(after: .screenUnlocked)
        case .inputDeviceChanged:
            prepare(after: .inputDeviceChanged)
        case .systemWillSleep, .displaysDidSleep, .screenLocked:
            break
        }
    }

    /// The hotkey went down: write what came before this start, to read a slow one against.
    public func holdBegan() {
        VoicedLog.capture.notice("before this hold: \(self.history.summary, privacy: .public)")
        history.recordHold()
    }

    private func prepare(after reason: MicrophonePreparation.Reason) {
        guard !hasGivenUp, authorization() == .granted else { return }
        if !isWatchingInputDevice {
            isWatchingInputDevice = true
            watchInputDevice { [weak self] in
                self?.record(.inputDeviceChanged)
            }
        }
        guard !isPreparing else {
            // One at a time. Whatever happened meanwhile gets a preparation of its own afterwards.
            reasonWaiting = reason
            return
        }
        isPreparing = true
        Task { [weak self] in
            await self?.runPreparation(after: reason)
        }
    }

    private func runPreparation(after reason: MicrophonePreparation.Reason) async {
        let preparation = await prepareInput(reason)
        isPreparing = false
        history.record(preparation)
        if preparation.startedInput {
            hasGivenUp = true
            reasonWaiting = nil
            VoicedLog.capture.error("preparation: the input device was running afterwards; not preparing again until Voiced is relaunched")
        } else if let next = reasonWaiting {
            reasonWaiting = nil
            prepare(after: next)
        }
    }
}

import AVFoundation

/// Whether macOS lets this app use the microphone.
public enum MicrophoneAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case granted

    /// What macOS has on record. Reading it asks nobody anything.
    public static func current() -> MicrophoneAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    public var logDescription: String {
        switch self {
        case .notDetermined: "not determined"
        case .denied: "denied"
        case .granted: "granted"
        }
    }
}

/// What one `MicrophoneCapture.prepare()` did, in numbers and states.
public struct MicrophonePreparation: Equatable, Sendable {
    /// What called for the preparation.
    public enum Reason: String, Sendable {
        case launch
        case microphoneGranted = "microphone granted"
        case systemWoke = "system woke"
        case displaysWoke = "displays woke"
        case screenUnlocked = "screen unlocked"
        case inputDeviceChanged = "input device changed"
        case check
    }

    /// Why a preparation left the input alone.
    public enum Skip: Equatable, Sendable {
        /// The Microphone is undetermined or denied. Nothing about audio was touched, not even
        /// the device's state: `before` and `after` are `nil`.
        case microphoneNotGranted
        case noInputDevice
        /// This process was recording, so the input was already found and in use.
        case recording
        /// The microphone is running: another app is using it, a call for example, or Voiced
        /// itself is recording and the system does not say so (see `isRunningHere`).
        case inUseElsewhere
        /// An input of this kind might be disturbed by being found: see `canBeFoundAhead`.
        case inputKind(InputDeviceStatus.Transport)
    }

    public enum Outcome: Equatable, Sendable {
        case found
        case skipped(Skip)
        /// The audio system refused. The description is safe to log.
        case failed(String)
    }

    public var outcome: Outcome
    public var duration: Duration
    public var before: InputDeviceStatus?
    public var after: InputDeviceStatus?

    public init(outcome: Outcome, duration: Duration, before: InputDeviceStatus?, after: InputDeviceStatus?) {
        self.outcome = outcome
        self.duration = duration
        self.before = before
        self.after = after
    }

    /// The input device was running after a preparation that looked for it. A preparation only
    /// looks for a device that nobody has running, so afterwards it must still be idle: one that
    /// started it would have opened the microphone outside a hold.
    ///
    /// This goes by whether the device runs in any process. Whether it runs in this one is not
    /// reported reliably (see `InputDeviceStatus.isRunningHere`), so an app that began to use
    /// the microphone in the same moment looks the same as a preparation at fault. That is the
    /// safe way round: the cost is that Voiced stops preparing until it is relaunched.
    public var startedInput: Bool {
        switch outcome {
        case .found, .failed:
            guard let after else { return false }
            return after.isRunningSomewhere || after.isRunningHere
        case .skipped:
            return false
        }
    }

    public var logDescription: String {
        let outcome = switch outcome {
        case .found: "input found"
        case .skipped(.microphoneNotGranted): "skipped, microphone not granted"
        case .skipped(.noInputDevice): "skipped, no input device"
        case .skipped(.recording): "skipped, recording"
        case .skipped(.inUseElsewhere): "skipped, input in use"
        case let .skipped(.inputKind(transport)): "skipped, \(transport.logDescription) input"
        case let .failed(description): "failed (\(description))"
        }
        return "\(outcome) in \(Int(duration / .milliseconds(1))) ms; device before: \(before?.logDescription ?? "none"); after: \(after?.logDescription ?? "none")"
    }

    /// The order matters. Without the grant nothing is asked of the audio system at all: on
    /// macOS 26, making an input node while the Microphone was undetermined raised the system's
    /// permission prompt and did not return while it stood unanswered. Then the device's state
    /// is read, which opens nothing, and only a device that nobody is using, of a kind that can
    /// be found ahead, is looked for.
    static func run(
        after reason: Reason,
        authorization: () -> MicrophoneAuthorization,
        status: () -> InputDeviceStatus?,
        findInput: () throws -> Void
    ) -> MicrophonePreparation {
        guard authorization() == .granted else {
            return finish(MicrophonePreparation(outcome: .skipped(.microphoneNotGranted), duration: .zero, before: nil, after: nil), after: reason)
        }
        guard let before = status() else {
            return finish(MicrophonePreparation(outcome: .skipped(.noInputDevice), duration: .zero, before: nil, after: nil), after: reason)
        }
        guard !before.isRunningHere else {
            return finish(MicrophonePreparation(outcome: .skipped(.recording), duration: .zero, before: before, after: before), after: reason)
        }
        guard !before.isRunningSomewhere else {
            return finish(MicrophonePreparation(outcome: .skipped(.inUseElsewhere), duration: .zero, before: before, after: before), after: reason)
        }
        guard before.transport.canBeFoundAhead else {
            return finish(MicrophonePreparation(outcome: .skipped(.inputKind(before.transport)), duration: .zero, before: before, after: before), after: reason)
        }

        let began = ContinuousClock.now
        var outcome = Outcome.found
        do {
            try findInput()
        } catch {
            outcome = .failed(VoicedLog.describe(error))
        }
        return finish(MicrophonePreparation(outcome: outcome, duration: ContinuousClock.now - began, before: before, after: status()), after: reason)
    }

    private static func finish(_ preparation: MicrophonePreparation, after reason: Reason) -> MicrophonePreparation {
        if preparation.startedInput {
            VoicedLog.capture.error("preparation after \(reason.rawValue, privacy: .public): \(preparation.logDescription, privacy: .public): the input device was idle before and is running now")
        } else {
            VoicedLog.capture.notice("preparation after \(reason.rawValue, privacy: .public): \(preparation.logDescription, privacy: .public)")
        }
        return preparation
    }
}

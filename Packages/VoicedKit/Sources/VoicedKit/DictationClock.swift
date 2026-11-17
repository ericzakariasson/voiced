import Foundation

/// How the dictation loop tells the time and waits for a moment to come.
///
/// The app passes real time. A test passes a clock it moves by hand, so that it decides when a
/// hold is confirmed instead of racing a real one.
public protocol DictationClock: Sendable {
    var now: ContinuousClock.Instant { get }
    /// Returns once `deadline` has come, at once if it already has. Throws if the task is
    /// cancelled first.
    func sleep(until deadline: ContinuousClock.Instant) async throws
}

/// Real time.
public struct SystemDictationClock: DictationClock {
    public init() {}

    public var now: ContinuousClock.Instant {
        ContinuousClock.now
    }

    public func sleep(until deadline: ContinuousClock.Instant) async throws {
        try await ContinuousClock().sleep(until: deadline)
    }
}

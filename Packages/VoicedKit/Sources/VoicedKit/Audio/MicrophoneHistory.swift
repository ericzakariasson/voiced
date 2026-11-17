import Foundation

/// What has happened since launch that can make the microphone slow to start: sleep, a dark or
/// locked screen, a change of input device, and how long ago the input was last found.
///
/// A slow start says nothing about its cause by itself. This is written to the log as each thing
/// happens and summed up when the hotkey goes down, so a slow start can be read against what came
/// before it. Times and states only.
@MainActor
public final class MicrophoneHistory {
    public enum Event: Sendable {
        case systemWillSleep
        case systemDidWake
        case displaysDidSleep
        case displaysDidWake
        case screenLocked
        case screenUnlocked
        case inputDeviceChanged
    }

    /// A stretch that began at `began` and, once `ended` is set, is over.
    private struct Stretch {
        var began: ContinuousClock.Instant?
        var ended: ContinuousClock.Instant?
    }

    private let now: () -> ContinuousClock.Instant
    private let launched: ContinuousClock.Instant
    private var sleep = Stretch()
    private var darkDisplays = Stretch()
    private var lock = Stretch()
    private var inputChanges = 0
    private var lastInputChange: ContinuousClock.Instant?
    private var inputLastFound: (at: ContinuousClock.Instant, how: String)?

    public convenience init() {
        self.init(now: { ContinuousClock.now })
    }

    /// `now` must keep counting while the Mac sleeps, as `ContinuousClock` does.
    public init(now: @escaping () -> ContinuousClock.Instant) {
        self.now = now
        launched = now()
    }

    public func record(_ event: Event) {
        let now = now()
        switch event {
        case .systemWillSleep:
            sleep = Stretch(began: now)
            VoicedLog.capture.notice("system: going to sleep")
        case .systemDidWake:
            sleep.ended = now
            VoicedLog.capture.notice("system: woke\(Self.after(self.sleep, "asleep"), privacy: .public)")
        case .displaysDidSleep:
            darkDisplays = Stretch(began: now)
            VoicedLog.capture.notice("system: displays went dark")
        case .displaysDidWake:
            darkDisplays.ended = now
            VoicedLog.capture.notice("system: displays woke\(Self.after(self.darkDisplays, "dark"), privacy: .public)")
        case .screenLocked:
            lock = Stretch(began: now)
            VoicedLog.capture.notice("system: screen locked")
        case .screenUnlocked:
            lock.ended = now
            VoicedLog.capture.notice("system: screen unlocked\(Self.after(self.lock, "locked"), privacy: .public)")
        case .inputDeviceChanged:
            inputChanges += 1
            lastInputChange = now
            // The preparation that follows writes which device it is now.
            VoicedLog.capture.notice("system: default input device changed, \(self.inputChanges) times since launch")
        }
    }

    /// A preparation found the input.
    public func record(_ preparation: MicrophonePreparation) {
        guard preparation.outcome == .found else { return }
        inputLastFound = (now(), "a preparation that took \(Self.milliseconds(preparation.duration)) ms")
    }

    /// The hotkey went down, and the hold's own start is about to find the input.
    public func recordHold() {
        inputLastFound = (now(), "a hold")
    }

    /// Everything above as one line, for the log line written when the hotkey goes down.
    public var summary: String {
        let now = now()
        func ago(_ instant: ContinuousClock.Instant) -> String {
            "\(Self.seconds(now - instant)) s ago"
        }
        func describe(_ stretch: Stretch, _ noun: String, ended: String, during: String, never: String) -> String {
            guard let began = stretch.began else {
                // The end of a stretch that began before launch.
                return stretch.ended.map { "\(noun) \(ended) \(ago($0))" } ?? "\(noun) \(never)"
            }
            guard let end = stretch.ended, end >= began else {
                return "\(noun) \(during) for \(Self.seconds(now - began)) s"
            }
            return "\(noun) \(ended) \(ago(end)) after \(Self.seconds(end - began)) s"
        }
        let input = lastInputChange.map { "input device changed \(inputChanges) times, last \(ago($0))" } ?? "input device unchanged"
        let found = inputLastFound.map { "input last found \(ago($0.at)) by \($0.how)" } ?? "input not found yet"
        return [
            "launched \(ago(launched))",
            describe(sleep, "system", ended: "woke", during: "asleep", never: "has not slept"),
            describe(darkDisplays, "displays", ended: "woke", during: "dark", never: "have not gone dark"),
            describe(lock, "screen", ended: "unlocked", during: "locked", never: "has not been locked"),
            input,
            found,
        ].joined(separator: "; ")
    }

    private static func after(_ stretch: Stretch, _ state: String) -> String {
        guard let began = stretch.began, let ended = stretch.ended, ended >= began else { return "" }
        return " after \(seconds(ended - began)) s \(state)"
    }

    private static func seconds(_ duration: Duration) -> Int {
        Int(duration / .seconds(1))
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration / .milliseconds(1))
    }
}

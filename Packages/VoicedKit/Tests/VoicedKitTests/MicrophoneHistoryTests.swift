import Foundation
import Testing
@testable import VoicedKit

@MainActor
@Suite struct MicrophoneHistoryTests {
    /// A history whose time the test moves.
    @MainActor
    private final class Timeline {
        var now = ContinuousClock.now
        private(set) lazy var history = MicrophoneHistory(now: { [unowned self] in now })

        func pass(_ duration: Duration) {
            now += duration
        }
    }

    @Test func aFreshLaunchHasNothingToTell() {
        let timeline = Timeline()
        _ = timeline.history
        timeline.pass(.seconds(5))

        #expect(timeline.history.summary == """
            launched 5 s ago; system has not slept; displays have not gone dark; \
            screen has not been locked; input device unchanged; input not found yet
            """)
    }

    @Test func aLockedScreenIsToldWithHowLongItLasted() {
        let timeline = Timeline()
        timeline.history.record(MicrophonePreparation(outcome: .found, duration: .milliseconds(180), before: nil, after: nil))
        timeline.pass(.seconds(700))
        timeline.history.record(.displaysDidSleep)
        timeline.history.record(.screenLocked)
        timeline.pass(.seconds(608))
        timeline.history.record(.displaysDidWake)
        timeline.pass(.seconds(3))
        timeline.history.record(.screenUnlocked)
        timeline.pass(.seconds(9))

        #expect(timeline.history.summary == """
            launched 1320 s ago; system has not slept; displays woke 12 s ago after 608 s; \
            screen unlocked 9 s ago after 611 s; input device unchanged; \
            input last found 1320 s ago by a preparation that took 180 ms
            """)
    }

    @Test func sleepAndAChangeOfInputAreTold() {
        let timeline = Timeline()
        _ = timeline.history
        timeline.pass(.seconds(60))
        timeline.history.record(.systemWillSleep)
        timeline.pass(.seconds(3600))
        timeline.history.record(.systemDidWake)
        timeline.pass(.seconds(2))
        timeline.history.record(.inputDeviceChanged)
        timeline.history.record(.inputDeviceChanged)
        timeline.pass(.seconds(4))
        timeline.history.recordHold()
        timeline.pass(.seconds(30))

        #expect(timeline.history.summary == """
            launched 3696 s ago; system woke 36 s ago after 3600 s; displays have not gone dark; \
            screen has not been locked; input device changed 2 times, last 34 s ago; \
            input last found 30 s ago by a hold
            """)
    }

    @Test func aStretchStillUnderWayIsToldAsSuch() {
        let timeline = Timeline()
        _ = timeline.history
        timeline.history.record(.screenLocked)
        timeline.pass(.seconds(45))

        #expect(timeline.history.summary.contains("screen locked for 45 s"))
    }

    @Test func anUnlockWhoseLockCameBeforeLaunchIsStillTold() {
        let timeline = Timeline()
        _ = timeline.history
        timeline.pass(.seconds(10))
        timeline.history.record(.screenUnlocked)
        timeline.pass(.seconds(2))

        #expect(timeline.history.summary.contains("screen unlocked 2 s ago;"))
    }

    @Test func aPreparationThatFoundNothingDoesNotCountAsFindingTheInput() {
        let timeline = Timeline()
        timeline.history.record(MicrophonePreparation(outcome: .failed("capture.noInputDevice"), duration: .milliseconds(4), before: nil, after: nil))
        timeline.history.record(MicrophonePreparation(outcome: .skipped(.recording), duration: .zero, before: nil, after: nil))
        timeline.history.record(MicrophonePreparation(outcome: .skipped(.inputKind(.bluetooth)), duration: .zero, before: nil, after: nil))

        #expect(timeline.history.summary.hasSuffix("input not found yet"))
    }
}

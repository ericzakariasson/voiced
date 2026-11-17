import Testing
@testable import VoicedKit

@Suite struct AccessibilityWakeTests {
    private func isCalledFor(
        kind: AppKind = .electron, askedTheAppInFront: Bool = true, focusResult: Int32? = -25212, alreadyMade: Bool = false
    ) -> Bool {
        AccessibilityWake.isCalledFor(
            kind: kind, askedTheAppInFront: askedTheAppInFront, focusResult: focusResult, alreadyMadeForThisRunOfTheApp: alreadyMade
        )
    }

    @Test func anElectronOrChromiumAppInFrontWithNoFocusedElementGetsTheRead() {
        #expect(isCalledFor(kind: .electron))
        #expect(isCalledFor(kind: .chromium))
    }

    @Test func anAppOfAnotherKindOrOfUnknownKindIsLeftAlone() {
        #expect(!isCalledFor(kind: .other))
        // One outside the standard application folders, whose files are not opened to find out.
        #expect(!isCalledFor(kind: .unknown))
    }

    @Test func itIsMadeOncePerRunOfAnApp() {
        #expect(!isCalledFor(alreadyMade: true))
    }

    @Test(arguments: [Int32?.some(0), -25204, -25205, -25211, nil])
    func anAppThatGaveAFocusedElementOrCouldNotBeAskedIsLeftAlone(focusResult: Int32?) {
        // An answer, a timeout, an unsupported question, a refusal, and no question at all.
        #expect(!isCalledFor(focusResult: focusResult))
    }

    @Test func theAppIsAskedAgainAFewTimesWithinTwoSecondsOfTheRead() {
        let times = AccessibilityWake.askAgainAfter

        #expect(times.count >= 3 && times.count <= 8)
        #expect(times == times.sorted())
        #expect(Set(times).count == times.count)
        #expect(times.first.map { $0 >= .milliseconds(100) } == true)
        #expect(times.last.map { $0 <= .seconds(2) } == true)
    }

    @Test func aLaterAnswerMovesThePillOnlyFromAStandInToTheText() {
        typealias Source = PillNearText.Source
        let all: [Source] = [.insertionPoint, .field, .window, .fixedPlace]
        for shown in all {
            for found in all {
                let expected = (shown == .window || shown == .fixedPlace) && (found == .insertionPoint || found == .field)
                #expect(AccessibilityWake.isWorthMovingThePill(from: shown, to: found) == expected, "from \(shown.rawValue) to \(found.rawValue)")
            }
        }
        // A pill by the insertion point is not moved, not even to another insertion point.
        #expect(!AccessibilityWake.isWorthMovingThePill(from: .insertionPoint, to: .insertionPoint))
        #expect(!AccessibilityWake.isWorthMovingThePill(from: .field, to: .insertionPoint))
    }

    @Test func onlyTheAppThatWasInFrontIsEverRead() {
        // Voiced itself, or the app behind Voiced's menu, was asked instead.
        #expect(!isCalledFor(askedTheAppInFront: false))
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import VoicedKit

@Suite struct PillPlacementTests {
    private typealias Display = PillPlacement.Display

    /// A 1440 × 900 laptop screen with a 25 pt menu bar and a 70 pt Dock.
    private let laptop = Display(id: "laptop", visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805))
    /// A 2560 × 1440 monitor to the right of it.
    private let monitor = Display(id: "monitor", visibleFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1415))

    @Test func untilItIsMovedThePillSitsBottomCentreAboveTheDock() {
        #expect(PillPlacement.defaultAnchor(on: laptop) == CGPoint(x: 720, y: 88))
    }

    @Test func aPlaceIsRememberedAndRestoredExactly() throws {
        let anchor = CGPoint(x: 1100, y: 600)
        let placement = try #require(PillPlacement.remembering(anchor: anchor, displays: [laptop, monitor]))

        #expect(placement.display == "laptop")
        let restored = placement.anchor(displays: [laptop, monitor], fallback: laptop)
        #expect(abs(restored.x - anchor.x) < 0.001 && abs(restored.y - anchor.y) < 0.001)
    }

    @Test func survivesBeingSavedAndLoaded() throws {
        let placement = PillPlacement(display: "monitor", x: 0.25, y: 0.75)
        let loaded = try JSONDecoder().decode(PillPlacement.self, from: JSONEncoder().encode(placement))

        #expect(loaded == placement)
    }

    @Test func aPlaceOnTheSecondDisplayIsRememberedOnThatDisplay() throws {
        let anchor = CGPoint(x: 3000, y: 900)
        let placement = try #require(PillPlacement.remembering(anchor: anchor, displays: [laptop, monitor]))

        #expect(placement.display == "monitor")
        let restored = placement.anchor(displays: [laptop, monitor], fallback: laptop)
        #expect(abs(restored.x - anchor.x) < 0.001 && abs(restored.y - anchor.y) < 0.001)
    }

    @Test func whenItsDisplayIsUnpluggedThePillMovesToTheSameSpotOnAnother() throws {
        let placement = try #require(PillPlacement.remembering(anchor: CGPoint(x: 3360, y: 1061.25), displays: [laptop, monitor]))
        #expect(placement.x == 0.75 && placement.y == 0.75)

        let onLaptop = placement.anchor(displays: [laptop], fallback: laptop)

        #expect(onLaptop == CGPoint(x: 1080, y: 70 + 0.75 * 805))
    }

    @Test func whenItsDisplayComesBackThePillReturnsToIt() throws {
        let anchor = CGPoint(x: 3360, y: 1061.25)
        let placement = try #require(PillPlacement.remembering(anchor: anchor, displays: [laptop, monitor]))
        _ = placement.anchor(displays: [laptop], fallback: laptop)

        #expect(placement.anchor(displays: [laptop, monitor], fallback: laptop) == anchor)
    }

    @Test func keepsItsRelativeSpotWhenTheDisplayChangesResolution() throws {
        let placement = try #require(PillPlacement.remembering(anchor: CGPoint(x: 360, y: 271.25), displays: [laptop]))
        let scaled = Display(id: "laptop", visibleFrame: CGRect(x: 0, y: 80, width: 1728, height: 1010))

        #expect(placement.anchor(displays: [scaled], fallback: scaled) == CGPoint(x: 432, y: 80 + 0.25 * 1010))
    }

    @Test func aPillDraggedPastAnEdgeIsBroughtBackOnScreen() {
        // Left, right, bottom and top of the laptop's usable area.
        #expect(PillPlacement.keepingOnScreen(CGPoint(x: -500, y: 400), displays: [laptop]).x == 104)
        #expect(PillPlacement.keepingOnScreen(CGPoint(x: 5000, y: 400), displays: [laptop]).x == 1336)
        #expect(PillPlacement.keepingOnScreen(CGPoint(x: 700, y: -90), displays: [laptop]).y == 78)
        #expect(PillPlacement.keepingOnScreen(CGPoint(x: 700, y: 2000), displays: [laptop]).y == 823)
    }

    @Test func aPointInsideIsLeftAlone() {
        let point = CGPoint(x: 700, y: 400)
        #expect(PillPlacement.keepingOnScreen(point, displays: [laptop, monitor]) == point)
    }

    @Test func aPointBetweenDisplaysGoesToTheNearestOne() {
        // Above the laptop, in the gap beside the taller monitor: 40 pt from the monitor, 325 from the laptop.
        let kept = PillPlacement.keepingOnScreen(CGPoint(x: 1400, y: 1200), displays: [laptop, monitor])
        #expect(kept == CGPoint(x: 1544, y: 1200))
    }

    @Test func aRememberedPlaceNeverPutsThePillOffScreen() {
        let placement = PillPlacement(display: "laptop", x: 5, y: -3)
        let anchor = placement.anchor(displays: [laptop], fallback: laptop)

        #expect(anchor == CGPoint(x: 1336, y: 78))
    }

    @Test func withNoDisplayThereIsNothingToRemember() {
        #expect(PillPlacement.remembering(anchor: .zero, displays: []) == nil)
    }
}

import CoreGraphics
import Testing
@testable import VoicedKit

@Suite struct AppPresentationTests {
    private let builtIn = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let external = CGRect(x: 1728, y: 0, width: 2560, height: 1440)

    @Test func openingTheAppAgainShowsSetupUntilSetupIsDoneThenSettings() {
        #expect(AppWindow.toShow(needsSetup: true) == .onboarding)
        #expect(AppWindow.toShow(needsSetup: false) == .settings)
    }

    @Test func windowsAreRecognisedByTheStartOfTheirIdentifier() {
        #expect(AppWindow.settings.matches(windowIdentifier: "settings"))
        #expect(AppWindow.settings.matches(windowIdentifier: "settings-AppWindow-1"))
        #expect(!AppWindow.settings.matches(windowIdentifier: "onboarding-AppWindow-1"))
        #expect(!AppWindow.onboarding.matches(windowIdentifier: nil))
    }

    @Test func anItemInTheMenuBarIsOnScreen() {
        let item = CGRect(x: 1140, y: 1084, width: 32, height: 33)

        let placement = MenuBarItemPlacement.of(itemFrame: item, displayFrames: [builtIn])

        #expect(placement == .onScreen(x: 1140, display: 0))
        #expect(placement.isVisible)
    }

    /// What this looked like on a Mac running Bartender: macOS called the item visible, but its
    /// window sat nine thousand points left of the display.
    @Test func anItemPushedOffTheDisplayIsOffScreen() {
        let item = CGRect(x: -9150, y: 1084, width: 24, height: 33)

        let placement = MenuBarItemPlacement.of(itemFrame: item, displayFrames: [builtIn, external])

        #expect(placement == .offScreen(x: -9150))
        #expect(!placement.isVisible)
        #expect(placement.logDescription.contains("off screen at x=-9150"))
    }

    @Test func anItemOnASecondDisplayIsOnScreen() {
        let item = CGRect(x: 3000, y: 1407, width: 32, height: 33)

        #expect(MenuBarItemPlacement.of(itemFrame: item, displayFrames: [builtIn, external]) == .onScreen(x: 3000, display: 1))
    }

    /// With the menu bar set to hide itself, or behind a full-screen app, the item sits just
    /// above the top edge of the display. That is not hidden: the pointer brings it down.
    @Test func anItemInATuckedAwayMenuBarIsOnScreen() {
        let item = CGRect(x: 1140, y: 1117, width: 32, height: 30)

        #expect(MenuBarItemPlacement.of(itemFrame: item, displayFrames: [builtIn]) == .onScreen(x: 1140, display: 0))
    }

    @Test func anItemPushedOffATuckedAwayMenuBarIsStillOffScreen() {
        let item = CGRect(x: -4355, y: 1117, width: 32, height: 30)

        #expect(MenuBarItemPlacement.of(itemFrame: item, displayFrames: [builtIn, external]) == .offScreen(x: -4355))
    }

    @Test func anItemFarAboveTheDisplayIsOffScreen() {
        let item = CGRect(x: 1140, y: 1200, width: 32, height: 30)

        #expect(MenuBarItemPlacement.of(itemFrame: item, displayFrames: [builtIn]) == .offScreen(x: 1140))
    }

    @Test func theItemIsPlacedOnlyWhenNothingSaysVoicedHasRunBefore() {
        #expect(MenuBarItemPosition.shouldPlaceForFirstLaunch(hasSavedPlace: false, hasLaunchedBefore: false, hasBeenGrantedAPermission: false))
        // The item has been somewhere: where the user or a menu bar manager put it.
        #expect(!MenuBarItemPosition.shouldPlaceForFirstLaunch(hasSavedPlace: true, hasLaunchedBefore: false, hasBeenGrantedAPermission: false))
        #expect(!MenuBarItemPosition.shouldPlaceForFirstLaunch(hasSavedPlace: false, hasLaunchedBefore: true, hasBeenGrantedAPermission: false))
        // A build from before the marker existed has left its permissions behind.
        #expect(!MenuBarItemPosition.shouldPlaceForFirstLaunch(hasSavedPlace: false, hasLaunchedBefore: false, hasBeenGrantedAPermission: true))
    }

    @Test func aShuffleAlongTheMenuBarIsNotANewSituation() {
        #expect(MenuBarItemPlacement.offScreen(x: -9150).isSameSituation(as: .offScreen(x: -9126)))
        #expect(MenuBarItemPlacement.onScreen(x: 1140, display: 0).isSameSituation(as: .onScreen(x: 1108, display: 0)))
        #expect(!MenuBarItemPlacement.onScreen(x: 1140, display: 0).isSameSituation(as: .offScreen(x: -9126)))
        #expect(!MenuBarItemPlacement.notCreated.isSameSituation(as: .offScreen(x: 0)))
        #expect(!MenuBarItemPlacement.notCreated.isSameSituation(as: .onScreen(x: 1140, display: 0)))
    }

    @Test func followingTheActiveDisplayIsNotANewSituation() {
        // With a second display attached, the item moves to whichever display is active.
        #expect(MenuBarItemPlacement.onScreen(x: 1140, display: 0).isSameSituation(as: .onScreen(x: 3000, display: 1)))
        #expect(MenuBarItemPlacement.onScreen(x: 3000, display: 1).isSameSituation(as: .onScreen(x: 1140, display: 0)))
    }

    @Test func aMissingOrEmptyItemIsNotOnScreen() {
        #expect(MenuBarItemPlacement.of(itemFrame: nil, displayFrames: [builtIn]) == .notCreated)

        let empty = CGRect(x: 1140, y: 1084, width: 0, height: 33)
        #expect(MenuBarItemPlacement.of(itemFrame: empty, displayFrames: [builtIn]) == .offScreen(x: 1140))
    }
}

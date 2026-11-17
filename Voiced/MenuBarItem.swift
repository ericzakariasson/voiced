import AppKit
import AVFoundation
import os
import VoicedKit

private let log = VoicedLog.setup

/// Asks macOS for a place in the menu bar where the icon can be seen.
enum MenuBarItem {
    /// Call before the item exists. For a first launch, asks for the right end of the menu bar;
    /// on any later launch the item stays where it was, hidden or not.
    static func prepareForLaunch(defaults: UserDefaults = .standard) {
        let isFirstLaunch = MenuBarItemPosition.shouldPlaceForFirstLaunch(
            hasSavedPlace: defaults.object(forKey: MenuBarItemPosition.defaultsKey) != nil,
            hasLaunchedBefore: defaults.bool(forKey: MenuBarItemPosition.hasLaunchedKey),
            hasBeenGrantedAPermission: AVCaptureDevice.authorizationStatus(for: .audio) != .notDetermined || AXIsProcessTrusted()
        )
        if isFirstLaunch {
            askForTheRightEnd(defaults: defaults)
            log.notice("menu bar item: first launch, asked macOS to put it at the right end of the menu bar")
        }
        defaults.set(true, forKey: MenuBarItemPosition.hasLaunchedKey)
    }

    /// Takes effect when the item is next created.
    static func askForTheRightEnd(defaults: UserDefaults = .standard) {
        defaults.set(MenuBarItemPosition.rightEnd, forKey: MenuBarItemPosition.defaultsKey)
    }
}

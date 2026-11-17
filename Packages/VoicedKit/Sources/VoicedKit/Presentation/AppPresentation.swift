import CoreGraphics
import Foundation

/// The two windows Voiced can open.
public enum AppWindow: String, CaseIterable, Sendable {
    case onboarding
    case settings

    /// The window to bring forward when the app is opened again while it is running, or when
    /// someone needs a way back into it: setup while setup is incomplete, Settings after that.
    public static func toShow(needsSetup: Bool) -> AppWindow {
        needsSetup ? .onboarding : .settings
    }

    /// SwiftUI gives a scene's window an identifier that starts with the scene's id.
    public func matches(windowIdentifier: String?) -> Bool {
        windowIdentifier?.hasPrefix(rawValue) == true
    }
}

/// Where the menu bar item ended up. macOS reports a status item as visible even when a menu bar
/// manager or a full menu bar has pushed it off the screen, so this goes by the item's frame.
public enum MenuBarItemPlacement: Equatable, Sendable {
    /// The item is not in the menu bar: it was never created, or it has been dragged out.
    case notCreated
    /// The item is inside the frame of a display.
    case onScreen(x: Int, display: Int)
    /// The item exists but is outside every display, so it cannot be seen or clicked.
    case offScreen(x: Int)

    public static func of(itemFrame: CGRect?, displayFrames: [CGRect]) -> MenuBarItemPlacement {
        guard let itemFrame else { return .notCreated }
        let x = Int(itemFrame.minX.rounded())
        // A menu bar that has tucked itself away, set to hide or behind a full-screen app, sits
        // just above the top edge of its display. Its items are a move of the pointer away, not hidden.
        let tuckedAway = itemFrame.offsetBy(dx: 0, dy: -itemFrame.height)
        guard itemFrame.width > 0, let display = displayFrames.firstIndex(where: { $0.contains(itemFrame) || $0.contains(tuckedAway) }) else {
            return .offScreen(x: x)
        }
        return .onScreen(x: x, display: display)
    }

    public var isVisible: Bool {
        if case .onScreen = self { return true }
        return false
    }

    /// Whether `other` is the same situation: seen, hidden or absent, wherever along the menu
    /// bar and on whichever display. With two displays the item follows the active one, so its
    /// display changes every time the pointer crosses over.
    public func isSameSituation(as other: MenuBarItemPlacement) -> Bool {
        switch (self, other) {
        case (.notCreated, .notCreated), (.offScreen, .offScreen), (.onScreen, .onScreen):
            true
        default:
            false
        }
    }

    /// One line for the log.
    public var logDescription: String {
        switch self {
        case .notCreated:
            "not in the menu bar: it was not created, or it was dragged out"
        case let .onScreen(x, display):
            "on screen at x=\(x) on display \(display)"
        case let .offScreen(x):
            "created but off screen at x=\(x): hidden by a menu bar manager such as Bartender, or by a full menu bar"
        }
    }
}

/// Where macOS is asked to put the menu bar item.
///
/// macOS puts a status item it has no saved place for at the left end of the menu bar icons.
/// That is left of the dividers a menu bar manager hides icons behind, and the first place a
/// full menu bar runs out of room. An item with a saved place is put back in order of that
/// value, the smallest furthest right, so a saved place of zero is the right end, next to the
/// system's own icons: right of every divider, and the last place to run out of room.
public enum MenuBarItemPosition {
    /// The default AppKit keeps a status item's place under, in the app's own domain. `Item-0`
    /// is the name AppKit gives the app's first status item, which is the only one Voiced has.
    public static let defaultsKey = "NSStatusItem Preferred Position Item-0"
    /// Set once Voiced has been launched, so the item is only ever placed for a first launch.
    public static let hasLaunchedKey = "hasLaunchedBefore"
    public static let rightEnd: Double = 0

    /// Whether to ask for the right end before the item is created. Only when nothing says
    /// Voiced has run on this Mac before: an item that has been somewhere is never moved
    /// without being asked, so one that was hidden on purpose stays hidden.
    public static func shouldPlaceForFirstLaunch(hasSavedPlace: Bool, hasLaunchedBefore: Bool, hasBeenGrantedAPermission: Bool) -> Bool {
        !hasSavedPlace && !hasLaunchedBefore && !hasBeenGrantedAPermission
    }
}

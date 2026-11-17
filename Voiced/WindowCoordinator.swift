import AppKit
import os
import VoicedKit

private let log = VoicedLog.setup

/// Keeps Voiced reachable while one of its windows is open, and reports where its menu bar item is.
///
/// Voiced is a menu bar app: no Dock icon, not in ⌘-Tab. A window of such an app is lost the
/// moment another app covers it, and the menu bar item is no way back when a menu bar manager has
/// hidden it. So a window is brought in front of every other app when it opens, and while one is
/// open Voiced is a regular app, with a Dock icon and a place in ⌘-Tab. It goes back to the menu
/// bar when the last window closes.
final class WindowCoordinator {
    private var observers: [any NSObjectProtocol] = []
    private var isRegularApp = false
    /// Windows that have been asked for but may not exist yet.
    private var pendingWindows = 0
    private var lastMenuBarItemPlacement: MenuBarItemPlacement?
    /// False once the item has been taken out of the menu bar. AppKit keeps its window, parked
    /// at a place inside the display, so the window's frame alone would call it on screen.
    var menuBarItemIsInserted = true
    /// Set while the item is taken out and put back at a new place: its absence then is not news.
    var isMovingMenuBarItem = false
    /// Told where the menu bar item is each time it is looked up, so the app can say when it is hidden.
    var onMenuBarItemPlacement: ((MenuBarItemPlacement) -> Void)?

    init() {
        let names = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMoveNotification,
            NSWindow.willCloseNotification,
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // On the next turn of the run loop: a closing window is still visible during this one.
                Task { @MainActor in
                    self?.update()
                }
            })
        }
    }

    /// Makes Voiced the frontmost app. Call before anything that puts a system prompt on screen,
    /// so the prompt does not open behind the app the user was in.
    func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Brings `appWindow` in front of every other app, after `open` has asked SwiftUI for it.
    func bringForward(_ appWindow: AppWindow, open: () -> Void = {}) {
        pendingWindows += 1
        update()
        activate()
        open()

        Task {
            // SwiftUI may create the window a moment after it is asked to.
            for wait in [0, 50, 150, 300, 600] {
                try? await Task.sleep(for: .milliseconds(wait))
                if let window = openWindow(for: appWindow) {
                    putInFront(window, as: appWindow)
                    break
                }
            }
            if openWindow(for: appWindow) == nil {
                log.error("\(appWindow.rawValue, privacy: .public) window was asked for but never appeared")
            }
            pendingWindows -= 1
            update()
        }
    }

    private func putInFront(_ window: NSWindow, as appWindow: AppWindow) {
        window.makeKeyAndOrderFront(nil)
        // Activation is a request macOS may turn down; this puts the window in front regardless.
        window.orderFrontRegardless()
        log.notice("\(appWindow.rawValue, privacy: .public) window (id \(window.identifier?.rawValue ?? "none", privacy: .public)) brought to the front; Voiced is \(NSApp.isActive ? "active" : "not active", privacy: .public)")
    }

    /// The setup and Settings windows: ordinary titled windows, as opposed to the indicator
    /// panel, the menu bar item and the panel that opens from it.
    private var appWindows: [NSWindow] {
        NSApp.windows.filter { window in
            window.styleMask.contains(.titled) && window.canBecomeMain && !(window is NSPanel)
                && window.className != "NSStatusBarWindow"
        }
    }

    private func openWindow(for appWindow: AppWindow) -> NSWindow? {
        let open = appWindows.filter(Self.isOpen)
        if let window = open.first(where: { appWindow.matches(windowIdentifier: $0.identifier?.rawValue) }) {
            return window
        }
        // Should SwiftUI ever name its windows differently, an open window is still the one meant.
        let recognised = open.contains { window in
            AppWindow.allCases.contains { $0.matches(windowIdentifier: window.identifier?.rawValue) }
        }
        return recognised ? nil : open.first
    }

    private static func isOpen(_ window: NSWindow) -> Bool {
        window.isVisible || window.isMiniaturized
    }

    private func update() {
        let open = appWindows.filter(Self.isOpen)
        let shouldBeRegularApp = !open.isEmpty || pendingWindows > 0
        if shouldBeRegularApp != isRegularApp {
            isRegularApp = shouldBeRegularApp
            NSApp.setActivationPolicy(shouldBeRegularApp ? .regular : .accessory)
            let names = open.map { $0.identifier?.rawValue ?? "unnamed" }.joined(separator: ", ")
            log.notice("Dock icon and ⌘-Tab \(shouldBeRegularApp ? "on" : "off", privacy: .public); open windows: \(names.isEmpty ? "none" : names, privacy: .public)")
        }
        // Not before the first report: the item does not exist yet in the first moments after launch.
        if lastMenuBarItemPlacement != nil {
            logMenuBarItem()
        }
    }

    /// Logs where the menu bar item is: once shortly after launch, then whenever it moves on or
    /// off the screen.
    ///
    /// macOS reports a status item as visible even when it has been pushed off the display, so the
    /// log would otherwise not say why the icon cannot be seen.
    func logMenuBarItem() {
        guard !isMovingMenuBarItem else { return }
        let statusWindow = menuBarItemIsInserted ? NSApp.windows.first { $0.className == "NSStatusBarWindow" } : nil
        let placement = MenuBarItemPlacement.of(itemFrame: statusWindow?.frame, displayFrames: NSScreen.screens.map(\.frame))
        onMenuBarItemPlacement?(placement)
        // Only moving on or off the screen is news, not a shuffle along the menu bar or a move to
        // the other display.
        if let last = lastMenuBarItemPlacement, last.isSameSituation(as: placement) { return }
        lastMenuBarItemPlacement = placement
        if placement.isVisible {
            log.notice("menu bar item: \(placement.logDescription, privacy: .public)")
        } else {
            log.error("menu bar item: \(placement.logDescription, privacy: .public)")
        }
    }
}

import AppKit
import SwiftUI

/// How tall a window's content may be on the screen the window is on: the screen's visible
/// height, between the menu bar and the Dock, less the window's own title bar.
///
/// Reports again when the window moves to another display, when a display changes, and when
/// the window comes to the front. As the window grows it is kept inside the visible area.
struct WindowHeightLimit: NSViewRepresentable {
    /// A visible height to use instead of the screen's, for previews and screenshots of a
    /// smaller display than the one at hand.
    var visibleScreenHeight: CGFloat?
    @Binding var limit: CGFloat

    /// What to assume until the window is known.
    static func initial(visibleScreenHeight: CGFloat?) -> CGFloat {
        limit(visibleHeight: visibleScreenHeight ?? NSScreen.main?.visibleFrame.height ?? 800, titleBar: 32)
    }

    /// Never so little that nothing can be read; a display that small does not exist.
    static func limit(visibleHeight: CGFloat, titleBar: CGFloat) -> CGFloat {
        max(visibleHeight - titleBar, 240)
    }

    func makeNSView(context: Context) -> Probe {
        Probe()
    }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.visibleScreenHeight = visibleScreenHeight
        probe.report = { newLimit in
            guard abs(newLimit - limit) > 0.5 else { return }
            limit = newLimit
        }
        probe.measure()
    }

    final class Probe: NSView {
        var visibleScreenHeight: CGFloat?
        var report: (CGFloat) -> Void = { _ in }
        private var observers: [any NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }

            let center = NotificationCenter.default
            let remeasure: [(Notification.Name, AnyObject?)] = [
                (NSWindow.didChangeScreenNotification, window),
                (NSWindow.didBecomeKeyNotification, window),
                (NSApplication.didChangeScreenParametersNotification, nil),
            ]
            for (name, object) in remeasure {
                observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.measure() }
                })
            }
            observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keepOnScreen() }
            })
            measure()
        }

        func measure() {
            guard let window, let visibleHeight = visibleScreenHeight ?? window.screen?.visibleFrame.height else { return }
            let titleBar = window.frame.height - window.contentLayoutRect.height
            let limit = WindowHeightLimit.limit(visibleHeight: visibleHeight, titleBar: titleBar)
            // Not during the layout pass that asked.
            Task { [weak self] in
                self?.report(limit)
            }
        }

        /// A window that has grown past the bottom of the visible area is moved up into it.
        private func keepOnScreen() {
            guard visibleScreenHeight == nil, let window, let visible = window.screen?.visibleFrame else { return }
            let frame = window.frame
            guard frame.height <= visible.height, frame.minY < visible.minY else { return }
            window.setFrameOrigin(NSPoint(x: frame.minX, y: visible.minY))
        }
    }
}

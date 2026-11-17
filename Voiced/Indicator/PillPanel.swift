import AppKit
import SwiftUI

/// The window the pill floats in.
///
/// It can be clicked and dragged, yet it can never take the keyboard: it is a non-activating
/// panel, so a click on it does not bring Voiced forward, and it refuses to become the key or
/// main window, so the app being dictated into keeps its insertion point and gets the paste.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        // The pill is dark in the light appearance too; see `IndicatorView`.
        appearance = NSAppearance(named: .darkAqua)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Clicks pass through until the pointer is over the pill itself; see `IndicatorPanel`.
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}

/// Hosts the pill and turns a drag on it into a move of the panel.
///
/// The drag is followed by hand rather than handed to the window server, so the panel can be
/// kept on screen while it moves and the whole thing can be exercised with synthetic events.
final class PillDragView: NSView {
    /// The pill's frame in this view's coordinates; only that part of the panel can be grabbed.
    var pillFrame: () -> CGRect = { .zero }
    /// Maps a proposed panel origin to the one to use, keeping the pill on screen.
    var constrain: (NSPoint) -> NSPoint = { $0 }
    var onDragBegan: () -> Void = {}
    /// Called once when a drag that moved the panel ends.
    var onDragEnded: () -> Void = {}
    /// Where the pointer is on screen during `event`. The real pointer by default; the focus
    /// check replaces it so that synthetic events can stand in for a hand on the mouse.
    var pointerLocation: (NSEvent) -> NSPoint = { _ in NSEvent.mouseLocation }

    private struct Drag {
        var panelOrigin: NSPoint
        var pointer: NSPoint
        var hasMoved = false
    }

    private var drag: Drag?

    var isDragging: Bool { drag != nil }

    // Top-left origin, the same as the SwiftUI content.
    override var isFlipped: Bool { true }

    init(content: some View) {
        super.init(frame: .zero)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The first click on a window that is not key is normally swallowed; the pill never is key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        return pillFrame().contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        drag = Drag(panelOrigin: window.frame.origin, pointer: pointerLocation(event))
        onDragBegan()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, var drag else { return }
        let pointer = pointerLocation(event)
        let proposed = NSPoint(
            x: drag.panelOrigin.x + pointer.x - drag.pointer.x,
            y: drag.panelOrigin.y + pointer.y - drag.pointer.y
        )
        let origin = constrain(proposed)
        guard origin != window.frame.origin else { return }
        window.setFrameOrigin(origin)
        drag.hasMoved = true
        self.drag = drag
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        self.drag = nil
        if drag.hasMoved {
            onDragEnded()
        }
    }
}

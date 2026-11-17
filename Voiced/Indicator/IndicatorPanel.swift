import AppKit
import Observation
import os
import SwiftUI
import VoicedKit

private let log = VoicedLog.setup

/// Shows the indicator in a floating panel that never takes focus from the app being typed into,
/// and lets it be dragged to wherever the user wants it.
final class IndicatorPanel {
    @Observable
    final class State {
        var content: IndicatorContent = .hidden
        /// Where the pill is inside the panel, as SwiftUI reports it.
        @ObservationIgnored var pillFrame: CGRect = .zero
    }

    private let controller: DictationController
    private let pill: PillSettings
    private let state = State()
    private let panel: PillPanel
    private let dragView: PillDragView
    private var noticeDismissal: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var shownNoticeSequence: Int?
    private var pointerWatch: Timer?
    private var screenObserver: (any NSObjectProtocol)?

    private static let size = NSSize(width: 460, height: 120)
    /// From the panel's origin to the pill's anchor, the middle of the pill's bottom edge.
    private static let anchorOffset = NSPoint(x: size.width / 2, y: IndicatorView.bottomPadding)

    #if DEBUG
    var window: NSWindow { panel }
    var dragSurface: PillDragView { dragView }
    /// What placed the pill for the dictation on screen; `nil` at the fixed place by setting.
    var placementForDictation: PillNearText? { dictationPlacement }
    var pillFrameOnScreen: CGRect { panel.convertToScreen(dragView.convert(state.pillFrame, to: nil)) }
    var contentShown: IndicatorContent { state.content }
    #endif

    init(controller: DictationController, pill: PillSettings) {
        self.controller = controller
        self.pill = pill

        panel = PillPanel(size: Self.size)
        let state = state
        dragView = PillDragView(content: IndicatorRoot(state: state, controller: controller))
        dragView.pillFrame = { state.pillFrame }
        panel.contentView = dragView

        dragView.constrain = { [weak self] origin in
            self?.constrained(origin) ?? origin
        }
        dragView.onDragBegan = { [weak self] in
            self?.wasTouchedThisDictation = true
        }
        dragView.onDragEnded = { [weak self] in
            self?.rememberPosition()
        }
        pill.textLookup.onLaterAnswer = { [weak self] in
            self?.placeAgainByTheText()
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // A display came or went, or changed size: put the pill where it belongs now.
                guard let self, self.panel.isVisible else { return }
                self.position()
            }
        }

        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = controller.phase
            _ = controller.microphone
            _ = controller.notice
            _ = pill.isPlacing
            _ = pill.placement
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
    }

    private func update() {
        switch controller.phase {
        case .starting:
            // Not yet known to be a dictation: a tap or a typed character must not flash the pill.
            break
        case .recording:
            placeForDictation()
            switch controller.microphone {
            case let .listening(since):
                show(.recording(since: since))
            case .startingSlowly:
                show(.startingMicrophone)
            case .starting, .off:
                // Audio is a moment away, as it is at the start of every hold. The pill waits
                // for it rather than say it is listening before it is.
                break
            }
        case .transcribing, .cleaning, .inserting:
            placeForDictation()
            // With cleanup switched off there is no polishing to show: the pill goes on saying
            // Transcribing… until the text has landed.
            show(.working(controller.isPolishing ? "Polishing…" : "Transcribing…"))
        case .idle:
            isShowingDictation = false
            if let notice = controller.notice, notice.sequence != shownNoticeSequence {
                shownNoticeSequence = notice.sequence
                show(.notice(notice.kind, notice.message))
                noticeDismissal = Task { [weak self] in
                    try? await Task.sleep(for: notice.kind == .error ? .seconds(6) : .seconds(4))
                    guard !Task.isCancelled else { return }
                    self?.noticeDismissal = nil
                    self?.update()
                }
            } else if noticeDismissal == nil {
                if pill.isPlacing {
                    // Placing is always about the fixed place.
                    if dictationPlacement != nil {
                        dictationPlacement = nil
                        if panel.isVisible { position() }
                    }
                    show(.placing)
                } else {
                    hide()
                }
            }
        }
        // A reset while the pill is showing moves it back at once.
        if panel.isVisible, !dragView.isDragging, pill.placement == nil, shownPlacement != nil {
            position()
        }
    }

    /// The placement the panel was last positioned with, to notice a reset.
    private var shownPlacement: PillPlacement?
    /// Where the dictation on screen put the pill. Decided once, when the dictation's pill first
    /// shows, and kept until the pill leaves the screen, so the pill does not jump.
    private var dictationPlacement: PillNearText?
    private var isShowingDictation = false
    /// A hand has been on the pill during this dictation; it then stays where the hand left it.
    private var wasTouchedThisDictation = false

    /// Decides where the pill goes for the dictation that has just begun.
    private func placeForDictation() {
        guard !isShowingDictation else { return }
        isShowingDictation = true
        wasTouchedThisDictation = false
        guard let fixedAnchor else { return }
        switch pill.mode {
        case .fixedPlace:
            dictationPlacement = nil
            let display = displays.firstIndex { $0.visibleFrame.contains(fixedAnchor) }
            let placed = PillNearText(source: .fixedPlace, anchor: fixedAnchor, display: display)
            log.notice("pill placed \(placed.logDescription, privacy: .public); text not asked for")
        case .nextToText:
            let answer = pill.textLookup.answer
            let placed = PillNearText.place(geometry: answer?.geometry, displays: displays, fixedAnchor: fixedAnchor)
            dictationPlacement = placed
            log.notice("pill placed \(placed.logDescription, privacy: .public); lookup: \(answer?.logDescription ?? "no answer in time", privacy: .public)")
        }
        // Still on screen from the dictation before, or from being placed: move it now.
        if panel.isVisible { position() }
    }

    /// The app in front said where its text is after the pill was already up: Voiced had just
    /// switched its accessibility on, and the pill went to the bottom of the window meanwhile.
    /// The one time a pill moves by itself during a dictation: once, to the text, while the
    /// hotkey is still held, and not after a hand has moved it.
    private func placeAgainByTheText() {
        guard isShowingDictation, controller.phase == .recording, pill.mode == .nextToText,
              !wasTouchedThisDictation, !dragView.isDragging,
              let shown = dictationPlacement, let fixedAnchor else { return }
        let answer = pill.textLookup.answer
        let placed = PillNearText.place(geometry: answer?.geometry, displays: displays, fixedAnchor: fixedAnchor)
        guard AccessibilityWake.isWorthMovingThePill(from: shown.source, to: placed.source) else { return }
        dictationPlacement = placed
        log.notice("pill placed again \(placed.logDescription, privacy: .public); lookup after the read: \(answer?.logDescription ?? "no answer", privacy: .public)")
        if panel.isVisible { position() }
    }

    /// The pill has left the screen. A new dictation may have been placed already while its
    /// pill waits for audio; that place is the new dictation's, and is kept.
    private func forgetPlacementOfTheDictationThatEnded() {
        guard !isShowingDictation else { return }
        dictationPlacement = nil
    }

    private func show(_ content: IndicatorContent) {
        noticeDismissal?.cancel()
        noticeDismissal = nil
        hideTask?.cancel()
        hideTask = nil

        if !panel.isVisible {
            position()
            panel.orderFrontRegardless()
            startWatchingPointer()
        }
        state.content = content
    }

    private func hide() {
        noticeDismissal?.cancel()
        noticeDismissal = nil
        guard state.content != .hidden || panel.isVisible else { return }
        state.content = .hidden
        // Let the pill animate out before the panel leaves the screen.
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.stopWatchingPointer()
            self?.panel.orderOut(nil)
            self?.forgetPlacementOfTheDictationThatEnded()
        }
    }

    // MARK: - Position

    private var displays: [PillPlacement.Display] {
        NSScreen.screens.map { PillPlacement.Display(id: Self.identifier(of: $0), visibleFrame: $0.visibleFrame) }
    }

    /// A display's UUID, which stays the same across restarts and re-plugging.
    private static func identifier(of screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        if let number, let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return screen.localizedName
    }

    /// Where the user left the pill, or bottom centre of the screen the pointer is on.
    private var fixedAnchor: CGPoint? {
        let pointer = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let fallback = pointerScreen.map({ PillPlacement.Display(id: Self.identifier(of: $0), visibleFrame: $0.visibleFrame) }) else {
            return nil
        }
        return pill.placement?.anchor(displays: displays, fallback: fallback) ?? PillPlacement.defaultAnchor(on: fallback)
    }

    /// The pill is beside the text of the dictation on screen, not at its fixed place.
    private var isBesideText: Bool {
        dictationPlacement.map { $0.source != .fixedPlace } ?? false
    }

    private func position() {
        guard var anchor = fixedAnchor else { return }
        shownPlacement = pill.placement
        if let dictationPlacement, isBesideText {
            anchor = PillPlacement.keepingOnScreen(dictationPlacement.anchor, displays: displays)
        }
        panel.setFrameOrigin(NSPoint(x: anchor.x - Self.anchorOffset.x, y: anchor.y - Self.anchorOffset.y))
    }

    /// Keeps the pill fully on a display while it is dragged.
    private func constrained(_ origin: NSPoint) -> NSPoint {
        let anchor = NSPoint(x: origin.x + Self.anchorOffset.x, y: origin.y + Self.anchorOffset.y)
        let kept = PillPlacement.keepingOnScreen(anchor, displays: displays)
        return NSPoint(x: kept.x - Self.anchorOffset.x, y: kept.y - Self.anchorOffset.y)
    }

    private func rememberPosition() {
        let origin = panel.frame.origin
        let anchor = NSPoint(x: origin.x + Self.anchorOffset.x, y: origin.y + Self.anchorOffset.y)
        if isBesideText {
            // Moved away from the text for this dictation; the fixed place is not what was dragged.
            dictationPlacement?.anchor = anchor
            log.notice("pill moved for this dictation only; Voiced is \(NSApp.isActive ? "active" : "not active", privacy: .public), pill is \(self.panel.isKeyWindow ? "key" : "not key", privacy: .public)")
            return
        }
        guard let placement = PillPlacement.remembering(anchor: anchor, displays: displays) else { return }
        shownPlacement = placement
        pill.remember(placement)
        // Whether Voiced is active matters: dragging the pill must not take the keyboard from the app being dictated into.
        log.notice("pill moved to x=\(placement.x, format: .fixed(precision: 2)) y=\(placement.y, format: .fixed(precision: 2)) of its display while \(String(describing: self.controller.phase), privacy: .public); Voiced is \(NSApp.isActive ? "active" : "not active", privacy: .public), pill is \(self.panel.isKeyWindow ? "key" : "not key", privacy: .public)")
    }

    // MARK: - Clicks

    /// The panel is larger than the pill, to leave room for the pill to change size. Clicks must
    /// reach the pill and nothing else, so the panel ignores the mouse except while the pointer is
    /// over the pill or a drag is under way.
    private func startWatchingPointer() {
        guard pointerWatch == nil else { return }
        pointerWatch = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMouseHandling()
            }
        }
        updateMouseHandling()
    }

    private func stopWatchingPointer() {
        pointerWatch?.invalidate()
        pointerWatch = nil
        panel.ignoresMouseEvents = true
    }

    private func updateMouseHandling() {
        let pillFrame = state.content == .hidden ? .zero : state.pillFrame
        let pillOnScreen = panel.convertToScreen(dragView.convert(pillFrame, to: nil))
        let pointerIsOverPill = !pillFrame.isEmpty && pillOnScreen.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !(pointerIsOverPill || dragView.isDragging)
    }
}

private struct IndicatorRoot: View {
    var state: IndicatorPanel.State
    var controller: DictationController

    var body: some View {
        IndicatorView(content: state.content, level: controller.level) { frame in
            state.pillFrame = frame
        }
    }
}

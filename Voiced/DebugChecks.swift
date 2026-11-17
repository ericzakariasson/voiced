#if DEBUG
import AppKit
import os
import SwiftUI
import VoicedKit

/// Checks that need the running app but no person: run by `make snapshots`, which fails if one
/// of them does. They drive the real windows with events made in the process, so they need no
/// Accessibility permission and never touch another app or the clipboard.
enum DebugChecks {
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(description: message) }
    }

    // MARK: - Dragging the pill must not take the keyboard

    private final class IdleCapture: AudioCapturing {
        func start() -> AsyncThrowingStream<AudioChunk, any Error> { AsyncThrowingStream { $0.finish() } }
        func stop() {}
    }

    private actor IdleSession: TranscriptionSession {
        func start() {}
        func send(audio: Data) {}
        func finish() async throws -> TranscriptionResult { TranscriptionResult(text: "", isComplete: true) }
        func cancel() {}
    }

    private struct IdleCleaner: TextCleaning {
        func clean(_ transcript: String) async throws -> String { transcript }
    }

    private final class IdleInserter: TextInserting {
        func insert(_ text: String) async throws {}
    }

    /// Stands a text field in for the app being dictated into, drags the real pill across the
    /// screen with synthetic mouse events, and checks that the text field still has the keyboard
    /// and still receives what is sent to it. Then checks that the pill's place is remembered,
    /// restored by a fresh panel, and reset.
    static func pillDragKeepsTheKeyboardWhereItWas() async throws {
        // Where the pill is left is saved here, and read again from here by a fresh panel.
        let defaults = DebugSettings()

        // A non-activating panel can hold the keyboard while Voiced is not the active app, which is
        // the only way a window of this process gets to be key in a session where it cannot activate.
        let textWindow = NSPanel(
            contentRect: NSRect(x: 120, y: 420, width: 360, height: 120),
            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false
        )
        textWindow.title = "Text field"
        textWindow.becomesKeyOnlyIfNeeded = false
        textWindow.hidesOnDeactivate = false
        textWindow.isReleasedWhenClosed = false
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        textWindow.contentView = textView
        textWindow.makeKeyAndOrderFront(nil)
        textWindow.makeFirstResponder(textView)
        try await Task.sleep(for: .milliseconds(300))
        defer { textWindow.orderOut(nil) }

        let controller = DictationController(dependencies: .init(
            apiKey: { nil },
            makeCapture: { IdleCapture() },
            makeTranscription: { _ in IdleSession() },
            makeCleaner: { _ in IdleCleaner() },
            inserter: IdleInserter()
        ))
        let settings = PillSettings(defaults: defaults)
        let panel = IndicatorPanel(controller: controller, pill: settings)
        settings.isPlacing = true
        try await Task.sleep(for: .milliseconds(900))
        let window = panel.window
        try require(window.isVisible, "the pill did not appear for placing")
        try require(window.styleMask.contains(.nonactivatingPanel), "the pill's panel would activate Voiced when clicked")
        try require(!window.canBecomeKey && !window.canBecomeMain, "the pill's panel can take the keyboard")

        let keyWindowBefore = NSApp.keyWindow
        try require(keyWindowBefore === textWindow, "the text field's window is not the key window to begin with: key window is \(keyWindowBefore?.title ?? "none")")
        let pasteTargetBefore = NSApp.target(forAction: #selector(NSText.paste(_:)), to: nil, from: nil) as AnyObject?
        try require(pasteTargetBefore === textView, "a paste would not go to the text field to begin with")
        let activeBefore = NSApp.isActive
        let frontmostBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let originBefore = window.frame.origin

        // A hand on the mouse: press on the middle of the pill, move 300 pt right and 200 pt up, let go.
        let surface = panel.dragSurface
        let pillInWindow = surface.convert(surface.pillFrame(), to: nil)
        try require(!pillInWindow.isEmpty, "the pill has not reported where it is")
        let grip = NSPoint(x: pillInWindow.midX, y: pillInWindow.midY)
        try require(surface.hitTest(surface.superview?.convert(grip, from: nil) ?? grip) === surface, "a press on the pill does not reach it")
        try require(surface.hitTest(NSPoint(x: 4, y: 4)) == nil, "a press beside the pill is not let through")

        var pointer = window.convertPoint(toScreen: grip)
        surface.pointerLocation = { _ in pointer }
        func mouse(_ type: NSEvent.EventType) throws -> NSEvent {
            guard let event = NSEvent.mouseEvent(
                with: type, location: grip, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) else {
                throw Failure(description: "could not make a mouse event")
            }
            return event
        }
        window.sendEvent(try mouse(.leftMouseDown))
        for _ in 0..<10 {
            pointer.x += 30
            pointer.y += 20
            window.sendEvent(try mouse(.leftMouseDragged))
            try await Task.sleep(for: .milliseconds(15))
        }
        window.sendEvent(try mouse(.leftMouseUp))
        try await Task.sleep(for: .milliseconds(100))

        let moved = NSPoint(x: window.frame.origin.x - originBefore.x, y: window.frame.origin.y - originBefore.y)
        try require(moved == NSPoint(x: 300, y: 200), "the pill moved by \(moved), not by the 300 × 200 it was dragged")

        // The keyboard is where it was.
        try require(!window.isKeyWindow && !window.isMainWindow, "the pill became the key window")
        try require(NSApp.keyWindow === keyWindowBefore, "the key window changed during the drag")
        try require(textWindow.firstResponder === textView, "the text field lost the keyboard")
        try require(NSApp.isActive == activeBefore, "Voiced's active state changed during the drag")
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostBefore, "the frontmost app changed during the drag")

        // And text sent the way a paste arrives, to whatever has the keyboard, lands in the text field.
        let target = NSApp.target(forAction: #selector(NSText.paste(_:)), to: nil, from: nil) as AnyObject?
        try require(target === textView, "a paste would now go to \(target.map { String(describing: type(of: $0)) } ?? "nothing"), not to the text field")
        textView.insertText("Dictated text.", replacementRange: NSRange(location: NSNotFound, length: 0))
        try require(textView.string == "Dictated text.", "text sent after the drag did not land in the text field")

        // The place is remembered, and a fresh panel, as after a relaunch, goes back to it.
        guard let remembered = PillSettings(defaults: defaults).placement else {
            throw Failure(description: "the pill's place was not saved")
        }
        let relaunchedSettings = PillSettings(defaults: defaults)
        let relaunched = IndicatorPanel(controller: controller, pill: relaunchedSettings)
        relaunchedSettings.isPlacing = true
        try await Task.sleep(for: .milliseconds(900))
        try require(relaunched.window.frame.origin == window.frame.origin, "a fresh panel opened at \(relaunched.window.frame.origin), not where the pill was left (\(window.frame.origin))")
        relaunchedSettings.isPlacing = false

        // Reset puts it back.
        settings.reset()
        try await Task.sleep(for: .milliseconds(300))
        try require(window.frame.origin == originBefore, "Reset Position left the pill at \(window.frame.origin), not at \(originBefore)")
        try require(PillSettings(defaults: defaults).placement == nil, "Reset Position did not clear the saved place")

        settings.isPlacing = false
        try await Task.sleep(for: .milliseconds(500))

        print("""
            Pill drag check passed: dragged 300 × 200 pt with 12 synthetic mouse events; \
            pill is a non-activating panel that cannot become key or main; \
            the text field's window was the key window before and after, first responder unchanged, \
            Voiced active before and after: \(activeBefore), frontmost app \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none") before and after; \
            a paste is still routed to the text field, and text sent there landed in it; \
            place saved as x=\(String(format: "%.3f", remembered.x)) y=\(String(format: "%.3f", remembered.y)), restored by a fresh panel, cleared by reset.
            """)
    }

    // MARK: - The menu bar panel must take the keyboard for the hotkey control

    /// Opens the real menu bar panel by clicking the status item, presses the hotkey control in
    /// it, sends a key through the app's event queue, and checks that the hotkey changed.
    /// Returns the panel so it can be photographed. Leaves the hotkey as it found it.
    static func menuPanelTakesTheKeyboard(model: AppModel) async throws -> NSWindow {
        guard let statusWindow = NSApp.windows.first(where: { $0.className == "NSStatusBarWindow" }),
              let button = statusButton(in: statusWindow.contentView) else {
            throw Failure(description: "the menu bar item has no button to click")
        }
        let windowsBefore = Set(NSApp.windows.map(ObjectIdentifier.init))
        button.performClick(nil)
        try await Task.sleep(for: .milliseconds(900))
        guard let panel = NSApp.windows.first(where: { !windowsBefore.contains(ObjectIdentifier($0)) && $0.isVisible }) else {
            throw Failure(description: "clicking the menu bar item opened no window")
        }
        try require(panel.canBecomeKey, "the menu bar panel cannot take the keyboard, so the hotkey control in it cannot hear a key")

        let hotkeyBefore = model.hotkey
        defer { model.setHotkey(hotkeyBefore) }

        // SwiftUI builds no accessibility tree until an assistive app asks, so the control is found
        // by its focus ring: the menu's controls in order are Finish Setup (while setup is
        // incomplete), the hotkey control, the two rows, Settings and Quit.
        let controls = focusRings(in: panel.contentView)
        let index = model.needsSetup ? 1 : 0
        guard controls.count > index else {
            throw Failure(description: "the menu bar panel has \(controls.count) controls; the hotkey control is missing")
        }
        let hotkeyControl = controls[index]
        let click = hotkeyControl.convert(NSPoint(x: hotkeyControl.bounds.midX, y: hotkeyControl.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: click, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) else {
                throw Failure(description: "could not make a mouse event")
            }
            panel.sendEvent(event)
            try await Task.sleep(for: .milliseconds(80))
        }
        try await Task.sleep(for: .milliseconds(300))
        try require(model.isRecordingHotkey, "pressing the hotkey control in the menu did not start it listening")

        // Right ⌘ down and up, on its own, through the app's event queue like a key from the keyboard.
        let target = hotkeyBefore.modifierKey == .rightCommand ? ModifierKey.rightControl : .rightCommand
        let flags: NSEvent.ModifierFlags = target == .rightCommand ? .command : .control
        for modifierFlags in [flags, []] {
            guard let event = NSEvent.keyEvent(
                with: .flagsChanged, location: .zero, modifierFlags: modifierFlags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: target.rawValue
            ) else {
                throw Failure(description: "could not make a key event")
            }
            NSApp.postEvent(event, atStart: false)
            try await Task.sleep(for: .milliseconds(150))
        }
        try require(model.hotkey == Hotkey(modifierKey: target), "the hotkey control in the menu did not take the key: hotkey is \(model.hotkey.displayName)")
        try require(!model.isRecordingHotkey, "the hotkey control in the menu kept listening after it took a key")

        // The pill's placement, from the same panel: a click on each half of its segmented control.
        func segmentedControls(in view: NSView?) -> [NSSegmentedControl] {
            guard let view else { return [] }
            return ((view as? NSSegmentedControl).map { [$0] } ?? []) + view.subviews.flatMap { segmentedControls(in: $0) }
        }
        guard let placementControl = segmentedControls(in: panel.contentView).first, placementControl.segmentCount == PillPlacementMode.allCases.count else {
            throw Failure(description: "the pill placement control is not in the menu bar panel")
        }
        let modeBefore = model.pill.mode
        defer { model.pill.mode = modeBefore }
        func clickSegment(_ segment: Int) async throws {
            let width = placementControl.bounds.width / CGFloat(placementControl.segmentCount)
            let point = placementControl.convert(NSPoint(x: width * (CGFloat(segment) + 0.5), y: placementControl.bounds.midY), to: nil)
            try await clickControlThatFollowsTheMouse(at: point, in: panel)
        }
        // The choice has to hold for the very next dictation, so one is begun right after each
        // click, the way the hotkey begins it, with a pill that reads the same settings.
        let controller = DictationController(dependencies: .init(
            apiKey: { "check-placeholder" },
            makeCapture: { DebugSnapshots.ScriptedCapture() },
            makeTranscription: { _ in DebugSnapshots.ScriptedSession() },
            makeCleaner: { _ in DebugSnapshots.ScriptedCleaner() },
            inserter: DebugSnapshots.DiscardingInserter()
        ))
        let indicator = IndicatorPanel(controller: controller, pill: model.pill)
        let appToAskBefore = model.pill.textLookup.appToAsk
        // The app in front in this session is not one Voiced may question; this process is.
        model.pill.textLookup.appToAsk = { PillTextLookup.Target(pid: getpid()) }
        defer { model.pill.textLookup.appToAsk = appToAskBefore }
        /// Returns how the dictation's pill was placed; `nil` when text was not asked for.
        func dictate() async throws -> PillNearText? {
            if model.pill.mode == .nextToText {
                model.pill.textLookup.begin()
            }
            controller.begin()
            try await Task.sleep(for: .milliseconds(700))
            try require(controller.phase == .recording, "the scripted dictation after a click in the menu did not start: \(controller.phase)")
            let placed = indicator.placementForDictation
            controller.cancel()
            try await Task.sleep(for: .milliseconds(600))
            return placed
        }

        // The other choice first, so that each click changes something.
        for mode in modeBefore == .nextToText ? [PillPlacementMode.fixedPlace, .nextToText] : [.nextToText, .fixedPlace] {
            guard let segment = PillPlacementMode.allCases.firstIndex(of: mode) else { continue }
            try await clickSegment(segment)
            try require(model.pill.mode == mode, "a click on \(mode.title) in the menu left the placement at \(model.pill.mode.title)")
            let asked = try await dictate() != nil
            try require(asked == (mode == .nextToText), "the dictation right after choosing \(mode.title) in the menu \(asked ? "still asked" : "did not ask") where the text is")
        }

        let cleanup = try await cleanupIsSwitchedInTheMenu(panel, model: model)

        print("""
            Menu panel check passed: clicking the status item opened \(panel.className) \
            (can become key: \(panel.canBecomeKey), is key now: \(panel.isKeyWindow), non-activating: \(panel.styleMask.contains(.nonactivatingPanel))); \
            the hotkey control in it started listening when pressed and took \(target.displayName) from the event queue; hotkey put back to \(hotkeyBefore.displayName); \
            starting from \(modeBefore.title), a click on each half of the pill placement control set the other choice and then that one again, and the dictation begun right after each click was placed by that choice; \
            placement put back to \(modeBefore.title); \
            \(cleanup)
            """)
        return panel
    }

    private actor QuickSession: TranscriptionSession {
        static let transcript = "um a scripted dictation"

        func start() {}
        func send(audio: Data) {}
        func cancel() {}

        func finish() async throws -> TranscriptionResult {
            try await Task.sleep(for: .milliseconds(300))
            return TranscriptionResult(text: Self.transcript, isComplete: true)
        }
    }

    private struct QuickCleaner: TextCleaning {
        static let cleaned = "A scripted dictation."

        func clean(_ transcript: String) async throws -> String {
            try await Task.sleep(for: .milliseconds(300))
            return Self.cleaned
        }
    }

    /// Takes long enough over the text for the pill's words to be read while it is on its way.
    private final class SlowInserter: TextInserting {
        private(set) var inserted: [String] = []

        func insert(_ text: String) async throws {
            try await Task.sleep(for: .milliseconds(500))
            inserted.append(text)
        }
    }

    /// Clicks the Cleanup switch in the real menu bar panel and, right after each click, runs a
    /// scripted dictation that reads the same setting. With the switch off, no cleaner is made,
    /// the transcript goes in as it came and the pill never says Polishing…; with it on, the
    /// cleaned text goes in after the pill has said so. Leaves the setting as it found it.
    private static func cleanupIsSwitchedInTheMenu(_ panel: NSWindow, model: AppModel) async throws -> String {
        func switches(in view: NSView?) -> [NSSwitch] {
            guard let view else { return [] }
            return ((view as? NSSwitch).map { [$0] } ?? []) + view.subviews.flatMap { switches(in: $0) }
        }
        guard let control = switches(in: panel.contentView).first else {
            throw Failure(description: "the Cleanup switch is not in the menu bar panel")
        }
        let wasOn = model.cleanup.isOn
        defer { model.cleanup.isOn = wasOn }
        func click() async throws {
            let point = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
            try await clickControlThatFollowsTheMouse(at: point, in: panel)
        }

        let pill = PillSettings(defaults: DebugSettings())
        pill.mode = .fixedPlace

        var cleanersMade = 0
        let inserter = SlowInserter()
        let controller = DictationController(dependencies: .init(
            apiKey: { "check-placeholder" },
            makeCapture: { DebugSnapshots.ScriptedCapture() },
            makeTranscription: { _ in QuickSession() },
            makeCleaner: { _ in
                cleanersMade += 1
                return QuickCleaner()
            },
            cleanupIsOn: { model.cleanup.isOn },
            inserter: inserter,
            minimumHold: .zero
        ))
        let indicator = IndicatorPanel(controller: controller, pill: pill)
        /// One dictation, begun the way the hotkey begins it. Returns what the pill said, in
        /// order, from the release until the text was in.
        func dictate() async throws -> [String] {
            controller.begin()
            try await Task.sleep(for: .milliseconds(500))
            try require(controller.phase == .recording, "the scripted dictation after a click on the Cleanup switch did not start: \(controller.phase)")
            controller.end()
            var words: [String] = []
            let deadline = ContinuousClock.now + .seconds(10)
            while controller.phase != .idle {
                try require(ContinuousClock.now < deadline, "the scripted dictation did not end: \(controller.phase)")
                if case let .working(word) = indicator.contentShown, words.last != word {
                    words.append(word)
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            try await Task.sleep(for: .milliseconds(600))
            try require(!indicator.window.isVisible, "the pill stayed on screen after the dictation")
            return words
        }

        // The other choice first, so that each click changes something.
        for isOn in [!wasOn, wasOn] {
            try await click()
            try require(model.cleanup.isOn == isOn, "a click on the Cleanup switch in the menu left cleanup \(model.cleanup.isOn ? "on" : "off")")
            try require(DebugRun.settings.object(forKey: CleanupSetting.defaultsKey) as? Bool == isOn, "the choice made with the Cleanup switch was not saved")
            let madeBefore = cleanersMade
            let words = try await dictate()
            let made = cleanersMade - madeBefore
            let text = inserter.inserted.last ?? ""
            if isOn {
                try require(made == 1 && text == QuickCleaner.cleaned, "with Cleanup on, \(made) cleaners were made and the text went in \(text == QuickSession.transcript ? "as it came" : "changed")")
                try require(words == ["Transcribing…", "Polishing…"], "with Cleanup on, the pill said \(words)")
            } else {
                try require(made == 0 && text == QuickSession.transcript, "with Cleanup off, \(made) cleaners were made and the text went in \(text == QuickSession.transcript ? "as it came" : "changed")")
                try require(words == ["Transcribing…"], "with Cleanup off, the pill said \(words)")
            }
        }
        try require(inserter.inserted.count == 2, "two dictations inserted \(inserter.inserted.count) texts")

        return """
            starting from Cleanup \(wasOn ? "on" : "off"), a click on its switch set the other choice and then that one again, each saved; \
            the dictation begun right after switching it off made no cleaner, put the transcript in as it came and showed Transcribing… and never Polishing…, \
            and the one after switching it on was cleaned up and showed Polishing…; Cleanup put back to \(wasOn ? "on" : "off").
            """
    }

    /// A release of the mouse button at one place in a window, sent again every half second
    /// until it is stopped.
    private final class RepeatedRelease {
        private let point: NSPoint
        private let window: NSWindow
        private var timer: Timer?
        private(set) var sentAgain = 0

        init(at point: NSPoint, in window: NSWindow) {
            self.point = point
            self.window = window
        }

        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) else {
                throw Failure(description: "could not make a mouse event")
            }
            return event
        }

        func start() {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sendAgain()
                }
            }
            // The common modes, so that it fires while a control is following the mouse.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        private func sendAgain() {
            guard let release = try? event(.leftMouseUp) else { return }
            sentAgain += 1
            NSApp.postEvent(release, atStart: true)
        }
    }

    /// A click on a control that follows the mouse in a loop of its own until the button comes
    /// up, as a segmented control and a switch do. The press does not return before the control
    /// has seen the release, so the release has to be waiting in the queue when the press is
    /// delivered. Should that release go missing, the press would wait for good and this copy
    /// with it, so the release is sent again for as long as the press has not returned.
    private static func clickControlThatFollowsTheMouse(at point: NSPoint, in window: NSWindow) async throws {
        let release = RepeatedRelease(at: point, in: window)
        let press = try release.event(.leftMouseDown)
        NSApp.postEvent(try release.event(.leftMouseUp), atStart: false)
        release.start()
        window.sendEvent(press)
        release.stop()
        if release.sentAgain > 0 {
            print("A click's release went missing and was sent again \(release.sentAgain) time(s) before the control let go.")
        }
        try await Task.sleep(for: .milliseconds(250))
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusButton(in: subview) { return button }
        }
        return nil
    }

    // MARK: - The pill goes next to the text

    /// A text view in this process stands in for the app being dictated into, and is asked
    /// through the real Accessibility calls: a process may question itself without the
    /// permission. Runs a scripted dictation for each of several insertion points and checks
    /// that the pill sits close to the real line, AppKit's own figure for it, without covering it.
    static func pillGoesNextToTheText(into directory: URL) async throws {
        guard let screen = NSScreen.main else { throw Failure(description: "no display") }
        let visible = screen.visibleFrame
        let textWindow = NSPanel(
            contentRect: NSRect(x: visible.midX - 220, y: visible.midY + 20, width: 440, height: 150),
            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false
        )
        textWindow.title = "Any App"
        textWindow.becomesKeyOnlyIfNeeded = false
        textWindow.hidesOnDeactivate = false
        textWindow.isReleasedWhenClosed = false
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { throw Failure(description: "no text view") }
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        let button = NSButton(title: "A Button", target: nil, action: nil)
        button.frame = NSRect(x: 12, y: 8, width: 100, height: 24)
        scrollView.frame = NSRect(x: 0, y: 40, width: 440, height: 110)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 150))
        content.addSubview(scrollView)
        content.addSubview(button)
        textWindow.contentView = content
        textWindow.makeKeyAndOrderFront(nil)
        defer { textWindow.orderOut(nil) }

        let controller = DictationController(dependencies: .init(
            apiKey: { "check-placeholder" },
            makeCapture: { DebugSnapshots.ScriptedCapture() },
            makeTranscription: { _ in DebugSnapshots.ScriptedSession() },
            makeCleaner: { _ in DebugSnapshots.ScriptedCleaner() },
            inserter: DebugSnapshots.DiscardingInserter()
        ))
        let pill = PillSettings(defaults: DebugSettings())
        pill.mode = .nextToText
        // The app in front in this session is not one Voiced may question; this process is.
        pill.textLookup.appToAsk = { PillTextLookup.Target(pid: getpid()) }
        let panel = IndicatorPanel(controller: controller, pill: pill)

        struct Outcome {
            var placed: PillNearText?
            var pill: CGRect
            var line: CGRect
            var lookup: String
        }
        /// One dictation, begun the way the hotkey begins it; the pill's place while it records.
        func dictate() async throws -> Outcome {
            pill.textLookup.begin()
            controller.begin()
            try await Task.sleep(for: .milliseconds(800))
            try require(controller.phase == .recording && panel.window.isVisible, "the scripted dictation did not start: \(controller.phase)")
            let outcome = Outcome(
                placed: panel.placementForDictation,
                pill: panel.pillFrameOnScreen,
                line: textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: nil),
                lookup: pill.textLookup.answer?.logDescription ?? "no answer"
            )
            return outcome
        }
        func finish() async throws {
            controller.cancel()
            try await Task.sleep(for: .milliseconds(700))
            try require(!panel.window.isVisible, "the pill stayed on screen after the dictation")
        }
        func describe(_ rect: CGRect) -> String {
            "\(Int(rect.width.rounded()))×\(Int(rect.height.rounded())) at x=\(Int(rect.minX.rounded())) y=\(Int(rect.minY.rounded()))"
        }
        /// Sideways the pill is centred on `x`, or as near to that as the text view's left and
        /// right edges allow, and the pill as drawn is between those edges. The edges are
        /// AppKit's own figure for the frame the text view gives through Accessibility.
        func checkSideways(_ outcome: Outcome, centredOn x: CGFloat, _ name: String) throws -> String {
            let field = textView.accessibilityFrame()
            let expected = PillNearText.withinField(x, field: field)
            try require(abs(outcome.pill.midX - expected) <= 1.5, "\(name): the pill's middle is \(Int(outcome.pill.midX - expected)) pt from where it belongs (insertion point at x=\(Int(x)), field \(describe(field)))")
            try require(outcome.pill.minX >= field.minX - 1 && outcome.pill.maxX <= field.maxX + 1, "\(name): the pill (\(describe(outcome.pill))) reaches past the field (\(describe(field)))")
            let moved = Int((expected - x).rounded())
            return moved == 0 ? "centred on it" : "moved \(abs(moved)) pt \(moved > 0 ? "right" : "left") to stay within the field"
        }
        /// The pill is by the line, not over it, and centred on the insertion point where the
        /// field has room for that.
        func checkBeside(_ outcome: Outcome, _ name: String, expectBelow: Bool) throws -> String {
            try require(outcome.placed?.source == .insertionPoint, "\(name): placed by \(outcome.placed?.source.rawValue ?? "nothing") (\(outcome.lookup))")
            let below = outcome.pill.maxY <= outcome.line.minY
            let above = outcome.pill.minY >= outcome.line.maxY
            try require(below || above, "\(name): the pill (\(describe(outcome.pill))) covers the line (\(describe(outcome.line)))")
            try require(below == expectBelow, "\(name): the pill is \(below ? "below" : "above") the line")
            let distance = below ? outcome.line.minY - outcome.pill.maxY : outcome.pill.minY - outcome.line.maxY
            try require(distance <= 6 + outcome.line.height + 1, "\(name): the pill is \(Int(distance)) pt from the line")
            let sideways = try checkSideways(outcome, centredOn: outcome.line.minX, name)
            try require(screen.visibleFrame.contains(outcome.pill), "\(name): the pill is partly off the screen")
            return "\(name): \(Int(distance.rounded())) pt \(below ? "below" : "above") the line, \(sideways)"
        }

        /// The text window and the pill as they sit on screen.
        func picture(_ name: String) throws {
            let frame = textWindow.frame.union(panel.pillFrameOnScreen).insetBy(dx: -16, dy: -16)
            try DebugSnapshots.capture([textWindow, panel.window], showing: frame, to: directory.appendingPathComponent(name))
        }

        var lines: [String] = []
        let text = "Dear all, thank you for coming on such short notice.\nThe second line is the one being edited here, in the middle.\nA third line follows it."
        textView.string = text
        textWindow.makeFirstResponder(textView)

        // In the middle of a line.
        textView.setSelectedRange(NSRange(location: 80, length: 0))
        var outcome = try await dictate()
        lines.append(try checkBeside(outcome, "mid-line", expectBelow: true))
        textView.updateInsertionPointStateAndRestartTimer(true)
        try picture("pill-next-to-text-below.png")
        // Dragged away from the text: for this dictation only, the fixed place stays as it was.
        panel.window.setFrameOrigin(NSPoint(x: panel.window.frame.minX + 40, y: panel.window.frame.minY - 30))
        panel.dragSurface.onDragEnded()
        try require(pill.placement == nil, "a drag away from the text was saved as the fixed place")
        try await finish()

        // At the very end of the text.
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        outcome = try await dictate()
        lines.append(try checkBeside(outcome, "end of the text", expectBelow: true))
        try await finish()

        // On an empty last line, where the nearest character with a box is on the line above.
        textView.string = text + "\n"
        textView.setSelectedRange(NSRange(location: (text as NSString).length + 1, length: 0))
        outcome = try await dictate()
        lines.append(try checkBeside(outcome, "empty last line", expectBelow: true))
        try await finish()

        // In an empty text.
        textView.string = ""
        outcome = try await dictate()
        lines.append(try checkBeside(outcome, "empty text", expectBelow: true))
        // The case the rule is for: centred on the insertion point, the pill would hang over
        // the left edge of the box.
        try require(outcome.pill.midX - outcome.line.minX > 40, "empty text: the pill was not moved in from the field's left edge")
        try picture("pill-next-to-text-empty.png")
        try await finish()

        // A selection.
        textView.string = text
        textView.setSelectedRange(NSRange(location: 57, length: 11))
        outcome = try await dictate()
        try require(outcome.placed?.source == .insertionPoint, "selection: placed by \(outcome.placed?.source.rawValue ?? "nothing")")
        try require(outcome.pill.maxY <= outcome.line.minY, "selection: the pill is not under it")
        lines.append("selection: under it, \(try checkSideways(outcome, centredOn: outcome.line.midX, "selection"))")
        try await finish()

        // No room below: the window at the bottom of the screen, the insertion point on the last
        // line of a text that fills it.
        let longText = text + "\nA fourth line.\nA fifth line.\nA sixth.\nThe last line is the one being edited."
        textView.string = longText
        textWindow.setFrameOrigin(NSPoint(x: visible.midX - 220, y: visible.minY))
        textView.setSelectedRange(NSRange(location: (longText as NSString).length - 13, length: 0))
        textView.scrollToEndOfDocument(nil)
        try await Task.sleep(for: .milliseconds(300))
        outcome = try await dictate()
        lines.append(try checkBeside(outcome, "no room below", expectBelow: false))
        textView.updateInsertionPointStateAndRestartTimer(true)
        try picture("pill-next-to-text-above.png")
        try await finish()
        textWindow.setFrameOrigin(NSPoint(x: visible.midX - 220, y: visible.midY + 20))
        textView.string = text

        // The keyboard on something that is not text, which is all an app built on Electron
        // gives: the bottom of the window that has the keyboard, on that window's display.
        let fixedPlace = PillPlacement.defaultAnchor(on: .init(id: "", visibleFrame: visible))
        textWindow.makeFirstResponder(button)
        outcome = try await dictate()
        try require(outcome.placed?.source == .window, "a button: placed by \(outcome.placed?.source.rawValue ?? "nothing") (\(outcome.lookup))")
        try require(textWindow.frame.contains(outcome.pill), "a button: the pill (\(describe(outcome.pill))) is not inside the window (\(describe(textWindow.frame)))")
        try require(abs(outcome.pill.midX - textWindow.frame.midX) <= 1.5, "a button: the pill is not centred in the window")
        try require(outcome.pill.minY - textWindow.frame.minY <= 24, "a button: the pill is \(Int(outcome.pill.minY - textWindow.frame.minY)) pt above the bottom of the window")
        lines.append("keyboard on a button: bottom of the window (\(outcome.lookup))")
        try picture("pill-in-the-window.png")
        try await finish()

        // An app that cannot be asked: the fixed place.
        textWindow.makeFirstResponder(textView)
        pill.textLookup.appToAsk = {
            PillTextLookup.Target(pid: NSWorkspace.shared.frontmostApplication.map(\.processIdentifier).flatMap { $0 == getpid() ? nil : $0 } ?? 1)
        }
        outcome = try await dictate()
        try require(outcome.placed?.source == .fixedPlace, "another app: placed by \(outcome.placed?.source.rawValue ?? "nothing")")
        lines.append("an app Voiced may not question: fixed place (\(outcome.lookup))")
        try await finish()
        pill.textLookup.appToAsk = { PillTextLookup.Target(pid: getpid()) }

        // The setting at Fixed Place: text is not asked for at all.
        pill.mode = .fixedPlace
        outcome = try await dictate()
        try require(outcome.placed == nil, "Fixed Place: the pill was placed by \(outcome.placed?.source.rawValue ?? "nothing")")
        try require(abs(outcome.pill.midX - fixedPlace.x) <= 1.5 && abs(outcome.pill.minY - fixedPlace.y) <= 1.5, "Fixed Place: the pill is not at the fixed place")
        lines.append("setting at Fixed Place: fixed place")
        try await finish()

        print("Pill-next-to-text check passed, asking a text view in this process through Accessibility:\n  " + lines.joined(separator: "\n  "))
    }

    // MARK: - The read that switches on another app's accessibility

    /// The read is made only for an Electron or Chromium app that was in front and gave no
    /// focused element, and once for each such app. No app is asked anything here: the lookup,
    /// the kind of app and the read itself are stand-ins, and process numbers stand in for apps.
    static func accessibilityIsSwitchedOnOncePerApp() async throws {
        struct App {
            var kind = AppKind.electron
            var focus: Int32 = AccessibilityWake.noFocusedElement
        }
        let app = OSAllocatedUnfairLock(initialState: App())
        let reads = OSAllocatedUnfairLock(initialState: [pid_t]())
        let lookup = PillTextLookup()
        lookup.locate = { _, _ in
            var answer = FocusedTextAnswer()
            answer.focus = app.withLock { $0.focus }
            return answer
        }
        lookup.kind = { _ in app.withLock { $0.kind } }
        lookup.wake = { pid in
            reads.withLock { $0.append(pid) }
            return 0
        }
        var target = PillTextLookup.Target(pid: 0)
        lookup.appToAsk = { target }
        func dictate(into pid: pid_t, kind: AppKind = .electron, focus: Int32 = AccessibilityWake.noFocusedElement, voicedInFront: Bool = false) async throws {
            target = PillTextLookup.Target(pid: pid, voicedInFront: voicedInFront)
            app.withLock { $0 = App(kind: kind, focus: focus) }
            lookup.begin()
            try await Task.sleep(for: .milliseconds(250))
        }

        try await dictate(into: 101)
        try require(reads.withLock { $0 } == [101], "an Electron app with no focused element was not read: \(reads.withLock { $0 })")
        try await dictate(into: 101)
        try await dictate(into: 101)
        try require(reads.withLock { $0 } == [101], "the same app was read more than once: \(reads.withLock { $0 })")
        try await dictate(into: 102, kind: .other)
        try await dictate(into: 108, kind: .unknown)
        try await dictate(into: 103, focus: 0)
        try await dictate(into: 104, focus: -25204)
        try await dictate(into: 105, voicedInFront: true)
        try require(reads.withLock { $0 } == [101], "an app that should be left alone was read: \(reads.withLock { $0 })")
        try await dictate(into: 106, kind: .chromium)
        try await dictate(into: 107)
        try require(reads.withLock { $0 } == [101, 106, 107], "a second and third app were not each read once: \(reads.withLock { $0 })")
        let moved = try await pillMovesToTheTextOnceTheAppAnswers()
        print("""
            Accessibility-switch check passed, with stand-ins and no app asked: an Electron app that gave no focused element was read once in three dictations; \
            an app of another kind, one of unknown kind, one that gave a focused element, one that timed out, and the app behind Voiced's own menu were not read; \
            a Chromium app and a second Electron app were each read once. \(moved)
            """)
    }

    /// After the read, the app is asked again while the hotkey is held, and the pill of that
    /// same dictation moves from the bottom of the window to the text when the app answers.
    /// A stand-in answers here: nothing for the first three questions, then a text position.
    private static func pillMovesToTheTextOnceTheAppAnswers() async throws -> String {
        guard let screen = NSScreen.main else { throw Failure(description: "no display") }
        let visible = screen.visibleFrame
        let window = CGRect(x: visible.midX - 220, y: visible.midY - 100, width: 440, height: 300)
        let field = CGRect(x: window.minX + 20, y: window.maxY - 120, width: 400, height: 100)
        let line = CGRect(x: field.minX + 150, y: field.maxY - 30, width: 0, height: 17)

        struct Script {
            /// How many questions go unanswered before the app says where its text is; `nil` for never.
            var silentFor: Int? = 3
            var asked = 0
        }
        let script = OSAllocatedUnfairLock(initialState: Script())
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let pill = PillSettings(defaults: DebugSettings())
        pill.mode = .nextToText
        pill.textLookup.appToAsk = { PillTextLookup.Target(pid: 120) }
        pill.textLookup.kind = { _ in .electron }
        pill.textLookup.wake = { _ in
            reads.withLock { $0 += 1 }
            return 0
        }
        pill.textLookup.locate = { _, _ in
            let answers = script.withLock { script -> Bool in
                script.asked += 1
                return script.silentFor.map { script.asked > $0 } ?? false
            }
            var answer = FocusedTextAnswer()
            if answers {
                answer.focus = 0
                answer.geometry = FocusedTextGeometry(insertionPoint: .init(rect: line, mayBeOneLineUp: false), field: field)
            } else {
                answer.focus = AccessibilityWake.noFocusedElement
                answer.geometry = FocusedTextGeometry(window: window)
            }
            return answer
        }
        let controller = DictationController(dependencies: .init(
            apiKey: { "check-placeholder" },
            makeCapture: { DebugSnapshots.ScriptedCapture() },
            makeTranscription: { _ in DebugSnapshots.ScriptedSession() },
            makeCleaner: { _ in DebugSnapshots.ScriptedCleaner() },
            inserter: DebugSnapshots.DiscardingInserter()
        ))
        let panel = IndicatorPanel(controller: controller, pill: pill)
        func asked() -> Int { script.withLock { $0.asked } }
        func hold(for duration: Duration) async throws {
            pill.textLookup.begin()
            controller.begin()
            try await Task.sleep(for: duration)
        }
        /// A hold is shown a quarter of a second after it begins, by a real clock, and the pill
        /// has no place before that. On a Mac that is busy, or that holds back the timers of an
        /// app that is not in front, that can come later than the 400 ms a hold here lasts, so
        /// a pill that has no place yet is waited for before its place is judged.
        func waitForThePillToBePlaced() async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            while panel.placementForDictation == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        func release() async throws {
            pill.textLookup.holdEnded()
            controller.cancel()
            try await Task.sleep(for: .milliseconds(700))
            try require(!panel.window.isVisible, "the pill stayed on screen after the dictation")
        }

        // The first dictation into the app. 400 ms in, the pill is up and the app has said nothing yet.
        try await hold(for: .milliseconds(400))
        try await waitForThePillToBePlaced()
        try require(panel.window.isVisible && panel.placementForDictation?.source == .window, "before the app answered, the pill was placed by \(panel.placementForDictation?.source.rawValue ?? "nothing")")
        let inWindow = panel.pillFrameOnScreen
        // The fourth question, half a second after the read, is answered.
        try await Task.sleep(for: .milliseconds(500))
        try require(panel.placementForDictation?.source == .insertionPoint, "after the app answered, the pill was still placed by \(panel.placementForDictation?.source.rawValue ?? "nothing") (asked \(asked()) times)")
        let byText = panel.pillFrameOnScreen
        try require(byText.maxY <= line.minY && line.minY - byText.maxY <= 8 && abs(byText.midX - line.midX) <= 1.5, "the pill did not move to the text: it is at \(byText), the line at \(line)")
        try require(byText != inWindow, "the pill did not move")
        let questions = asked()
        try require(questions == 4 && reads.withLock { $0 } == 1, "the app was asked \(questions) times and read \(reads.withLock { $0 }) times")
        try await Task.sleep(for: .milliseconds(1200))
        try require(asked() == questions, "the app was asked again after it had answered")
        try await release()

        // The next dictation into the same app is answered at once: one question, no read, no move.
        script.withLock { $0 = Script(silentFor: 0) }
        try await hold(for: .milliseconds(600))
        try require(panel.placementForDictation?.source == .insertionPoint && asked() == 1 && reads.withLock { $0 } == 1, "the second dictation was placed by \(panel.placementForDictation?.source.rawValue ?? "nothing") after \(asked()) questions")
        try await release()

        // An app that never answers is asked a few times while the key is held, and no longer.
        script.withLock { $0 = Script(silentFor: nil) }
        pill.textLookup.appToAsk = { PillTextLookup.Target(pid: 121) }
        let began = ContinuousClock.now
        try await hold(for: .milliseconds(400))
        try await waitForThePillToBePlaced()
        try require(panel.placementForDictation?.source == .window, "an app that says nothing got the pill by \(panel.placementForDictation?.source.rawValue ?? "nothing")")
        let held = ContinuousClock.now - began
        try await release()
        let whileHeld = asked()
        // The first question, the ones the schedule had come to while the key was down, and one to spare.
        let mostWhileHeld = 2 + AccessibilityWake.askAgainAfter.filter { $0 <= held }.count
        try await Task.sleep(for: .milliseconds(1500))
        try require(asked() == whileHeld && whileHeld <= mostWhileHeld, "an app that says nothing was asked \(asked()) times, \(asked() - whileHeld) of them after the key came up, where \(mostWhileHeld) were due at most")
        // And for a whole hold: once at the start and then as often as the schedule says.
        pill.textLookup.appToAsk = { PillTextLookup.Target(pid: 122) }
        script.withLock { $0 = Script(silentFor: nil) }
        try await hold(for: .milliseconds(2400))
        try require(asked() == 1 + AccessibilityWake.askAgainAfter.count, "through a long hold, an app that says nothing was asked \(asked()) times")
        try require(panel.placementForDictation?.source == .window, "the pill left the window though the app said nothing")
        try await release()
        return "Asked again after the read, the app answered on the fourth question and the pill moved from the bottom of the window to the text during the same hold; an app that never answers was asked \(1 + AccessibilityWake.askAgainAfter.count) times in a long hold and not at all after the key came up."
    }

    // MARK: - Settings fits any display

    /// The scroll view that Settings scrolls in: the outermost one in the window.
    private static func settingsScrollView(in window: NSWindow) -> NSScrollView? {
        func find(_ view: NSView?) -> NSScrollView? {
            guard let view else { return nil }
            if let scrollView = view as? NSScrollView { return scrollView }
            for subview in view.subviews {
                if let found = find(subview) { return found }
            }
            return nil
        }
        return find(window.contentView)
    }

    /// How far the content can be scrolled, and how far it has been.
    private static func scrolling(in window: NSWindow) -> (room: CGFloat, offset: CGFloat)? {
        guard let scrollView = settingsScrollView(in: window), let document = scrollView.documentView else { return nil }
        let clip = scrollView.contentView.bounds
        return (max(document.frame.height - clip.height, 0), clip.minY - document.frame.minY)
    }

    /// Turns the scroll wheel over the middle of the window, the way a hand would: the event
    /// goes to whatever view is under the pointer and finds its own way to the scroll view.
    private static func turnWheel(in window: NSWindow, by points: Int32) async throws {
        guard let content = window.contentView,
              let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -points, wheel2: 0, wheel3: 0),
              let event = NSEvent(cgEvent: wheel) else {
            throw Failure(description: "could not make a scroll wheel event")
        }
        let middle = NSPoint(x: content.bounds.midX, y: content.bounds.midY)
        guard let target = content.hitTest(content.superview?.convert(middle, from: content) ?? middle) else {
            throw Failure(description: "nothing is under the pointer in the middle of Settings")
        }
        target.scrollWheel(with: event)
        try await Task.sleep(for: .milliseconds(250))
    }

    /// The real Settings window, on whatever display this Mac has: inside the visible area, and
    /// scrolling to its last row when it had to be made shorter than its content.
    static func settingsWindowFitsItsScreen(_ window: NSWindow) async throws {
        guard let visible = window.screen?.visibleFrame else { throw Failure(description: "Settings is on no screen") }
        try await Task.sleep(for: .milliseconds(500))
        let frame = window.frame
        try require(frame.height <= visible.height + 0.5, "Settings is \(Int(frame.height)) pt tall on a screen with \(Int(visible.height)) pt between the menu bar and the Dock")
        try require(frame.minY >= visible.minY - 0.5 && frame.maxY <= visible.maxY + 0.5, "Settings reaches outside the visible area: \(frame) in \(visible)")
        guard let before = scrolling(in: window) else { throw Failure(description: "Settings has no scroll view") }
        var note = "its content fits, so nothing scrolls"
        if before.room > 0.5 {
            for _ in 0..<12 {
                try await turnWheel(in: window, by: 200)
            }
            guard let after = scrolling(in: window) else { throw Failure(description: "Settings lost its scroll view") }
            try require(abs(after.offset - after.room) <= 1, "the scroll wheel took Settings \(Int(after.offset)) pt of the \(Int(after.room)) pt to its last row")
            for _ in 0..<12 {
                try await turnWheel(in: window, by: -200)
            }
            note = "its content is \(Int(before.room)) pt taller, and the scroll wheel reaches the last row"
        }
        print("Settings-on-this-display check passed: the real window is \(Int(frame.width)) × \(Int(frame.height)) pt inside a visible area \(Int(visible.height)) pt tall; \(note).")
    }

    /// Settings as it would be on smaller displays, with the visible height handed in: every
    /// height from far smaller than any Mac's to larger than the content, for the window with
    /// and without the rows a hidden menu bar icon adds. Saves pictures at a 13-inch and a
    /// 14-inch laptop's height.
    static func settingsFitsSmallDisplays(into directory: URL) async throws {
        struct Variant {
            var name: String
            var file: String
            var model: () -> AppModel
        }
        let variants = [
            Variant(name: "icon visible", file: "", model: { DebugSnapshots.fixedModel(microphone: true, accessibility: true, key: true) }),
            Variant(name: "icon hidden", file: "-icon-hidden", model: {
                DebugSnapshots.fixedModel(microphone: true, accessibility: true, key: true, menuBarIconHidden: true)
            }),
        ]
        // Default scaling, a 37 pt menu bar (the notch) and an 80 pt Dock.
        let pictured: [(name: String, file: String, visibleHeight: CGFloat)] = [
            ("13-inch MacBook Air, 1470 × 956", "13-inch", 956 - 37 - 80),
            ("14-inch MacBook Pro, 1512 × 982", "14-inch", 982 - 37 - 80),
        ]

        /// Settings in a window of its own, told the display's visible height.
        func open(_ variant: Variant, visibleHeight: CGFloat, appearance: NSAppearance.Name = .aqua) async throws -> NSWindow {
            let window = DebugSnapshots.KeyableWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Voiced Settings"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(Monochrome.canvas)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            let hosting = NSHostingView(rootView: SettingsView(visibleScreenHeight: visibleHeight).environment(variant.model()))
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)
            window.center()
            window.orderFront(nil)
            // The window tells the view how tall its title bar is; the view then settles on a height.
            for _ in 0..<3 {
                try await Task.sleep(for: .milliseconds(120))
                window.setContentSize(hosting.fittingSize)
            }
            return window
        }

        var lines: [String] = []
        for variant in variants {
            let roomy = try await open(variant, visibleHeight: 10_000)
            let natural = roomy.frame.height
            let naturalScrolling = scrolling(in: roomy)
            roomy.orderOut(nil)
            try require(naturalScrolling?.room ?? 1 <= 0.5, "\(variant.name): Settings scrolls even with all the room it wants")

            var scrolled = 0
            var whole = 0
            for visibleHeight in stride(from: CGFloat(400), through: 1200, by: 40) {
                let window = try await open(variant, visibleHeight: visibleHeight)
                defer { window.orderOut(nil) }
                let height = window.frame.height
                try require(height <= visibleHeight + 0.5, "\(variant.name): \(Int(height)) pt tall where \(Int(visibleHeight)) pt can be seen")
                guard let state = scrolling(in: window) else { throw Failure(description: "\(variant.name): Settings has no scroll view") }
                if natural <= visibleHeight {
                    // Room for all of it: the window it always was, and nothing to scroll.
                    try require(abs(height - natural) <= 0.5, "\(variant.name): \(Int(height)) pt tall with room for its \(Int(natural)) pt")
                    try require(state.room <= 0.5, "\(variant.name): scrolls by \(Int(state.room)) pt though it fits")
                    whole += 1
                } else {
                    // Not enough room: as tall as can be seen, and the rest a scroll away.
                    try require(abs(height - visibleHeight) <= 0.5, "\(variant.name): \(Int(height)) pt tall where \(Int(visibleHeight)) pt can be seen")
                    // All of what does not fit, and a little more when a scroll bar that takes up
                    // width makes a line of text wrap.
                    let hidden = natural - visibleHeight
                    try require(state.room >= hidden - 1 && state.room <= hidden + 60, "\(variant.name): \(Int(state.room)) pt to scroll, \(Int(hidden)) pt hidden")
                    for _ in 0..<(Int(state.room) / 150 + 2) {
                        try await turnWheel(in: window, by: 200)
                    }
                    let end = scrolling(in: window)
                    try require(abs((end?.offset ?? -1) - state.room) <= 1, "\(variant.name) at \(Int(visibleHeight)) pt: the scroll wheel stopped \(Int(state.room - (end?.offset ?? 0))) pt short of the last row")
                    scrolled += 1
                }
            }
            lines.append("\(variant.name): \(Int(natural)) pt tall when it fits; from 400 to 1200 pt of visible height it fitted whole \(whole) times and scrolled to its last row \(scrolled) times")

            for display in pictured {
                for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                    let window = try await open(variant, visibleHeight: display.visibleHeight, appearance: appearance)
                    defer { window.orderOut(nil) }
                    try await Task.sleep(for: .milliseconds(500))
                    let state = scrolling(in: window)
                    let scrolls = (state?.room ?? 0) > 0.5
                    let name = "settings-\(display.file)\(variant.file)"
                    try DebugSnapshots.capture(window, to: directory.appendingPathComponent("\(name)\(scrolls ? "-top" : "")-\(suffix).png"))
                    if scrolls {
                        for _ in 0..<(Int(state?.room ?? 0) / 150 + 2) {
                            try await turnWheel(in: window, by: 200)
                        }
                        try await Task.sleep(for: .milliseconds(400))
                        try DebugSnapshots.capture(window, to: directory.appendingPathComponent("\(name)-bottom-\(suffix).png"))
                    }
                    if suffix == "light" {
                        lines.append("\(display.name), \(Int(display.visibleHeight)) pt visible, \(variant.name): window \(Int(window.frame.height)) pt tall, \(scrolls ? "scrolls \(Int(state?.room ?? 0)) pt" : "fits whole")")
                    }
                }
            }
        }
        let scrollBars = NSScroller.preferredScrollerStyle == .overlay ? "overlaid on the content" : "always shown, taking \(Int(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))) pt of width"
        print("Settings-on-small-displays check passed (scroll bars on this Mac: \(scrollBars)):\n  " + lines.joined(separator: "\n  "))
    }

    // MARK: - The windows open without the menu bar icon

    /// SwiftUI's window opener reaches the app through the menu bar icon's view. Takes it away
    /// and checks that Settings still opens.
    static func settingsOpensWithoutTheMenuBarIcon(model: AppModel) async throws {
        let opener = model.openWindow
        model.openWindow = nil
        defer { model.openWindow = opener }

        func settingsWindow() -> NSWindow? {
            NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && AppWindow.settings.matches(windowIdentifier: $0.identifier?.rawValue) }
        }
        try require(settingsWindow() == nil, "the Settings window is already open")
        model.show(.settings)
        try await Task.sleep(for: .seconds(1))
        guard let window = settingsWindow() else {
            throw Failure(description: "Settings did not open without the window opener")
        }
        try require(window.frame.width >= 500 && window.frame.height >= 400, "the Settings window opened empty: \(window.frame.size)")
        let size = window.frame.size
        // Asking again brings the same window forward instead of making a second one.
        model.show(.settings)
        try await Task.sleep(for: .milliseconds(500))
        let open = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) && AppWindow.settings.matches(windowIdentifier: $0.identifier?.rawValue) }
        try require(open.count == 1, "asking for Settings twice opened \(open.count) windows")
        window.close()
        try await Task.sleep(for: .milliseconds(300))
        print("Settings-without-the-icon check passed: with the window opener taken away, Settings opened as a \(Int(size.width)) × \(Int(size.height)) pt window; asking twice left one window.")
    }

    // MARK: - A hidden menu bar icon comes into view

    static var menuBarCheckIsRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-VoicedMenuBarCheck")
    }

    static func runMenuBarCheckIfRequested(model: AppModel) {
        guard menuBarCheckIsRequested else { return }
        Task {
            do {
                try await hiddenMenuBarIconComesIntoView(model: model)
            } catch {
                print("Menu bar check failed: \(error)")
                exit(1)
            }
            exit(0)
        }
    }

    /// The menu bar icon's saved place as it was before the menu bar check, and the way back to
    /// it however the check ends: at its end, by its time limit, or by a signal that can be
    /// caught, such as Ctrl-C or `kill`. A check that ended with the place where it had put it
    /// could leave the person's icon out of sight behind a menu bar manager's divider.
    ///
    /// A copy that cannot stay running comes before a place put back. So the end is armed
    /// first and waits for nothing: the place gets `endsWhateverHappens` to go back, and the
    /// process ends then at the latest, with the place perhaps still where the check had it.
    /// What is left besides is an end nothing in the process can answer: a hard kill, a crash,
    /// the Mac going down.
    nonisolated enum IconPlaceBeforeTheCheck {
        private enum Place: Sendable {
            case none
            /// As a property list, so that it goes back as the kind of value it was.
            case saved(Data)
        }

        /// `nil` until the check has read the place: until then it has changed nothing.
        private static let before = OSAllocatedUnfairLock<Place?>(initialState: nil)
        private static let signalSources = OSAllocatedUnfairLock(uncheckedState: [any DispatchSourceSignal]())

        /// Call before the check's first change to the place.
        static func remember() {
            let value = UserDefaults.standard.object(forKey: MenuBarItemPosition.defaultsKey)
            let saved = value.flatMap { try? PropertyListSerialization.data(fromPropertyList: $0, format: .binary, options: 0) }
            before.withLock { $0 = saved.map(Place.saved) ?? Place.none }
        }

        /// Saves the place as it was, from any thread, and returns once the preferences have
        /// it, so that it holds even if the process ends the next moment. That wait has no
        /// limit of its own, so the lock is held only to read what was remembered: a caller
        /// that never comes back from here holds up nobody else.
        static func putBack() {
            guard let place = before.withLock({ $0 }) else { return }
            let defaults = UserDefaults.standard
            switch place {
            case .none:
                defaults.removeObject(forKey: MenuBarItemPosition.defaultsKey)
            case let .saved(data):
                guard let value = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return }
                defaults.set(value, forKey: MenuBarItemPosition.defaultsKey)
            }
            defaults.synchronize()
        }

        /// How long the place has to go back once the check is being ended, before the process
        /// ends without it.
        static let endsWhateverHappens: Duration = .seconds(5)

        /// Ends the check `limit` from now, and at once on a signal, with the place put back.
        static func endTheCheck(after limit: Duration, code: Int32, saying line: String) {
            let seconds = Double(limit / .milliseconds(1)) / 1000
            Thread.detachNewThread {
                Thread.sleep(forTimeInterval: seconds)
                putBackAndEndTheProcess(code: code, saying: line)
            }
            let sources = [SIGINT, SIGTERM, SIGHUP, SIGQUIT].map { number -> any DispatchSourceSignal in
                // The signal no longer ends the process by itself; the source below does.
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
                source.setEventHandler {
                    putBackAndEndTheProcess(code: 128 + number, saying: "Menu bar check ended by signal \(number).")
                }
                source.resume()
                return source
            }
            signalSources.withLockUnchecked { $0 = sources }
        }

        /// From a thread of its own, never the main one.
        ///
        /// First the end that depends on nothing: on a thread that waits on no queue and takes
        /// no lock, the process ends `endsWhateverHappens` from now, whether or not the place
        /// has gone back by then.
        ///
        /// Then the place is put back on the main thread, where everything that writes it
        /// runs: the check, the app's Show in Menu Bar and macOS's own bookkeeping. While the
        /// main thread is putting it back and ending the process, none of them is writing.
        ///
        /// A main thread that has not taken this up within a second is taken to be stuck, and
        /// the place is put back from here. That it then writes nothing is an assumption: a
        /// main thread that was only busy is still running, and could write the check's value
        /// again after the place has gone back and before the process ends.
        private static func putBackAndEndTheProcess(code: Int32, saying line: String) -> Never {
            let seconds = Int(endsWhateverHappens / .seconds(1))
            StandaloneCheck.endProcess(after: endsWhateverHappens, code: code, saying: [
                line,
                "The menu bar icon's saved place did not go back within \(seconds) seconds, so it may be where the check had put it.",
            ])
            DispatchQueue.main.async {
                end(code: code, saying: line)
            }
            Thread.sleep(forTimeInterval: 1)
            end(code: code, saying: line)
        }

        private static func end(code: Int32, saying line: String) -> Never {
            putBack()
            StandaloneCheck.say(line)
            StandaloneCheck.say("The menu bar icon's saved place is as it was before the check.")
            // Not `exit`: nothing may run on the way out that a stuck thread could hold up.
            _exit(code)
        }
    }

    /// Needs something that hides icons the way a menu bar manager does: `make menu-bar-check`
    /// starts a stand-in. Puts the icon where a new one lands, behind the manager's divider, and
    /// checks that Voiced sees it as hidden and that the Show in Menu Bar action brings it into
    /// view; the same for an icon with a saved place behind the divider, and for one that has
    /// been dragged out of the menu bar. The icon's saved place is put back afterwards.
    ///
    /// The one Debug run that uses the person's saved settings, and one key of them: the menu
    /// bar icon's place. macOS itself reads that place when the icon is created, from the
    /// settings of the app the icon belongs to and from nowhere else, and Show in Menu Bar works
    /// by saving a place there. So the Makefile says to quit a running Voiced first. The place
    /// is put back when the check ends, when its time limit ends it and when a signal that can
    /// be caught does: see `IconPlaceBeforeTheCheck`.
    private static func hiddenMenuBarIconComesIntoView(model: AppModel) async throws {
        let defaults = UserDefaults.standard
        let key = MenuBarItemPosition.defaultsKey
        let savedPlace = defaults.object(forKey: key)
        IconPlaceBeforeTheCheck.remember()
        defer { IconPlaceBeforeTheCheck.putBack() }
        try await Task.sleep(for: .milliseconds(1500))

        func placement() -> String {
            model.windows.logMenuBarItem()
            return model.menuBarItem?.logDescription ?? "not looked up"
        }
        /// Creates the item anew, the way a launch does, with `place` as its saved place.
        func recreate(savedPlace place: Double?) async throws {
            model.menuBarItemIsInserted = false
            try await Task.sleep(for: .milliseconds(400))
            if let place {
                defaults.set(place, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            model.menuBarItemIsInserted = true
            try await Task.sleep(for: .milliseconds(1200))
        }
        func bringIntoView(from start: String) async throws -> String {
            try require(model.menuBarItemIsHidden, "Voiced does not see the icon as hidden when it is \(start)")
            model.bringMenuBarItemIntoView()
            try await Task.sleep(for: .milliseconds(1600))
            let end = placement()
            try require(!model.menuBarItemIsHidden, "Show in Menu Bar left the icon hidden: \(end)")
            try require(model.menuBarItemMove == nil, "the move was not recorded as done")
            try require(defaults.double(forKey: key) == MenuBarItemPosition.rightEnd && defaults.object(forKey: key) != nil, "the right end was not saved as the icon's place")
            return end
        }

        var lines: [String] = []

        try await recreate(savedPlace: nil)
        var start = placement()
        try require(
            model.menuBarItemIsHidden,
            "an icon with no saved place is not hidden (\(start)); nothing is hiding icons, so this check has nothing to work against"
        )
        var end = try await bringIntoView(from: start)
        lines.append("no saved place, where a new icon lands: \(start) -> \(end)")

        try await recreate(savedPlace: 6000)
        start = placement()
        end = try await bringIntoView(from: start)
        lines.append("saved place behind the divider: \(start) -> \(end)")

        model.menuBarItemIsInserted = false
        try await Task.sleep(for: .milliseconds(1200))
        start = placement()
        end = try await bringIntoView(from: start)
        lines.append("dragged out of the menu bar: \(start) -> \(end)")

        // Back to where it was before the check.
        try await recreate(savedPlace: (savedPlace as? NSNumber)?.doubleValue)
        print("Menu bar check passed: Show in Menu Bar brought the icon into view from\n  " + lines.joined(separator: "\n  ") + "\n  put back afterwards: \(placement())")
    }

    /// SwiftUI gives each focusable control a focus ring view; these are they, top to bottom.
    private static func focusRings(in view: NSView?) -> [NSView] {
        guard let view else { return [] }
        let own = view.className.hasSuffix("FocusRingView") ? [view] : []
        return own + view.subviews.flatMap { focusRings(in: $0) }
    }
}
#endif

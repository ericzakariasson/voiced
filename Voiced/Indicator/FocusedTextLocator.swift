import ApplicationServices
import Foundation
import VoicedKit

/// What came of asking the app in front where its text is being edited.
nonisolated struct FocusedTextAnswer: Sendable {
    /// Whose answer this is.
    enum Asked: String, Sendable {
        /// Another app: the one in front, or the one that was in front before Voiced's menu.
        case other
        /// Voiced itself. Only the interface checks do that.
        case voiced
        /// No app: none was in front, or one of Voiced's own windows had the keyboard.
        case nobody
    }

    var geometry = FocusedTextGeometry()
    var asked = Asked.other
    /// Voiced was the app in front when the hotkey went down.
    var voicedInFront = false
    var appKind = AppKind.other
    /// The accessibility result of each question, 0 for an answer; `nil` when it was not asked.
    var focus: Int32?
    var range: Int32?
    var bounds: Int32?
    var frame: Int32?
    var window: Int32?
    var milliseconds = 0

    /// For the log: who was asked, what kind of app it is, result codes and a duration. Which
    /// app it was is never written.
    var logDescription: String {
        func code(_ value: Int32?) -> String { value.map(String.init) ?? "-" }
        let front = voicedInFront ? " front=voiced" : ""
        return "asked=\(asked.rawValue)\(front) kind=\(appKind.rawValue) focus=\(code(focus)) range=\(code(range)) bounds=\(code(bounds)) frame=\(code(frame)) window=\(code(window)) in \(milliseconds) ms"
    }
}

/// Asks an app, through Accessibility, where its text is being edited.
///
/// Only geometry is read: which element has the keyboard, where the selection starts and how
/// long it is (two numbers, needed to ask for its box), the box of that stretch of text, and
/// the element's position and size. When the app gives none of that, as apps built on Chromium
/// and Electron do not, which window has the keyboard and that window's position and size.
/// The text itself is never asked for: no value, no selected text, no string for a range, no
/// title. Nothing is ever written to the other app.
///
/// One read is made for its effect and not for its answer: `readApplicationRole`, which
/// switches on the accessibility tree of an app built on Electron or Chromium. When it may be
/// made is decided by `AccessibilityWake`.
nonisolated enum FocusedTextLocator {
    /// How long one question may take. A dictation's pill appears a quarter of a second after
    /// the hotkey goes down, and an app that is busy must not hold that up.
    static let timeout: Float = 0.1

    static func locate(pid: pid_t, primaryDisplayHeight: CGFloat) -> FocusedTextAnswer {
        let start = ContinuousClock.now
        var answer = FocusedTextAnswer()
        ask(pid: pid, primaryDisplayHeight: primaryDisplayHeight, into: &answer)
        let elapsed = ContinuousClock.now - start
        answer.milliseconds = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        return answer
    }

    /// Reads the role of the app's own accessibility object, which says "application" for every
    /// app, and throws the answer away. Apps built on Electron and Chromium take the read as the
    /// sign of an assistive app other than VoiceOver and switch on a basic accessibility tree,
    /// after which they say where their text is. The tree stays on until that app quits.
    ///
    /// Returns the accessibility result of the read, 0 for an answer.
    static func readApplicationRole(pid: pid_t) -> Int32 {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(application, kAXRoleAttribute as CFString, &role).rawValue
    }

    private static func ask(pid: pid_t, primaryDisplayHeight: CGFloat, into answer: inout FocusedTextAnswer) {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)

        let isAnswering = askAboutText(application, primaryDisplayHeight: primaryDisplayHeight, into: &answer)
        // An app that says nothing about its text can still say where its window is. One that
        // did not answer in time, or may not be asked at all, is not asked a second thing.
        guard isAnswering, answer.geometry.insertionPoint == nil, answer.geometry.field == nil else { return }
        askAboutWindow(application, primaryDisplayHeight: primaryDisplayHeight, into: &answer)
    }

    /// Which window has the keyboard, and where it is: the focused window, or the main one when
    /// the app names none as focused.
    private static func askAboutWindow(_ application: AXUIElement, primaryDisplayHeight: CGFloat, into answer: inout FocusedTextAnswer) {
        var windowValue: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &windowValue)
        if result != .success, result != .cannotComplete {
            result = AXUIElementCopyAttributeValue(application, kAXMainWindowAttribute as CFString, &windowValue)
        }
        answer.window = result.rawValue
        guard result == .success, let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return }
        let window = windowValue as! AXUIElement
        AXUIElementSetMessagingTimeout(window, timeout)

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
        answer.window = positionResult == .success ? sizeResult.rawValue : positionResult.rawValue
        if positionResult == .success, sizeResult == .success, let position = point(positionValue), let size = size(sizeValue) {
            answer.geometry.window = FocusedTextGeometry.appKitRect(
                fromTopLeft: CGRect(origin: position, size: size), primaryDisplayHeight: primaryDisplayHeight
            )
        }
    }

    /// Returns whether the app is answering: `false` when it may not be asked or took too long.
    private static func askAboutText(_ application: AXUIElement, primaryDisplayHeight: CGFloat, into answer: inout FocusedTextAnswer) -> Bool {
        var focused: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused)
        answer.focus = focusResult.rawValue
        guard focusResult == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return focusResult != .cannotComplete && focusResult != .apiDisabled
        }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)

        func screenRect(_ rect: CGRect) -> CGRect {
            FocusedTextGeometry.appKitRect(fromTopLeft: rect, primaryDisplayHeight: primaryDisplayHeight)
        }

        // Where the selection is, as a position and a length.
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        answer.range = rangeResult.rawValue
        if rangeResult == .cannotComplete { return false }
        let selection = rangeResult == .success ? range(rangeValue) : nil

        /// The box of a stretch of text, when the app gives one that has a height.
        func box(location: Int, length: Int) -> CGRect? {
            var range = CFRange(location: location, length: length)
            guard location >= 0, let parameter = AXValueCreate(.cfRange, &range) else { return nil }
            var result: CFTypeRef?
            let boundsResult = AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result
            )
            answer.bounds = boundsResult.rawValue
            guard boundsResult == .success, let rect = rect(result), rect.height > 0 else { return nil }
            return rect
        }

        var isText = selection != nil
        if let selection {
            if selection.length > 0 {
                if let selected = box(location: selection.location, length: selection.length) {
                    answer.geometry.insertionPoint = .init(rect: screenRect(selected), mayBeOneLineUp: false)
                }
            } else if let next = box(location: selection.location, length: 1) {
                // The character after the insertion point is on its line, and starts where it is.
                let rect = CGRect(x: next.minX, y: next.minY, width: 0, height: next.height)
                answer.geometry.insertionPoint = .init(rect: screenRect(rect), mayBeOneLineUp: false)
            } else if let empty = box(location: selection.location, length: 0) {
                // At the end of the text there is no character after. The box of an empty stretch
                // is in the right place across, but AppKit reports it one line higher than it is.
                answer.geometry.insertionPoint = .init(rect: screenRect(empty), mayBeOneLineUp: true)
            } else if let previous = box(location: selection.location - 1, length: 1) {
                // No box for an empty stretch: the character before ends where the insertion
                // point is, unless it is a line break, which sits at the end of the line above.
                let rect = CGRect(x: previous.maxX, y: previous.minY, width: 0, height: previous.height)
                answer.geometry.insertionPoint = .init(rect: screenRect(rect), mayBeOneLineUp: true)
            }
        }

        if answer.geometry.insertionPoint == nil {
            // Web content names its positions with opaque markers instead of numbers.
            var markers: CFTypeRef?
            let markerResult = AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markers)
            if markerResult == .success, let markers {
                isText = true
                var result: CFTypeRef?
                let boundsResult = AXUIElementCopyParameterizedAttributeValue(
                    element, "AXBoundsForTextMarkerRange" as CFString, markers, &result
                )
                answer.bounds = boundsResult.rawValue
                if boundsResult == .success, let rect = rect(result), rect.height > 0 {
                    answer.geometry.insertionPoint = .init(rect: screenRect(rect), mayBeOneLineUp: true)
                }
            }
        }

        // The frame of the element, when it has shown itself to hold text. A button or a window
        // has the keyboard too at times, and the pill has no business beside those.
        guard isText else { return true }
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        answer.frame = positionResult == .success ? sizeResult.rawValue : positionResult.rawValue
        if positionResult == .success, sizeResult == .success, let position = point(positionValue), let size = size(sizeValue) {
            answer.geometry.field = screenRect(CGRect(origin: position, size: size))
        }
        return true
    }

    /// The app's answer as a packed range, point, size or rectangle; `nil` when it sent something else.
    private static func packed(_ reference: CFTypeRef?, as type: AXValueType) -> AXValue? {
        guard let reference, CFGetTypeID(reference) == AXValueGetTypeID() else { return nil }
        let wrapped = reference as! AXValue
        return AXValueGetType(wrapped) == type ? wrapped : nil
    }

    private static func range(_ reference: CFTypeRef?) -> CFRange? {
        var range = CFRange()
        guard let wrapped = packed(reference, as: .cfRange), AXValueGetValue(wrapped, .cfRange, &range) else { return nil }
        return range
    }

    private static func rect(_ reference: CFTypeRef?) -> CGRect? {
        var rect = CGRect.zero
        guard let wrapped = packed(reference, as: .cgRect), AXValueGetValue(wrapped, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func point(_ reference: CFTypeRef?) -> CGPoint? {
        var point = CGPoint.zero
        guard let wrapped = packed(reference, as: .cgPoint), AXValueGetValue(wrapped, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(_ reference: CFTypeRef?) -> CGSize? {
        var size = CGSize.zero
        guard let wrapped = packed(reference, as: .cgSize), AXValueGetValue(wrapped, .cgSize, &size) else { return nil }
        return size
    }
}

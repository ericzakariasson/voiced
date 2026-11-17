import Foundation

/// When Voiced makes the one read it makes for its effect on another app.
///
/// Apps built on Electron and browsers built on Chromium keep their accessibility tree off, and
/// with it every position of their text, until an assistive app shows itself. For assistive
/// apps other than VoiceOver they take a read of the application's role as that sign, and
/// switch on a basic tree without being told that a screen reader is present. The tree stays
/// on until the app quits, and nothing an outside app does switches it off again.
///
/// The tree is built after the read, so the answer that prompted the read stays empty. The app
/// is therefore asked again a few times while the hotkey is still held, and the pill moves to
/// the text once if an answer comes: see `askAgainAfter` and `isWorthMovingThePill`.
///
/// So the read is made as seldom as it can be: only for the app that was in front when the
/// hotkey went down, only when that app is of such a kind and said it has no focused element,
/// and once per run of that app. The caller sees to "only while the pill is set to Next to
/// Text", since nothing is asked at all otherwise.
public enum AccessibilityWake {
    /// The accessibility result "no value", which is what such an app answers when asked for
    /// its focused element while its tree is off.
    public static let noFocusedElement: Int32 = -25212

    /// When the app is asked again where its text is, counted from the read. How long an app
    /// takes to build its tree is its own affair and has not been measured; these cover a second
    /// and a half, closely at first, and then the app is left alone until the next dictation.
    public static let askAgainAfter: [Duration] = [150, 300, 500, 750, 1000, 1500].map { .milliseconds($0) }

    /// Whether a place found by asking again is worth moving a pill that is already on screen.
    /// Only from the stand-ins for a text position to a text position: a pill that sits by the
    /// text stays where it is, and nothing ever moves it away from the text.
    public static func isWorthMovingThePill(from shown: PillNearText.Source, to found: PillNearText.Source) -> Bool {
        (shown == .window || shown == .fixedPlace) && (found == .insertionPoint || found == .field)
    }

    public static func isCalledFor(
        kind: AppKind,
        askedTheAppInFront: Bool,
        focusResult: Int32?,
        alreadyMadeForThisRunOfTheApp: Bool
    ) -> Bool {
        // Only a kind known to answer the read. An app of unknown kind is left alone: finding
        // out its kind would mean opening files that macOS may ask the person about.
        askedTheAppInFront && (kind == .electron || kind == .chromium) && focusResult == noFocusedElement && !alreadyMadeForThisRunOfTheApp
    }
}

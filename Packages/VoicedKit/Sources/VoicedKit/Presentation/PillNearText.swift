import CoreGraphics
import Foundation

/// Where the pill goes when a dictation starts.
public enum PillPlacementMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Where the user left it, or bottom centre until it has been moved.
    case fixedPlace
    /// By the insertion point of the text being edited, when the app in front says where that is.
    case nextToText

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fixedPlace: "Fixed Place"
        case .nextToText: "Next to Text"
        }
    }

    /// What a Mac gets on which nobody has chosen: the pill by the text.
    public static let whenNotChosen = PillPlacementMode.nextToText

    /// The choice as the preferences hold it. A choice is saved when it is made, so one who
    /// chose Fixed Place keeps it; where nothing is saved, or nothing that can be read, nobody
    /// has chosen.
    public init(saved: String?) {
        self = saved.flatMap(PillPlacementMode.init(rawValue:)) ?? .whenNotChosen
    }
}

/// What the app in front said about where text is being edited. Geometry only: nothing here
/// is, or is derived from, the text itself. Rectangles are in AppKit screen coordinates, with
/// the origin at the bottom left of the primary display.
public struct FocusedTextGeometry: Equatable, Sendable {
    public struct InsertionPoint: Equatable, Sendable {
        /// The insertion point, or the selection when there is one.
        public var rect: CGRect
        /// The rectangle may be that of the line above the insertion point. An app can only be
        /// asked for the box of a stretch of text. At the very end of a text there is no
        /// character after the insertion point to ask about, and what apps answer for an empty
        /// stretch, or for the character before, can be one line too high.
        public var mayBeOneLineUp: Bool

        public init(rect: CGRect, mayBeOneLineUp: Bool) {
            self.rect = rect
            self.mayBeOneLineUp = mayBeOneLineUp
        }
    }

    public var insertionPoint: InsertionPoint?
    /// The frame of the focused text field.
    public var field: CGRect?
    /// The frame of the window that has the keyboard. Asked for only when the app gave neither
    /// of the above, as apps built on Chromium and Electron do not.
    public var window: CGRect?

    public init(insertionPoint: InsertionPoint? = nil, field: CGRect? = nil, window: CGRect? = nil) {
        self.insertionPoint = insertionPoint
        self.field = field
        self.window = window
    }

    /// Accessibility reports rectangles with the origin at the top left of the primary display.
    public static func appKitRect(fromTopLeft rect: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Where the pill goes for one dictation when it is to sit next to the text, and what decided it.
///
/// Below the line being edited, centred on the insertion point, the way the system's own
/// dictation indicator sits; above it when there is no room below. Never over the line itself.
/// Sideways it stays within the field: at the start of an empty chat box the pill would
/// otherwise hang over the box's left edge and cover what is beside it.
/// Without an insertion point, by the focused field; without that, at the bottom of the window
/// that has the keyboard, which at least is on the display being looked at; without that, the
/// fixed place.
public struct PillNearText: Equatable, Sendable {
    public enum Source: String, Sendable {
        case insertionPoint = "insertion point"
        case field
        case window
        case fixedPlace = "fixed place"
    }

    /// Why a place nearer the text was passed over.
    public enum Reason: String, Error, Sendable {
        /// The app gave none.
        case notGiven = "not given"
        /// A rectangle that is no rectangle, or too small to be what it is said to be.
        case notUsable = "not usable"
        case offEveryDisplay = "off every display"
        /// A selection of many lines says little about where the words will go.
        case tooTall = "too tall"
        /// Text scrolled out of its field, or an app that answers nonsense.
        case outsideItsField = "outside its field"
        case noRoom = "no room for the pill"
    }

    public struct PassedOver: Equatable, Sendable {
        public var source: Source
        public var reason: Reason

        public init(_ source: Source, _ reason: Reason) {
            self.source = source
            self.reason = reason
        }
    }

    public var source: Source
    /// The middle of the pill's bottom edge, in AppKit screen coordinates.
    public var anchor: CGPoint
    /// The display the pill is on, as an index into the displays given; `nil` when the fixed
    /// place is on none of them.
    public var display: Int?
    /// The nearer places that were not used, nearest first, each with its reason.
    public var passedOver: [PassedOver]

    public init(source: Source, anchor: CGPoint, display: Int?, passedOver: [PassedOver] = []) {
        self.source = source
        self.anchor = anchor
        self.display = display
        self.passedOver = passedOver
    }

    /// Air between the pill and the text it sits by.
    static let gap: CGFloat = 6
    /// A field up to this tall is a line or a few of them: a search field, a chat box. The pill
    /// may then sit above it. Above a whole document is too far from the eye.
    static let tallestSmallField: CGFloat = 120

    public static func place(
        geometry: FocusedTextGeometry?,
        displays: [PillPlacement.Display],
        fixedAnchor: CGPoint
    ) -> PillNearText {
        var passedOver: [PassedOver] = []
        /// Tries one place; a refusal is written down and the next place gets its turn.
        func attempt(_ source: Source, _ placing: () -> Result<PillNearText, Reason>) -> PillNearText? {
            switch placing() {
            case var .success(placed):
                placed.passedOver = passedOver
                return placed
            case let .failure(reason):
                passedOver.append(PassedOver(source, reason))
                return nil
            }
        }
        let field = geometry?.field
        return attempt(.insertionPoint) { geometry?.insertionPoint.map { beside($0, field: field, displays: displays) } ?? .failure(.notGiven) }
            ?? attempt(.field) { field.map { beside(field: $0, displays: displays) } ?? .failure(.notGiven) }
            ?? attempt(.window) { geometry?.window.map { inside(window: $0, displays: displays) } ?? .failure(.notGiven) }
            ?? PillNearText(
                source: .fixedPlace,
                anchor: fixedAnchor,
                display: displays.firstIndex { $0.visibleFrame.contains(fixedAnchor) },
                passedOver: passedOver
            )
    }

    private static func beside(
        _ insertionPoint: FocusedTextGeometry.InsertionPoint,
        field: CGRect?,
        displays: [PillPlacement.Display]
    ) -> Result<PillNearText, Reason> {
        let rect = insertionPoint.rect
        guard isFinite(rect), rect.height >= 2, rect.width >= 0 else { return .failure(.notUsable) }
        let middle = CGPoint(x: rect.midX, y: rect.midY)
        guard let index = displays.firstIndex(where: { $0.visibleFrame.contains(middle) }) else { return .failure(.offEveryDisplay) }
        let visible = displays[index].visibleFrame
        guard rect.height <= visible.height / 2 else { return .failure(.tooTall) }
        // A box that may be one line up may sit just above the field, on the first line.
        if let field, isFinite(field) {
            let reach = field.insetBy(dx: -4, dy: -4)
            let oneLineDown = CGPoint(x: middle.x, y: middle.y - rect.height)
            guard reach.contains(middle) || (insertionPoint.mayBeOneLineUp && reach.contains(oneLineDown)) else {
                return .failure(.outsideItsField)
            }
        }

        // Room for one more line when the box may be that of the line above.
        let lineBelow = insertionPoint.mayBeOneLineUp ? rect.height : 0
        let below = rect.minY - lineBelow - gap - PillPlacement.height
        let above = rect.maxY + gap
        let y: CGFloat
        if below >= visible.minY + PillPlacement.margin {
            y = below
        } else if above + PillPlacement.height <= visible.maxY - PillPlacement.margin {
            y = above
        } else {
            return .failure(.noRoom)
        }
        let x = centred(on: withinField(rect.midX, field: field), within: visible)
        return .success(PillNearText(source: .insertionPoint, anchor: CGPoint(x: x, y: y), display: index))
    }

    /// Where the pill's centre goes along the line: on `x`, moved no further than it takes for
    /// the pill to stay between the field's left and right edges, which it may touch. A field
    /// narrower than the pill gets the pill centred on it. Without a field, `x` as it is: the
    /// window is not asked for when the app says where its text is, so it bounds nothing.
    public static func withinField(_ x: CGFloat, field: CGRect?) -> CGFloat {
        guard let field, isFinite(field) else { return x }
        let minX = field.minX + PillPlacement.halfWidth
        let maxX = field.maxX - PillPlacement.halfWidth
        return minX <= maxX ? min(max(x, minX), maxX) : field.midX
    }

    /// The display that shows most of `rect`, and the part of it that shows there.
    private static func showing(_ rect: CGRect, on displays: [PillPlacement.Display]) -> (index: Int, part: CGRect)? {
        let shown = displays.enumerated().compactMap { index, display -> (index: Int, part: CGRect)? in
            let part = rect.intersection(display.visibleFrame)
            return part.isNull || part.isEmpty ? nil : (index, part)
        }
        return shown.max { $0.part.width * $0.part.height < $1.part.width * $1.part.height }
    }

    private static func beside(field: CGRect, displays: [PillPlacement.Display]) -> Result<PillNearText, Reason> {
        guard isFinite(field), field.width >= 8, field.height >= 8 else { return .failure(.notUsable) }
        guard let (index, part) = showing(field, on: displays) else { return .failure(.offEveryDisplay) }
        let visible = displays[index].visibleFrame

        let below = field.minY - gap - PillPlacement.height
        let above = field.maxY + gap
        let inside = part.minY + PillPlacement.margin
        let y: CGFloat
        if field.minY >= visible.minY, below >= visible.minY + PillPlacement.margin {
            y = below
        } else if field.height <= tallestSmallField, field.maxY <= visible.maxY, above + PillPlacement.height <= visible.maxY - PillPlacement.margin {
            y = above
        } else if part.height >= PillPlacement.height + 2 * PillPlacement.margin {
            // No room around it: along the bottom of the part of the field that is on screen.
            y = inside
        } else {
            return .failure(.noRoom)
        }
        return .success(PillNearText(source: .field, anchor: CGPoint(x: centred(on: part.midX, within: visible), y: y), display: index))
    }

    /// Inside the window, at the bottom centre of the part of it that is on screen: where the
    /// pill sits on a display by default, but in the window being typed into.
    private static func inside(window: CGRect, displays: [PillPlacement.Display]) -> Result<PillNearText, Reason> {
        guard isFinite(window), window.width >= 8, window.height >= 8 else { return .failure(.notUsable) }
        guard let (index, part) = showing(window, on: displays) else { return .failure(.offEveryDisplay) }
        let visible = displays[index].visibleFrame
        // The pill must fit inside the part that shows, or it would sit over another window.
        guard part.width >= 2 * (PillPlacement.halfWidth + PillPlacement.margin),
              part.height >= PillPlacement.height + PillPlacement.defaultLift + PillPlacement.margin else {
            return .failure(.noRoom)
        }
        let anchor = CGPoint(x: centred(on: part.midX, within: visible), y: part.minY + PillPlacement.defaultLift)
        return .success(PillNearText(source: .window, anchor: anchor, display: index))
    }

    /// As near to `x` as the pill can be centred while staying fully on the display.
    private static func centred(on x: CGFloat, within visible: CGRect) -> CGFloat {
        let minX = visible.minX + PillPlacement.halfWidth + PillPlacement.margin
        let maxX = visible.maxX - PillPlacement.halfWidth - PillPlacement.margin
        return minX <= maxX ? min(max(x, minX), maxX) : visible.midX
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite
            && [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy { $0.isFinite }
    }

    /// For the log: the source, numbers, and why each nearer place was passed over. Nothing else.
    public var logDescription: String {
        let place = "x=\(Int(anchor.x.rounded())) y=\(Int(anchor.y.rounded()))"
        let display = display.map { "on display \($0)" } ?? "on no display"
        let whyNotNearer = passedOver.isEmpty ? "" : ", " + passedOver.map { "\($0.source.rawValue) \($0.reason.rawValue)" }.joined(separator: ", ")
        switch source {
        case .insertionPoint, .field:
            return "by the \(source.rawValue) at \(place) \(display)\(whyNotNearer)"
        case .window:
            return "in the window at \(place) \(display)\(whyNotNearer)"
        case .fixedPlace:
            return "at the fixed place, \(place) \(display)\(whyNotNearer)"
        }
    }
}

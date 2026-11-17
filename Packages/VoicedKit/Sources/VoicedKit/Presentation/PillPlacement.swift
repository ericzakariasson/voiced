import CoreGraphics
import Foundation

/// Where the user left the recording pill, remembered relative to the display it was on.
///
/// The position is kept as fractions of the display's usable area rather than as points, so it
/// survives a change of resolution or arrangement. If the display is gone, the same fractions are
/// applied to another display; when it comes back, the pill returns to it.
///
/// Every point here is the pill's anchor: the middle of its bottom edge, in screen coordinates.
public struct PillPlacement: Codable, Equatable, Sendable {
    /// A connected display: a stable identifier and the area not taken by the menu bar or the Dock.
    public struct Display: Equatable, Sendable {
        public var id: String
        public var visibleFrame: CGRect

        public init(id: String, visibleFrame: CGRect) {
            self.id = id
            self.visibleFrame = visibleFrame
        }
    }

    public var display: String
    /// Across the display's usable area, 0 at its left edge and 1 at its right.
    public var x: Double
    /// Up the display's usable area, 0 at its bottom edge and 1 at its top.
    public var y: Double

    public init(display: String, x: Double, y: Double) {
        self.display = display
        self.x = x
        self.y = y
    }

    /// Room the pill needs around its anchor to stay fully on screen: half its usual width to each
    /// side, its height above, and a little air.
    static let halfWidth: CGFloat = 96
    static let height: CGFloat = 44
    static let margin: CGFloat = 8

    /// How far above the bottom of the usable area the pill sits until it has been moved.
    static let defaultLift: CGFloat = 18

    /// Remembers an anchor. Returns `nil` only when no display is connected.
    public static func remembering(anchor: CGPoint, displays: [Display]) -> PillPlacement? {
        guard let display = display(nearest: anchor, in: displays) else { return nil }
        let frame = display.visibleFrame
        let onScreen = keepingOnScreen(anchor, within: frame)
        return PillPlacement(
            display: display.id,
            x: frame.width > 0 ? (onScreen.x - frame.minX) / frame.width : 0.5,
            y: frame.height > 0 ? (onScreen.y - frame.minY) / frame.height : 0
        )
    }

    /// Where the anchor belongs now: on the remembered display if it is connected, otherwise at
    /// the same relative spot on `fallback`. Always far enough inside for the pill to be visible.
    public func anchor(displays: [Display], fallback: Display) -> CGPoint {
        let frame = (displays.first { $0.id == display } ?? fallback).visibleFrame
        let point = CGPoint(x: frame.minX + x * frame.width, y: frame.minY + y * frame.height)
        return Self.keepingOnScreen(point, within: frame)
    }

    /// Where the pill sits until it has been moved: bottom centre, just above the Dock.
    public static func defaultAnchor(on display: Display) -> CGPoint {
        CGPoint(x: display.visibleFrame.midX, y: display.visibleFrame.minY + defaultLift)
    }

    /// The nearest point to `anchor` at which the pill is fully visible on one of the displays.
    public static func keepingOnScreen(_ anchor: CGPoint, displays: [Display]) -> CGPoint {
        guard let display = display(nearest: anchor, in: displays) else { return anchor }
        return keepingOnScreen(anchor, within: display.visibleFrame)
    }

    private static func keepingOnScreen(_ anchor: CGPoint, within frame: CGRect) -> CGPoint {
        let minX = frame.minX + halfWidth + margin
        let maxX = frame.maxX - halfWidth - margin
        let minY = frame.minY + margin
        let maxY = frame.maxY - height - margin
        return CGPoint(
            x: minX <= maxX ? min(max(anchor.x, minX), maxX) : frame.midX,
            y: minY <= maxY ? min(max(anchor.y, minY), maxY) : frame.minY
        )
    }

    /// The display holding the point, or failing that the closest one.
    private static func display(nearest point: CGPoint, in displays: [Display]) -> Display? {
        if let containing = displays.first(where: { $0.visibleFrame.contains(point) }) {
            return containing
        }
        return displays.min { distance(from: point, to: $0.visibleFrame) < distance(from: point, to: $1.visibleFrame) }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

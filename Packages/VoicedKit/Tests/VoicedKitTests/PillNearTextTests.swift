import CoreGraphics
import Testing
@testable import VoicedKit

@Suite struct PillNearTextTests {
    /// A MacBook display with a Dock along the bottom and a menu bar on top.
    private let builtIn = PillPlacement.Display(id: "built-in", visibleFrame: CGRect(x: 0, y: 70, width: 1728, height: 1010))
    /// A monitor to its right.
    private let monitor = PillPlacement.Display(id: "monitor", visibleFrame: CGRect(x: 1728, y: 0, width: 2560, height: 1415))
    /// A monitor to its left, standing higher.
    private let left = PillPlacement.Display(id: "left", visibleFrame: CGRect(x: -1920, y: 200, width: 1920, height: 1055))
    private let fixed = CGPoint(x: 864, y: 88)

    private var displays: [PillPlacement.Display] { [builtIn, monitor, left] }

    private func caret(x: CGFloat, y: CGFloat, height: CGFloat = 17, mayBeOneLineUp: Bool = false) -> FocusedTextGeometry.InsertionPoint {
        .init(rect: CGRect(x: x, y: y, width: 0, height: height), mayBeOneLineUp: mayBeOneLineUp)
    }

    /// The pill's box for an anchor: the middle of its bottom edge.
    private func pill(at anchor: CGPoint) -> CGRect {
        CGRect(x: anchor.x - PillPlacement.halfWidth, y: anchor.y, width: 2 * PillPlacement.halfWidth, height: PillPlacement.height)
    }

    private func place(_ insertionPoint: FocusedTextGeometry.InsertionPoint?, field: CGRect? = nil, window: CGRect? = nil) -> PillNearText {
        PillNearText.place(
            geometry: FocusedTextGeometry(insertionPoint: insertionPoint, field: field, window: window), displays: displays, fixedAnchor: fixed
        )
    }

    // MARK: - By the insertion point

    @Test func thePillSitsJustBelowTheLineCentredOnTheInsertionPoint() {
        let placed = place(caret(x: 600, y: 500))

        #expect(placed.source == .insertionPoint)
        #expect(placed.display == 0)
        #expect(placed.anchor == CGPoint(x: 600, y: 500 - 6 - 44))
        #expect(pill(at: placed.anchor).maxY < 500)
    }

    @Test(arguments: [
        CGPoint(x: 600, y: 500), CGPoint(x: 3, y: 900), CGPoint(x: 1725, y: 75), CGPoint(x: 900, y: 1060),
        CGPoint(x: 3000, y: 4), CGPoint(x: 4280, y: 1390), CGPoint(x: -1900, y: 210), CGPoint(x: -10, y: 1240),
    ])
    func whereverTheInsertionPointIsThePillIsFullyOnItsDisplayAndOffItsLine(point: CGPoint) throws {
        let insertionPoint = caret(x: point.x, y: point.y)
        let placed = place(insertionPoint)

        #expect(placed.source == .insertionPoint)
        let index = try #require(placed.display)
        let visible = displays[index].visibleFrame
        #expect(visible.contains(CGPoint(x: insertionPoint.rect.midX, y: insertionPoint.rect.midY)))
        let box = pill(at: placed.anchor)
        #expect(visible.contains(box))
        // Not over the line: entirely below it or entirely above it.
        #expect(box.maxY <= insertionPoint.rect.minY || box.minY >= insertionPoint.rect.maxY)
        // And close to it.
        #expect(min(abs(box.maxY - insertionPoint.rect.minY), abs(box.minY - insertionPoint.rect.maxY)) <= 6)
    }

    @Test func withNoRoomBelowThePillGoesAboveTheLine() {
        // A line just above the Dock.
        let placed = place(caret(x: 600, y: 90))

        #expect(placed.source == .insertionPoint)
        #expect(placed.anchor == CGPoint(x: 600, y: 90 + 17 + 6))
    }

    @Test func atTheEdgeOfADisplayThePillStaysOnThatDisplay() {
        // The right edge of the built-in display, where the monitor begins.
        let right = place(caret(x: 1720, y: 500))
        #expect(right.display == 0)
        #expect(right.anchor.x == 1624, "1728 less half the pill and the margin")

        // The left edge of the monitor.
        let onMonitor = place(caret(x: 1732, y: 500))
        #expect(onMonitor.display == 1)
        #expect(onMonitor.anchor.x == 1832)
    }

    @Test func aSecondDisplayIsUsedWhenTheTextIsOnIt() {
        let placed = place(caret(x: -1000, y: 700))

        #expect(placed.display == 2)
        #expect(placed.anchor == CGPoint(x: -1000, y: 700 - 6 - 44))
    }

    @Test func aBoxThatMayBeTheLineAboveLeavesRoomForOneMoreLine() {
        let certain = place(caret(x: 600, y: 500))
        let uncertain = place(caret(x: 600, y: 500, mayBeOneLineUp: true))

        #expect(uncertain.anchor.y == certain.anchor.y - 17)
        // Whether the real line is the reported one or the one below it, the pill is under it.
        let realLineIfOneDown = CGRect(x: 600, y: 500 - 17, width: 0, height: 17)
        #expect(pill(at: uncertain.anchor).maxY <= realLineIfOneDown.minY)
    }

    @Test func aBoxThatMayBeTheLineAboveStillGoesAboveWhenThereIsNoRoomBelow() {
        let placed = place(caret(x: 600, y: 120, mayBeOneLineUp: true))

        // Above the reported line, which is above the real one either way.
        #expect(placed.anchor == CGPoint(x: 600, y: 120 + 17 + 6))
    }

    /// An empty text: AppKit reports the insertion point one line up, which is above the field.
    @Test func aBoxOneLineAboveItsFieldIsUsedWhenTheRealLineMayBeTheOneBelow() {
        let field = CGRect(x: 400, y: 300, width: 600, height: 400)
        let reported = caret(x: 410, y: 700, mayBeOneLineUp: true)
        let placed = place(reported, field: field)

        #expect(placed.source == .insertionPoint)
        // Under the first line of the field, which is where the insertion point really is,
        // and no further left than the field's own edge.
        #expect(placed.anchor == CGPoint(x: 400 + 96, y: 700 - 17 - 6 - 44))

        // The same box from an app that vouches for the line is outside the field: not used.
        #expect(place(caret(x: 410, y: 700), field: field).source == .field)
    }

    @Test func aSelectionIsTreatedAsTheLineBeingEdited() {
        let selection = FocusedTextGeometry.InsertionPoint(rect: CGRect(x: 400, y: 500, width: 300, height: 17), mayBeOneLineUp: false)
        let placed = place(selection)

        #expect(placed.source == .insertionPoint)
        #expect(placed.anchor == CGPoint(x: 550, y: 500 - 6 - 44))
    }

    // MARK: - Within the field, sideways

    /// A chat box: one line, wider than the pill, in the middle of the built-in display.
    private let chatBox = CGRect(x: 400, y: 300, width: 600, height: 40)

    /// The middle of the pill, left to right.
    private func middle(_ placed: PillNearText) -> Double {
        Double(placed.anchor.x)
    }

    @Test func atTheStartOfAnEmptyChatBoxThePillStaysWithinTheBoxesLeftEdge() {
        let placed = place(caret(x: 412, y: 311), field: chatBox)

        #expect(placed.source == .insertionPoint)
        // Centred on the insertion point it would reach 96 pt left of it, over what is beside the box.
        #expect(middle(placed) == 400 + 96)
        #expect(pill(at: placed.anchor).minX == chatBox.minX)
        // Up and down nothing changes: just below the line.
        #expect(placed.anchor == CGPoint(x: 496, y: 311 - 6 - 44))
        #expect(placed.anchor.y == place(caret(x: 412, y: 311)).anchor.y)
    }

    @Test func atTheEndOfAFullLineThePillStaysWithinTheRightEdge() {
        let placed = place(caret(x: 990, y: 311), field: chatBox)

        #expect(middle(placed) == 1000 - 96)
        #expect(pill(at: placed.anchor).maxX == chatBox.maxX)
    }

    @Test(arguments: [496.0, 497, 600, 700, 903, 904])
    func withRoomOnBothSidesThePillIsCentredOnTheInsertionPoint(x: Double) {
        #expect(middle(place(caret(x: x, y: 311), field: chatBox)) == x)
    }

    @Test(arguments: [396.0, 400, 412, 495, 600, 905, 1000, 1003])
    func whereverTheInsertionPointIsInAWideFieldThePillIsBetweenItsEdges(x: Double) {
        let placed = place(caret(x: x, y: 311), field: chatBox)

        #expect(placed.source == .insertionPoint)
        let box = pill(at: placed.anchor)
        #expect(box.minX >= chatBox.minX && box.maxX <= chatBox.maxX)
        // And moved no further from the insertion point than that took.
        #expect(middle(placed) == min(max(x, 496), 904))
    }

    @Test func aSelectionIsCentredAndThenKeptWithinTheField() {
        let nearTheStart = FocusedTextGeometry.InsertionPoint(rect: CGRect(x: 410, y: 311, width: 100, height: 17), mayBeOneLineUp: false)
        let inTheMiddle = FocusedTextGeometry.InsertionPoint(rect: CGRect(x: 600, y: 311, width: 100, height: 17), mayBeOneLineUp: false)

        #expect(middle(place(nearTheStart, field: chatBox)) == 496)
        #expect(middle(place(inTheMiddle, field: chatBox)) == 650)
    }

    @Test func aFieldExactlyAsWideAsThePillHoldsItEdgeToEdge() {
        let field = CGRect(x: 400, y: 300, width: 192, height: 40)

        for x in [402.0, 496, 590] {
            let placed = place(caret(x: x, y: 311), field: field)
            #expect(middle(placed) == 496)
            #expect(pill(at: placed.anchor).minX == field.minX && pill(at: placed.anchor).maxX == field.maxX)
        }
    }

    @Test func aFieldNarrowerThanThePillGetsThePillCentredOnIt() {
        // A search field of 120 pt: the pill reaches 36 pt past it on each side.
        let field = CGRect(x: 400, y: 300, width: 120, height: 22)

        for x in [402.0, 460, 518] {
            let placed = place(caret(x: x, y: 302), field: field)
            #expect(placed.source == .insertionPoint)
            #expect(placed.anchor == CGPoint(x: 460, y: 302 - 6 - 44))
        }
        // Just under the pill's width counts as narrower.
        #expect(middle(place(caret(x: 402, y: 302), field: CGRect(x: 400, y: 300, width: 191, height: 22))) == 495.5)
    }

    @Test func theDisplaysEdgeCountsForMoreThanTheFields() {
        // A field that runs from the left edge of the display: the pill keeps the display's margin.
        let atTheEdge = CGRect(x: 0, y: 300, width: 600, height: 40)
        #expect(middle(place(caret(x: 5, y: 311), field: atTheEdge)) == 96 + 8)

        // A field that runs off the right edge of the last display: the pill stays on the display.
        let runningOff = CGRect(x: 4000, y: 300, width: 600, height: 40)
        let placed = place(caret(x: 4280, y: 311), field: runningOff)
        #expect(placed.display == 1)
        #expect(middle(placed) == 4288 - 96 - 8)

        // A narrow field at the very edge: centred on it would be partly off the display.
        let narrow = CGRect(x: 0, y: 300, width: 120, height: 22)
        #expect(middle(place(caret(x: 5, y: 302), field: narrow)) == 96 + 8)
    }

    @Test func withoutAFieldNothingBoundsThePillButTheDisplay() {
        // The window is given here, but it is asked for only when the app gave no text position,
        // so it must not move the pill when it happens to be known.
        let window = CGRect(x: 400, y: 200, width: 800, height: 600)

        #expect(place(caret(x: 410, y: 500), window: window).anchor == CGPoint(x: 410, y: 500 - 6 - 44))
        #expect(place(caret(x: 410, y: 500)).anchor == CGPoint(x: 410, y: 500 - 6 - 44))
        // A field that is no rectangle is no field.
        let nonsense = CGRect(x: CGFloat.nan, y: 300, width: 600, height: 40)
        #expect(middle(place(caret(x: 410, y: 500), field: nonsense)) == 410)
    }

    @Test func withinAFieldTheRuleForAboveAndBelowIsUnchanged() {
        // At the bottom of the screen the pill goes above the line, and is still kept within the field.
        let field = CGRect(x: 400, y: 72, width: 600, height: 40)
        let placed = place(caret(x: 412, y: 83), field: field)

        #expect(placed.source == .insertionPoint)
        #expect(placed.anchor == CGPoint(x: 496, y: 83 + 17 + 6))
    }

    // MARK: - Falling back to the field

    @Test func withoutAnInsertionPointThePillGoesBelowTheField() {
        let field = CGRect(x: 400, y: 600, width: 300, height: 22)
        let placed = place(nil, field: field)

        #expect(placed.source == .field)
        #expect(placed.anchor == CGPoint(x: 550, y: 600 - 6 - 44))
    }

    @Test func aSmallFieldAtTheBottomOfTheScreenGetsThePillAboveIt() {
        // A chat box just above the Dock.
        let field = CGRect(x: 400, y: 80, width: 600, height: 40)
        let placed = place(nil, field: field)

        #expect(placed.source == .field)
        #expect(placed.anchor == CGPoint(x: 700, y: 80 + 40 + 6))
    }

    @Test func aDocumentThatFillsTheScreenGetsThePillAlongItsBottom() {
        let field = CGRect(x: 0, y: 70, width: 1728, height: 950)
        let placed = place(nil, field: field)

        #expect(placed.source == .field)
        #expect(placed.anchor == CGPoint(x: 864, y: 70 + 8))
    }

    @Test func aFieldPartlyOffTheScreenIsJudgedByThePartThatShows() {
        // A window dragged halfway off the bottom right of the monitor.
        let field = CGRect(x: 3800, y: -400, width: 900, height: 800)
        let placed = place(nil, field: field)

        #expect(placed.source == .field)
        #expect(placed.display == 1)
        // Centred on the part that shows, and inside the display.
        #expect(placed.anchor == CGPoint(x: (3800 + 4288) / 2, y: 8))
        #expect(monitor.visibleFrame.contains(pill(at: placed.anchor)))
    }

    @Test func aFieldAcrossTwoDisplaysUsesTheOneThatShowsMoreOfIt() {
        let field = CGRect(x: 1500, y: 500, width: 1000, height: 30)
        let placed = place(nil, field: field)

        #expect(placed.display == 1)
        #expect(placed.anchor == CGPoint(x: (1728 + 2500) / 2, y: 500 - 6 - 44))
    }

    @Test func anInsertionPointScrolledOutOfItsFieldFallsBackToTheField() {
        let field = CGRect(x: 400, y: 600, width: 300, height: 200)
        let placed = place(caret(x: 450, y: 300), field: field)

        #expect(placed.source == .field)
        #expect(placed.anchor == CGPoint(x: 550, y: 600 - 6 - 44))
    }

    @Test func anInsertionPointOffEveryDisplayFallsBackToTheField() {
        let field = CGRect(x: 400, y: 600, width: 300, height: 22)

        #expect(place(caret(x: 9000, y: 9000), field: field).source == .field)
        #expect(place(caret(x: 600, y: 30), field: field).source == .field, "under the Dock")
    }

    @Test func aSelectionOfManyLinesFallsBackToTheField() {
        let field = CGRect(x: 0, y: 70, width: 1728, height: 950)
        let selection = FocusedTextGeometry.InsertionPoint(rect: CGRect(x: 100, y: 200, width: 900, height: 700), mayBeOneLineUp: false)

        #expect(place(selection, field: field).source == .field)
    }

    @Test(arguments: [
        CGRect.zero,
        CGRect(x: 600, y: 500, width: 0, height: 0),
        CGRect(x: CGFloat.nan, y: 500, width: 0, height: 17),
        CGRect(x: 600, y: CGFloat.infinity, width: 0, height: 17),
        CGRect.null,
        CGRect.infinite,
    ])
    func anInsertionPointThatMakesNoSenseIsNotUsed(rect: CGRect) {
        let field = CGRect(x: 400, y: 600, width: 300, height: 22)
        let placed = place(.init(rect: rect, mayBeOneLineUp: false), field: field)

        #expect(placed.source == .field)
    }

    // MARK: - Falling back to the fixed place

    @Test func withNoAnswerThePillGoesToTheFixedPlace() {
        let placed = PillNearText.place(geometry: nil, displays: displays, fixedAnchor: fixed)

        // The fixed place of these tests is on the first display, and nothing nearer was given.
        #expect(placed.source == .fixedPlace)
        #expect(placed.anchor == fixed)
        #expect(placed.display == 0)
        #expect(placed.passedOver == [.init(.insertionPoint, .notGiven), .init(.field, .notGiven), .init(.window, .notGiven)])
    }

    // MARK: - In the window, when the app says nothing about its text

    @Test func withOnlyAWindowThePillGoesToTheBottomCentreOfThatWindow() {
        // What an app built on Electron gives: no focused element, and a window.
        let window = CGRect(x: 2000, y: 200, width: 1400, height: 900)

        let placed = place(nil, window: window)

        #expect(placed.source == .window)
        #expect(placed.display == 1)
        #expect(placed.anchor == CGPoint(x: 2700, y: 218))
        #expect(window.contains(pill(at: placed.anchor)))
        #expect(placed.passedOver == [.init(.insertionPoint, .notGiven), .init(.field, .notGiven)])
    }

    @Test func aWindowIsUsedOnlyWhenNothingNearerIs() {
        let window = CGRect(x: 100, y: 100, width: 1200, height: 800)

        #expect(place(caret(x: 600, y: 500), window: window).source == .insertionPoint)
        #expect(place(nil, field: CGRect(x: 400, y: 600, width: 300, height: 22), window: window).source == .field)
    }

    @Test func aWindowPartlyBelowTheScreenGetsThePillAtTheBottomOfThePartThatShows() {
        // The lower 300 points are below the Dock's edge of the built-in display.
        let window = CGRect(x: 200, y: -230, width: 1000, height: 800)

        let placed = place(nil, window: window)

        #expect(placed.source == .window)
        #expect(placed.anchor == CGPoint(x: 700, y: 70 + 18))
        #expect(builtIn.visibleFrame.contains(pill(at: placed.anchor)))
    }

    @Test func aWindowAcrossTwoDisplaysUsesTheOneThatShowsMoreOfIt() {
        // 328 points of it on the built-in display, 872 on the monitor.
        let window = CGRect(x: 1400, y: 300, width: 1200, height: 600)

        let placed = place(nil, window: window)

        #expect(placed.display == 1)
        #expect(monitor.visibleFrame.contains(pill(at: placed.anchor)))
    }

    @Test(arguments: [
        // Too narrow or too low for the pill to sit inside it.
        CGRect(x: 400, y: 400, width: 150, height: 600),
        CGRect(x: 400, y: 400, width: 600, height: 50),
        // Off every display, and nonsense.
        CGRect(x: 9000, y: 9000, width: 800, height: 600),
        CGRect.zero,
        CGRect.null,
        CGRect(x: CGFloat.nan, y: 0, width: 800, height: 600),
    ])
    func aWindowThePillCannotSitInIsNotUsed(window: CGRect) {
        let placed = place(nil, window: window)

        #expect(placed.source == .fixedPlace)
        #expect(placed.passedOver.last?.source == .window)
        #expect(placed.passedOver.last?.reason != .notGiven)
    }

    // MARK: - Why a nearer place was passed over

    @Test func eachPlacePassedOverIsNamedWithItsReason() {
        let field = CGRect(x: 400, y: 480, width: 300, height: 60)
        let window = CGRect(x: 100, y: 100, width: 1200, height: 800)

        // Scrolled out of its field: the field is used instead.
        #expect(place(caret(x: 500, y: 900), field: field).passedOver == [.init(.insertionPoint, .outsideItsField)])
        // On no display.
        #expect(place(caret(x: 9000, y: 9000), window: window).passedOver == [.init(.insertionPoint, .offEveryDisplay), .init(.field, .notGiven)])
        // A selection of many lines.
        #expect(place(.init(rect: CGRect(x: 400, y: 200, width: 300, height: 700), mayBeOneLineUp: false)).passedOver.first == .init(.insertionPoint, .tooTall))
        // A rectangle that is none.
        #expect(place(.init(rect: .zero, mayBeOneLineUp: false)).passedOver.first == .init(.insertionPoint, .notUsable))
        // A field too small to be one, and a window nowhere to be seen.
        #expect(place(nil, field: CGRect(x: 400, y: 600, width: 2, height: 2), window: CGRect(x: 9000, y: 9000, width: 800, height: 600)).passedOver == [
            .init(.insertionPoint, .notGiven), .init(.field, .notUsable), .init(.window, .offEveryDisplay),
        ])
        // By the insertion point, nothing was passed over.
        #expect(place(caret(x: 600, y: 500)).passedOver.isEmpty)
    }

    // MARK: - A large display as the main one, with the laptop below it

    /// An external display, 3200 × 1350, is the primary one, and the built-in one, 1728 × 1117,
    /// sits below it, 575 in from the left.
    private var externalAboveBuiltIn: [PillPlacement.Display] {
        [
            // Each less its menu bar; the built-in one also less a Dock.
            PillPlacement.Display(id: "external", visibleFrame: CGRect(x: 0, y: 0, width: 3200, height: 1320)),
            PillPlacement.Display(id: "built-in", visibleFrame: CGRect(x: 575, y: -1117, width: 1728, height: 1010)),
        ]
    }

    @Test func textOnTheLaptopBelowALargerMainDisplayIsFoundOnTheLaptop() {
        // Accessibility measures down from the top of the primary display: 1350 is its bottom
        // edge and the top of the laptop's display, 2467 the bottom of the laptop's.
        let onTheLaptop = FocusedTextGeometry.appKitRect(fromTopLeft: CGRect(x: 1400, y: 1900, width: 0, height: 18), primaryDisplayHeight: 1350)
        #expect(onTheLaptop == CGRect(x: 1400, y: -568, width: 0, height: 18))

        let placed = PillNearText.place(
            geometry: FocusedTextGeometry(insertionPoint: .init(rect: onTheLaptop, mayBeOneLineUp: false)),
            displays: externalAboveBuiltIn, fixedAnchor: CGPoint(x: 1900, y: 335)
        )

        #expect(placed.source == .insertionPoint)
        #expect(placed.display == 1)
        #expect(placed.anchor == CGPoint(x: 1400, y: -568 - 6 - 44))
        #expect(externalAboveBuiltIn[1].visibleFrame.contains(pill(at: placed.anchor)))
    }

    @Test func textOnTheLargerMainDisplayIsFoundThere() {
        let onTheExternal = FocusedTextGeometry.appKitRect(fromTopLeft: CGRect(x: 2100, y: 700, width: 0, height: 18), primaryDisplayHeight: 1350)
        #expect(onTheExternal == CGRect(x: 2100, y: 632, width: 0, height: 18))

        let placed = PillNearText.place(
            geometry: FocusedTextGeometry(insertionPoint: .init(rect: onTheExternal, mayBeOneLineUp: false)),
            displays: externalAboveBuiltIn, fixedAnchor: CGPoint(x: 1900, y: 335)
        )

        #expect(placed.display == 0)
        #expect(placed.anchor == CGPoint(x: 2100, y: 632 - 6 - 44))
    }

    @Test func aWindowOnTheLaptopPutsThePillOnTheLaptopThoughTheFixedPlaceIsOnTheOtherDisplay() {
        // Without the window's frame, an app that gave no text had the pill go to its fixed
        // place on the external display. With the window's frame it stays with the app.
        let window = FocusedTextGeometry.appKitRect(fromTopLeft: CGRect(x: 700, y: 1400, width: 1500, height: 1000), primaryDisplayHeight: 1350)
        #expect(window == CGRect(x: 700, y: -1050, width: 1500, height: 1000))

        let placed = PillNearText.place(
            geometry: FocusedTextGeometry(window: window), displays: externalAboveBuiltIn, fixedAnchor: CGPoint(x: 1900, y: 335)
        )

        #expect(placed.source == .window)
        #expect(placed.display == 1)
        #expect(externalAboveBuiltIn[1].visibleFrame.contains(pill(at: placed.anchor)))

        // Without the window, the fixed place, and the line says which display that is.
        let fallback = PillNearText.place(geometry: FocusedTextGeometry(), displays: externalAboveBuiltIn, fixedAnchor: CGPoint(x: 1900, y: 335))
        #expect(fallback.source == .fixedPlace)
        #expect(fallback.display == 0)
    }

    @Test(arguments: [
        // The second display to the right, to the left, above and below a 1728 × 1117 primary.
        (CGRect(x: 1728, y: 0, width: 1920, height: 1080), CGRect(x: 2000, y: 300, width: 40, height: 20)),
        (CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: -1500, y: 300, width: 40, height: 20)),
        (CGRect(x: 0, y: -1080, width: 1920, height: 1080), CGRect(x: 300, y: -700, width: 40, height: 20)),
        (CGRect(x: 0, y: 1117, width: 1920, height: 1080), CGRect(x: 300, y: 1500, width: 40, height: 20)),
    ])
    func aRectangleOnASecondDisplayAnywhereAroundThePrimaryLandsOnThatDisplay(display: CGRect, rect: CGRect) {
        // `display` and `rect` as Accessibility gives them, measured down from the primary's top.
        let primaryHeight: CGFloat = 1117
        let displayInAppKit = FocusedTextGeometry.appKitRect(fromTopLeft: display, primaryDisplayHeight: primaryHeight)
        let flipped = FocusedTextGeometry.appKitRect(fromTopLeft: rect, primaryDisplayHeight: primaryHeight)

        #expect(displayInAppKit.contains(flipped))
        // As far below the display's top edge in one system as in the other.
        #expect(displayInAppKit.maxY - flipped.maxY == rect.minY - display.minY)
        #expect(flipped.minX - displayInAppKit.minX == rect.minX - display.minX)
    }

    @Test func withAnEmptyAnswerThePillGoesToTheFixedPlace() {
        #expect(place(nil).source == .fixedPlace)
        #expect(place(nil).anchor == fixed)
    }

    @Test(arguments: [
        CGRect.zero,
        CGRect(x: 400, y: 600, width: 2, height: 2),
        CGRect(x: 9000, y: 9000, width: 300, height: 22),
        CGRect(x: 400, y: 20, width: 300, height: 22),
        CGRect.null,
        CGRect(x: CGFloat.nan, y: 0, width: 300, height: 22),
    ])
    func aFieldThatMakesNoSenseOrCannotBeSeenIsNotUsed(field: CGRect) {
        #expect(place(nil, field: field).source == .fixedPlace)
    }

    @Test func aSliverOfAFieldWithNoRoomAroundItIsNotUsed() {
        // Thirty points of a tall field showing above the Dock, with the rest below the screen.
        let field = CGRect(x: 400, y: -500, width: 300, height: 600)

        #expect(place(nil, field: field).source == .fixedPlace)
    }

    @Test func withNoDisplaysThePillGoesToTheFixedPlace() {
        let geometry = FocusedTextGeometry(insertionPoint: caret(x: 600, y: 500), field: CGRect(x: 400, y: 480, width: 300, height: 60))

        #expect(PillNearText.place(geometry: geometry, displays: [], fixedAnchor: fixed).source == .fixedPlace)
    }

    // MARK: - Coordinates and wording

    @Test func accessibilityRectanglesAreFlippedIntoScreenCoordinates() {
        // 286 from the top of a 720-point display, 14 tall: its bottom edge is 420 from the bottom.
        let flipped = FocusedTextGeometry.appKitRect(fromTopLeft: CGRect(x: 266, y: 286, width: 0, height: 14), primaryDisplayHeight: 720)

        #expect(flipped == CGRect(x: 266, y: 420, width: 0, height: 14))
    }

    @Test func aRectangleOnADisplayAboveThePrimaryOneFlipsToo() {
        let flipped = FocusedTextGeometry.appKitRect(fromTopLeft: CGRect(x: 100, y: -500, width: 40, height: 20), primaryDisplayHeight: 1117)

        #expect(flipped == CGRect(x: 100, y: 1597, width: 40, height: 20))
    }

    @Test func theLogLineHoldsTheSourceAndNumbersOnly() {
        #expect(place(caret(x: 600, y: 500)).logDescription == "by the insertion point at x=600 y=450 on display 0")
        #expect(place(nil, field: CGRect(x: 400, y: 600, width: 300, height: 22)).logDescription
            == "by the field at x=550 y=550 on display 0, insertion point not given")
        #expect(place(nil, window: CGRect(x: 2000, y: 200, width: 1400, height: 900)).logDescription
            == "in the window at x=2700 y=218 on display 1, insertion point not given, field not given")
        #expect(place(nil).logDescription
            == "at the fixed place, x=864 y=88 on display 0, insertion point not given, field not given, window not given")
        #expect(PillNearText(source: .fixedPlace, anchor: CGPoint(x: -5000, y: 88), display: nil).logDescription == "at the fixed place, x=-5000 y=88 on no display")
    }

    @Test func theKindOfAppIsToldFromItsFrameworks() {
        #expect(AppKind.of(frameworks: ["Electron Framework.framework", "Squirrel.framework", "Cursor Helper (Renderer).app"]) == .electron)
        #expect(AppKind.of(frameworks: ["Google Chrome Framework.framework"]) == .chromium)
        #expect(AppKind.of(frameworks: ["Microsoft Edge Framework.framework"]) == .chromium)
        #expect(AppKind.of(frameworks: ["Chromium Embedded Framework.framework", "Sparkle.framework"]) == .chromium)
        #expect(AppKind.of(frameworks: ["Sparkle.framework", "Some Other Framework.framework"]) == .other)
        #expect(AppKind.of(frameworks: []) == .other)
        #expect(AppKind.electron.rawValue == "electron")
    }

    @Test func theSettingHasTwoChoicesInTitleCase() {
        #expect(PillPlacementMode.allCases.map(\.title) == ["Fixed Place", "Next to Text"])
        #expect(PillPlacementMode(rawValue: "nextToText") == .nextToText)
    }

    @Test func whereNobodyHasChosenThePillGoesNextToTheText() {
        #expect(PillPlacementMode.whenNotChosen == .nextToText)
        // A new install, and one on which the control was never touched: nothing is saved.
        #expect(PillPlacementMode(saved: nil) == .nextToText)
    }

    @Test func aSavedChoiceIsKept() {
        // Fixed Place is saved only by choosing it, and stays chosen.
        #expect(PillPlacementMode(saved: "fixedPlace") == .fixedPlace)
        #expect(PillPlacementMode(saved: "nextToText") == .nextToText)
        for mode in PillPlacementMode.allCases {
            #expect(PillPlacementMode(saved: mode.rawValue) == mode)
        }
    }

    @Test func aSavedChoiceThatCannotBeReadCountsAsNone() {
        #expect(PillPlacementMode(saved: "") == .nextToText)
        #expect(PillPlacementMode(saved: "Fixed Place") == .nextToText)
        #expect(PillPlacementMode(saved: "somewhereElse") == .nextToText)
    }
}

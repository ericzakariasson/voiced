#if DEBUG
import AppKit
import os
import SwiftUI
import VoicedKit

/// Development aid, compiled into Debug builds only: pictures of the real pill, for checking
/// that it looks the same in the light and the dark appearance, and as reference for anything
/// that has to show the pill, such as the film in video/.
///
///     Voiced.app/Contents/MacOS/Voiced -VoicedPillCaptures /path/to/folder [-VoicedPillPlates /path/to/plates]
///
/// Every picture is of this process's own windows: the real pill panel, in front of a plain
/// window of this process that stands in for whatever is on screen behind the pill. The window
/// server draws the two together, so the glass shows what is behind it as it does in use, and
/// since no other app's window is asked for, no Screen Recording permission is involved.
///
/// The pill is driven by fixed states or by a scripted dictation. Nothing here opens the
/// microphone, and the copy that runs has no hotkey.
enum DebugPillCaptures {
    static var isRequested: Bool {
        DebugRun.argument("-VoicedPillCaptures") != nil
    }

    /// The settings of every pill here and of the model behind the menu bar item.
    private static let defaults = DebugRun.settings

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    private final class PlaceholderKey: SecretStore, @unchecked Sendable {
        func read() throws -> String? { "captures-placeholder" }
        func save(_ secret: String) throws {}
        func delete() throws {}
    }

    /// The model behind the menu bar item in this mode: set up, and with a dictation loop whose
    /// audio is scripted, so the item can be photographed while it says it is recording.
    static func makeModel() -> AppModel {
        AppModel(
            permissions: Permissions(microphone: .granted, accessibility: true),
            secretStore: PlaceholderKey(),
            defaults: defaults,
            controller: scriptedController(script: Script(levels: Script.speech(seconds: 6)))
        )
    }

    static func run(model: AppModel) {
        guard let path = DebugRun.argument("-VoicedPillCaptures") else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let plates = DebugRun.argument("-VoicedPillPlates").map { URL(fileURLWithPath: $0, isDirectory: true) }
        let only = DebugRun.argument("-VoicedPillCapturesOnly")
        // Each line as it is printed, also into a file: a run takes minutes.
        setvbuf(stdout, nil, _IOLBF, 0)
        Task {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await captureAll(model: model, into: directory, plates: plates, only: only)
            } catch {
                print("Pill captures failed: \(error)")
                exit(1)
            }
            exit(0)
        }
    }

    private static func captureAll(model: AppModel, into directory: URL, plates: URL?, only: String?) async throws {
        // An app that is not in front has its timers held back and bunched together, which
        // would show as a pill that stutters and pictures taken in bursts.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Photographing the pill sixty times a second")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        try await Task.sleep(for: .seconds(1.5))
        guard let screen = NSScreen.main else { throw Failure(description: "no display") }
        print("Display: \(Int(screen.frame.width)) × \(Int(screen.frame.height)) pt at \(screen.backingScaleFactor)x, \(screen.maximumFramesPerSecond) frames per second, colour space \"\(screen.colorSpace?.localizedName ?? "unknown")\"")
        guard screen.backingScaleFactor == 2 else {
            throw Failure(description: "The captures are made at 2x, and this display is at \(screen.backingScaleFactor)x.")
        }
        func folder(_ name: String) throws -> URL {
            let url = directory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        func wanted(_ part: String) -> Bool {
            only.map { $0.split(separator: ",").contains(Substring(part)) } ?? true
        }
        if wanted("match") { try await lightAndDarkMatch(on: screen, into: folder("light-dark-match")) }
        if wanted("stills") { try await stills(on: screen, into: folder("stills")) }
        if wanted("motion") { try await motionOverWhite(on: screen, into: folder("motion-over-white")) }
        if wanted("film") {
            if let plates {
                try await motionOverPlates(from: plates, on: screen, into: folder("film"))
            } else {
                print("No plates were given (-VoicedPillPlates): the captures over the film's backgrounds were not made.")
            }
        }
        if wanted("menu") { try await menuBarItem(model: model, into: folder("menu-bar-item")) }
        print("Pill captures finished.")
    }

    // MARK: - Being on time

    /// Waits without trusting a timer. A sleep of a few milliseconds can come back a tenth of a
    /// second late, on a virtual Mac above all, and a script that is to hit a frame cannot have
    /// that. A thread of its own spins until the moment has come.
    nonisolated enum Punctual {
        static func sleep(until deadline: ContinuousClock.Instant) async throws {
            let isCancelled = OSAllocatedUnfairLock(initialState: false)
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let thread = Thread {
                        while ContinuousClock.now < deadline, !isCancelled.withLock({ $0 }) {}
                        continuation.resume()
                    }
                    thread.qualityOfService = .userInteractive
                    thread.start()
                }
            } onCancel: {
                isCancelled.withLock { $0 = true }
            }
            try Task.checkCancellation()
        }

        static func sleep(for duration: Duration) async throws {
            try await sleep(until: ContinuousClock.now + duration)
        }
    }

    /// The dictation loop's own waits, on time.
    nonisolated struct PunctualClock: DictationClock {
        var now: ContinuousClock.Instant { ContinuousClock.now }

        func sleep(until deadline: ContinuousClock.Instant) async throws {
            try await Punctual.sleep(until: deadline)
        }
    }

    /// Returns as soon as something observable has become true, without asking again and again.
    private static func wait(until condition: @escaping () -> Bool) async {
        while !condition() {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = condition()
                } onChange: {
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }
    }

    // MARK: - Pixels

    /// A picture as plain bytes, four per pixel: red, green, blue, alpha, top row first.
    nonisolated struct Pixels: @unchecked Sendable {
        var width: Int
        var height: Int
        var bytes: [UInt8]

        /// The image's own numbers, with no colour conversion: it is drawn in its own colour space.
        init(_ image: CGImage) throws {
            width = image.width
            height = image.height
            bytes = [UInt8](repeating: 0, count: width * height * 4)
            let space = image.colorSpace.flatMap { $0.supportsOutput && $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
            let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
                guard let space, let context = CGContext(
                    data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            guard drawn else { throw Failure(description: "Could not read a picture's pixels.") }
        }

        init(width: Int, height: Int, bytes: [UInt8]) {
            self.width = width
            self.height = height
            self.bytes = bytes
        }

        init(width: Int, height: Int, grey: UInt8) {
            self.init(width: width, height: height, bytes: (0..<width * height).flatMap { _ in [grey, grey, grey, 255] })
        }

        /// The part inside `rect`, which is in pixels with the origin at the top left.
        func cropped(to rect: CGRect) -> Pixels {
            let x0 = max(0, Int(rect.minX)), y0 = max(0, Int(rect.minY))
            let w = min(width - x0, Int(rect.width)), h = min(height - y0, Int(rect.height))
            var out = [UInt8]()
            out.reserveCapacity(w * h * 4)
            for row in 0..<h {
                let from = ((y0 + row) * width + x0) * 4
                out.append(contentsOf: bytes[from..<from + w * 4])
            }
            return Pixels(width: w, height: h, bytes: out)
        }

        /// These numbers as an image in sRGB.
        func image() throws -> CGImage {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let image = CGImage(
                      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                      decode: nil, shouldInterpolate: false, intent: .defaultIntent
                  ) else {
                throw Failure(description: "Could not make an image.")
            }
            return image
        }

        func write(to url: URL) throws {
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
                throw Failure(description: "Could not write \(url.lastPathComponent).")
            }
            CGImageDestinationAddImage(destination, try image(), nil)
            guard CGImageDestinationFinalize(destination) else {
                throw Failure(description: "Could not write \(url.lastPathComponent).")
            }
        }
    }

    /// A picture file's own numbers, read as sRGB.
    private static func pixels(contentsOf url: URL) throws -> (pixels: Pixels, image: CGImage) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure(description: "Could not read \(url.lastPathComponent).")
        }
        return (try Pixels(image), image)
    }

    /// How two pictures of the same size differ.
    nonisolated struct Difference: Sendable {
        var differingPixels = 0
        /// The largest difference in any one channel, of 255.
        var largest = 0
        /// The box around every differing pixel, in pixels from the top left; `nil` when none differs.
        var box: CGRect?

        var summary: String {
            guard let box else { return "0 pixels differ" }
            return "\(differingPixels) pixels differ, by at most \(largest) of 255, inside x=\(Int(box.minX))…\(Int(box.maxX) - 1) y=\(Int(box.minY))…\(Int(box.maxY) - 1)"
        }

        init(_ one: Pixels, _ other: Pixels) {
            guard one.width == other.width, one.height == other.height else {
                differingPixels = max(one.width * one.height, other.width * other.height)
                largest = 255
                box = CGRect(x: 0, y: 0, width: max(one.width, other.width), height: max(one.height, other.height))
                return
            }
            if one.bytes == other.bytes { return }
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            var count = 0, worstOfAll = 0
            let width = one.width, height = one.height
            one.bytes.withUnsafeBufferPointer { a in
                other.bytes.withUnsafeBufferPointer { b in
                    for y in 0..<height {
                        let row = y * width * 4
                        for x in 0..<width {
                            let i = row + x * 4
                            if a[i] == b[i], a[i + 1] == b[i + 1], a[i + 2] == b[i + 2], a[i + 3] == b[i + 3] { continue }
                            var worst = 0
                            for channel in 0..<4 {
                                worst = max(worst, abs(Int(a[i + channel]) - Int(b[i + channel])))
                            }
                            count += 1
                            worstOfAll = max(worstOfAll, worst)
                            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                        }
                    }
                }
            }
            differingPixels = count
            largest = worstOfAll
            if maxX >= 0 {
                box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            }
        }
    }

    // MARK: - The window server's picture of this app's own windows

    nonisolated enum WindowServer {
        private typealias ImageFromArray = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?
        /// `CGWindowListCreateImageFromArray` is hidden from Swift in current SDKs, hence the lookup by name.
        private static let imageFromArray: ImageFromArray? = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImageFromArray")
            .map { unsafeBitCast($0, to: ImageFromArray.self) }

        /// The named windows drawn together, the first in front, at the display's full resolution.
        /// `bounds` counts from the top left of the primary display, as the window server does.
        static func picture(ofWindows numbers: [Int], bounds: CGRect) -> CGImage? {
            guard let imageFromArray else { return nil }
            var identifiers: [UnsafeRawPointer?] = numbers.map { UnsafeRawPointer(bitPattern: $0) }
            guard let array = CFArrayCreate(nil, &identifiers, identifiers.count, nil) else { return nil }
            let bestResolution: UInt32 = 1 << 3
            return imageFromArray(bounds, array, bestResolution)?.takeRetainedValue()
        }
    }

    /// A part of the screen, given in AppKit's coordinates, as the window server counts it.
    static func windowServerBounds(_ frame: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// One picture of `windows` together, the first in front.
    private static func picture(of windows: [NSWindow], showing frame: CGRect) throws -> Pixels {
        guard let image = WindowServer.picture(ofWindows: windows.map(\.windowNumber), bounds: windowServerBounds(frame)) else {
            throw Failure(description: "The window server gave no picture.")
        }
        return try Pixels(image)
    }

    /// When this display shows a new picture: measured, not taken to be sixty times a second on
    /// the dot from some moment of our choosing.
    nonisolated struct Cadence: Sendable {
        /// Seconds from one picture on the display to the next.
        var period: Double
        /// A moment at which the display showed a new picture.
        var change: ContinuousClock.Instant
    }

    /// Finds the display's cadence by watching a speck of a window whose colour never rests,
    /// several thousand times a second for a second, and noting when it changes.
    private static func measureCadence(on screen: NSScreen) async throws -> Cadence {
        // A Mac that stalls for a moment while it is watched gives a crooked answer; ask again.
        var failure: any Error = Failure(description: "The display's cadence could not be measured.")
        for _ in 1...6 {
            do {
                return try await watchCadence(on: screen)
            } catch {
                failure = error
            }
        }
        throw failure
    }

    private static func watchCadence(on screen: NSScreen) async throws -> Cadence {
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 4, height: 4)
        let speck = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        speck.isReleasedWhenClosed = false
        speck.hasShadow = false
        speck.ignoresMouseEvents = true
        // In front of everything, as the pill is: a window that cannot be seen is not kept up to date.
        speck.level = .statusBar
        // Drawn the way the pill is drawn: a new grey for every picture the display asks for.
        speck.contentView = NSHostingView(rootView: TimelineView(.animation) { moment in
            Color(white: moment.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.5) * 2)
        })
        speck.orderFrontRegardless()
        defer { speck.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(400))

        let number = speck.windowNumber
        let bounds = windowServerBounds(frame)
        let (changes, looks): ([ContinuousClock.Instant], Int) = await withCheckedContinuation { continuation in
            let thread = Thread {
                var changes: [ContinuousClock.Instant] = []
                var last: UInt8?
                var looks = 0
                let until = ContinuousClock.now + .seconds(2)
                while ContinuousClock.now < until {
                    let asked = ContinuousClock.now
                    guard let image = WindowServer.picture(ofWindows: [number], bounds: bounds),
                          let data = image.dataProvider?.data, CFDataGetLength(data) > 1 else { continue }
                    let value = CFDataGetBytePtr(data)[1]
                    looks += 1
                    if let last, last != value {
                        changes.append(asked)
                    }
                    last = value
                }
                continuation.resume(returning: (changes, looks))
            }
            thread.qualityOfService = .userInteractive
            thread.start()
        }
        guard changes.count >= 40 else {
            throw Failure(description: "The display's cadence could not be measured: \(changes.count) changes in two seconds.")
        }
        // Count the changes off in whole pictures, and fit one period to all of them.
        let times = changes.map { Recorder.seconds($0 - changes[0]) }
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }.filter { $0 > 0.008 && $0 < 0.03 }.sorted()
        guard !gaps.isEmpty else { throw Failure(description: "The display's cadence could not be measured.") }
        let rough = gaps[gaps.count / 2]
        let counts = times.map { ($0 / rough).rounded() }
        let n = Double(times.count)
        let meanCount = counts.reduce(0, +) / n, meanTime = times.reduce(0, +) / n
        var together = 0.0, spread = 0.0
        for (count, time) in zip(counts, times) {
            together += (count - meanCount) * (time - meanTime)
            spread += (count - meanCount) * (count - meanCount)
        }
        let fitted = together / spread
        // Two seconds of watching fix the period to about a thousandth, and over a take of
        // several hundred pictures that is half a picture. The display's own figure is exact
        // where the watching agrees with it, and the watching then only says where the beat falls.
        let nominal = 1 / Double(max(screen.maximumFramesPerSecond, 1))
        guard abs(fitted - nominal) < nominal * 0.005 else {
            throw Failure(description: "The display showed a new picture every \(rounded(fitted * 1000)) ms while it was watched, and says it shows \(screen.maximumFramesPerSecond) a second.")
        }
        let period = nominal
        // Where on the beat the changes fall: each as an angle, and the mean of the angles.
        var sine = 0.0, cosine = 0.0
        for time in times {
            let angle = time / period * 2 * .pi
            sine += sin(angle)
            cosine += cos(angle)
        }
        var phase = atan2(sine, cosine) / (2 * .pi) * period
        if phase < 0 { phase += period }
        var worst = 0.0
        for time in times {
            var off = (time - phase).truncatingRemainder(dividingBy: period)
            if off > period / 2 { off -= period }
            if off < -period / 2 { off += period }
            worst = max(worst, abs(off))
        }
        // A change is seen at the first look after it: on average half a look late.
        let look = 2 / Double(max(looks, 1))
        print("Display cadence: \(changes.count) changes seen in two seconds, \(rounded(fitted * 1000)) ms apart by fit, taken as \(rounded(period * 1000)) ms; none more than \(rounded(worst * 1000)) ms off the beat; one look every \(rounded(look * 1000)) ms.")
        guard worst < period / 3 else {
            throw Failure(description: "The display does not keep a steady beat.")
        }
        return Cadence(period: period, change: changes[0] + .nanoseconds(Int64((phase - look / 2) * 1e9)))
    }

    /// Photographs windows once for each picture the display shows, on a thread of its own, so
    /// that the main thread is free to run the pill. It asks halfway between two of the
    /// display's pictures, where a picture can neither be caught twice nor missed.
    nonisolated final class Recorder: @unchecked Sendable {
        struct Frame: @unchecked Sendable {
            /// When the picture was asked for, in seconds since the recording began.
            var seconds: Double
            var image: CGImage
        }

        let began: ContinuousClock.Instant
        let cadence: Cadence
        private let numbers: [Int]
        private let bounds: CGRect
        private let lock = NSLock()
        private var frames: [Frame] = []
        private var isStopped = false
        private let finished = DispatchSemaphore(value: 0)
        /// Run on the main thread once for every picture, from `start` on. Set before `start`.
        var everyPicture: (@MainActor @Sendable () -> Void)?

        init(windowNumbers: [Int], bounds: CGRect, cadence: Cadence) {
            numbers = windowNumbers
            self.bounds = bounds
            self.cadence = cadence
            // The first moment from now that lies halfway between two of the display's pictures.
            let sinceChange = Self.seconds(ContinuousClock.now - cadence.change)
            let next = ((sinceChange / cadence.period).rounded(.up) + 0.5) * cadence.period
            began = cadence.change + .nanoseconds(Int64(next * 1e9))
        }

        static func seconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }

        func start() {
            let thread = Thread { [self] in
                var tick = 0
                while true {
                    lock.lock()
                    let stop = isStopped
                    lock.unlock()
                    if stop { break }
                    // Not a sleep: a sleep of a sixtieth of a second can come back a tenth of a
                    // second late, on a virtual Mac above all. This thread spins until it is time.
                    let due = began + .nanoseconds(Int64(Double(tick) * cadence.period * 1e9))
                    while ContinuousClock.now < due {}
                    let asked = Self.seconds(ContinuousClock.now - began)
                    if let everyPicture {
                        DispatchQueue.main.async { everyPicture() }
                    }
                    if let image = WindowServer.picture(ofWindows: numbers, bounds: bounds) {
                        lock.lock()
                        frames.append(Frame(seconds: asked, image: image))
                        lock.unlock()
                    }
                    tick += 1
                }
                finished.signal()
            }
            thread.qualityOfService = .userInteractive
            thread.start()
        }

        func stop() -> [Frame] {
            lock.lock()
            isStopped = true
            lock.unlock()
            finished.wait()
            return frames
        }

        var secondsNow: Double {
            Self.seconds(ContinuousClock.now - began)
        }
    }

    // MARK: - What is behind the pill

    /// A plain window of this process, behind the pill: one grey, or a picture shown pixel for pixel.
    final class Backdrop {
        let window: NSWindow
        private let view = NSView()

        init(frame: NSRect) {
            window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .normal
            window.hasShadow = false
            window.isOpaque = true
            window.ignoresMouseEvents = true
            view.wantsLayer = true
            view.frame = NSRect(origin: .zero, size: frame.size)
            window.contentView = view
            window.orderFrontRegardless()
        }

        func show(grey: UInt8) {
            let value = CGFloat(grey) / 255
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.layer?.contents = nil
            view.layer?.backgroundColor = CGColor(srgbRed: value, green: value, blue: value, alpha: 1)
            CATransaction.commit()
        }

        func show(_ image: CGImage) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.layer?.contentsScale = 2
            view.layer?.contentsGravity = .resize
            view.layer?.magnificationFilter = .nearest
            view.layer?.minificationFilter = .nearest
            view.layer?.contents = image
            CATransaction.commit()
        }

        /// Has the window server draw again, without drawing anything: moves a layer that has
        /// nothing in it.
        ///
        /// The spinner in the pill is turned by the window server, not by Voiced: the app starts
        /// an animation that repeats for ever and commits nothing more. On a Mac where no window
        /// counts as visible, such as one with nobody at the screen, the window server draws only
        /// when an app commits something, so the spinner stood still as soon as the pill around
        /// it had settled, and a square told to turn for ever in a plain window did the same.
        /// Called for every picture, this is the commit that a screen being looked at never needs.
        func keepTheWindowServerDrawing() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if nothing.superlayer == nil {
                nothing.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
                view.layer?.addSublayer(nothing)
            }
            nothing.position.x = nothing.position.x == 0.5 ? 1.5 : 0.5
            CATransaction.commit()
        }

        private let nothing = CALayer()

        func close() {
            window.orderOut(nil)
        }
    }

    private static let backgrounds: [(name: String, grey: UInt8)] = [("white", 255), ("light-grey", 217), ("mid-grey", 128), ("dark", 31)]

    // MARK: - The pill with fixed content

    /// The real pill panel showing one fixed state at a time, in front of a backdrop.
    ///
    /// A state is shown in one of two ways. Still: in a panel made for it, with nothing coming
    /// or going, which gives the same picture every time, to the pixel. Turning: in a panel
    /// that is already up, by way of the states that come before it in use, which is how a
    /// spinner is caught while it turns; one that comes up with its panel may never start, and
    /// any comes to rest about a second after it came up.
    final class Stage {
        static let size = NSSize(width: 460, height: 120)

        @Observable
        final class Shown {
            var content = IndicatorContent.hidden
            var level: Float = 0
            /// Where the pill is inside the panel, as SwiftUI reports it: from the top left, in points.
            @ObservationIgnored var pillFrame = CGRect.zero
        }

        private struct Root: View {
            var shown: Shown

            var body: some View {
                IndicatorView(content: shown.content, level: shown.level) { frame in
                    shown.pillFrame = frame
                }
            }
        }

        let frame: NSRect
        let backdrop: Backdrop
        private let lasting = PillPanel(size: Stage.size)
        private let shown = Shown()
        private var still: PillPanel?

        init(on screen: NSScreen) {
            let origin = NSPoint(x: (screen.visibleFrame.midX - Self.size.width / 2).rounded(), y: screen.visibleFrame.minY + 40)
            frame = NSRect(origin: origin, size: Self.size)
            backdrop = Backdrop(frame: frame)
            lasting.contentView = PillDragView(content: Root(shown: shown))
            lasting.setFrameOrigin(frame.origin)
            lasting.orderFrontRegardless()
        }

        func showStill(_ state: FixedState) async throws {
            shown.content = .hidden
            still?.orderOut(nil)
            let panel = PillPanel(size: Self.size)
            panel.contentView = PillDragView(content: IndicatorView(content: state.content(), level: state.level))
            panel.setFrameOrigin(frame.origin)
            panel.orderFrontRegardless()
            still = panel
            try await Task.sleep(for: .milliseconds(1200))
        }

        func showTurning(_ state: FixedState) async throws {
            still?.orderOut(nil)
            still = nil
            shown.content = .hidden
            try await Task.sleep(for: .milliseconds(500))
            for before in state.after {
                shown.level = 0.7
                shown.content = before()
                try await Task.sleep(for: .milliseconds(400))
            }
            shown.level = state.level
            shown.content = state.content()
            try await Task.sleep(for: .milliseconds(450))
        }

        /// Where the spinner is in a picture of the panel, in pixels, going by where the pill
        /// was when the state was last shown turning: the spinner leads the pill's row, 18 pt
        /// in from the pill's left edge, 16 pt across.
        var spinnerBox: CGRect {
            CGRect(x: (shown.pillFrame.minX + 14) * 2, y: (shown.pillFrame.midY - 12) * 2, width: 48, height: 48)
        }

        func picture() throws -> Pixels {
            try DebugPillCaptures.picture(of: windows, showing: frame)
        }

        var windows: [NSWindow] {
            [still ?? lasting, backdrop.window]
        }

        func close() {
            still?.orderOut(nil)
            lasting.orderOut(nil)
            backdrop.close()
        }
    }

    struct FixedState {
        var name: String
        /// Made when it is shown, so that a clock starts where the script wants it.
        var content: () -> IndicatorContent
        var level: Float = 0
        /// Something in it moves by itself: the microphone's pulse and the clock.
        var moves = false
        /// It has the spinner, which turns on a clock of its own and comes to rest where it will.
        var spins = false
        /// The states the pill passes through on its way to this one in use.
        var after: [() -> IndicatorContent] = []
    }

    private static let recording: () -> IndicatorContent = { .recording(since: Date().addingTimeInterval(-3.5)) }

    private static let fixedStates: [FixedState] = [
        FixedState(name: "starting-microphone", content: { .startingMicrophone }),
        // 3.5 s in when it is shown: the clock reads 0:04 from half a second to a second and a half after that.
        FixedState(name: "recording", content: recording, level: 0.7, moves: true),
        FixedState(name: "transcribing", content: { .working("Transcribing…") }, spins: true, after: [recording]),
        FixedState(name: "polishing", content: { .working("Polishing…") }, spins: true, after: [recording, { .working("Transcribing…") }]),
        FixedState(name: "warning", content: { .notice(.warning, "Cleanup failed, inserted the raw transcript.") }),
        FixedState(name: "error", content: { .notice(.error, "The Grok API Key was rejected. Check it in Settings.") }),
        FixedState(name: "placing", content: { .placing }),
    ]

    // MARK: - The same in the light and the dark appearance

    /// A copy with one rectangle painted over, so that two pictures can be compared outside it.
    private static func covering(_ box: CGRect, in pixels: Pixels) -> Pixels {
        var copy = pixels
        for y in Int(box.minY)..<Int(box.maxY) {
            for i in (y * pixels.width + Int(box.minX)) * 4..<(y * pixels.width + Int(box.maxX)) * 4 {
                copy.bytes[i] = 0
            }
        }
        return copy
    }

    /// Every state over every background, once with the app in the light appearance and once
    /// in the dark one, and how the two pictures differ.
    ///
    /// Three states have a mark that moves by itself, and two runs are never at the very same
    /// point of it. Such a state is photographed for two seconds in each appearance.
    ///
    /// - Recording: the microphone pulses and the clock counts. The part of the picture that
    ///   changed during the two seconds is the part that moves. Outside it the light and the
    ///   dark picture must be the same; inside it, every light picture is set against every
    ///   dark one, and the nearest pair counts.
    /// - Transcribing and polishing: the spinner turns, and comes to rest where it will. A
    ///   picture of the state shown still must be the same outside the spinner; the spinner
    ///   itself is compared as the nearest pair of a light and a dark picture of it, taken
    ///   while it turns.
    private static func lightAndDarkMatch(on screen: NSScreen, into directory: URL) async throws {
        let cadence = try await measureCadence(on: screen)
        let stage = Stage(on: screen)
        defer {
            stage.close()
            NSApp.appearance = nil
        }
        var lines = [
            "# The pill in the light and in the dark appearance",
            "",
            "Each row is one state over one background, photographed at 2x (920 × 240 pixels) with the app in the light appearance and again in the dark one.",
            "",
            "Three states have a mark that moves by itself, and two runs are never at the same point of it, so those states are photographed for two seconds in each appearance. In recording, the part that changed in that time (the microphone that pulses, the clock) is the moving part. In transcribing and polishing it is the spinner. Outside the moving part the two appearances are compared as they are; inside it, the nearest pair of a light and a dark picture is compared.",
            "",
            "| State | Background | Outside the moving part | The moving part |",
            "| --- | --- | --- | --- |",
        ]
        var differingOutside = 0
        var differingInside = 0
        for background in backgrounds {
            stage.backdrop.show(grey: background.grey)
            for state in fixedStates {
                var spinner = CGRect.null
                /// The state brought up in one appearance, and its pictures: two seconds of them
                /// where something moves. The last is of the state shown still.
                func photograph(in appearance: NSAppearance.Name) async throws -> [Pixels] {
                    NSApp.appearance = NSAppearance(named: appearance)
                    var pictures: [Pixels] = []
                    if state.spins {
                        try await stage.showTurning(state)
                        // Now, while the pill stands: as it leaves, it shrinks.
                        spinner = stage.spinnerBox
                    } else {
                        try await stage.showStill(state)
                    }
                    if state.moves || state.spins {
                        let recorder = Recorder(windowNumbers: stage.windows.map(\.windowNumber), bounds: windowServerBounds(stage.frame), cadence: cadence)
                        recorder.start()
                        try await Task.sleep(for: .seconds(2))
                        pictures = try recorder.stop().map { try Pixels($0.image) }
                    }
                    if state.spins {
                        try await stage.showStill(state)
                    }
                    if !state.moves {
                        pictures.append(try stage.picture())
                    }
                    return pictures
                }
                var light = try await photograph(in: .aqua)
                var dark = try await photograph(in: .darkAqua)
                guard let lastLight = light.last, let lastDark = dark.last else {
                    throw Failure(description: "No pictures of \(state.name) over \(background.name).")
                }
                // The backdrop must have come through as it was asked for, or the pictures show something else.
                let corner = Array(lastLight.bytes[0..<3])
                guard corner == [background.grey, background.grey, background.grey] else {
                    throw Failure(description: "The \(background.name) background came out as \(corner), not \(background.grey).")
                }

                var moving = CGRect.null
                if state.spins {
                    moving = spinner
                } else if state.moves {
                    // Whatever changed from one picture to the next.
                    for run in [light, dark] {
                        for (earlier, later) in zip(run, run.dropFirst()) {
                            if let box = Difference(earlier, later).box {
                                moving = moving.union(box)
                            }
                        }
                    }
                }
                var best = (light: lastLight, dark: lastDark)
                let outside: Difference
                var inside: Difference?
                if moving.isNull {
                    outside = Difference(lastLight, lastDark)
                } else {
                    outside = Difference(covering(moving, in: lastLight), covering(moving, in: lastDark))
                    // A spinner turns for a moment and rests where it will. When the two runs
                    // never showed it at the same point, both are run again and the pictures of
                    // every run so far are set against each other.
                    for run in 1...6 {
                        let lightParts = light.map { $0.cropped(to: moving) }
                        let darkParts = dark.map { $0.cropped(to: moving) }
                        // A pair that is the same to the byte is found at once; only where there
                        // is none is every pair measured for how far apart it is.
                        let darkIndex = Dictionary(darkParts.enumerated().map { ($0.element.bytes, $0.offset) }, uniquingKeysWith: { first, _ in first })
                        if let i = lightParts.firstIndex(where: { darkIndex[$0.bytes] != nil }), let j = darkIndex[lightParts[i].bytes] {
                            inside = Difference(lightParts[i], darkParts[j])
                            if !state.spins {
                                best = (light[i], dark[j])
                            }
                            break
                        }
                        search: for (i, lightPart) in lightParts.enumerated() {
                            for (j, darkPart) in darkParts.enumerated() {
                                let difference = Difference(lightPart, darkPart)
                                if inside.map({ (difference.largest, difference.differingPixels) < ($0.largest, $0.differingPixels) }) ?? true {
                                    inside = difference
                                    // For the spinner the settled pictures are kept: the words are still coming in the early ones.
                                    if !state.spins {
                                        best = (light[i], dark[j])
                                    }
                                    if difference.differingPixels == 0 { break search }
                                }
                            }
                        }
                        guard state.spins, inside?.differingPixels != 0, run < 6 else { break }
                        light += try await photograph(in: .aqua)
                        dark += try await photograph(in: .darkAqua)
                    }
                }
                try best.light.write(to: directory.appendingPathComponent("\(state.name)-over-\(background.name)-light.png"))
                try best.dark.write(to: directory.appendingPathComponent("\(state.name)-over-\(background.name)-dark.png"))
                differingOutside += outside.differingPixels
                differingInside += inside?.differingPixels ?? 0
                let what = state.spins ? "the spinner, " : ""
                let movingPart = inside.map { "\(what)\(Int(moving.width)) × \(Int(moving.height)) pixels at x=\(Int(moving.minX)) y=\(Int(moving.minY)); nearest of \(light.count) × \(dark.count) pairs: \($0.summary)" } ?? "nothing moves"
                lines.append("| \(state.name) | \(background.name) | \(outside.summary) | \(movingPart) |")
                print("Light against dark, \(state.name) over \(background.name): \(outside.summary) outside the moving part; the moving part: \(movingPart)")
            }
        }
        let verdict = differingOutside + differingInside == 0
            ? "No pixel differs in any state over any background: not outside the marks that move by themselves, and not in them, where a light and a dark picture at the same point of the movement were found every time."
            : "\(differingOutside) pixels differ outside the marks that move by themselves, and \(differingInside) in them at the nearest point of the movement found."
        lines.append("")
        lines.append(verdict)
        try (lines.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("differences.md"), atomically: true, encoding: .utf8)
        print("Light and dark: \(verdict)")
        guard differingOutside + differingInside == 0 else {
            throw Failure(description: "The pill is not the same in the light and the dark appearance.")
        }
    }

    // MARK: - Stills

    private static func stills(on screen: NSScreen, into directory: URL) async throws {
        let stage = Stage(on: screen)
        NSApp.appearance = NSAppearance(named: .aqua)
        defer {
            stage.close()
            NSApp.appearance = nil
        }
        stage.backdrop.show(grey: 255)
        for state in fixedStates {
            try await stage.showStill(state)
            try stage.picture().write(to: directory.appendingPathComponent("\(state.name)-over-white.png"))
        }
        print("Saved \(fixedStates.count) stills over white, 920 × 240 pixels each: the whole pill panel, with the pill standing 10 pt above its bottom edge.")
    }

    // MARK: - A scripted dictation

    /// What a scripted dictation does and how long each part of it takes.
    struct Script {
        /// The level the pill's bars are to show for each tenth of a second of audio.
        var levels: [Float]
        /// From the first audio to the hotkey coming up.
        var recording: Duration = .milliseconds(5500)
        /// How long the pill says "Transcribing…", from the hotkey coming up.
        var transcribing: Duration = .milliseconds(450)
        var polishing: Duration = .milliseconds(700)
        var minimumHold: Duration = DictationController.defaultMinimumHold

        /// A made-up voice: words of a few tenths of a second with short gaps between them.
        nonisolated static func speech(seconds: Double) -> [Float] {
            let words: [Float] = [0.22, 0.95, 0.31, 0.88, 0.42, 0.74, 0.55, 0.67, 0.12, 0, 0.5, 0.81, 0.36, 0.92, 0.6, 0.28, 0.79, 0.47, 0.08, 0]
            return [0] + (0..<Int((seconds * 10).rounded(.up))).map { words[$0 % words.count] }
        }
    }

    /// 100 ms of a square wave, whose loudness is simply its amplitude.
    private nonisolated static func tone(amplitude: Int16) -> Data {
        let samples = (0..<1600).map { ($0 / 40).isMultiple(of: 2) ? amplitude : -amplitude }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Audio for which the app's own level meter shows `levels`, one chunk of 100 ms per level.
    /// The meter fits its scale to what it has heard, so each chunk's loudness is found by
    /// trying it on a copy of the meter as the dictation's own meter will stand at that point.
    nonisolated static func audio(showing levels: [Float]) -> (chunks: [Data], shown: [Float]) {
        var meter = LevelMeter()
        var chunks: [Data] = []
        var shown: [Float] = []
        for target in levels {
            var low: Int16 = 0, high: Int16 = 32767
            if target <= 0 {
                // A quiet room, not digital silence.
                high = 8
            } else {
                while high - low > 1 {
                    let middle = low + (high - low) / 2
                    var trial = meter
                    if trial.level(forPCM16: tone(amplitude: middle)) < target {
                        low = middle
                    } else {
                        high = middle
                    }
                }
            }
            let chunk = tone(amplitude: high)
            shown.append(meter.level(forPCM16: chunk))
            chunks.append(chunk)
        }
        return (chunks, shown)
    }

    /// Hands out scripted audio, one chunk every 100 ms from the moment it is started.
    final class ScriptedAudio: AudioCapturing {
        private let chunks: [Data]
        private var feeder: Task<Void, Never>?

        init(chunks: [Data]) {
            self.chunks = chunks
        }

        func start() -> AsyncThrowingStream<AudioChunk, any Error> {
            let (stream, continuation) = AsyncThrowingStream<AudioChunk, any Error>.makeStream()
            let chunks = chunks
            feeder = Task {
                let began = ContinuousClock.now
                var index = 0
                while !Task.isCancelled {
                    try? await Punctual.sleep(until: began + .milliseconds(100 * index))
                    guard !Task.isCancelled else { break }
                    // After the script, the quiet room goes on until the hotkey comes up.
                    continuation.yield(AudioChunk(pcm: index < chunks.count ? chunks[index] : DebugPillCaptures.tone(amplitude: 8)))
                    index += 1
                }
                continuation.finish()
            }
            return stream
        }

        func stop() {
            feeder?.cancel()
        }
    }

    private actor TimedSession: TranscriptionSession {
        let lasts: Duration

        init(lasts: Duration) {
            self.lasts = lasts
        }

        func start() {}
        func send(audio: Data) {}
        func cancel() {}

        func finish() async throws -> TranscriptionResult {
            try await Punctual.sleep(for: lasts)
            return TranscriptionResult(text: "um this is a scripted dictation", isComplete: true)
        }
    }

    private struct TimedCleaner: TextCleaning {
        var lasts: Duration

        func clean(_ transcript: String) async throws -> String {
            try await Punctual.sleep(for: lasts)
            return "This is a scripted dictation."
        }
    }

    /// Pastes nothing, and says when it would have.
    final class Paste: TextInserting {
        var onInsert: () -> Void = {}

        func insert(_ text: String) async throws {
            onInsert()
        }
    }

    private static func scriptedController(script: Script, paste: Paste = Paste()) -> DictationController {
        let chunks = audio(showing: script.levels).chunks
        let releaseTail = Duration.milliseconds(150)
        let transcribing = max(script.transcribing - releaseTail, .zero)
        let polishing = script.polishing
        return DictationController(dependencies: .init(
            apiKey: { "captures-placeholder" },
            makeCapture: { ScriptedAudio(chunks: chunks) },
            // "Transcribing…" is up from the release: through the release tail, then the session.
            makeTranscription: { _ in TimedSession(lasts: transcribing) },
            makeCleaner: { _ in TimedCleaner(lasts: polishing) },
            inserter: paste,
            minimumHold: script.minimumHold,
            releaseTail: releaseTail,
            clock: PunctualClock()
        ))
    }

    /// One scripted dictation through the real controller and the real pill panel, photographed
    /// once for each picture the display shows, from before the pill appears until after it
    /// has gone.
    private struct Take {
        var frames: [Recorder.Frame] = []
        /// Seconds from one picture to the next, as measured on this display just before.
        var period = 1.0 / 60
        /// When each thing happened, in seconds since the recording began.
        var keyDown = 0.0
        var listening = 0.0
        var released = 0.0
        var polishing = 0.0
        var pasted = 0.0
        /// When the controller was seen to be done, which it is as soon as the paste is asked for.
        var done = 0.0
        var placement: PillNearText?
        /// Where the pill panel and the pill itself were while the pill was up.
        var panelFrame = CGRect.zero
        var pillFrame = CGRect.zero
        var levelsShown: [Float] = []

        /// The first picture taken at or after a moment.
        func index(at seconds: Double) -> Int {
            frames.firstIndex { $0.seconds >= seconds } ?? frames.count
        }

        /// The longest time between two pictures, in milliseconds.
        var longestGap: Double {
            DebugPillCaptures.rounded((zip(frames.dropFirst(), frames).map { $0.seconds - $1.seconds }.max() ?? 0) * 1000)
        }
    }

    private final class Times {
        var pasted = 0.0
    }

    private static func take(
        script: Script, pill: PillSettings, behind: [NSWindow], showing frame: CGRect, on screen: NSScreen,
        everyPicture: (@MainActor @Sendable () -> Void)? = nil, atPaste: @escaping () -> Void = {}
    ) async throws -> Take {
        let paste = Paste()
        let controller = scriptedController(script: script, paste: paste)
        let panel = IndicatorPanel(controller: controller, pill: pill)
        // Just before, every time: a beat measured minutes ago has drifted.
        let cadence = try await measureCadence(on: screen)
        let recorder = Recorder(windowNumbers: ([panel.window] + behind).map(\.windowNumber), bounds: windowServerBounds(frame), cadence: cadence)
        var take = Take()
        take.period = cadence.period
        take.levelsShown = audio(showing: script.levels).shown
        let times = Times()
        paste.onInsert = {
            times.pasted = recorder.secondsNow
            atPaste()
        }
        recorder.everyPicture = everyPicture

        recorder.start()
        try await Punctual.sleep(for: .milliseconds(300))
        take.keyDown = recorder.secondsNow
        if pill.mode == .nextToText {
            pill.textLookup.begin()
            // The answer is asked for off the main thread; a real one is there in a few milliseconds too.
            while pill.textLookup.answer == nil {
                try await Task.sleep(for: .milliseconds(1))
            }
            take.keyDown = recorder.secondsNow
        }
        controller.begin()
        await wait { controller.isListening }
        take.listening = recorder.secondsNow
        try await Punctual.sleep(until: recorder.began + .nanoseconds(Int64(take.listening * 1e9)) + script.recording)
        take.released = recorder.secondsNow
        take.panelFrame = panel.window.frame
        take.pillFrame = panel.pillFrameOnScreen
        controller.end()
        await wait { controller.phase != .transcribing }
        take.polishing = recorder.secondsNow
        await wait { controller.phase == .idle }
        take.done = recorder.secondsNow
        take.placement = panel.placementForDictation
        while panel.window.isVisible {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(250))
        take.frames = recorder.stop()
        take.pasted = times.pasted
        guard controller.notice == nil else {
            throw Failure(description: "The scripted dictation ended with a notice.")
        }
        return take
    }

    /// How many pictures in a stretch are the same as the one before, where every one ought to
    /// differ because something in the pill is moving.
    private static func repeats(in pictures: [Pixels], from start: Int, to end: Int) -> Int {
        guard end > start + 1 else { return 0 }
        return (start + 1..<end).filter { pictures[$0].bytes == pictures[$0 - 1].bytes }.count
    }

    /// The longest run of pictures in a stretch that are each the same as the one before.
    private static func longestRest(in pictures: [Pixels], from start: Int, to end: Int) -> Int {
        var longest = 0, run = 0
        for index in max(start + 1, 1)..<max(end, start + 1) {
            run = pictures[index].bytes == pictures[index - 1].bytes ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    private static func write(json value: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private static func box(_ rect: CGRect) -> [String: Int] {
        ["left": Int(rect.minX), "top": Int(rect.minY), "width": Int(rect.width), "height": Int(rect.height)]
    }

    // MARK: - The motion over white

    /// The pill at its fixed place over white, through one whole dictation, timed as the app
    /// times it: the pill appears once the hotkey has been held a quarter of a second, and its
    /// clock counts from the first audio, which here arrives as the hotkey goes down.
    private static func motionOverWhite(on screen: NSScreen, into directory: URL) async throws {
        NSApp.appearance = NSAppearance(named: .aqua)
        defer { NSApp.appearance = nil }
        let settings = PillSettings(defaults: defaults)
        settings.mode = .fixedPlace
        settings.reset()
        // Where the app puts the pill until it has been moved, and the panel around it.
        let anchor = PillPlacement.defaultAnchor(on: PillPlacement.Display(id: "captures", visibleFrame: screen.visibleFrame))
        let frame = CGRect(x: anchor.x - Stage.size.width / 2, y: anchor.y - IndicatorView.bottomPadding, width: Stage.size.width, height: Stage.size.height)
        let white = Backdrop(frame: frame)
        defer { white.close() }
        white.show(grey: 255)
        try await Task.sleep(for: .milliseconds(300))

        let script = Script(levels: Script.speech(seconds: 5.5))
        let blank = Pixels(width: Int(frame.width) * 2, height: Int(frame.height) * 2, grey: 255)
        // A take in which the pictures were not taken evenly, or one was caught twice, is taken again.
        var kept: (take: Take, pictures: [Pixels], appears: Int, last: Int, repeated: Int)?
        for attempt in 1...4 {
            let take = try await take(
                script: script, pill: settings, behind: [white.window], showing: frame, on: screen,
                everyPicture: { white.keepTheWindowServerDrawing() }
            )
            guard take.panelFrame == frame else {
                throw Failure(description: "The pill panel was at \(take.panelFrame), not at \(frame) where the white is.")
            }
            let pictures = try take.frames.map { try Pixels($0.image) }
            guard let appears = pictures.firstIndex(where: { $0.bytes != blank.bytes }),
                  let last = pictures.lastIndex(where: { $0.bytes != blank.bytes }) else {
                throw Failure(description: "The pill never showed over the white.")
            }
            // While it records, the microphone pulses and the bars move: no two pictures alike.
            let repeated = repeats(in: pictures, from: appears, to: take.index(at: take.released))
            let even = take.longestGap < take.period * 1500
            print("Motion over white, take \(attempt): \(pictures.count) pictures, \(repeated) the same as the one before while recording, longest gap \(take.longestGap) ms.")
            if kept.map({ repeated < $0.repeated }) ?? true, even || attempt == 4 {
                kept = (take, pictures, appears, last, repeated)
            }
            if repeated == 0, even { break }
        }
        guard let kept else { throw Failure(description: "No take of the motion over white.") }
        let take = kept.take
        // The spinner is up from soon after the release until the paste, and must turn all the while.
        let spinnerRests = longestRest(in: kept.pictures, from: take.index(at: take.released) + 4, to: take.index(at: take.pasted))
        guard spinnerRests <= 6 else {
            throw Failure(description: "Motion over white: the spinner stood still for \(spinnerRests) pictures while the pill was working.")
        }
        for (index, picture) in kept.pictures.enumerated() {
            try picture.write(to: directory.appendingPathComponent(String(format: "%04d.png", index)))
        }
        let pillBox = CGRect(
            x: (take.pillFrame.minX - frame.minX) * 2, y: (frame.maxY - take.pillFrame.maxY) * 2,
            width: take.pillFrame.width * 2, height: take.pillFrame.height * 2
        )
        try write(json: [
            "about": "Voiced's real pill at its fixed place over white, through one scripted dictation, photographed at 2x once for each picture the display showed. Each picture is the whole pill panel, 460 × 120 pt. The numbers under frameOf are picture numbers.",
            "frames": kept.pictures.count,
            "secondsFromOneFrameToTheNext": take.period,
            "pixelsPerPoint": 2,
            "longestGapBetweenFramesInMilliseconds": take.longestGap,
            "framesTheSameAsTheOneBeforeWhileRecording": kept.repeated,
            "longestRunOfFramesTheSameWhileTheSpinnerIsUp": spinnerRests,
            "pillWhileRecording": box(pillBox),
            "frameOf": [
                "hotkeyDown": take.index(at: take.keyDown),
                "firstAudioAndClockZero": take.index(at: take.listening),
                "pillAppears": kept.appears,
                "hotkeyUpAndTranscribing": take.index(at: take.released),
                "polishing": take.index(at: take.polishing),
                "textPastedAndPillStartsToLeave": take.index(at: take.pasted),
                "pillGone": kept.last + 1,
            ],
            "levelPerTenthOfASecondAsked": script.levels.map { rounded(Double($0)) },
            "levelPerTenthOfASecondShown": take.levelsShown.map { rounded(Double($0)) },
        ], to: directory.appendingPathComponent("timeline.json"))
        print("Motion over white: \(kept.pictures.count) pictures, one every \(rounded(take.period * 1000)) ms; the pill appears on \(kept.appears) and is gone by \(kept.last + 1).")
    }

    // MARK: - The motion over the film's own backgrounds

    private static func rect(_ value: Any?) throws -> CGRect {
        guard let value = value as? [String: Any],
              let left = (value["left"] as? NSNumber)?.doubleValue, let top = (value["top"] as? NSNumber)?.doubleValue,
              let width = (value["width"] as? NSNumber)?.doubleValue, let height = (value["height"] as? NSNumber)?.doubleValue else {
            throw Failure(description: "plates.json: a rectangle is missing.")
        }
        return CGRect(x: left, y: top, width: width, height: height)
    }

    private static func number(_ value: Any?, _ what: String) throws -> Double {
        guard let number = (value as? NSNumber)?.doubleValue else { throw Failure(description: "plates.json: \(what) is missing.") }
        return number
    }

    /// What one take over a plate came to.
    private struct FilmTake {
        /// The longest run of pictures, while the spinner is up, each the same as the one before.
        var spinnerRests: Int
        /// Milliseconds from the paste being asked for to the controller being seen done.
        var doneAfterPaste: Double
        /// The first picture taken after the paste was asked for, counted from the pill appearing.
        var pastedBeforePicture: Int
        /// The picture on which the plate with the text first shows, where it shows at all.
        var textShows: Int?
        /// The pictures from the one the pill first shows on to the last it shows on.
        var pictures: [Pixels]
        /// The picture on which each change first shows, counted from the pill appearing.
        var shows: [String: Int]
        var repeatedWhileRecording: Int
        var repeatedInAll: Int
        var longestGap: Double
        var period: Double
        var pillArea: CGRect
        var anchor: CGPoint
        var levelsShown: [Float]
        var textShowsInRectangle: Bool
    }

    /// For each plate of the film: the real pill, placed by the app's own rule from the text
    /// position the plate gives, run through the plate's timeline, in front of the plate itself.
    ///
    /// The plate is shown pixel for pixel in a window of this process, and that is checked
    /// before anything else. The pictures are numbered from the one the pill first shows on,
    /// which stands for the film frame on which the pill appears. A take is repeated, with its
    /// waits a frame longer or shorter, until each change shows on the frame the film names.
    private static func motionOverPlates(from plates: URL, on screen: NSScreen, into directory: URL) async throws {
        NSApp.appearance = NSAppearance(named: .aqua)
        defer { NSApp.appearance = nil }
        let description = try JSONSerialization.jsonObject(with: Data(contentsOf: plates.appendingPathComponent("plates.json")))
        guard let description = description as? [String: Any], let list = description["plates"] as? [[String: Any]],
              let film = description["film"] as? [String: Any] else {
            throw Failure(description: "plates.json could not be read.")
        }
        let filmSize = CGSize(width: try number(film["width"], "film.width"), height: try number(film["height"], "film.height"))
        let frame = CGRect(
            x: screen.frame.minX, y: screen.visibleFrame.minY + ((screen.visibleFrame.height - filmSize.height / 2) / 2).rounded(.down),
            width: filmSize.width / 2, height: filmSize.height / 2
        )
        guard screen.visibleFrame.contains(frame) else {
            throw Failure(description: "A plate of \(Int(filmSize.width)) × \(Int(filmSize.height)) pixels does not fit this display at 2x.")
        }
        /// A rectangle of the plate, in film pixels from its top left, as it lies on this screen.
        func onScreen(_ rect: CGRect) -> CGRect {
            CGRect(x: frame.minX + rect.minX / 2, y: frame.maxY - rect.maxY / 2, width: rect.width / 2, height: rect.height / 2)
        }
        let backdrop = Backdrop(frame: frame)
        defer { backdrop.close() }
        var summary: [[String: Any]] = []

        for plate in list {
            guard let app = plate["app"] as? String, let beforeName = plate["plate"] as? String, let landedName = plate["plateLanded"] as? String,
                  let pillInPlate = plate["pill"] as? [String: Any], let timeline = plate["timeline"] as? [String: Any],
                  let levels = (plate["level"] as? [String: Any])?["values"] as? [NSNumber] else {
                throw Failure(description: "plates.json: a plate is incomplete.")
            }
            guard try number(plate["pixelsPerPoint"], "pixelsPerPoint") == 2 else {
                throw Failure(description: "The \(app) plate is not at 2 film pixels per point.")
            }
            let before = try pixels(contentsOf: plates.appendingPathComponent(beforeName))
            let landed = try pixels(contentsOf: plates.appendingPathComponent(landedName))

            // The plate on screen must be the plate, pixel for pixel, or nothing after means anything.
            for (name, picture) in [(beforeName, before), (landedName, landed)] {
                backdrop.show(picture.image)
                try await Task.sleep(for: .milliseconds(400))
                let shown = try self.picture(of: [backdrop.window], showing: frame)
                let difference = Difference(shown, picture.pixels)
                guard difference.differingPixels == 0 else {
                    throw Failure(description: "\(name) did not come through pixel for pixel: \(difference.summary).")
                }
            }

            let captureRect = try rect(pillInPlate["suggestedCaptureRect"] ?? pillInPlate["box"])
            let pillBox = try rect(pillInPlate["box"])
            let line = try rect(plate["insertionPointLine"])
            let field = try rect(plate["field"])
            guard let anchorInPlate = pillInPlate["anchor"] as? [String: Any] else { throw Failure(description: "plates.json: no anchor.") }
            let plateAnchor = CGPoint(x: try number(anchorInPlate["x"], "anchor.x"), y: try number(anchorInPlate["y"], "anchor.y"))
            // What the film takes the app to be told: an app built on AppKit gives the box of
            // the line above the insertion point at the end of a text, any other the line itself.
            let lineUp = (plate["appBuiltAs"] as? String) == "appKit" ? line.offsetBy(dx: 0, dy: -line.height) : line
            var answer = FocusedTextAnswer()
            answer.geometry = FocusedTextGeometry(insertionPoint: .init(rect: onScreen(lineUp), mayBeOneLineUp: true), field: onScreen(field))
            answer.focus = 0
            let scripted = answer

            // The window server takes its bounds in whole points, and the rectangle may begin on
            // an odd pixel: the pictures are taken of the whole points around it and cut to it.
            let around = CGRect(
                x: (captureRect.minX / 2).rounded(.down) * 2, y: (captureRect.minY / 2).rounded(.down) * 2, width: 0, height: 0
            ).union(CGRect(x: (captureRect.maxX / 2).rounded(.up) * 2, y: (captureRect.maxY / 2).rounded(.up) * 2, width: 0, height: 0))
            let cut = captureRect.offsetBy(dx: -around.minX, dy: -around.minY)
            let beforeCrop = before.pixels.cropped(to: captureRect)
            let landedCrop = landed.pixels.cropped(to: captureRect)

            func frames(_ key: String) throws -> Int {
                Int(try number((timeline[key] as? [String: Any])?["frame"], "timeline.\(key).frame"))
            }
            let appearsInFilm = try frames("appears")
            let asked: [String: Int] = [
                "transcribing": try frames("transcribing") - appearsInFilm,
                "polishing": try frames("polishing") - appearsInFilm,
                "leaves": try frames("leaves") - appearsInFilm,
            ]

            /// One take with the given waits, and what the pictures show.
            func attempt(_ script: Script) async throws -> FilmTake {
                backdrop.show(before.image)
                try await Task.sleep(for: .milliseconds(400))
                let settings = PillSettings(defaults: defaults)
                settings.reset()
                settings.mode = .nextToText
                settings.textLookup.appToAsk = { PillTextLookup.Target(pid: getpid()) }
                settings.textLookup.locate = { _, _ in scripted }
                let take = try await take(
                    script: script, pill: settings, behind: [backdrop.window], showing: onScreen(around), on: screen,
                    everyPicture: { backdrop.keepTheWindowServerDrawing() }
                ) {
                    backdrop.show(landed.image)
                }

                // Where the app's own rule put the pill, in film pixels, against where the film has it.
                guard let placed = take.placement else { throw Failure(description: "\(app): the pill was not placed by the rule.") }
                let placedInPlate = CGPoint(x: (placed.anchor.x - frame.minX) * 2, y: (frame.maxY - placed.anchor.y) * 2)
                guard placed.source == .insertionPoint, abs(placedInPlate.x - plateAnchor.x) < 0.01, abs(placedInPlate.y - plateAnchor.y) < 0.01 else {
                    throw Failure(description: "\(app): the app's rule puts the pill by the \(placed.source.rawValue) at \(placedInPlate) in the plate, and the film has it at \(plateAnchor).")
                }

                let pictures = try take.frames.map { try Pixels($0.image).cropped(to: cut) }
                // Each picture against the plate behind it at the time: the one it differs from less.
                let differences = pictures.map { picture -> (landed: Bool, difference: Difference) in
                    let fromBefore = Difference(picture, beforeCrop)
                    guard fromBefore.differingPixels > 0 else { return (false, fromBefore) }
                    let fromLanded = Difference(picture, landedCrop)
                    return fromLanded.differingPixels < fromBefore.differingPixels ? (true, fromLanded) : (false, fromBefore)
                }
                guard let appears = differences.firstIndex(where: { $0.difference.differingPixels > 0 }),
                      let lastWithPill = differences.lastIndex(where: { $0.difference.differingPixels > 0 }) else {
                    throw Failure(description: "\(app): the pill never showed over the plate.")
                }
                // The film pastes the rectangle in whole. So what differs from the plate, which is the
                // pill, must lie well inside it: an edge that is the plate's own leaves no seam.
                let inside = CGRect(x: 0, y: 0, width: captureRect.width, height: captureRect.height).insetBy(dx: 8, dy: 8)
                var pillArea = CGRect.null
                for (index, entry) in differences.enumerated() {
                    guard let box = entry.difference.box else { continue }
                    pillArea = pillArea.union(box)
                    guard inside.contains(box) else {
                        // Left behind for whoever looks into it.
                        try? pictures[index].write(to: directory.appendingPathComponent("\(app)-failed-picture-\(index).png"))
                        try? beforeCrop.write(to: directory.appendingPathComponent("\(app)-failed-plate-before.png"))
                        try? landedCrop.write(to: directory.appendingPathComponent("\(app)-failed-plate-landed.png"))
                        throw Failure(description: "\(app): picture \(index) differs from the plate near the edge of the rectangle: \(entry.difference.summary).")
                    }
                }
                // The plate with the text goes behind the pill at the paste. Where the text shows
                // inside the rectangle, the pictures say on which one it came.
                let pasted = take.index(at: take.pasted)
                let textShowsInRectangle = beforeCrop.bytes != landedCrop.bytes
                if textShowsInRectangle {
                    guard let firstLanded = differences.firstIndex(where: { $0.landed }), abs(firstLanded - pasted) <= 2,
                          differences[firstLanded...lastWithPill].allSatisfy({ $0.landed }) else {
                        throw Failure(description: "\(app): the plate with the text did not come behind the pill at the paste and stay.")
                    }
                }

                // When each change shows, read from the pictures. The pill is as wide as what it
                // says, so its box changes when it turns to "Transcribing…" and when it starts to
                // leave. Between "Transcribing…" and "Polishing…" the words change beside a spinner
                // that never rests; the spinner changes a small part of a picture, the words a
                // wide one.
                func pillOn(_ index: Int) -> CGRect {
                    differences[min(max(index, 0), differences.count - 1)].difference.box ?? .null
                }
                func first(from start: Int, _ what: String, where changed: (Int) -> Bool) throws -> Int {
                    guard let found = (max(start, 1)..<pictures.count).first(where: changed) else {
                        throw Failure(description: "\(app): the change to \(what) could not be found in the pictures.")
                    }
                    return found
                }
                let released = take.index(at: take.released)
                let recordingBox = pillOn(released - 2)
                let showsTranscribing = try first(from: released - 1, "transcribing") { pillOn($0).width != recordingBox.width }
                let polishing = take.index(at: take.polishing)
                let showsPolishing = try first(from: polishing - 1, "polishing") {
                    let change = Difference(pictures[$0], pictures[$0 - 1])
                    return change.largest >= 60 && (change.box?.width ?? 0) >= 60
                }
                let settledBox = pillOn(pasted - 2)
                let showsLeaving = try first(from: pasted - 1, "leaving") {
                    abs(pillOn($0).width - settledBox.width) >= 2 || abs(pillOn($0).height - settledBox.height) >= 2
                }
                // The spinner is up from "Transcribing…" until the paste, and must turn all the while.
                let spinnerRests = longestRest(in: pictures, from: showsTranscribing, to: pasted)
                guard spinnerRests <= 6 else {
                    throw Failure(description: "\(app): the spinner stood still for \(spinnerRests) pictures while the pill was working.")
                }
                let firstLanded = differences.firstIndex(where: { $0.landed })
                return FilmTake(
                    spinnerRests: spinnerRests,
                    doneAfterPaste: (take.done - take.pasted) * 1000,
                    pastedBeforePicture: pasted - appears,
                    textShows: firstLanded.map { $0 - appears },
                    pictures: Array(pictures[appears...lastWithPill]),
                    shows: ["transcribing": showsTranscribing - appears, "polishing": showsPolishing - appears, "leaves": showsLeaving - appears],
                    repeatedWhileRecording: repeats(in: pictures, from: appears, to: released),
                    repeatedInAll: repeats(in: pictures, from: appears, to: lastWithPill + 1),
                    longestGap: take.longestGap, period: take.period, pillArea: pillArea,
                    anchor: placedInPlate, levelsShown: take.levelsShown, textShowsInRectangle: textShowsInRectangle
                )
            }

            func duration(_ seconds: Double) -> Duration {
                .nanoseconds(Int64((seconds * 1e9).rounded()))
            }
            let lasts = { (key: String) throws -> Double in
                try number((timeline[key] as? [String: Any])?["lastsSeconds"], "timeline.\(key).lastsSeconds")
            }
            var script = Script(
                levels: levels.map(\.floatValue),
                recording: duration(try number(timeline["recordingSeconds"], "recordingSeconds")),
                transcribing: duration(try lasts("transcribing")),
                polishing: duration(try lasts("polishing")),
                // The film's pill appears with the first audio.
                minimumHold: .zero
            )
            /// How far a take is from the film's frames, and how clean it is otherwise.
            func faults(_ take: FilmTake) -> Int {
                asked.map { abs((take.shows[$0.key] ?? 0) - $0.value) }.reduce(0, +) * 10 + take.repeatedWhileRecording
                    + (take.longestGap > take.period * 1500 ? 1000 : 0)
            }
            var best: FilmTake?
            for number in 1...8 {
                let take = try await attempt(script)
                let off = asked.keys.sorted().map { "\($0) \((take.shows[$0] ?? 0) - (asked[$0] ?? 0))" }.joined(separator: ", ")
                print("Film, \(app), take \(number): frames off the film's (\(off)); \(take.repeatedWhileRecording) pictures the same as the one before while recording; longest gap \(take.longestGap) ms.")
                if best.map({ faults(take) < faults($0) }) ?? true {
                    best = take
                }
                if faults(take) == 0 { break }
                // A change that showed late is asked for that many frames sooner next time.
                let late = asked.mapValues { _ in 0 }.merging(take.shows) { _, shown in shown }
                let lateT = (late["transcribing"] ?? 0) - (asked["transcribing"] ?? 0)
                let lateP = (late["polishing"] ?? 0) - (asked["polishing"] ?? 0)
                let lateL = (late["leaves"] ?? 0) - (asked["leaves"] ?? 0)
                script.recording -= duration(Double(lateT) * take.period)
                script.transcribing -= duration(Double(lateP - lateT) * take.period)
                script.polishing -= duration(Double(lateL - lateP) * take.period)
            }
            guard let best else { throw Failure(description: "\(app): no take.") }

            let folder = directory.appendingPathComponent(app, isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (number, picture) in best.pictures.enumerated() {
                try picture.write(to: folder.appendingPathComponent(String(format: "%04d.png", number)))
            }
            let levelError = zip(script.levels, best.levelsShown).map { abs(Double($0) - Double($1)) }.max() ?? 0
            let room = pillBox.offsetBy(dx: -captureRect.minX, dy: -captureRect.minY)
            let entry: [String: Any] = [
                "scene": app,
                "frames": best.pictures.count,
                "firstFrameIsFilmFrame": appearsInFilm,
                "rectangleInFilmPixels": box(captureRect),
                "plateBehind": ["fromFrame0": beforeName, "fromTheFrameTheTextLandsOn": landedName],
                "theTextShowsInsideTheRectangle": best.textShowsInRectangle,
                "frameOnWhichEachChangeShowsCountedFromThePillAppearing": ["captured": best.shows, "inPlatesJson": asked],
                "pillDrawnWithinInRectangle": box(best.pillArea),
                "roomTheFilmKeepsForThePillInRectangle": box(room),
                "pixelsOutsideThePillThatDifferFromThePlate": 0,
                "anchorByTheAppsRuleInFilmPixels": ["x": best.anchor.x, "y": best.anchor.y],
                "levelPerTenthOfASecondShown": best.levelsShown.map { rounded(Double($0)) },
                "largestDifferenceFromTheLevelAsked": rounded(levelError),
                "longestGapBetweenFramesInMilliseconds": best.longestGap,
                "secondsFromOneFrameToTheNext": best.period,
                "framesTheSameAsTheOneBeforeWhileRecording": best.repeatedWhileRecording,
                "framesTheSameAsTheOneBeforeInAll": best.repeatedInAll,
                "longestRunOfFramesTheSameWhileTheSpinnerIsUp": best.spinnerRests,
                "atThePaste": [
                    "firstFrameTakenAfterThePasteWasAskedFor": best.pastedBeforePicture,
                    "frameThePlateWithTheTextShowsOn": best.textShows.map { $0 as Any } ?? NSNull(),
                    "frameThePillFirstChangesOn": best.shows["leaves"] ?? -1,
                    "millisecondsFromThePasteToTheControllerBeingDone": rounded(best.doneAfterPaste),
                ] as [String: Any],
            ]
            try write(json: entry, to: folder.appendingPathComponent("capture.json"))
            summary.append(entry.filter { $0.key != "levelPerTenthOfASecondShown" })
            let onTime = faults(best) == 0 ? "every change shows on the film's frame" : "NOT every change shows on the film's frame: \(best.shows) against \(asked)"
            print("Film, \(app), at the paste: asked for just before picture \(best.pastedBeforePicture); the controller was done \(rounded(best.doneAfterPaste)) ms later; the plate with the text shows on picture \(best.textShows.map(String.init) ?? "none in the rectangle"); the pill first changes on picture \(best.shows["leaves"] ?? -1). The spinner never stood still for more than \(best.spinnerRests) pictures.")
            print("Film, \(app): \(best.pictures.count) pictures of \(Int(captureRect.width)) × \(Int(captureRect.height)) pixels at left=\(Int(captureRect.minX)) top=\(Int(captureRect.minY)); \(onTime); the pill is drawn within left=\(Int(best.pillArea.minX)) top=\(Int(best.pillArea.minY)) \(Int(best.pillArea.width)) × \(Int(best.pillArea.height)) of the rectangle, and everything else in it is the plate, pixel for pixel; levels within \(rounded(levelError)); \(best.repeatedInAll) pictures the same as the one before.")
        }
        try write(json: ["scenes": summary], to: directory.appendingPathComponent("captures.json"))
    }

    // MARK: - The menu bar item

    /// The real menu bar item, alone: its own window, which holds the mark and nothing of the
    /// menu bar behind it. Once idle, once while the scripted dictation is recording.
    ///
    /// Where the session shows no menu bar, the window server has no picture of the item; the
    /// item is then asked to draw itself, which gives the mark as the item draws it and leaves
    /// out whatever the menu bar does to it.
    private static func menuBarItem(model: AppModel, into directory: URL) async throws {
        guard let item = NSApp.windows.first(where: { $0.className == "NSStatusBarWindow" }), let content = item.contentView else {
            print("Menu bar item: there is none in this session, so it was not captured.")
            return
        }
        var drewItself = false
        func save(_ name: String) throws {
            let pixels: Pixels
            // No bounds: the window as it is, wherever the menu bar has put it.
            if item.screen != nil, let image = WindowServer.picture(ofWindows: [item.windowNumber], bounds: .null) {
                pixels = try Pixels(image)
            } else {
                drewItself = true
                let size = content.bounds.size
                guard let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ) else { throw Failure(description: "Could not make a picture of the menu bar item.") }
                bitmap.size = size
                content.cacheDisplay(in: content.bounds, to: bitmap)
                guard let image = bitmap.cgImage else { throw Failure(description: "Could not make a picture of the menu bar item.") }
                pixels = try Pixels(image)
            }
            try pixels.write(to: directory.appendingPathComponent(name))
            print("Menu bar item: saved \(name), \(pixels.width) × \(pixels.height) pixels.")
        }
        try save("idle.png")
        model.controller.begin()
        await wait { model.controller.isListening }
        try await Task.sleep(for: .milliseconds(600))
        try save("recording.png")
        model.controller.cancel()
        try await Task.sleep(for: .milliseconds(400))
        if drewItself {
            print("Menu bar item: this session shows no menu bar (the item's window is on no screen), so the item drew itself into the picture. That gives the mark as the item draws it, on nothing; it leaves out the menu bar behind it and how the bar tints the mark.")
        }
    }
}
#endif

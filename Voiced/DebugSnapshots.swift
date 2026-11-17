#if DEBUG
import AppKit
import SwiftUI
import VoicedKit

/// Development aid, compiled into Debug builds only: saves PNGs of the app's UI and quits.
///
///     Voiced.app/Contents/MacOS/Voiced -VoicedSnapshots /path/to/folder
///
/// `*-live*.png` are the app's real windows: onboarding and settings in whatever state this Mac is
/// in, and the real indicator panel driven through a scripted dictation. The rest are the same
/// SwiftUI views hosted in plain windows with fixed state, once in the light and once in the dark
/// appearance, so every state can be captured without granting permissions or having a key.
/// `app-icon.png` is the icon macOS shows for this build.
enum DebugSnapshots {
    static var isRequested: Bool {
        DebugRun.argument("-VoicedSnapshots") != nil
    }

    static func runIfRequested(model: AppModel) {
        guard let path = DebugRun.argument("-VoicedSnapshots") else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        Task {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await captureAll(model: model, into: directory)
            } catch {
                print("Snapshots failed: \(error)")
                exit(1)
            }
            exit(0)
        }
    }

    private struct SnapshotError: Error, CustomStringConvertible {
        var description: String
    }

    private final class FixedSecretStore: SecretStore, @unchecked Sendable {
        let secret: String?

        init(secret: String?) {
            self.secret = secret
        }

        func read() throws -> String? { secret }
        func save(_ secret: String) throws {}
        func delete() throws {}
    }

    /// The height between the menu bar and the Dock of a 16-inch MacBook Pro: room for all of
    /// Settings, so the pictures show the whole window whatever display they are taken on.
    private static let roomyDisplay: CGFloat = 1084

    static func fixedModel(
        microphone: Bool, accessibility: Bool, key: Bool, menuBarIconHidden: Bool = false, menuBarIconStayedHidden: Bool = false
    ) -> AppModel {
        AppModel(
            permissions: Permissions(microphone: microphone ? .granted : .notDetermined, accessibility: accessibility),
            secretStore: FixedSecretStore(secret: key ? "snapshot-placeholder" : nil),
            // Settings of its own for each model: what one picture changes, no other sees.
            defaults: DebugSettings(),
            menuBarItem: menuBarIconHidden || menuBarIconStayedHidden ? .offScreen(x: -9138) : .onScreen(x: 1200, display: 0),
            menuBarItemMove: menuBarIconStayedHidden ? .stayedHidden : nil
        )
    }

    private static func fixedModel(ready: Bool) -> AppModel {
        fixedModel(microphone: ready, accessibility: ready, key: ready)
    }

    /// The setup window at each point a person passes through, in the order they usually do.
    private static var setupStates: [(name: String, model: AppModel, editor: APIKeyEditor)] {
        let typedKey = "xai-0000000000000000000000000000"
        return [
            ("setup", fixedModel(ready: false), APIKeyEditor()),
            ("setup-microphone-allowed", fixedModel(microphone: true, accessibility: false, key: false), APIKeyEditor()),
            ("setup-accessibility-allowed", fixedModel(microphone: false, accessibility: true, key: false), APIKeyEditor()),
            ("setup-key-entered", fixedModel(microphone: true, accessibility: true, key: false), APIKeyEditor(input: typedKey)),
            ("setup-key-checking", fixedModel(microphone: true, accessibility: true, key: false), APIKeyEditor(input: typedKey, status: .checking)),
            ("setup-key-rejected", fixedModel(microphone: true, accessibility: true, key: false), APIKeyEditor(input: typedKey, status: .message("That key was rejected. Check that you copied all of it.", isError: true))),
            ("setup-key-accepted", fixedModel(ready: true), APIKeyEditor(status: .message("The key works. Saved in your Keychain.", isError: false))),
            ("setup-ready", fixedModel(ready: true), APIKeyEditor()),
            ("setup-menu-bar-icon-hidden", fixedModel(microphone: true, accessibility: true, key: true, menuBarIconHidden: true), APIKeyEditor()),
            ("setup-menu-bar-icon-still-hidden", fixedModel(microphone: true, accessibility: true, key: true, menuBarIconStayedHidden: true), APIKeyEditor()),
        ]
    }

    private static func captureAll(model: AppModel, into directory: URL) async throws {
        // A regular, frontmost app draws its windows in their active state.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .seconds(1.5))
        print("Frontmost: \(NSApp.isActive)")
        print("Windows at launch: \(NSApp.windows.map { "\($0.identifier?.rawValue ?? "-") [\($0.title)] visible=\($0.isVisible)" })")

        try await DebugChecks.settingsOpensWithoutTheMenuBarIcon(model: model)

        // The real windows, in both appearances. Setting the app's appearance changes this run only.
        model.show(WindowID.settings)
        try await Task.sleep(for: .seconds(1))
        guard let settings = liveWindow(titled: "Voiced Settings") else {
            throw SnapshotError(description: "The Settings window did not open.")
        }
        try await DebugChecks.settingsWindowFitsItsScreen(settings)
        // The real menu bar panel, opened by clicking the status item, with a check that its hotkey control works.
        let menuPanel = try await DebugChecks.menuPanelTakesTheKeyboard(model: model)

        for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            NSApp.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .seconds(1))
            if let onboarding = liveWindow(titled: "Welcome to Voiced") {
                try capture(onboarding, to: directory.appendingPathComponent("onboarding-live-\(suffix).png"))
            } else {
                print("The onboarding window is not open (setup is already complete on this Mac).")
            }
            try capture(settings, to: directory.appendingPathComponent("settings-live-\(suffix).png"))
            try capture(menuPanel, to: directory.appendingPathComponent("menu-live-\(suffix).png"))
        }
        NSApp.appearance = nil
        NSApp.windows.filter(\.isVisible).forEach { $0.orderOut(nil) }

        try await DebugChecks.pillDragKeepsTheKeyboardWhereItWas()
        try await DebugChecks.pillGoesNextToTheText(into: directory)
        try await DebugChecks.accessibilityIsSwitchedOnOncePerApp()
        try await DebugChecks.settingsFitsSmallDisplays(into: directory)

        try await captureLiveIndicator(into: directory)

        let setup = fixedModel(ready: false)
        let ready = fixedModel(ready: true)
        // The clock keeps running while the picture is taken, a second after the window opens.
        let indicators: [(String, () -> IndicatorContent, Float)] = [
            ("indicator-starting-microphone", { .startingMicrophone }, 0),
            ("indicator-recording", { .recording(since: Date().addingTimeInterval(-83)) }, 1),
            ("indicator-working", { .working("Transcribing…") }, 0),
            ("indicator-warning", { .notice(.warning, "Cleanup failed, inserted the raw transcript.") }, 0),
            ("indicator-error", { .notice(.error, "The Grok API Key was rejected. Check it in Settings.") }, 0),
            ("indicator-placing", { .placing }, 0),
        ]

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .darkAqua ? "dark" : "light"
            @discardableResult
            func shoot(_ surface: String, style: WindowStyle, @ViewBuilder content: () -> some View) async throws -> NSSize {
                try await snapshot("\(surface)-\(suffix)", in: directory, style: style, appearance: appearance, content: content)
            }

            var setupSizes: [String: NSSize] = [:]
            for state in setupStates {
                setupSizes[state.name] = try await shoot(state.name, style: .hiddenTitleBar) {
                    OnboardingView(keyEditor: state.editor).environment(state.model)
                }
            }
            let distinctSizes = Set(setupSizes.values.map { "\(Int($0.width))x\(Int($0.height))" })
            print("Setup window sizes across \(setupSizes.count) states (\(suffix)): \(distinctSizes.sorted().joined(separator: ", "))")
            guard distinctSizes.count == 1 else {
                throw SnapshotError(description: "The setup window changes size between states.")
            }
            try await shoot("settings", style: .titled("Voiced Settings")) {
                SettingsView(visibleScreenHeight: roomyDisplay).environment(ready)
            }
            try await shoot("settings-first-run", style: .titled("Voiced Settings")) {
                SettingsView(visibleScreenHeight: roomyDisplay).environment(setup)
            }
            try await shoot("settings-key-rejected", style: .titled("Voiced Settings")) {
                SettingsView(keyEditor: APIKeyEditor(
                    arrangement: .formRows,
                    input: "xai-0000000000000000000000000000",
                    status: .message("That key was rejected. Check that you copied all of it.", isError: true)
                ), visibleScreenHeight: roomyDisplay)
                .environment(fixedModel(microphone: true, accessibility: true, key: false))
            }
            try await shoot("settings-menu-bar-icon-hidden", style: .titled("Voiced Settings")) {
                SettingsView(visibleScreenHeight: roomyDisplay).environment(fixedModel(microphone: true, accessibility: true, key: true, menuBarIconHidden: true))
            }
            try await shoot("settings-menu-bar-icon-still-hidden", style: .titled("Voiced Settings")) {
                SettingsView(visibleScreenHeight: roomyDisplay).environment(fixedModel(microphone: true, accessibility: true, key: true, menuBarIconStayedHidden: true))
            }
            try await shoot("menu", style: .popover) {
                MenuContentView().environment(ready)
            }
            // The same two surfaces with the pill set to stay at its fixed place.
            let fixedPlace = fixedModel(ready: true)
            fixedPlace.pill.mode = .fixedPlace
            try await shoot("menu-pill-fixed-place", style: .popover) {
                MenuContentView().environment(fixedPlace)
            }
            try await shoot("settings-pill-fixed-place", style: .titled("Voiced Settings")) {
                SettingsView(visibleScreenHeight: roomyDisplay).environment(fixedPlace)
            }
            // And with cleanup switched off.
            let cleanupOff = fixedModel(ready: true)
            cleanupOff.cleanup.isOn = false
            try await shoot("menu-cleanup-off", style: .popover) {
                MenuContentView().environment(cleanupOff)
            }
            try await shoot("settings-cleanup-off", style: .titled("Voiced Settings")) {
                SettingsView(visibleScreenHeight: roomyDisplay).environment(cleanupOff)
            }
            try await shoot("menu-needs-setup", style: .popover) {
                MenuContentView().environment(setup)
            }
            for (surface, content, level) in indicators {
                try await shoot(surface, style: .desktop) {
                    IndicatorView(content: content(), level: level)
                        .frame(width: 460, height: 120)
                }
            }
        }

        try saveAppIcon(to: directory.appendingPathComponent("app-icon.png"))
    }

    /// The icon macOS shows for this build in Finder and the Dock.
    private static func saveAppIcon(to url: URL) throws {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let pixels = 512
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw SnapshotError(description: "Could not draw the app icon.")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError(description: "Could not encode the app icon.")
        }
        try png.write(to: url)
        print("Saved \(url.path) (\(pixels)x\(pixels))")
    }

    // MARK: - The real indicator panel, driven by a scripted dictation

    final class ScriptedCapture: AudioCapturing {
        /// How long the audio engine takes to start; nothing is heard until then.
        private let startsAfter: Duration
        private var feeder: Task<Void, Never>?

        init(startsAfter: Duration = .zero) {
            self.startsAfter = startsAfter
        }

        func start() -> AsyncThrowingStream<AudioChunk, any Error> {
            let (stream, continuation) = AsyncThrowingStream<AudioChunk, any Error>.makeStream()
            let startsAfter = startsAfter
            feeder = Task {
                try? await Task.sleep(for: startsAfter)
                var spoken = false
                while !Task.isCancelled {
                    // A quiet room for a moment, then a voice at changing volume.
                    continuation.yield(AudioChunk(pcm: Self.tone(amplitude: spoken ? .random(in: 1200...4000) : 20)))
                    spoken = true
                    try? await Task.sleep(for: .milliseconds(100))
                }
                continuation.finish()
            }
            return stream
        }

        func stop() {
            feeder?.cancel()
        }

        /// 100 ms of a 200 Hz square wave: enough to move the level meter.
        private static func tone(amplitude: Int16) -> Data {
            let samples = (0..<1600).map { ($0 / 40).isMultiple(of: 2) ? amplitude : -amplitude }
            return samples.withUnsafeBufferPointer { Data(buffer: $0) }
        }
    }

    actor ScriptedSession: TranscriptionSession {
        func start() {}
        func send(audio: Data) {}
        func cancel() {}

        func finish() async throws -> TranscriptionResult {
            try await Task.sleep(for: .seconds(1.5))
            return TranscriptionResult(text: "um this is a scripted dictation", isComplete: true)
        }
    }

    struct ScriptedCleaner: TextCleaning {
        func clean(_ transcript: String) async throws -> String {
            try await Task.sleep(for: .seconds(1.5))
            throw XAIError.rateLimited
        }
    }

    final class DiscardingInserter: TextInserting {
        func insert(_ text: String) async throws {}
    }

    /// Runs one dictation with scripted edges and photographs the real panel at each stage.
    /// Its microphone takes two seconds to start, as a real one did after a Mac was unlocked.
    private static func captureLiveIndicator(into directory: URL) async throws {
        let controller = DictationController(dependencies: .init(
            apiKey: { "snapshot-placeholder" },
            makeCapture: { ScriptedCapture(startsAfter: .seconds(2)) },
            makeTranscription: { _ in ScriptedSession() },
            makeCleaner: { _ in ScriptedCleaner() },
            inserter: DiscardingInserter(),
            minimumHold: .zero
        ))
        let panel = IndicatorPanel(controller: controller, pill: PillSettings(defaults: DebugSettings()))
        // A page behind the pill: the pill is glass, and glass over nothing shows nothing of itself.
        var page: NSWindow?
        defer { page?.orderOut(nil) }
        func stage(_ name: String, expecting phase: DictationController.Phase) async throws {
            try await Task.sleep(for: .milliseconds(700))
            guard controller.phase == phase, panel.window.isVisible else {
                throw SnapshotError(description: "Indicator \(name): phase is \(controller.phase), panel visible: \(panel.window.isVisible)")
            }
            print("Indicator panel frame: \(panel.window.frame) on screen \(NSScreen.main?.frame ?? .zero)")
            if page == nil {
                let window = NSWindow(contentRect: panel.window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.contentView = NSHostingView(rootView: DesktopStandIn())
                window.setFrame(panel.window.frame, display: true)
                window.orderFrontRegardless()
                page = window
                try await Task.sleep(for: .milliseconds(200))
            }
            try capture((page.map { [$0] } ?? []) + [panel.window], showing: panel.window.frame, to: directory.appendingPathComponent("indicator-\(name)-live.png"))
        }

        controller.begin()
        // A usual microphone would be heard from by now. This one is not, so there is no pill yet.
        try await Task.sleep(for: .milliseconds(300))
        guard controller.microphone == .starting, !panel.window.isVisible else {
            throw SnapshotError(description: "Before the microphone counts as slow: microphone is \(controller.microphone), panel visible: \(panel.window.isVisible)")
        }
        try await stage("starting-microphone", expecting: .recording)
        guard controller.microphone == .startingSlowly else {
            throw SnapshotError(description: "A second into a two-second start, the microphone is \(controller.microphone)")
        }
        try await Task.sleep(for: .seconds(1.2))
        try await stage("recording", expecting: .recording)
        guard controller.isListening else {
            throw SnapshotError(description: "After the microphone started, the microphone is \(controller.microphone)")
        }
        print("Indicator panel waited for the microphone before it showed listening.")
        controller.end()
        try await stage("transcribing", expecting: .transcribing)
        try await Task.sleep(for: .seconds(1.2))
        try await stage("polishing", expecting: .cleaning)
        try await Task.sleep(for: .seconds(1))
        try await stage("notice", expecting: .idle)

        // The notice stays up for four seconds, then the panel leaves the screen.
        try await Task.sleep(for: .seconds(5))
        guard !panel.window.isVisible else {
            throw SnapshotError(description: "The indicator panel did not hide after its notice.")
        }
        print("Indicator panel hid after the notice.")
    }

    private enum WindowStyle {
        case titled(String)
        case hiddenTitleBar
        /// Stands in for the menu bar panel, whose real window only opens on a click.
        case popover
        /// Stands in for whatever is on screen behind the floating indicator.
        case desktop
    }

    private static func snapshot(
        _ name: String,
        in directory: URL,
        style: WindowStyle,
        appearance: NSAppearance.Name,
        @ViewBuilder content: () -> some View
    ) async throws -> NSSize {
        let window: NSWindow
        switch style {
        case let .titled(title):
            window = KeyableWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = title
            // What `containerBackground(_:for: .window)` does to the real window.
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(Monochrome.canvas)
            window.contentView = NSHostingView(rootView: content())
        case .hiddenTitleBar:
            window = KeyableWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: content())
        case .popover:
            window = KeyableWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = NSHostingView(rootView: content().background(.regularMaterial, in: .rect(cornerRadius: 16)))
        case .desktop:
            window = KeyableWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: content().background(DesktopStandIn()))
        }
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 400, height: 300))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: window)
        try await Task.sleep(for: .seconds(1))
        try capture(window, to: directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
        return window.contentView?.fittingSize ?? .zero
    }

    /// A window that draws as the key window of the active app, whatever the session allows.
    /// macOS will not let an app launched from a script come to the front, and controls in a
    /// window that is not key draw dimmed, which is not how they look in use.
    final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
    }

    /// A document-like page in the current appearance: grey lines of "text" on paper.
    private struct DesktopStandIn: View {
        var body: some View {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.background)
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(0..<7, id: \.self) { line in
                        Capsule()
                            .fill(.primary.opacity(0.22))
                            .frame(width: [380, 420, 300, 410, 350, 430, 240][line], height: 7)
                    }
                }
                .padding(18)
            }
        }
    }

    private static func liveWindow(titled title: String) -> NSWindow? {
        NSApp.windows.first { $0.title == title && $0.isVisible }
    }

    private typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// Several of this app's own windows in one picture, as the window server draws them
    /// together, the first at the back: glass in a window in front shows the window behind it,
    /// as it does on screen. `frame` is the part of the screen to show. Only this app's windows
    /// are asked for, which needs no Screen Recording permission.
    static func capture(_ windows: [NSWindow], showing frame: CGRect, to url: URL) throws {
        let bounds = DebugPillCaptures.windowServerBounds(frame)
        guard let image = DebugPillCaptures.WindowServer.picture(ofWindows: windows.reversed().map(\.windowNumber), bounds: bounds),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw SnapshotError(description: "Could not capture \(url.lastPathComponent).")
        }
        try png.write(to: url)
        print("Saved \(url.path) (\(image.width)x\(image.height))")
    }

    /// `CGWindowListCreateImage` is hidden from Swift in current SDKs, hence the lookup by name.
    private static func image(of window: NSWindow) throws -> CGImage {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else {
            throw SnapshotError(description: "CGWindowListCreateImage is unavailable.")
        }
        let createImage = unsafeBitCast(symbol, to: WindowImageFunction.self)
        let includingWindow: UInt32 = 1 << 3
        let boundsIgnoreFraming: UInt32 = 1 << 0
        guard let image = createImage(.null, includingWindow, UInt32(window.windowNumber), boundsIgnoreFraming)?.takeRetainedValue() else {
            throw SnapshotError(description: "Could not capture the \(window.title) window.")
        }
        return image
    }

    static func capture(_ window: NSWindow, to url: URL) throws {
        let image = try image(of: window)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw SnapshotError(description: "Could not encode \(url.lastPathComponent).")
        }
        try png.write(to: url)
        print("Saved \(url.path) (\(image.width)x\(image.height))")
    }
}
#endif

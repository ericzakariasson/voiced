import AppKit
import Observation
import os
import SwiftUI
import VoicedKit

private let log = VoicedLog.setup

enum WindowID {
    static let onboarding = AppWindow.onboarding.rawValue
    static let settings = AppWindow.settings.rawValue
}

/// The app's state: settings, permissions, and the wiring between the hotkey and the dictation loop.
@Observable
final class AppModel {
    enum KeySaveResult: Equatable {
        case saved
        /// Saved, though xAI could not be reached to check it.
        case savedUnverified(String)
        case rejected(String)
    }

    let permissions: Permissions
    let controller: DictationController
    private(set) var hotkey: Hotkey
    private(set) var hasAPIKey: Bool
    /// Accessibility is granted, yet macOS would not let Voiced watch the keyboard.
    private(set) var hotkeyIsUnavailable = false
    /// Where the menu bar icon is; `nil` in the first moments after launch, before it is known.
    private(set) var menuBarItem: MenuBarItemPlacement?
    /// Whether the icon is in the menu bar. False for the moment it takes to move it, and after
    /// the user has ⌘-dragged it out of the menu bar; it is back the next time Voiced is launched.
    var menuBarItemIsInserted = true {
        didSet {
            windows.menuBarItemIsInserted = menuBarItemIsInserted
            guard menuBarItemIsInserted != oldValue, !windows.isMovingMenuBarItem else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                windows.logMenuBarItem()
            }
        }
    }
    enum MenuBarItemMove: Equatable {
        case moving
        /// It was moved to the right end and still cannot be seen.
        case stayedHidden
    }
    private(set) var menuBarItemMove: MenuBarItemMove?
    /// Where the pill goes.
    let pill: PillSettings
    /// Whether a dictation is cleaned up before it is inserted.
    let cleanup: CleanupSetting

    /// Set by the hotkey recorder so key presses reach it instead of starting a dictation.
    var isRecordingHotkey = false {
        didSet { hotkeyMonitor?.isSuspended = isRecordingHotkey }
    }

    /// SwiftUI's window opener, handed over by the menu bar label once it exists.
    @ObservationIgnored var openWindow: ((String) -> Void)? {
        didSet {
            if oldValue == nil, openWindow != nil {
                log.notice("window opener installed")
            }
        }
    }
    @ObservationIgnored let windows = WindowCoordinator()
    @ObservationIgnored private let secretStore: any SecretStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keyHolder: KeyHolder
    @ObservationIgnored private var hotkeyMonitor: HotkeyMonitor?
    @ObservationIgnored private var microphone: MicrophoneEvents?
    @ObservationIgnored private var setupPrompt: Task<Void, Never>?
    @ObservationIgnored private var directWindows: [AppWindow: NSWindow] = [:]

    private static let hotkeyDefaultsKey = "hotkey"

    /// Hands the key to the dictation loop without a Keychain read per dictation.
    private final class KeyHolder {
        var apiKey: String?
    }

    var needsSetup: Bool {
        !hasAPIKey || !permissions.allGranted
    }

    /// The menu bar icon exists but cannot be seen: a menu bar manager keeps it in its hidden
    /// section, or a full menu bar has pushed it off the screen.
    var menuBarItemIsHidden: Bool {
        menuBarItem.map { !$0.isVisible } ?? false
    }

    init(
        permissions: Permissions = Permissions(),
        secretStore: any SecretStore = KeychainSecretStore(),
        defaults: UserDefaults = .standard,
        menuBarItem: MenuBarItemPlacement? = nil,
        menuBarItemMove: MenuBarItemMove? = nil,
        controller: DictationController? = nil
    ) {
        self.permissions = permissions
        self.secretStore = secretStore
        self.defaults = defaults
        self.menuBarItem = menuBarItem
        self.menuBarItemMove = menuBarItemMove
        pill = PillSettings(defaults: defaults)

        hotkey = defaults.data(forKey: Self.hotkeyDefaultsKey)
            .flatMap { try? JSONDecoder().decode(Hotkey.self, from: $0) } ?? .default

        let keyHolder = KeyHolder()
        keyHolder.apiKey = (try? secretStore.read()).flatMap { $0.isEmpty ? nil : $0 }
        self.keyHolder = keyHolder
        hasAPIKey = keyHolder.apiKey != nil

        // The loop asks the setting itself, each time the hotkey goes down.
        let cleanup = CleanupSetting(defaults: defaults)
        self.cleanup = cleanup

        let configuration = XAIConfiguration.default
        // The real loop, unless a debug mode brings one whose audio is scripted.
        self.controller = controller ?? DictationController(dependencies: .init(
            apiKey: { keyHolder.apiKey },
            makeCapture: { MicrophoneCapture(sampleRate: Double(configuration.sampleRate)) },
            makeTranscription: { StreamingTranscriptionSession(apiKey: $0, configuration: configuration) },
            makeCleaner: { TranscriptCleaner(apiKey: $0, configuration: configuration) },
            cleanupIsOn: { cleanup.isOn },
            inserter: PasteboardTextInserter()
        ))

        windows.onMenuBarItemPlacement = { [weak self] placement in
            if self?.menuBarItem != placement {
                self?.menuBarItem = placement
            }
        }
    }

    /// Starts watching the hotkey and the permissions. Call once, at launch.
    func start() {
        hotkeyMonitor = HotkeyMonitor(hotkey: hotkey) { [weak self] action in
            self?.handle(action)
        }
        let microphone = MicrophoneEvents(sampleRate: Double(XAIConfiguration.default.sampleRate))
        self.microphone = microphone
        permissions.onChange = { [weak self] in
            self?.logState("permissions changed")
            self?.syncHotkeyMonitor()
            microphone.permissionsChanged()
        }
        permissions.willPrompt = { [weak self] in
            self?.windows.activate()
        }
        permissions.startMonitoring()
        logState("launched")
        syncHotkeyMonitor()
        microphone.start()
    }

    private func logState(_ event: String) {
        log.notice("\(event, privacy: .public): key saved=\(self.hasAPIKey) microphone=\(String(describing: self.permissions.microphone), privacy: .public) accessibility=\(self.permissions.accessibility) hotkey=\(self.hotkey.displayName, privacy: .public)")
    }

    private func syncHotkeyMonitor() {
        guard let hotkeyMonitor else { return }
        guard permissions.accessibility else {
            hotkeyMonitor.stop()
            hotkeyIsUnavailable = false
            return
        }
        hotkeyIsUnavailable = !hotkeyMonitor.start()
        if hotkeyIsUnavailable {
            // Right after the permission is granted, macOS can take a moment to honour it.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.syncHotkeyMonitor()
            }
        }
    }

    private func handle(_ action: HotkeyStateMachine.Action) {
        switch action {
        case .begin:
            guard hasAPIKey, permissions.microphone == .granted else {
                // Setup is incomplete. Say so only once the key has been held like a dictation,
                // not when it was tapped or used to type a character.
                log.notice("hotkey down, but setup is incomplete: key saved=\(self.hasAPIKey) microphone=\(String(describing: self.permissions.microphone), privacy: .public)")
                cancelSetupPrompt()
                setupPrompt = Task { [weak self] in
                    try? await Task.sleep(for: DictationController.defaultMinimumHold)
                    guard !Task.isCancelled else { return }
                    self?.promptForSetup()
                }
                return
            }
            if pill.mode == .nextToText {
                // Now, while the keyboard is where the words will go.
                pill.textLookup.begin()
            }
            microphone?.holdBegan()
            controller.begin()
        case .end:
            cancelSetupPrompt()
            pill.textLookup.holdEnded()
            controller.end()
        case .cancel:
            cancelSetupPrompt()
            pill.textLookup.holdEnded()
            controller.cancel()
        }
    }

    private func cancelSetupPrompt() {
        setupPrompt?.cancel()
        setupPrompt = nil
    }

    private func promptForSetup() {
        setupPrompt = nil
        guard hasAPIKey else {
            // Without a key the controller only posts its "add your key" notice.
            controller.begin()
            show(WindowID.settings)
            return
        }
        if permissions.microphone != .granted {
            // The setup window first, so the system's prompt opens over Voiced and not behind
            // whichever app the hotkey was pressed in.
            show(.onboarding)
            permissions.requestMicrophone()
        }
    }

    func setHotkey(_ hotkey: Hotkey) {
        self.hotkey = hotkey
        if let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: Self.hotkeyDefaultsKey)
        }
        hotkeyMonitor?.setHotkey(hotkey)
    }

    /// Checks the key with xAI, then stores it in the Keychain. A key xAI rejects is not stored.
    func saveAPIKey(_ input: String) async -> KeySaveResult {
        let apiKey = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return .rejected("Enter a Grok API Key.")
        }

        // The key itself is never logged, only what became of it.
        var unverifiedReason: String?
        do {
            try await APIKeyChecker().check(apiKey)
            log.notice("key check: xAI accepted the key")
        } catch XAIError.invalidAPIKey {
            log.error("key check: xAI rejected the key; not saved")
            return .rejected("That key was rejected. Check that you copied all of it.")
        } catch {
            log.error("key check could not be completed: \(VoicedLog.describe(error), privacy: .public); saving the key unchecked")
            unverifiedReason = (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        do {
            try secretStore.save(apiKey)
            log.notice("key saved to the Keychain")
        } catch {
            log.error("key could not be saved: \(VoicedLog.describe(error), privacy: .public)")
            return .rejected((error as? any LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        keyHolder.apiKey = apiKey
        hasAPIKey = true
        if let unverifiedReason {
            return .savedUnverified("Saved, but the key could not be checked. \(unverifiedReason)")
        }
        return .saved
    }

    /// Returns `false`, leaving the key in place, when the Keychain refuses.
    @discardableResult
    func removeAPIKey() -> Bool {
        do {
            try secretStore.delete()
        } catch {
            return false
        }
        keyHolder.apiKey = nil
        hasAPIKey = false
        return true
    }

    func show(_ windowID: String) {
        guard let window = AppWindow(rawValue: windowID) else { return }
        show(window)
    }

    /// Opens the window, or finds it if it is already open, and brings it in front of every other app.
    func show(_ window: AppWindow) {
        windows.bringForward(window) {
            if directWindows[window]?.isVisible == true { return }
            guard let openWindow else {
                openDirectly(window)
                return
            }
            openWindow(window.rawValue)
        }
    }

    /// SwiftUI's opener arrives through the menu bar icon's view. Should it never arrive, the
    /// windows must still open, so this makes one by hand around the same view.
    private func openDirectly(_ window: AppWindow) {
        log.error("the window opener is not installed; opening the \(window.rawValue, privacy: .public) window directly")
        let content: NSViewController
        let title: String
        switch window {
        case .onboarding:
            content = NSHostingController(rootView: OnboardingView().environment(self))
            title = "Welcome to Voiced"
        case .settings:
            content = NSHostingController(rootView: SettingsView().environment(self))
            title = "Voiced Settings"
        }
        let made = directWindows[window] ?? NSWindow(contentViewController: content)
        made.contentViewController = content
        made.styleMask = [.titled, .closable, .miniaturizable]
        made.title = title
        made.identifier = NSUserInterfaceItemIdentifier(window.rawValue)
        made.isReleasedWhenClosed = false
        made.center()
        made.makeKeyAndOrderFront(nil)
        directWindows[window] = made
    }

    /// Closes a window that was made by hand; one SwiftUI opened is closed by SwiftUI.
    func closeDirectWindow(_ window: AppWindow) {
        directWindows[window]?.close()
    }

    /// Moves a hidden icon to the right end of the menu bar, where a menu bar manager's dividers
    /// and a full menu bar do not reach. Only ever on request: an icon may be hidden on purpose.
    func bringMenuBarItemIntoView() {
        guard menuBarItemMove != .moving else { return }
        menuBarItemMove = .moving
        log.notice("menu bar item: asked to come into view")
        Task {
            // macOS reads an item's saved place only when the item is created, so take it out,
            // save the new place, and put it back.
            windows.isMovingMenuBarItem = true
            menuBarItemIsInserted = false
            try? await Task.sleep(for: .milliseconds(300))
            MenuBarItem.askForTheRightEnd()
            menuBarItemIsInserted = true
            try? await Task.sleep(for: .milliseconds(700))
            windows.isMovingMenuBarItem = false
            windows.logMenuBarItem()
            menuBarItemMove = menuBarItemIsHidden ? .stayedHidden : nil
            let outcome = menuBarItem?.logDescription ?? "not looked up"
            if menuBarItemIsHidden {
                log.error("menu bar item: still hidden after the move: \(outcome, privacy: .public)")
            } else {
                log.notice("menu bar item: moved into view: \(outcome, privacy: .public)")
            }
        }
    }

    /// The way back into the app: setup while it is incomplete, Settings after that.
    func showMainWindow() {
        show(AppWindow.toShow(needsSetup: needsSetup))
    }
}

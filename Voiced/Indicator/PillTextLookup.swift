import AppKit
import os
import VoicedKit

/// One dictation's question to the app in front: where is the text being edited?
///
/// Asked the moment the hotkey goes down, off the main thread, so the answer is there by the
/// time the pill appears and a slow app delays nothing. An answer that comes later is dropped:
/// the pill is placed once per dictation and does not jump.
///
/// One exception. An app whose accessibility Voiced has just switched on had nothing to say
/// the first time. It is asked again a few times while the hotkey is held, and the first
/// answer with a text position is handed on through `onLaterAnswer`.
final class PillTextLookup {
    /// The app to ask for one dictation.
    struct Target {
        /// `nil` when nobody is to be asked.
        var pid: pid_t?
        /// Voiced was the app in front.
        var voicedInFront = false
    }

    /// The answer for the dictation under way; `nil` until it arrives.
    private(set) var answer: FocusedTextAnswer?
    /// A text position arrived for the dictation under way after the first answer had none.
    var onLaterAnswer: () -> Void = {}
    private var generation = 0
    /// The hotkey of the dictation under way is still down.
    private var isHeld = false
    private let apps = AppsInFront()
    private var kinds = AppKindCache()
    /// The apps whose accessibility Voiced has switched on, so that each gets the read once.
    private var woken: Set<AppKindCache.Run> = []

    /// Which app to ask. The interface checks replace it to ask a text view of their own.
    lazy var appToAsk: () -> Target = { [apps] in apps.target() }
    var locate: @Sendable (pid_t, CGFloat) -> FocusedTextAnswer = FocusedTextLocator.locate
    /// What the app is built on, from its bundle. Asked once for each run of an app.
    var kind: @Sendable (URL?) -> AppKind = { AppKind.of(bundle: $0) }
    /// The read that switches on an app's accessibility; see `AccessibilityWake`.
    var wake: @Sendable (pid_t) -> Int32 = FocusedTextLocator.readApplicationRole

    /// The hotkey came up, or the dictation was dropped: nothing more is asked for it.
    func holdEnded() {
        isHeld = false
    }

    func begin() {
        generation += 1
        isHeld = true
        answer = nil
        let target = appToAsk()
        // Accessibility measures from the top of the primary display, AppKit from its bottom.
        guard let pid = target.pid, let primaryDisplayHeight = NSScreen.screens.first?.frame.height else {
            var nobody = FocusedTextAnswer()
            nobody.asked = .nobody
            nobody.voicedInFront = target.voicedInFront
            answer = nobody
            return
        }
        let generation = generation
        let locate = locate
        let asked: FocusedTextAnswer.Asked = pid == getpid() ? .voiced : .other
        let voicedInFront = target.voicedInFront
        let app = NSRunningApplication(processIdentifier: pid)
        let bundle = app?.bundleURL
        let run = AppKindCache.Run(pid: pid, launched: app?.launchDate)
        let knownKind = kinds.claim(run)
        let kind = kind
        let wake = wake
        Task.detached(priority: .userInitiated) { [weak self] in
            var answer = locate(pid, primaryDisplayHeight)
            answer.asked = asked
            answer.voicedInFront = voicedInFront
            if let knownKind {
                answer.appKind = knownKind
            } else {
                // The first dictation into this run of the app: look inside its bundle, once.
                answer.appKind = kind(bundle)
                await self?.remember(answer.appKind, for: run)
            }
            // The answer first: this dictation's pill does not wait for the read below.
            await self?.receive(answer, for: generation)

            let askedTheAppInFront = asked == .other && !voicedInFront
            guard await self?.claimWake(of: run, answer: answer, askedTheAppInFront: askedTheAppInFront) == true else { return }
            let began = ContinuousClock.now
            let result = wake(pid)
            let milliseconds = VoicedLog.milliseconds(since: began)
            VoicedLog.setup.notice("pill lookup: read the role of the app in front to switch on its accessibility, once for this app: result=\(result) kind=\(answer.appKind.rawValue, privacy: .public) in \(milliseconds) ms")
            guard result == 0 else { return }

            // The app builds its tree now. Ask again while the key is held, so that this
            // dictation's pill can still go by the text; the same questions, nothing more.
            var asks = 0
            var found = false
            for delay in AccessibilityWake.askAgainAfter {
                try? await Task.sleep(until: began + delay, clock: .continuous)
                guard await self?.isStillHeld(generation) == true else { break }
                asks += 1
                var later = locate(pid, primaryDisplayHeight)
                later.asked = asked
                later.voicedInFront = voicedInFront
                later.appKind = answer.appKind
                if later.geometry.insertionPoint != nil || later.geometry.field != nil {
                    found = true
                    await self?.receiveLater(later, for: generation)
                    break
                }
            }
            VoicedLog.setup.notice("pill lookup: asked again \(asks) times after the read: text \(found ? "found" : "not found", privacy: .public) \(VoicedLog.milliseconds(since: began)) ms after the read")
        }
    }

    private func isStillHeld(_ generation: Int) -> Bool {
        self.generation == generation && isHeld
    }

    /// An answer with a text position, for a dictation whose first answer had none.
    private func receiveLater(_ answer: FocusedTextAnswer, for generation: Int) {
        guard isStillHeld(generation) else { return }
        self.answer = answer
        onLaterAnswer()
    }

    /// Whether the read is to be made now. Says yes at most once for one run of an app.
    private func claimWake(of run: AppKindCache.Run, answer: FocusedTextAnswer, askedTheAppInFront: Bool) -> Bool {
        let isCalledFor = AccessibilityWake.isCalledFor(
            kind: answer.appKind,
            askedTheAppInFront: askedTheAppInFront,
            focusResult: answer.focus,
            alreadyMadeForThisRunOfTheApp: woken.contains(run)
        )
        if isCalledFor {
            woken.insert(run)
        }
        return isCalledFor
    }

    private func remember(_ kind: AppKind, for run: AppKindCache.Run) {
        kinds.remember(kind, for: run)
    }

    /// Keeps the answer unless a newer dictation has begun since it was asked for.
    private func receive(_ answer: FocusedTextAnswer, for generation: Int) {
        guard self.generation == generation else { return }
        self.answer = answer
    }
}

/// Knows which app the words are going to, which is not always the one in front: Voiced itself
/// is in front while one of its windows is, and it must never ask itself where its text is.
private final class AppsInFront {
    /// The app that was last in front, other than Voiced.
    private var lastOther: pid_t?
    private var observer: (any NSObjectProtocol)?

    init() {
        lastOther = NSWorkspace.shared.frontmostApplication.map(\.processIdentifier).flatMap { $0 == getpid() ? nil : $0 }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let activated = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                self?.activated(activated)
            }
        }
    }

    private func activated(_ pid: pid_t?) {
        guard let pid, pid != getpid() else { return }
        lastOther = pid
    }

    func target() -> PillTextLookup.Target {
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return PillTextLookup.Target(pid: nil)
        }
        guard front == getpid() else {
            return PillTextLookup.Target(pid: front)
        }
        // Voiced is in front. With one of its windows holding the keyboard, the words go into
        // that window, and there is nobody to ask. With only its menu bar panel up, they go to
        // the app that was in front before.
        if let key = NSApp.keyWindow, key.styleMask.contains(.titled), !(key is NSPanel) {
            return PillTextLookup.Target(pid: nil, voicedInFront: true)
        }
        let previous = lastOther.flatMap { NSRunningApplication(processIdentifier: $0) }
        return PillTextLookup.Target(pid: previous?.isTerminated == false ? previous?.processIdentifier : nil, voicedInFront: true)
    }
}

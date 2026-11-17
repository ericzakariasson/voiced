import CoreGraphics
import Foundation
import os
import VoicedKit

private let log = VoicedLog.hotkey

/// Watches the keyboard system-wide for the dictation hotkey.
///
/// Uses an active event tap, which needs the Accessibility permission. An active tap (rather than
/// a listen-only one) lets a key-combination hotkey be kept from the focused app while it is held.
final class HotkeyMonitor {
    private var machine: HotkeyStateMachine
    private let onAction: (HotkeyStateMachine.Action) -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// While suspended, every event passes through untouched. Used while a new hotkey is recorded.
    var isSuspended = false {
        didSet {
            if isSuspended { resetMachine() }
        }
    }

    var isRunning: Bool {
        tap != nil
    }

    init(hotkey: Hotkey, onAction: @escaping (HotkeyStateMachine.Action) -> Void) {
        machine = HotkeyStateMachine(hotkey: hotkey)
        self.onAction = onAction
    }

    func setHotkey(_ hotkey: Hotkey) {
        log.notice("hotkey set to \(hotkey.displayName, privacy: .public)")
        if let action = machine.setHotkey(hotkey) {
            deliver(action)
        }
    }

    /// Hands the action over on the next turn of the main run loop. Starting a recording takes a
    /// moment, and doing that inside the tap callback would hold up every keyboard event meanwhile.
    private func deliver(_ action: HotkeyStateMachine.Action) {
        Task { [onAction] in
            onAction(action)
        }
    }

    /// Returns `false` when the tap cannot be created, which means Accessibility is not granted.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let events: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("event tap could not be created; macOS is not letting Voiced watch the keyboard")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        log.notice("event tap started, hotkey=\(self.machine.hotkey.displayName, privacy: .public)")
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        log.notice("event tap stopped")
        resetMachine()
    }

    private func resetMachine() {
        if let action = machine.reset() {
            log.notice("hold cancelled: key state was reset")
            deliver(action)
        }
    }

    /// Returns whether the event should be swallowed.
    fileprivate func handle(_ event: TappedEvent) -> Bool {
        switch event.type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system switched the tap off; key state seen so far can no longer be trusted.
            log.error("event tap was switched off by the system (\(event.type == .tapDisabledByTimeout ? "it was too slow" : "user input", privacy: .public)); switching it back on")
            resetMachine()
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        case .keyDown, .keyUp, .flagsChanged:
            break
        default:
            return false
        }
        guard !isSuspended, event.sourceUserData != PasteKeystroke.eventMarker else { return false }

        let kind: HotkeyEvent.Kind = switch event.type {
        case .keyDown: .keyDown
        case .keyUp: .keyUp
        default: .flagsChanged
        }
        let outcome = machine.handle(HotkeyEvent(
            kind: kind,
            keyCode: event.keyCode,
            flags: event.flags,
            isRepeat: event.isRepeat
        ))
        if let action = outcome.action {
            // Only the hotkey's own transitions are logged, never which other key was pressed.
            switch action {
            case .begin:
                log.notice("hotkey down")
            case .end:
                log.notice("hotkey up")
            case .cancel:
                log.notice("hold cancelled: another key was pressed while the hotkey was held")
            }
            deliver(action)
        }
        return outcome.consume
    }
}

/// The parts of a `CGEvent` the monitor needs, copied out so they can cross to the main actor.
private struct TappedEvent: Sendable {
    var type: CGEventType
    var keyCode: UInt16
    var flags: UInt64
    var isRepeat: Bool
    var sourceUserData: Int64
}

/// The tap's run loop source is on the main run loop, so this always runs on the main thread.
private nonisolated func hotkeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let passThrough = Unmanaged.passUnretained(event)
    guard let userInfo else { return passThrough }

    let tapped = TappedEvent(
        type: type,
        keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
        flags: event.flags.rawValue,
        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
        sourceUserData: event.getIntegerValueField(.eventSourceUserData)
    )
    let monitorAddress = UInt(bitPattern: userInfo)
    let consume = MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: monitorAddress) else { return false }
        return Unmanaged<HotkeyMonitor>.fromOpaque(pointer).takeUnretainedValue().handle(tapped)
    }
    return consume ? nil : passThrough
}

import Foundation

/// A keyboard event reduced to what the hotkey logic needs.
public struct HotkeyEvent: Equatable, Sendable {
    public enum Kind: Sendable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    public var kind: Kind
    public var keyCode: UInt16
    /// Raw `CGEventFlags`.
    public var flags: UInt64
    public var isRepeat: Bool

    public init(kind: Kind, keyCode: UInt16, flags: UInt64, isRepeat: Bool = false) {
        self.kind = kind
        self.keyCode = keyCode
        self.flags = flags
        self.isRepeat = isRepeat
    }
}

/// Turns a stream of keyboard events into hold-to-talk actions for one hotkey.
public struct HotkeyStateMachine: Sendable {
    public enum Action: Equatable, Sendable {
        case begin
        case end
        case cancel
    }

    public struct Outcome: Equatable, Sendable {
        public var action: Action?
        /// Whether the event should be kept from the focused app.
        public var consume: Bool

        public init(action: Action? = nil, consume: Bool = false) {
            self.action = action
            self.consume = consume
        }

        static let ignore = Outcome()
    }

    public private(set) var hotkey: Hotkey
    public private(set) var isActive = false
    private var modifierIsDown = false
    private var swallowKeyUntilReleased = false

    public init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    /// Replaces the hotkey. Returns `.cancel` when a hold was in progress.
    public mutating func setHotkey(_ hotkey: Hotkey) -> Action? {
        self.hotkey = hotkey
        return reset()
    }

    /// Forgets all key state. Returns `.cancel` when a hold was in progress.
    public mutating func reset() -> Action? {
        let wasActive = isActive
        isActive = false
        modifierIsDown = false
        swallowKeyUntilReleased = false
        return wasActive ? .cancel : nil
    }

    public mutating func handle(_ event: HotkeyEvent) -> Outcome {
        if let modifierKey = hotkey.modifierKey {
            handleModifierOnly(event, key: modifierKey)
        } else {
            handleCombination(event)
        }
    }

    private mutating func handleModifierOnly(_ event: HotkeyEvent, key: ModifierKey) -> Outcome {
        switch event.kind {
        case .flagsChanged where event.keyCode == key.rawValue:
            let pressed = key.isPressed(flags: event.flags, wasPressed: modifierIsDown)
            if pressed, !modifierIsDown {
                modifierIsDown = true
                guard !otherModifiersHeld(flags: event.flags, besides: key) else { return .ignore }
                isActive = true
                return Outcome(action: .begin)
            }
            if !pressed, modifierIsDown {
                modifierIsDown = false
                guard isActive else { return .ignore }
                isActive = false
                return Outcome(action: .end)
            }
            return .ignore

        case .flagsChanged, .keyDown:
            // Another key while the modifier is held means a shortcut or a special character, not dictation.
            guard isActive else { return .ignore }
            isActive = false
            return Outcome(action: .cancel)

        case .keyUp:
            return .ignore
        }
    }

    private func otherModifiersHeld(flags: UInt64, besides key: ModifierKey) -> Bool {
        if flags & EventFlagMask.allGeneric & ~key.genericMask != 0 {
            return true
        }
        guard let deviceMask = key.deviceMask else { return false }
        return flags & EventFlagMask.allDevice & ~deviceMask != 0
    }

    private mutating func handleCombination(_ event: HotkeyEvent) -> Outcome {
        switch event.kind {
        case .keyDown where event.keyCode == hotkey.keyCode:
            if isActive || swallowKeyUntilReleased {
                return Outcome(consume: true)
            }
            guard !event.isRepeat, Hotkey.Modifiers(eventFlags: event.flags) == hotkey.modifiers else {
                return .ignore
            }
            isActive = true
            return Outcome(action: .begin, consume: true)

        case .keyDown where event.keyCode == Hotkey.escapeKeyCode && isActive:
            isActive = false
            swallowKeyUntilReleased = true
            return Outcome(action: .cancel, consume: true)

        case .keyUp where event.keyCode == hotkey.keyCode:
            if isActive {
                isActive = false
                return Outcome(action: .end, consume: true)
            }
            if swallowKeyUntilReleased {
                swallowKeyUntilReleased = false
                return Outcome(consume: true)
            }
            return .ignore

        case .flagsChanged where isActive:
            guard !Hotkey.Modifiers(eventFlags: event.flags).isSuperset(of: hotkey.modifiers) else {
                return .ignore
            }
            // Letting go of the modifiers first also ends the hold; the key itself is still down.
            isActive = false
            swallowKeyUntilReleased = true
            return Outcome(action: .end)

        default:
            return .ignore
        }
    }
}

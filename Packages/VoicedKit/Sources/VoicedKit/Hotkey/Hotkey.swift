import Foundation

/// Raw `CGEventFlags` bits, kept here so the hotkey logic stays free of AppKit and testable.
enum EventFlagMask {
    static let shift: UInt64 = 0x0002_0000
    static let control: UInt64 = 0x0004_0000
    static let option: UInt64 = 0x0008_0000
    static let command: UInt64 = 0x0010_0000
    static let function: UInt64 = 0x0080_0000
    static let allGeneric: UInt64 = shift | control | option | command | function

    /// Device-dependent bits (`NX_DEVICE*KEYMASK`) that tell the left key from the right one.
    static let leftControl: UInt64 = 0x0001
    static let leftShift: UInt64 = 0x0002
    static let rightShift: UInt64 = 0x0004
    static let leftCommand: UInt64 = 0x0008
    static let rightCommand: UInt64 = 0x0010
    static let leftOption: UInt64 = 0x0020
    static let rightOption: UInt64 = 0x0040
    static let rightControl: UInt64 = 0x2000
    static let allDevice: UInt64 = 0x207F
}

/// A physical modifier key that can be held on its own as the dictation hotkey.
public enum ModifierKey: UInt16, CaseIterable, Sendable {
    case rightCommand = 54
    case leftCommand = 55
    case leftShift = 56
    case leftOption = 58
    case leftControl = 59
    case rightShift = 60
    case rightOption = 61
    case rightControl = 62
    case function = 63

    public var displayName: String {
        switch self {
        case .rightCommand: "Right ⌘"
        case .leftCommand: "Left ⌘"
        case .leftShift: "Left ⇧"
        case .rightShift: "Right ⇧"
        case .leftOption: "Left ⌥"
        case .rightOption: "Right ⌥"
        case .leftControl: "Left ⌃"
        case .rightControl: "Right ⌃"
        case .function: "Fn"
        }
    }

    var genericMask: UInt64 {
        switch self {
        case .rightCommand, .leftCommand: EventFlagMask.command
        case .leftShift, .rightShift: EventFlagMask.shift
        case .leftOption, .rightOption: EventFlagMask.option
        case .leftControl, .rightControl: EventFlagMask.control
        case .function: EventFlagMask.function
        }
    }

    var deviceMask: UInt64? {
        switch self {
        case .rightCommand: EventFlagMask.rightCommand
        case .leftCommand: EventFlagMask.leftCommand
        case .leftShift: EventFlagMask.leftShift
        case .rightShift: EventFlagMask.rightShift
        case .leftOption: EventFlagMask.leftOption
        case .rightOption: EventFlagMask.rightOption
        case .leftControl: EventFlagMask.leftControl
        case .rightControl: EventFlagMask.rightControl
        case .function: nil
        }
    }

    func isPressed(flags: UInt64, wasPressed: Bool) -> Bool {
        guard flags & genericMask != 0 else { return false }
        guard let deviceMask else { return true }
        if flags & EventFlagMask.allDevice != 0 {
            return flags & deviceMask != 0
        }
        // Synthetic events carry no device bits; each flagsChanged for this key then toggles it.
        return !wasPressed
    }
}

/// The key held to dictate: either one modifier key on its own, or a key with modifiers.
public struct Hotkey: Codable, Equatable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        public init(eventFlags: UInt64) {
            var modifiers: Modifiers = []
            if eventFlags & EventFlagMask.control != 0 { modifiers.insert(.control) }
            if eventFlags & EventFlagMask.option != 0 { modifiers.insert(.option) }
            if eventFlags & EventFlagMask.shift != 0 { modifiers.insert(.shift) }
            if eventFlags & EventFlagMask.command != 0 { modifiers.insert(.command) }
            self = modifiers
        }

        public var symbols: String {
            var result = ""
            if contains(.control) { result += "⌃" }
            if contains(.option) { result += "⌥" }
            if contains(.shift) { result += "⇧" }
            if contains(.command) { result += "⌘" }
            return result
        }
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers
    /// The character the key produced when the hotkey was recorded, for display on other layouts.
    public var keyLabel: String?

    public init(keyCode: UInt16, modifiers: Modifiers = [], keyLabel: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    public init(modifierKey: ModifierKey) {
        self.init(keyCode: modifierKey.rawValue)
    }

    public static let rightOption = Hotkey(modifierKey: .rightOption)
    public static let `default` = rightOption

    public var modifierKey: ModifierKey? {
        modifiers.isEmpty ? ModifierKey(rawValue: keyCode) : nil
    }

    public var isModifierOnly: Bool {
        modifierKey != nil
    }

    public var displayName: String {
        if let modifierKey {
            return modifierKey.displayName
        }
        return modifiers.symbols + Self.keyName(keyCode: keyCode, label: keyLabel)
    }

    /// A key with no ⌘, ⌃ or ⌥ would swallow ordinary typing, so only function keys may stand alone.
    public static func isUsableCombination(keyCode: UInt16, modifiers: Modifiers) -> Bool {
        if ModifierKey(rawValue: keyCode) != nil {
            return false
        }
        if !modifiers.isDisjoint(with: [.command, .control, .option]) {
            return true
        }
        return functionKeyNames[keyCode] != nil
    }

    static func keyName(keyCode: UInt16, label: String?) -> String {
        if let name = specialKeyNames[keyCode] ?? functionKeyNames[keyCode] {
            return name
        }
        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return label.uppercased()
        }
        return "Key \(keyCode)"
    }

    static let escapeKeyCode: UInt16 = 53

    private static let specialKeyNames: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 117: "⌦",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    private static let functionKeyNames: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]
}

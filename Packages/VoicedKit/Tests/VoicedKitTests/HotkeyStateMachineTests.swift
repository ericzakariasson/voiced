import Foundation
import Testing
@testable import VoicedKit

private enum Flags {
    static let none: UInt64 = 0x100
    static let rightOption: UInt64 = 0x100 | EventFlagMask.option | EventFlagMask.rightOption
    static let leftOption: UInt64 = 0x100 | EventFlagMask.option | EventFlagMask.leftOption
    static let bothOptions: UInt64 = rightOption | leftOption
    static let leftCommand: UInt64 = 0x100 | EventFlagMask.command | EventFlagMask.leftCommand
    static let commandAndRightOption: UInt64 = leftCommand | rightOption
    static let function: UInt64 = 0x100 | EventFlagMask.function
    static let controlOption: UInt64 = 0x100 | EventFlagMask.control | EventFlagMask.option | EventFlagMask.leftControl | EventFlagMask.leftOption
    static let control: UInt64 = 0x100 | EventFlagMask.control | EventFlagMask.leftControl
}

private let spaceKey: UInt16 = 49
private let escapeKey: UInt16 = 53
private let letterA: UInt16 = 0

private func flagsChanged(_ key: ModifierKey, _ flags: UInt64) -> HotkeyEvent {
    HotkeyEvent(kind: .flagsChanged, keyCode: key.rawValue, flags: flags)
}

private func keyDown(_ keyCode: UInt16, _ flags: UInt64 = Flags.none, isRepeat: Bool = false) -> HotkeyEvent {
    HotkeyEvent(kind: .keyDown, keyCode: keyCode, flags: flags, isRepeat: isRepeat)
}

private func keyUp(_ keyCode: UInt16, _ flags: UInt64 = Flags.none) -> HotkeyEvent {
    HotkeyEvent(kind: .keyUp, keyCode: keyCode, flags: flags)
}

private typealias Outcome = HotkeyStateMachine.Outcome

@Suite struct ModifierOnlyHotkeyTests {
    @Test func holdingTheModifierBeginsAndReleasingEnds() {
        var machine = HotkeyStateMachine(hotkey: .rightOption)

        #expect(machine.handle(flagsChanged(.rightOption, Flags.rightOption)) == Outcome(action: .begin))
        #expect(machine.isActive)
        #expect(machine.handle(flagsChanged(.rightOption, Flags.none)) == Outcome(action: .end))
        #expect(!machine.isActive)
    }

    @Test func modifierEventsAreNeverConsumed() {
        var machine = HotkeyStateMachine(hotkey: .rightOption)

        #expect(!machine.handle(flagsChanged(.rightOption, Flags.rightOption)).consume)
        #expect(!machine.handle(flagsChanged(.rightOption, Flags.none)).consume)
    }

    @Test func theOtherSideOfTheSameModifierDoesNothing() {
        var machine = HotkeyStateMachine(hotkey: .rightOption)

        #expect(machine.handle(flagsChanged(.leftOption, Flags.leftOption)) == Outcome())
        #expect(machine.handle(flagsChanged(.leftOption, Flags.none)) == Outcome())
    }

    @Test func typingACharacterWithTheModifierCancels() {
        var machine = HotkeyStateMachine(hotkey: .rightOption)
        _ = machine.handle(flagsChanged(.rightOption, Flags.rightOption))

        #expect(machine.handle(keyDown(letterA, Flags.rightOption)) == Outcome(action: .cancel))
        #expect(machine.handle(keyUp(letterA, Flags.rightOption)) == Outcome())
        #expect(machine.handle(flagsChanged(.rightOption, Flags.none)) == Outcome())
    }

    /// Right ⌥ types characters such as @ and { on some layouts. The keystroke must reach the app,
    /// and the rest of that hold must do nothing: no second cancel, and no dictation at release.
    @Test func aCharacterTypedWithTheModifierPassesThroughAndTheRestOfTheHoldIsIgnored() {
        var machine = HotkeyStateMachine(hotkey: .rightOption)
        let digitTwo: UInt16 = 19
        let digitSeven: UInt16 = 26
        _ = machine.handle(flagsChanged(.rightOption, Flags.rightOption))

        let first = machine.handle(keyDown(digitTwo, Flags.rightOption))
        #expect(first == Outcome(action: .cancel, consume: false))
        #expect(!machine.isActive)

        // The key repeats, comes up, and a second character follows while ⌥ stays down.
        #expect(machine.handle(keyDown(digitTwo, Flags.rightOption, isRepeat: true)) == Outcome())
        #expect(machine.handle(keyUp(digitTwo, Flags.rightOption)) == Outcome())
        #expect(machine.handle(keyDown(digitSeven, Flags.rightOption)) == Outcome())
        #expect(machine.handle(keyUp(digitSeven, Flags.rightOption)) == Outcome())
        #expect(machine.handle(flagsChanged(.rightOption, Flags.none)) == Outcome())

        // The next hold on its own dictates again.
        #expect(machine.handle(flagsChanged(.rightOption, Flags.rightOption)) == Outcome(action: .begin))
        #expect(machine.handle(flagsChanged(.rightOption, Flags.none)) == Outcome(action: .end))
    }

    @Test func releasingAKeyThatWasAlreadyDownDoesNotCancel() {
        var machine = HotkeyStateMachine(hotkey: .rightOption)
        // Fast typing: the previous letter is still down when the hotkey is pressed.
        _ = machine.handle(keyDown(letterA))
        _ = machine.handle(flagsChanged(.rightOption, Flags.rightOption))

        #expect(machine.handle(keyUp(letterA, Flags.rightOption)) == Outcome())
        #expect(machine.isActive)
        #expect(machine.handle(flagsChanged(.rightOption, Flags.none)) == Outcome(action: .end))
    }

    @Test func pressingAnotherModifierWhileHoldingCancels() {
        var machine = HotkeyStateMachine(hotkey: .rightOption)
        _ = machine.handle(flagsChanged(.rightOption, Flags.rightOption))

        #expect(machine.handle(flagsChanged(.leftCommand, Flags.commandAndRightOption)) == Outcome(action: .cancel))
        #expect(machine.handle(flagsChanged(.rightOption, Flags.leftCommand)) == Outcome())
    }

    @Test func doesNotBeginWhenAnotherModifierIsAlreadyHeld() {
        var machine = HotkeyStateMachine(hotkey: .rightOption)
        _ = machine.handle(flagsChanged(.leftCommand, Flags.leftCommand))

        #expect(machine.handle(flagsChanged(.rightOption, Flags.commandAndRightOption)) == Outcome())
        #expect(machine.handle(flagsChanged(.rightOption, Flags.leftCommand)) == Outcome())
        #expect(!machine.isActive)
    }

    @Test func doesNotBeginWhenTheOtherSideIsAlreadyHeld() {
        var machine = HotkeyStateMachine(hotkey: .rightOption)
        _ = machine.handle(flagsChanged(.leftOption, Flags.leftOption))

        #expect(machine.handle(flagsChanged(.rightOption, Flags.bothOptions)) == Outcome())
    }

    @Test func releaseIsDetectedWhileTheOtherSideStaysDown() {
        var machine = HotkeyStateMachine(hotkey: .rightOption)
        _ = machine.handle(flagsChanged(.rightOption, Flags.rightOption))
        // Left Option goes down mid-hold (cancels), then Right Option is released while Left stays down.
        _ = machine.handle(flagsChanged(.leftOption, Flags.bothOptions))
        _ = machine.handle(flagsChanged(.rightOption, Flags.leftOption))
        _ = machine.handle(flagsChanged(.leftOption, Flags.none))

        #expect(machine.handle(flagsChanged(.rightOption, Flags.rightOption)) == Outcome(action: .begin))
    }

    @Test func worksWithoutDeviceBits() {
        var machine = HotkeyStateMachine(hotkey: .rightOption)
        let optionOnly = EventFlagMask.option

        #expect(machine.handle(flagsChanged(.rightOption, optionOnly)) == Outcome(action: .begin))
        #expect(machine.handle(flagsChanged(.rightOption, 0)) == Outcome(action: .end))
    }

    @Test func functionKeyCanBeTheHotkey() {
        var machine = HotkeyStateMachine(hotkey: Hotkey(modifierKey: .function))

        #expect(machine.handle(flagsChanged(.function, Flags.function)) == Outcome(action: .begin))
        #expect(machine.handle(flagsChanged(.function, Flags.none)) == Outcome(action: .end))
    }

    @Test func changingTheHotkeyMidHoldCancels() {
        var machine = HotkeyStateMachine(hotkey: .rightOption)
        _ = machine.handle(flagsChanged(.rightOption, Flags.rightOption))

        #expect(machine.setHotkey(Hotkey(modifierKey: .function)) == .cancel)
        #expect(machine.setHotkey(.rightOption) == nil)
    }
}

@Suite struct CombinationHotkeyTests {
    private let hotkey = Hotkey(keyCode: spaceKey, modifiers: [.control, .option])

    @Test func holdingTheCombinationBeginsAndReleasingTheKeyEnds() {
        var machine = HotkeyStateMachine(hotkey: hotkey)

        #expect(machine.handle(keyDown(spaceKey, Flags.controlOption)) == Outcome(action: .begin, consume: true))
        #expect(machine.handle(keyUp(spaceKey, Flags.controlOption)) == Outcome(action: .end, consume: true))
    }

    @Test func keyRepeatsWhileHeldAreSwallowed() {
        var machine = HotkeyStateMachine(hotkey: hotkey)
        _ = machine.handle(keyDown(spaceKey, Flags.controlOption))

        #expect(machine.handle(keyDown(spaceKey, Flags.controlOption, isRepeat: true)) == Outcome(consume: true))
        #expect(machine.isActive)
    }

    @Test func theKeyWithOtherModifiersPassesThrough() {
        var machine = HotkeyStateMachine(hotkey: hotkey)

        #expect(machine.handle(keyDown(spaceKey, Flags.none)) == Outcome())
        #expect(machine.handle(keyDown(spaceKey, Flags.control)) == Outcome())
        #expect(machine.handle(keyUp(spaceKey, Flags.none)) == Outcome())
    }

    @Test func releasingTheModifiersFirstEndsAndSwallowsTheRestOfTheKeyPress() {
        var machine = HotkeyStateMachine(hotkey: hotkey)
        _ = machine.handle(keyDown(spaceKey, Flags.controlOption))

        #expect(machine.handle(flagsChanged(.leftOption, Flags.control)) == Outcome(action: .end))
        #expect(machine.handle(keyDown(spaceKey, Flags.control, isRepeat: true)) == Outcome(consume: true))
        #expect(machine.handle(keyUp(spaceKey, Flags.none)) == Outcome(consume: true))
        // The next, unrelated press of the key is left alone.
        #expect(machine.handle(keyDown(spaceKey, Flags.none)) == Outcome())
    }

    @Test func escapeCancelsWhileHeld() {
        var machine = HotkeyStateMachine(hotkey: hotkey)
        _ = machine.handle(keyDown(spaceKey, Flags.controlOption))

        #expect(machine.handle(keyDown(escapeKey, Flags.controlOption)) == Outcome(action: .cancel, consume: true))
        #expect(machine.handle(keyUp(spaceKey, Flags.controlOption)) == Outcome(consume: true))
        #expect(!machine.isActive)
    }

    @Test func escapeIsLeftAloneWhenIdle() {
        var machine = HotkeyStateMachine(hotkey: hotkey)

        #expect(machine.handle(keyDown(escapeKey)) == Outcome())
    }

    @Test func otherKeysPassThroughWhileHeld() {
        var machine = HotkeyStateMachine(hotkey: hotkey)
        _ = machine.handle(keyDown(spaceKey, Flags.controlOption))

        #expect(machine.handle(keyDown(letterA, Flags.controlOption)) == Outcome())
        #expect(machine.isActive)
    }
}

@Suite struct HotkeyTests {
    @Test func displayNames() {
        #expect(Hotkey.rightOption.displayName == "Right ⌥")
        #expect(Hotkey(modifierKey: .function).displayName == "Fn")
        #expect(Hotkey(keyCode: spaceKey, modifiers: [.control, .option]).displayName == "⌃⌥Space")
        #expect(Hotkey(keyCode: letterA, modifiers: [.command, .shift], keyLabel: "a").displayName == "⇧⌘A")
        #expect(Hotkey(keyCode: 105).displayName == "F13")
    }

    @Test func defaultIsRightOption() {
        #expect(Hotkey.default.modifierKey == .rightOption)
        #expect(Hotkey.default.isModifierOnly)
    }

    @Test func combinationsNeedAModifierUnlessTheyAreFunctionKeys() {
        #expect(Hotkey.isUsableCombination(keyCode: spaceKey, modifiers: [.option]))
        #expect(Hotkey.isUsableCombination(keyCode: 105, modifiers: []))
        #expect(!Hotkey.isUsableCombination(keyCode: letterA, modifiers: []))
        #expect(!Hotkey.isUsableCombination(keyCode: letterA, modifiers: [.shift]))
        #expect(!Hotkey.isUsableCombination(keyCode: ModifierKey.rightOption.rawValue, modifiers: [.command]))
    }

    @Test func survivesEncodingAndDecoding() throws {
        let hotkey = Hotkey(keyCode: letterA, modifiers: [.command, .option], keyLabel: "a")
        let decoded = try JSONDecoder().decode(Hotkey.self, from: JSONEncoder().encode(hotkey))

        #expect(decoded == hotkey)
    }

    @Test func modifiersAreReadFromEventFlags() {
        #expect(Hotkey.Modifiers(eventFlags: Flags.controlOption) == [.control, .option])
        #expect(Hotkey.Modifiers(eventFlags: Flags.function) == [])
    }
}

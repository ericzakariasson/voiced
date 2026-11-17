import AppKit
import SwiftUI
import VoicedKit

/// A button that shows the hotkey and, when clicked, records the next key press as the new one.
///
/// Accepts one modifier key pressed and released on its own (Right ⌥, Fn, …) or a key held with
/// ⌘, ⌃ or ⌥. Esc cancels.
struct HotkeyRecorder: View {
    @Environment(AppModel.self) private var model

    @State private var isRecording = false
    @State private var monitor: Any?
    /// The single modifier pressed since recording began, if nothing else was pressed with it.
    @State private var loneModifier: ModifierKey?
    @State private var sawOtherInput = false

    var body: some View {
        Button(action: toggle) {
            // One width for both states, so the control does not jump when it starts listening.
            HStack(spacing: 6) {
                if isRecording {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .symbolEffect(.pulse)
                    Text("Press a Key…")
                } else {
                    Text(model.hotkey.displayName)
                }
            }
            .frame(width: 96)
        }
        .help("Click, then press the key or combination you want to hold while dictating")
        .onDisappear(perform: stop)
    }

    private func toggle() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        isRecording = true
        loneModifier = nil
        sawOtherInput = false
        model.isRecordingHotkey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if isRecording {
            isRecording = false
            model.isRecordingHotkey = false
        }
    }

    private func handle(_ event: NSEvent) {
        let modifiers = Hotkey.Modifiers(eventFlags: UInt64(event.modifierFlags.rawValue))

        if event.type == .keyDown {
            if event.keyCode == 53, modifiers.isEmpty {
                stop()
                return
            }
            guard Hotkey.isUsableCombination(keyCode: event.keyCode, modifiers: modifiers) else {
                // A plain key would swallow ordinary typing. Whatever modifier is down no longer counts as pressed alone.
                loneModifier = nil
                sawOtherInput = true
                NSSound.beep()
                return
            }
            commit(Hotkey(keyCode: event.keyCode, modifiers: modifiers, keyLabel: event.charactersIgnoringModifiers))
            return
        }

        // flagsChanged: a modifier went down or came up.
        let anyModifierDown = !modifiers.isEmpty || event.modifierFlags.contains(.function)
        if anyModifierDown {
            if loneModifier == nil, !sawOtherInput, let key = ModifierKey(rawValue: event.keyCode) {
                loneModifier = key
            } else {
                // A second modifier joined: this is the start of a combination, not a lone key.
                loneModifier = nil
                sawOtherInput = true
            }
        } else if let loneModifier {
            commit(Hotkey(modifierKey: loneModifier))
        } else {
            // Everything is released; the next press starts from a clean slate.
            sawOtherInput = false
        }
    }

    private func commit(_ hotkey: Hotkey) {
        model.setHotkey(hotkey)
        stop()
    }
}

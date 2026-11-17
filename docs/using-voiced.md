# Using Voiced

What Voiced does, what it leaves out, and how to use it. To build it, see [Building and changing Voiced](building.md); when something does not work, see [Troubleshooting](troubleshooting.md).

## What v1 does

- **The dictation loop.** Hold **Right ⌥ (Option)**, speak, release. The text is pasted into the focused app, usually a second or two after you let go.
- **Cleanup.** Punctuation, capitalization and paragraphs are fixed, and filler words and false starts are removed. Your wording, meaning and language are left alone. If the cleanup step fails, Voiced pastes the raw transcript and says so. Cleanup can be switched off.
- **A pill that shows what is happening.** Bars that follow your voice and a clock while it records, then Transcribing… and Polishing…. It is dark glass with white marks, whether your Mac is in the light or the dark appearance. If the microphone is slow to start, the pill says Starting Microphone… until audio arrives, and the dictation ends with a warning that its beginning may be missing. It can stay at a fixed place, which you choose by dragging it, or sit next to the text you are dictating into.
- **Setup and settings.** A setup window for the two permissions and the key; Settings for the hotkey, the key, the pill, cleanup and the menu bar icon.

## What v1 does not do

- No custom dictionary, snippets, per-app tone, or voice commands.
- No offline or on-device transcription. Every dictation needs the network and an xAI API key, and xAI bills that key's account for the usage.
- No history. Voiced keeps no audio and no transcripts.
- No live transcript while you speak, and no language setting: Voiced sends none and leaves the language to xAI's transcription model.
- No auto-update or launch at login. You download each release yourself, and one whose name ends in `-unsigned` has to be approved before macOS opens it; see [Install](../README.md#install).

## Everyday use

- **Change the hotkey** in the menu bar menu or in Settings: click the hotkey button and press a single modifier key (Right ⌘, Fn, …) or a combination such as ⌃⌥Space.
- **Cancel a dictation** by pressing any other key while holding a lone modifier, or Esc when the hotkey is a combination.
- **Choose where the pill goes** under Pill in the menu bar menu or in Settings › Pill: Next to Text, the default, or Fixed Place. Next to Text puts the pill by your text cursor when you start dictating, below the line, or above it when there is no room below. It is centred on the cursor and kept within the left and right edges of the text field, so at the start of an empty box it does not cover what is beside the box. Apps built on Chromium or Electron, such as Chrome, Slack and Cursor, say where their text cursor is only once Voiced has switched their accessibility support on, which it does at the first dictation into them; that first time the pill starts at the bottom of the app's window and moves to the text once the app says where it is, if you are still holding the key. It goes to the fixed place only when not even the window is given.
- **Move the fixed place** by dragging the pill, on any display. Settings › Pill › Show Pill puts it on screen so you can place it without dictating, and Reset Position sends it back to the bottom centre. A pill that is sitting next to text can be dragged too, and moves for that dictation only. Dragging never takes the keyboard from the app you are dictating into.
- **Switch cleanup off** with Cleanup in the menu bar menu or under Settings › Cleanup, when you want your words as they were transcribed. Nothing is then sent for cleanup, and the pill says Transcribing… until the text is in. A change applies from the next time you hold the hotkey.
- **Get back to Voiced** by opening it again while it runs, from Finder, Spotlight or `open`: that brings up setup while setup is incomplete and Settings after that. Voiced has a Dock icon only while one of its windows is open.

## Known limits

- Insertion pastes with ⌘V, so it works wherever paste works and nowhere else.
- A new dictation cannot start while the previous one is still being transcribed.
- Voiced has been run on macOS 26 only.

# Permissions and privacy

What Voiced is allowed to do on your Mac, what it sends and where, and what it keeps.

## Permissions

Voiced asks for two permissions and cannot work without both.

| Permission | Why |
| --- | --- |
| **Microphone** | To record you while the hotkey is held. The microphone is on from the moment the hotkey goes down until just after you release it, and at no other time. |
| **Accessibility** | To notice the hotkey while another app is in front, which takes a system-wide keyboard event tap, and to paste the result by sending ⌘V to the focused app. With the pill set to Next to Text, as it is until you choose Fixed Place, also to ask the app in front where its text cursor is, or failing that where its window is. |

To keep starts quick, Voiced finds a built-in or wired input device at launch, after the Mac wakes or is unlocked, and when the input device changes, which does not turn the microphone on; it leaves a Bluetooth input alone until the hotkey goes down. It does this only once Microphone is granted.

The event tap sees every key press, because that is the only way to see a global hotkey. Voiced uses it to recognise the hotkey and nothing else: it does not record, store, send or log which keys you press.

Voiced is not sandboxed, because event taps and Accessibility do not work in the sandbox. It runs with the hardened runtime and one entitlement, audio input.

## What is read from other apps

With the pill set to Next to Text, Voiced asks the app in front, each time the hotkey goes down, where its text cursor and text field are on screen, and, when the app gives neither, where its window is. It asks only where they are, never what they contain, and it writes nothing to the other app. The answer places the pill and is used for nothing else: it is neither stored nor sent.

Voiced also looks at which frameworks that app is built with, to tell whether the app is built on Electron, on Chromium or on neither. It looks once per app, and only inside apps in the standard application folders; an app that runs from anywhere else is noted as unknown without its files being touched.

One question is asked for its effect and not for its answer. Apps built on Electron or Chromium, such as Cursor, Slack and Chrome, say nothing about their text until an assistive app shows itself. When such an app is in front and gives no position, Voiced reads the role of the app itself, once for each such app. The app takes that read as the sign of an assistive app, as it would from macOS's Voice Control, and switches on its accessibility support. Voiced then asks the app again where its text is, up to six times over the next second and a half while the key is still held, so that the pill can move to the text during that same dictation; from the next dictation on, the first question is answered. That support then stays on in that app until it quits, which costs the app some processor time and memory, and Voiced cannot switch it off again. The app is not told that a screen reader is present. An app of unknown kind, one outside the standard application folders, is not read.

Next to Text is the default. With Fixed Place, nothing is asked.

## Where the key is kept

In your login Keychain, as a generic password named "Voiced Grok API Key" (service `com.ericzakariasson.Voiced`, account `xai-api-key`). Voiced reads it once at launch and keeps it in memory while it runs. The key is not written to preferences, files or logs. Remove in Settings deletes it from the Keychain.

## What leaves your Mac

Voiced talks to one host, `api.x.ai`, over TLS, with your key in the `Authorization` header. It makes three kinds of request:

| When | Request | What is sent |
| --- | --- | --- |
| You click Save on a key | `GET https://api.x.ai/v1/api-key` | The key, to check that xAI accepts it. A key xAI rejects is not stored; if xAI cannot be reached, the key is stored unchecked and Voiced says so. |
| You hold the hotkey | `wss://api.x.ai/v1/stt` | Your voice, as 16 kHz mono 16-bit PCM, streamed while you speak. |
| You release the hotkey | `POST https://api.x.ai/v1/responses` | The transcript and the cleanup instructions, with `store: false`. Not made for a dictation begun with Cleanup switched off. |

Nothing is sent for a tap: xAI is contacted only once the hotkey has been held for a quarter of a second. From then on the audio is streamed as you speak, so a dictation you cancel later has already been sent, though nothing is pasted.

That is all of it. There is no analytics, crash reporting, update check or other server. What xAI does with the audio and text it receives is governed by xAI's terms and your account's settings, not by Voiced.

## What stays on your Mac

- **Audio** is held in memory and never written to disk.
- **The finished text** goes onto the clipboard to be pasted, marked as transient so that clipboard managers following the nspasteboard.org convention skip it, and whatever was on the clipboard before is put back within a second unless you copied something else meanwhile.
- **Where your text cursor or the window is,** which Next to Text asks for, is used to place the pill and is neither stored nor sent.
- **Preferences** hold the hotkey, the pill's fixed place and placement choice, whether cleanup is on, the menu bar icon's place and a marker that Voiced has been launched before.

## What the log holds

Voiced writes to the macOS unified log on your Mac and sends none of it anywhere. [Troubleshooting](troubleshooting.md) shows how to read it.

- **It holds** stages, counts, sizes, timings, error kinds, where the pill was put on screen, and whether the app in front was built on Electron, on Chromium or on neither, or that this is unknown, but never which app it was.
- **It also holds what can make the microphone slow to start:** when the Mac or its displays slept and woke, when the screen was locked and unlocked, when the input device changed, and that device's kind, number and sample rate and whether it was in use, by Voiced or by any app.
- **It never holds** the key, audio, transcript text, which keys you pressed, or an error message from xAI.

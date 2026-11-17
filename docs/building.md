# Building and changing Voiced

## Requirements

- A Mac running **macOS 26 or later**.
- **Xcode 26.2 or later**, the full app and not only the Command Line Tools. The project has been built with Xcode 26.2 and 27.1.
- **Your own xAI API key** from [console.x.ai](https://console.x.ai). The app calls it the Grok API Key.

Nothing else to install: the project has no third-party dependencies.

## Build and run

```sh
git clone https://github.com/ericzakariasson/voiced.git
cd voiced
make run
```

`make run` builds a Release `Voiced.app` into `build/` and opens it. The first build takes under a minute. You can also open `Voiced.xcodeproj` in Xcode and press Run.

Then, in the setup window that opens:

1. **Microphone:** click Allow and accept the system prompt.
2. **Accessibility:** click Open Settings, then switch Voiced on under Privacy & Security › Accessibility. The setup window notices within a second.
3. **Grok API Key:** paste your key and click Save. Voiced checks the key with xAI before storing it.
4. Click into any text field, hold **Right ⌥**, speak, and release.

Those three steps need you: macOS only lets a person grant permissions, and the key is yours to enter.

## Sign with your own team if you plan to rebuild

With no setup, the app is signed ad hoc. That runs fine, but macOS treats every rebuild of an ad hoc app as a new app: Accessibility has to be granted again after each build, and the Keychain asks for your password before handing the saved key to the new build.

To keep the permissions and the key across rebuilds, sign with an Apple Development certificate. A free Apple Account is enough: add it in Xcode › Settings › Accounts, then Manage Certificates › + › Apple Development. Then tell `make` your team ID once:

```sh
echo 'TEAM = ABCDE12345' > local.mk
```

`local.mk` is git-ignored, so the ID stays on your Mac. The team ID is the `OU` field of the certificate, which this prints:

```sh
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

The output holds three 10-character IDs, and only the one after `OU=` is the team ID. If you have more than one Apple Development certificate, the command prints only the first; Keychain Access shows the Organizational Unit of each.

If you choose a team in Xcode's Signing & Capabilities pane instead, Xcode writes the ID into `Voiced.xcodeproj/project.pbxproj`. Do not commit that change.

## Commands

| Command | What it does |
| --- | --- |
| `make run` | Build, quit a running Voiced, and launch the new build |
| `make build` | Build `build/Build/Products/Release/Voiced.app` |
| `make quit` | Quit a running Voiced |
| `make test` | Run the tests. No network, microphone, key or permissions needed |
| `make dmg` | Package a disk image to install Voiced from; see [releasing](releasing.md) |
| `make clean` | Remove build output |

The checks, `make test-live`, `make snapshots`, `make probe`, `make menu-bar-check` and `make microphone-check`, are in the full table in [`AGENTS.md`](../AGENTS.md#commands), with what each needs and how long it takes.

Options for any build command: `TEAM=ABCDE12345` signs with that team for one build, `MACOS=27.0` builds for a different minimum macOS than the project's 26.0, and `DERIVED_DATA=build-next` builds into another folder, for example beside a copy that is running.

## Tests

`make test` runs the package's unit and integration tests. They cover the pipeline end to end with a local WebSocket server standing in for xAI, and need no key, microphone or permissions.

`make test-live` talks to the real API. With `XAI_API_KEY` set in the environment, it speaks a sentence with `say`, streams it to the transcription endpoint, cleans the transcript, and checks the result; the key is read from the environment only and is never printed. Without a key, it only checks how the API turns away a made-up key.

## How it works

```
hold hotkey ─▶ microphone ─▶ 16 kHz PCM ─▶ xAI streaming speech to text
                                                    │ transcript
release hotkey ──────────────────────────────────▶ │
                                                    ▼
                focused app ◀─ paste ◀─ Grok cleanup (punctuation, casing, fillers)
```

| Step | xAI API | Model |
| --- | --- | --- |
| Transcription | `wss://api.x.ai/v1/stt` (streaming WebSocket, raw PCM frames) | `grok-voice-transcribe-2.0` |
| Cleanup | `POST https://api.x.ai/v1/responses` with `store: false` | `grok-4.3`, reasoning effort `none` |
| Key check on save | `GET https://api.x.ai/v1/api-key` | n/a |

Audio streams to xAI while you speak, so the transcript is nearly complete by the time you release the key. The cleanup model is told to leave wording and meaning alone and never to act on what the transcript says. If it returns nothing, or something much longer than what you said, Voiced pastes the raw transcript instead. With Cleanup switched off, the cleanup request is not made and the transcript is pasted as it came.

## Changing it

`Packages/VoicedKit` holds everything that can be tested without a person at the keyboard: the dictation pipeline, as a Swift package with its tests. The app target, `Voiced/`, holds what needs a screen, a keyboard or a permission. [`AGENTS.md`](../AGENTS.md) has the file-by-file layout, the conventions, and a table of changes people often ask for with the files each one touches.

# AGENTS.md

Instructions for coding agents working on Voiced: how to build, test, run and change the app with nobody explaining it. Everything written for agents is in this file. `README.md` is the short front page for people, and `docs/` holds the detail for them: [using Voiced](docs/using-voiced.md), [troubleshooting](docs/troubleshooting.md), [permissions and privacy](docs/privacy.md), [building](docs/building.md) and [releasing](docs/releasing.md).

Voiced is a native macOS menu bar dictation app in Swift and SwiftUI. Hold a hotkey, speak, release: the audio streams to the xAI API for transcription, a Grok model cleans the transcript, and the text is pasted into the focused app.

## First run

When a person hands you this repository, do this before the change they asked for:

1. Check the Mac against [Requirements](#requirements) and tell the person if it falls short.
2. Run `make test`, then `make run`, and tell them what happened.
3. Stop and tell them which setup steps are theirs: granting Microphone and Accessibility, and entering their xAI API key in Voiced's setup window. Never ask for the key and never try those steps for them (see [What only a person can do](#what-only-a-person-can-do)).
4. When they say Voiced is working, make the change, following this file.

## Requirements

Check these first, and stop and tell the person if one is not met. Nothing here can be fixed by installing a package.

| Need | Check | Expect |
| --- | --- | --- |
| macOS 26 or later | `sw_vers -productVersion` | 26.0 or higher |
| Xcode 26.2 or later, selected | `xcodebuild -version` | `Xcode 26.2` or higher. An error naming the Command Line Tools means Xcode is missing or not selected; selecting it takes `sudo xcode-select -s` with the path of the Xcode app, usually `/Applications/Xcode.app`, which is the person's call. |

Linux, Windows and cloud containers cannot build or run this project. There are no third-party dependencies and no package manager step.

**Code must build on the oldest supported Xcode.** Xcode 26.2 ships Swift 6.2.3, which is stricter about concurrency than the Swift in Xcode 26.4 and 27.1. It rejected a `[weak self]` capture inside `MainActor.run` in a detached task ("sending 'self' risks causing data races") that the newer compilers accepted; the fix was to hand the value to a method on the main actor, as `PillTextLookup.begin` does now. A change that builds only on a newer Xcode is not finished. If this Mac has no Xcode 26.2, keep to the concurrency patterns already in the code and say in your report that the build on 26.2 is unchecked.

## Commands

Run from the repository root. All of them work on a fresh clone with nothing configured.

| Command | What it does | Time |
| --- | --- | --- |
| `make test` | Unit and integration tests of the pipeline (`swift test` on `Packages/VoicedKit`). No network, microphone, key or permissions. | About 20 s the first time |
| `make build` | Release build to `build/Build/Products/Release/Voiced.app` | Under a minute clean; 20 to 30 s on Apple silicon |
| `make run` | `make build`, then quit every running Voiced, then open the new build | |
| `make quit` | Quit every running Voiced | |
| `make snapshots` | Debug build, then save PNGs of every screen to `snapshots/` and run the interface checks. Exits non-zero if a check fails. | About 3 minutes |
| `make pill-captures` | Debug build, then photograph the real pill into `pill-captures/`: every state in the light and the dark appearance with how the two differ, stills, one whole dictation picture by picture, and the menu bar item. Exits non-zero if the two appearances differ. See [Checking interface changes](#checking-interface-changes). | About 4 minutes, 6 with `PLATES` |
| `make test-live` | Tests against the real xAI API. Without `XAI_API_KEY` in the environment, only checks that a made-up key is turned away. | |
| `make probe` | Print where the menu bar icon lands on this Mac, from an inert second copy | A few seconds after a Debug build |
| `make menu-bar-check` | Check that an icon hidden by a menu bar manager can be brought into view. Quit a running Voiced first. | About 25 s |
| `make microphone-check` | Measure that getting the microphone ready does not start it, from a copy that never becomes an app and so cannot disturb a running Voiced. Passes only if its last line is `Microphone check result: 0`; result 2 means nothing could be checked, as without the Microphone grant. | A few seconds after a Debug build; 20 s at most |
| `make dmg` | Release build for Apple silicon and Intel, packaged as `build/dmg/Voiced-<version>-unsigned.dmg` and checked. Signed ad hoc; see [Releasing](#releasing). Builds in `build/dmg`, so the app `make run` uses is left alone. | Under a minute clean on Apple silicon; about 10 s after that |
| `make clean` | Remove `build/`, the package's `.build/`, `snapshots/` and `pill-captures/` | |

Options for any build command: `CONFIG=Debug`, `TEAM=<team id>`, `MACOS=27.0` (another minimum macOS), `DERIVED_DATA=build-next` (another output folder, to build beside a running copy).

Success looks like this:

- `make test` ends with `Test run with N tests in M suites passed`. The two live xAI suites, five tests, are reported as skipped; that is expected.
- `make build` ends with `** BUILD SUCCEEDED **` and `Built build/Build/Products/Release/Voiced.app`. The project's sources compile without warnings; keep it that way. The one `warning:` line in the output, "Metadata extraction skipped", comes from Xcode's App Intents tool and not from the sources.
- After `make run`, `pgrep -x Voiced` prints a process ID. On a Mac where setup is incomplete the setup window opens; the [log](#logs) confirms it with a `launched:` line and an `onboarding window … brought to the front` line.

`make run` and `make quit` stop every process named Voiced on the Mac, including one started from another checkout or by someone else on a shared machine. Before either, run `pgrep -lf Voiced`. If it lists a copy you did not start, do not run them: tell the person and wait. Two copies must not run side by side anyway, since both would answer the hotkey. `make build`, `make test`, `make probe` and `make microphone-check` quit nothing and are safe meanwhile.

The tests include three that write to the real login Keychain under a throwaway service name and delete what they wrote; they never prompt. To leave the Keychain untouched: `swift test --package-path Packages/VoicedKit --skip KeychainSecretStoreTests`.

## What only a person can do

Build, test and launch need nobody. These steps do, and you must hand them over rather than attempt them:

1. **Microphone:** click Allow in Voiced's setup window and accept the macOS prompt.
2. **Accessibility:** switch Voiced on in System Settings › Privacy & Security › Accessibility.
3. **The key:** paste an xAI API key from [console.x.ai](https://console.x.ai) into the setup window and click Save.
4. **Signing, optionally:** create an Apple Development certificate in Xcode and put the team ID in `local.mk` (see [Signing](#signing)).
5. **A real dictation:** hold Right ⌥, speak, release. Only this proves the whole loop.

Do not script the permission prompts, edit the TCC database, or drive System Settings. Do not ask the person to paste the key into the chat, a file or an environment variable for you; they type it into the app, which stores it in the Keychain. After they have dictated something, you can read the [log](#logs) to see how it went.

## Layout

```
Voiced.xcodeproj/            One app target (Voiced), one shared scheme (Voiced)
Voiced/                      The app target
  VoicedApp.swift              VoicedMain (@main); the MenuBarExtra and the two Window scenes; AppDelegate
  AppModel.swift               App state; builds the DictationController and its dependencies
  HotkeyMonitor.swift          The CGEventTap that feeds HotkeyStateMachine
  Permissions.swift            Microphone and Accessibility status and prompts
  WindowCoordinator.swift      Brings windows forward, toggles the Dock icon, finds the menu bar icon
  MenuBarItem.swift            First-launch placement of the menu bar icon
  MicrophoneEvents.swift       Tells MicrophoneReadiness about sleep, wake, lock, unlock and input changes
  Indicator/                   The pill: IndicatorView (SwiftUI), IndicatorPanel and PillPanel (AppKit), PillSettings,
                               and PillTextLookup and FocusedTextLocator, which find the text cursor
  Views/                       OnboardingView, SettingsView, MenuContentView, APIKeyEditor, HotkeyRecorder,
                               PermissionRows, PillPlacementPicker, CleanupToggle, WindowHeightLimit, GlassComponents
                               (colours, buttons, shared controls)
  DebugSnapshots.swift         Debug only: `make snapshots`
  DebugChecks.swift            Debug only: the interface checks, and `make menu-bar-check`
  DebugProbe.swift             Debug only: `make probe`
  DebugMicrophoneCheck.swift   Debug only: `make microphone-check`
  DebugPillCaptures.swift      Debug only: `make pill-captures`
  DebugRun.swift               Debug only: what those runs share: settings kept in memory, and a time limit
  AppIcon.icon/                Icon Composer icon: one SVG and icon.json
  Voiced.entitlements          Audio input only
Packages/VoicedKit/          Swift package: the pipeline, testable without a person
  Sources/VoicedKit/
    DictationController.swift  The loop: begin, confirm hold, end, transcribe, clean, insert
    DictationClock.swift       How the loop tells the time, so tests can move it by hand
    Hotkey/                    Hotkey (the model) and HotkeyStateMachine (pure logic)
    Audio/                     MicrophoneCapture, PCM16Converter, AudioChunker, LevelMeter; MicrophoneReadiness,
                               MicrophonePreparation, MicrophoneHistory and InputDeviceStatus, for the microphone
                               ahead of a hold
    Transcription/             StreamingTranscriptionSession, WebSocketConnection, STTServerEvent, TranscriptAssembler
    Cleanup/                   TranscriptCleaner.swift: TranscriptCleaner (request and prompt) and CleanupGuard;
                               CleanupSetting.swift: whether the pass is made at all, and SettingsStore, where
                               that is saved
    Insertion/                 TextInserter.swift: PasteboardTextInserter and PasteKeystroke
    Secrets/                   SecretStore.swift: SecretStore and KeychainSecretStore
    XAI/                       XAIConfiguration (endpoints, models), XAIError, APIKeyChecker
    Presentation/              AppPresentation.swift, PillPlacement.swift, PillNearText.swift, AppKind.swift,
                               AccessibilityWake.swift: which window to show,
                               where the icon and the pill go
    Logging/                   VoicedLog: the loggers and the rule for what may be logged; StandaloneCheck
  Tests/VoicedKitTests/        One test file per area; fakes in Support/
Tools/MenuBarManagerStandIn.swift   A stand-in menu bar manager for `make menu-bar-check`
Tools/make-dmg.sh            `make dmg`: build, sign, package, notarize when asked, and check
.github/workflows/release.yml   The Release workflow: `make dmg` on a GitHub runner, and the GitHub Release
Makefile                     Every command above
local.mk                     Yours, git-ignored: per-machine settings such as TEAM
README.md                    The front page for people: short, with links into docs/
docs/                        For people: using-voiced.md, troubleshooting.md, privacy.md, building.md, releasing.md
  media/                       The film of Voiced in use as an animated WebP, which the README shows
video/                       That film's source, a project of its own; video/README.md says how the film and the WebP are made
```

How a dictation flows: `HotkeyMonitor` turns key events into `begin`, `end` and `cancel` through `HotkeyStateMachine`; `AppModel` passes them to `DictationController`, which starts `MicrophoneCapture`, feeds audio to a `TranscriptionSession`, hands the transcript to a `TextCleaning`, and gives the result to a `TextInserting`. With the Cleanup setting (`CleanupSetting`) off when the hotkey went down, no `TextCleaning` is made for that dictation and the transcript is inserted as it came. `IndicatorPanel` observes the controller's `phase` and `microphone` and shows the pill: listening only once audio has arrived, Starting Microphone… when none has half a second after the hotkey went down, and Polishing… only while the controller's `isPolishing` says so. With the pill set to Next to Text, `AppModel` also starts a `PillTextLookup` when the hotkey goes down (see [The pill next to text](#the-pill-next-to-text)).

## Conventions

- **Logic goes in VoicedKit, with a test.** Anything that can be decided without a screen, a keyboard or a permission belongs in the package. The app target stays thin.
- **Dependencies are protocols:** `AudioCapturing`, `TranscriptionSession`, `TextCleaning`, `TextInserting`, `SecretStore`, `SettingsStore`, `HTTPTransport`, `WebSocketConnecting` and `DictationClock`. `AppModel.init` is the one place the real implementations are chosen. Tests pass fakes: `FakeHTTPTransport`, `FakeWebSocketConnection`, `FakeWebSocketConnector` and `InMemorySettingsStore` are shared, in `Tests/VoicedKitTests/Support/TestSupport.swift`; the fakes for capture, session, cleaner and inserter are private to `DictationControllerTests.swift`.
- **Swift 6 with strict concurrency.** The app target defaults to `MainActor` isolation; the package does not, so mark isolation there explicitly.
- **Tests use Swift Testing** (`@Test`, `#expect`, `@Suite`), not XCTest. Test names are sentences describing behaviour, such as `aFailedCleanupInsertsTheRawTranscriptWithAWarning`.
- **Tests must not write settings on the Mac that runs them.** A `UserDefaults` domain made for a test stays listed among that person's settings after the test has emptied it, one more with every run. A test of a saved setting passes an `InMemorySettingsStore`.
- **Tests must not depend on short real-time waits.** A test that allowed 100 ms for something to happen failed two runs in four on a busy Mac. Wait for a condition with `waitUntil` from `Support/TestSupport.swift`, or give a real-time wait a wide margin: a second, not a tenth. `DictationControllerTests.swift` moves a `ManualClock` by hand, so no hold test waits on real time.
- **No third-party dependencies.** Ask the person before adding one.
- **New files need no project edits.** `Voiced/` is a file-system-synchronized group and `Packages/VoicedKit` is a package, so a Swift file added to either is compiled without touching `project.pbxproj`.
- **Models and endpoints live in one file,** `XAI/XAIConfiguration.swift`.
- **Interface:** black and white only, no colour, including for errors and success; states are told apart by shape and wording. The system font. Title Case for labels and buttons. Standard controls, except the one main action per window. The key is called "Grok API Key" in the interface. Styling comes from `Views/GlassComponents.swift`. Every surface follows the Mac's appearance but one: the pill is dark glass with white marks in the light appearance too, so that it reads the same over any window. `IndicatorView` sets that for itself and `PillPanel` for its window; `make pill-captures` fails if the two appearances come out differently.
- **Comments** explain why, not what. Match the existing ones.
- **Commit messages** are one plain sentence saying what changed, such as "Start the audio engine off the main thread".
- **Keep the docs true.** If a change alters what the app does or does not do, its settings, what leaves the Mac, which permissions are needed, or a command, update the file under `docs/` that covers it, `README.md` where its summary is touched, and this file, in the same change. The README stays a front page of about a minute's reading: detail goes in `docs/`, and instructions for agents go here.

## Recipes

**Add a setting.** Follow the hotkey: a property on `AppModel`, read from `UserDefaults` in `init` and written back in its setter (`hotkeyDefaultsKey` and `setHotkey`), with a control in `Views/SettingsView.swift`. The dictation loop's dependencies are closures built in `AppModel.init` before `self` exists, so a setting the loop must read goes through a small holder object the closure captures, the way `KeyHolder` carries the key. `PillSettings` is the pattern for a group of settings with its own type, and `CleanupSetting`, in VoicedKit with its own tests, for a setting that is its own holder: it saves itself, and the loop asks it when the hotkey goes down. Add a Settings state to `DebugSnapshots.swift` that shows the new control.

**Change a step of the loop.** The steps are in `DictationController.process`, and what the pill says for each phase is in `Indicator/IndicatorPanel.swift`. To skip or replace a step, change it in the controller, with a test in `DictationControllerTests.swift`, so that the phases, the pill and the log stay honest. Swapping in a different `TextCleaning` or `TextInserting` in `AppModel.init` is right when the step still happens, only differently.

**Change the cleanup prompt or a model.** The prompt is `TranscriptCleaner.instructions`; models and endpoints are in `XAI/XAIConfiguration.swift`. `make test` never calls xAI, so it cannot tell whether a new prompt or model behaves. `make test-live` with the person's key checks only that one spoken sentence comes back cleaned. Say plainly that the result needs the person's own dictation to confirm.

**Add to Settings.** The Settings window is as tall as its rows when the screen has room for them, and never taller than the screen's visible area, between the menu bar and the Dock: on a smaller display the form scrolls inside the window. `Views/WindowHeightLimit.swift` supplies the limit and `SettingsView` wraps the form in a scroll view, so a new row needs no sizing work of its own. Put a new row in an existing section where one fits. `make snapshots` checks that the window still fits and still scrolls to its last row across display heights.

## Changes people often ask for

Voiced is meant to be remixed. Where to start for each:

| Idea | Where |
| --- | --- |
| Change how text is cleaned up: a different tone, bullet lists, British spelling | The prompt in `Packages/VoicedKit/Sources/VoicedKit/Cleanup/TranscriptCleaner.swift`. `CleanupGuard` in the same file rejects results much longer than the transcript. |
| Paste the raw transcript, with no cleanup | Already a setting: Cleanup, in the menu bar panel and in Settings, on unless switched off. `Packages/VoicedKit/Sources/VoicedKit/Cleanup/CleanupSetting.swift` holds and saves it; `DictationController` asks it when the hotkey goes down, skips the step in `process`, and says through `isPolishing` when the pill may claim to be polishing; the switch is `Voiced/Views/CleanupToggle.swift` |
| Use other models, or another provider | Models and endpoints are in `Packages/VoicedKit/Sources/VoicedKit/XAI/XAIConfiguration.swift`. For another provider, implement `TranscriptionSession` and `TextCleaning` and pass them in `Voiced/AppModel.swift`. |
| A custom dictionary or text snippets | Between cleanup and insertion in `process` in `Packages/VoicedKit/Sources/VoicedKit/DictationController.swift`, or as extra lines in the cleanup prompt |
| Tap to start and tap to stop, instead of holding | `Packages/VoicedKit/Sources/VoicedKit/Hotkey/HotkeyStateMachine.swift`, and the minimum hold in `DictationController.swift`. The default key is in `Hotkey/Hotkey.swift`. |
| Show the words in the pill as you speak | Transcript events arrive in `Packages/VoicedKit/Sources/VoicedKit/Transcription/StreamingTranscriptionSession.swift`, which today only collects them; the pill is `Voiced/Indicator/IndicatorView.swift` |
| Restyle the pill or the windows | `Voiced/Indicator/IndicatorView.swift`, and the shared colours and controls in `Voiced/Views/GlassComponents.swift` |
| Type the text instead of pasting it | A new `TextInserting` beside the one in `Packages/VoicedKit/Sources/VoicedKit/Insertion/TextInserter.swift`, passed as `inserter` in `Voiced/AppModel.swift` |

## The pill next to text

The pill has two placements, chosen under Pill in the menu bar panel or in Settings: Next to Text, the default, and Fixed Place. With Next to Text, Voiced asks the app in front where its text is being edited and puts the pill there; an app that says nothing about its text, as apps built on Chromium and Electron do not, is asked where its window is, and the pill goes to the bottom of that window. Such an app also gets one read that is made for its effect: it switches on the app's accessibility tree, and is asked again during that hold, so that the pill can move to the text once the app answers. This is the only place Voiced reads anything from another app.

| File | What it holds |
| --- | --- |
| `Voiced/Indicator/PillTextLookup.swift` | One question per dictation. `AppModel.handle` calls `begin()` when the hotkey goes down, only while the mode is Next to Text, and `holdEnded()` when it comes up. The question is asked off the main thread, and an answer that arrives after a newer dictation began is dropped. The one case of more questions: after the read that switches on an app's accessibility, the same question is asked again at the times in `AccessibilityWake.askAgainAfter` while the hotkey is held, and the first answer with a text position is handed to the panel through `onLaterAnswer`. Voiced never asks itself: with only its menu bar panel in front, the app that was in front before is asked, and with one of its windows holding the keyboard, nobody is. |
| `Voiced/Indicator/FocusedTextLocator.swift` | The Accessibility calls, each with a 0.1 s timeout, and `FocusedTextAnswer`, their result. The window is asked for only when the app answered and gave neither an insertion point nor a field. |
| `Packages/VoicedKit/Sources/VoicedKit/Presentation/PillNearText.swift` | `PillPlacementMode`, `FocusedTextGeometry`, and the placement rule as pure logic: below the line and centred on the insertion point, moved sideways only as far as it takes to stay between the field's left and right edges, and centred on a field narrower than the pill; above the line when there is no room below; by the field when there is no insertion point; at the bottom of the window when there is no field either; otherwise the fixed place. Each place passed over is kept with its reason, for the log. Tests in `PillNearTextTests.swift`. |
| `Packages/VoicedKit/Sources/VoicedKit/Presentation/AppKind.swift` | Whether the app asked is built on Electron, on Chromium or on neither, told from the names of the frameworks in its bundle, once per run of the app (`AppKindCache`). Tests in `AppKindTests.swift`. |
| `Packages/VoicedKit/Sources/VoicedKit/Presentation/AccessibilityWake.swift` | When the read that switches on an app's accessibility is made. Tests in `AccessibilityWakeTests.swift`. |
| `Voiced/Indicator/IndicatorPanel.swift` | `placeForDictation()` decides once, when a dictation's pill first shows, and logs the decision. A drag while the pill is beside text moves it for that dictation only. `placeAgainByTheText()` is the one time a pill moves by itself: once, from the window or the fixed place to the text, while the hotkey is held and no hand has touched the pill, when an app answers after its accessibility was switched on. It logs a `pill placed again …` line. |
| `Voiced/Indicator/PillSettings.swift` | The saved mode, under the preferences key `pillPlacementMode`. It is saved when it is chosen, and `PillPlacementMode(saved:)` reads it: Next to Text where nothing is saved, so a Mac on which Fixed Place was chosen keeps it and every other gets Next to Text. |
| `Voiced/Views/PillPlacementPicker.swift` | The segmented control, used by `MenuContentView` and `SettingsView` |
| `Voiced/DebugChecks.swift` | `pillGoesNextToTheText`, run by `make snapshots`: a text view in Voiced's own process stands in for the other app, since a process may question itself without the permission |

Rules a change must keep:

- **Read positions only.** Today that is: which element has the keyboard, where the selection starts and how long it is, the box of that stretch of text (or the text-marker equivalents that web content uses), and the element's position and size; and, when the app gives none of that, which window has the keyboard and that window's position and size. Never an element's value, selected text, the string for a range, a title, the role of anything inside the app, or anything else that is or describes content.
- **Write nothing to another app.** No attribute is set and no action is performed. `AXUIElementSetMessagingTimeout` only sets how long Voiced waits.
- **Switch on one thing only, by one read.** `FocusedTextLocator.readApplicationRole` reads the role of the app's own accessibility object, which is the same word for every app, and throws the answer away. Apps built on Electron and Chromium switch on a basic accessibility tree at that read, as they would for an assistive app such as Voice Control, and it stays on until the app quits. `AccessibilityWake` says when the read is made: only for the app in front at hotkey down, only when it is known to be an Electron or Chromium app and gave no focused element, and once per run of that app. An app of `unknown` kind is not read: the read has a purpose only in those two kinds, and finding the kind must never cost a prompt. Nothing is asked unless the mode is Next to Text, so the read is never made otherwise. That dictation's pill goes to the bottom of the app's window first. The app is then asked the same position questions again, at most six times in a second and a half and only while the hotkey is held, and the pill moves to the text once if an answer comes; `AccessibilityWake.isWorthMovingThePill` says when. Nothing else is switched on or asked for to get there.
- **Never set `AXManualAccessibility` or `AXEnhancedUserInterface`.** They tell the app that a screen reader is present, and editors built on VS Code, Cursor among them, then change how they behave.
- **Touch another app's files only inside the standard application folders:** `/Applications`, `/System/Applications`, `/System/Library/CoreServices` and `~/Applications`, and never through a symbolic link. Opening the bundle of an app that runs from Desktop, Documents, Downloads or a removable or network volume can make macOS ask the person whether Voiced may access that place. `AppKind.of(bundle:)` decides from the path alone and calls such an app `unknown`.
- **Never ask Voiced itself.** Its menu bar panel has no text, and a dictation begun right after a click in it is meant for the app behind it.
- **Ask only when the setting asks for it:** only while the mode is Next to Text, once per dictation (and again after the read above, as said there), off the main thread, with the timeout. The pill and the hotkey never wait for an answer; a missing answer means the fixed place.
- **Use the answer to place the pill and for nothing else.** It is not saved and not sent.
- **Log one `pill placed …` line per dictation,** in the `setup` category, holding numbers and fixed words only: what decided the place and why each nearer place was passed over, the pill's coordinates, the display, who was asked (`asked=other`, `voiced` or `nobody`, with `front=voiced` when Voiced was in front), the kind of app (`kind=electron`, `chromium`, `other` or `unknown`), the result code of each Accessibility call, and how long the lookup took. Never the app's name or bundle identifier. The read that switches on accessibility writes a `pill lookup: read the role of the app in front …` line of its own, with its result code and the kind of app. After it, `pill lookup: asked again N times after the read: text found|not found …` says how the questions that followed went, and `pill placed again …` that the pill moved to the text.
- **Keep `docs/privacy.md` true.** It says exactly what is read from other apps, and the README's Privacy section sums it up.

Asking another app takes the Accessibility permission, so you cannot check this against a real app yourself. After a change here, `make test` covers the placement rule and `make snapshots` the lookup inside Voiced's own process; the person has to try it in real apps.

## The microphone ahead of a hold

Finding the input device once took two seconds of a start that otherwise takes 90 ms, and those seconds came out of a dictation's first words. So Voiced finds the input ahead of time, at launch, when Microphone is granted, and when the Mac wakes, is unlocked or changes input device. `MicrophoneReadiness` decides when, `MicrophonePreparation.run` decides whether, and `MicrophoneCapture.prepare` does the lookup on the capture queue.

Rules a change must keep:

- **The microphone is opened only inside a hold.** A preparation makes an engine, reads its input's format and lets it go: no tap, no `prepare()`, no `start()`. The orange dot must never light outside a hold.
- **Nothing of audio without the grant.** While Microphone is undetermined or denied, no engine is made, the device's state is not read and the input device is not watched. The grant is the first thing `MicrophonePreparation.run` asks.
- **Leave alone an input that might be disturbed:** Bluetooth, virtual, aggregate or unknown, since opening a headset's input can move it to its call profile, and any input another app is using.
- **Measure, do not reason.** After a change here, the person runs `make microphone-check` on a Mac where Voiced has the grant; `STAND_IN=stuck` and `STAND_IN=bluetooth` try the check itself with no audio. Tests use stand-ins for the engine and the device and never touch a real one.
- **Log numbers and states only:** the device's kind, number, sample rate and whether it is running, never its name.

## Git

- Work on a branch. This is the person's clone: do not push, open a pull request or change a remote unless they ask.
- If `git commit` fails with "Author identity unknown", the Mac has no git identity. Ask the person which name and email to use and pass them for that commit with `git -c user.name=… -c user.email=…`; do not write git configuration.
- Before committing, check `git status` and `git diff --stat` for anything you did not mean to change.
- This repository's own history is one commit per release, and now and then one between releases that changes only the documentation, copied from a private working repository. `git log` shows versions, not how changes were made, so take the conventions from this file and not from the log.

## Signing

The project's `DEVELOPMENT_TEAM` is empty, so a plain build is signed ad hoc and runs with no Apple account. The cost is that macOS treats each ad hoc rebuild as a new app: the Accessibility grant stops working and the Keychain asks for the login password before releasing the saved key.

To keep both across rebuilds, the person signs with their own team, set in `local.mk`:

```sh
echo 'TEAM = ABCDE12345' > local.mk
```

The Makefile includes `local.mk` and passes `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY="Apple Development"` to `xcodebuild`. `local.mk` is git-ignored. The team ID is the `OU` in the output of:

```sh
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

The output holds three 10-character IDs; only the one after `OU=` is the team ID. With more than one Apple Development certificate in the Keychain the command prints only the first, so ask the person which team they mean before writing `local.mk`.

If that prints nothing, the Mac has no Apple Development certificate; the person creates one in Xcode › Settings › Accounts › Manage Certificates. Do not write a team ID anywhere but `local.mk`, and never into `project.pbxproj`. If `git diff` shows `DEVELOPMENT_TEAM` or `DevelopmentTeam` with a value, revert that hunk before committing.

After an ad hoc rebuild, tell the person that Accessibility needs granting again: they remove Voiced from the Accessibility list in System Settings and switch it on again for the new build.

## Releasing

`docs/releasing.md` is the guide. Pushing a tag such as `v0.2.0` runs `.github/workflows/release.yml`, which runs `make dmg` on GitHub's `macos-26` runner with Xcode 26.2 and attaches the DMG to the GitHub Release of that tag. Started by hand, the workflow keeps the DMG as an artifact of the run and publishes nothing.

- **Do not push a tag, publish a Release or start the workflow unless the person asks.** A tag publishes; and on a private repository each minute on the macOS runner is billed as ten.
- **The signing secrets are the person's.** A Developer ID certificate and a notarization key live as repository secrets that the person adds in GitHub's settings. Never ask for their values, and never put a certificate, a key, a password or a team ID in the repository, a log or a report. With no secrets the DMG is ad hoc signed and its name ends in `-unsigned`; keep it so that nobody can take one for the other.
- **Keep the output free of the team ID.** `Tools/make-dmg.sh` passes what the signing tools print through `redact`, and the workflow masks the team ID before the first step that could print it.
- **You can check only the unsigned path.** `make dmg` proves the build, the ad hoc signature, the image and the checks. Signing with a Developer ID, notarizing and stapling run only with the person's secrets, so say that they are unchecked after a change there, until a run with the secrets has passed.
- **Keep `docs/releasing.md` true** when the workflow, the script, the secrets' names or what an unsigned build costs the person installing it changes.

## Checking interface changes

You cannot see the app, so use the snapshots:

```sh
make snapshots
```

This builds Debug and runs the app with `-VoicedSnapshots`, which writes PNGs to `snapshots/` (git-ignored) and quits. Read the PNGs to check your change. It needs no permissions and no key. It opens Voiced's windows in front of everything for two to three minutes, so warn a person who is using the Mac. It starts its own Debug copy and quits only that, so it can run while Voiced is running; run one snapshot run at a time on a Mac, because both would put their windows in front.

The code of a Debug run never reads or changes the person's saved settings, with the one exception set out below, and keeps no settings of its own on the Mac. The copy has the bundle identifier of the person's Voiced, so `UserDefaults.standard` in it is their settings: Debug code must not use it. A run's settings are a `DebugSettings` (`Voiced/DebugRun.swift`), which keeps them in memory: `DebugRun.settings` for the app the run shows, which therefore begins as on a first launch, and a new `DebugSettings()` for anything else a check sets up.

What macOS does is another matter, for any copy that shows the menu bar item, as the snapshots, the pill captures, the probe and the menu bar check all do. When it creates the item it reads the icon's saved place, `NSStatusItem Preferred Position Item-0`, from the app's settings, and it may write keys of its own there. This much has been measured: on a Mac whose session shows no menu bar, the saved settings were read about every 0.4 seconds from before a snapshot run, a pill-captures run and a probe were each launched until after each had ended, and were the same at every read; and after a menu bar check macOS had written `NSStatusItem VisibleCC Item-0` there. What macOS writes during these runs on a Mac that shows its menu bar has not been measured.

`make menu-bar-check` is the one run whose own code uses the saved settings, and one key of them: the icon's saved place, since macOS reads it from nowhere else and Show in Menu Bar works by saving a place there. A check that runs to its end puts the place back. So does a check that is ended early by its time limit or by a signal it catches, which are `SIGINT`, `SIGTERM`, `SIGHUP` and `SIGQUIT`, as from Ctrl-C, `kill` or a closed terminal: it saves the place as it was and waits until the preferences have it before the process ends (`IconPlaceBeforeTheCheck` in `Voiced/DebugChecks.swift`). It waits five seconds at most, because a copy that cannot stay running comes first: if the preferences have not taken the value by then, the copy ends anyway and the place may be left as the check had it. One gap remains: if the main thread is busy for more than a second without being stuck, the place is put back from another thread, and the main thread could write the check's value again in the instant before the process ends. That has not been seen. What is left besides is an end that nothing in the process can answer: a hard kill, as by `kill -9`, a crash, or the Mac going down. The saved place then stays where the check had put it. The person's Voiced reads it the next time it creates its icon, which can leave the icon out of sight behind a menu bar manager's divider. The person puts it back in the window that opens when Voiced is opened again while it is running: Settings once setup is complete, where the button is under Menu Bar Icon, and the setup window before that. Show in Menu Bar moves the icon to the right end of the menu bar, which is not necessarily where it was. macOS's own note that the icon is shown, `NSStatusItem VisibleCC Item-0`, stays behind either way.

In any other check, do not click Show in Menu Bar, the button in the Move into View row of Settings and beside the hidden-icon note in the setup window, and do not call `AppModel.bringMenuBarItemIntoView()`. It saves the right end as the icon's place through `MenuBarItem.askForTheRightEnd()`, which writes `UserDefaults.standard` whatever settings the model was given.

Every such run also ends itself if it has not finished in time (`DebugRun.armTimeLimitIfRequested`: 15 minutes for the snapshots, 30 for the pill captures, 3 for the menu bar check, 1 for the probe), with a last line that says so and exit code 3, which `make` reports as `Error 3`, so that a copy cannot stay running on someone's Mac. A check that clicks a control which follows the mouse until the button comes up, as a segmented control and a switch do, uses `clickControlThatFollowsTheMouse` in `Voiced/DebugChecks.swift`, which sends the release again if it goes missing.

- Each surface is saved in the light and the dark appearance: `<surface>-light.png` and `<surface>-dark.png`. The setup window is saved in every state a person passes through (`setup-*.png`), and Settings, the menu and the pill in theirs.
- Files named `*-live*.png` are the real windows in whatever state this Mac is in: its permissions and whether a key is saved. Their settings are those of a first launch, since a run does not read the saved ones. The rest are the same SwiftUI views with fixed state, so they look the same on every Mac. The fixed-state Settings pictures are drawn as on a display with room for the whole window; `settings-13-inch-*.png` and `settings-14-inch-*.png` show it on a 13-inch and a 14-inch laptop, where the taller states scroll.
- The run prints `Frontmost: true` or `Frontmost: false`. When it is false, which is usual on a Mac with nobody at the screen, the windows are drawn inactive: buttons dimmed, switches grey. Layout, wording and sizes can still be judged; how an active control is coloured cannot, so ask the person to look at the running app.
- When you add a screen or a state, add it to `Voiced/DebugSnapshots.swift` so it is captured too.
- The run also performs seven checks and fails if one does. They are in `Voiced/DebugChecks.swift`:
  1. Settings opens without the menu bar icon.
  2. The real Settings window fits inside this Mac's visible screen area, and scrolls to its last row if it had to be made shorter than its content.
  3. The hotkey, the pill's placement and Cleanup can be changed from the menu bar panel, and a dictation begun right after is placed by the new choice, and cleaned up or not by it: with Cleanup off no cleaner is made, the transcript goes in as it came, and the pill says Transcribing… and never Polishing….
  4. Dragging the pill leaves the keyboard with the other app.
  5. With Next to Text the pill lands beside the text cursor without covering the line and without reaching past the field's left or right edge, at the bottom of the window that has the keyboard when there is no text to find, and at the fixed place when the app cannot be asked.
  6. Settings, told a display's visible height, fits at visible heights from 400 to 1200 pt: whole where there is room, and scrolling to its last row where there is not.
  7. The read that switches on another app's accessibility is made once per app, and only for an Electron or Chromium app that was in front and gave no focused element. Asked again after the read, an app that then answers gets the pill moved from the bottom of its window to the text during the same hold, and one that never answers is asked no more once the key is up. It runs on stand-ins and asks no app anything.
- The setup window has one fixed size in every state; the run fails if a change makes it differ between states.

For changes to how the menu bar icon is placed or recovered, also run `make menu-bar-check`.

For changes to the pill, also run `make pill-captures`. The snapshots show the pill as a view on a stand-in page. This shows the real pill panel in front of a plain window of the same process, drawn together by the window server, so the glass shows what is behind it as it does in use. Only Voiced's own windows are photographed, so no Screen Recording permission is involved; the pill is driven by fixed states and a scripted dictation, never by the microphone, and the copy that runs has no hotkey. Like the snapshots it puts windows in front of everything, for four to six minutes, and it keeps several processor cores busy to stay on time, so run nothing heavy beside it. It writes to `pill-captures/` (git-ignored):

- `light-dark-match/`: every state over white, light grey, mid grey and dark, in the light and in the dark appearance, with `differences.md`. The run fails unless the two are the same pixel for pixel. Three states have a mark that moves by itself (the microphone's pulse and the clock, the spinner); for those the part that moves is found from the pictures and the nearest pair of a light and a dark picture is compared.
- `stills/`: each state over white.
- `motion-over-white/`: one dictation at the fixed place, one picture for each picture the display shows, with `timeline.json`.
- `menu-bar-item/`: the menu bar item idle and while recording. On a Mac whose session shows no menu bar the item draws itself, which leaves out what the menu bar does to it.
- With `make pill-captures PLATES=<folder>`, `film/<scene>/`: the same dictation placed by the app's own rule and run to a timeline over pictures of your own, described by a `plates.json` in that folder; `video/plates.py` makes the film's. Takes are repeated until each change shows on the frame the timeline names.

The pictures are made at 2x, so the display must be at 2x. What they show of the glass is what this Mac's window server draws; a virtual Mac may draw it more plainly than real hardware.

## Logs

Voiced writes one line per stage of a dictation to the unified log, subsystem `com.ericzakariasson.Voiced`, categories `hotkey`, `dictation`, `capture`, `transcription`, `cleanup`, `insertion` and `setup`:

```sh
/usr/bin/log show --last 10m --info --style compact --predicate 'subsystem == "com.ericzakariasson.Voiced"'
```

Use `stream --level info` in place of `show --last 10m --info` to follow it live. Give the full path, because zsh has a `log` builtin.

On an account that is not an administrator, `log` answers "Could not open local log store" or "Must be admin". Then start the app so that its log lines go to a file instead. This replaces `make run`, and like it quits every running Voiced, so check `pgrep -lf Voiced` first:

```sh
make build && make quit
open --env OS_ACTIVITY_DT_MODE=YES --stderr "$PWD/build/voiced.log" build/Build/Products/Release/Voiced.app
```

Voiced's own lines in that file carry a category in brackets, such as `[setup]` or `[dictation]`: `grep -E '\[(setup|hotkey|dictation|capture|transcription|cleanup|insertion)\]' build/voiced.log`. System frameworks write there too, and their lines, some of which read like errors, can be ignored.

A healthy launch writes a `[setup]` line beginning `launched: key saved=`. The line also reports the microphone and Accessibility status, so it tells you how far the person's setup has got. Each dictation writes one `[setup]` line beginning `pill placed`, which says whether the pill went by the insertion point, by the field, into the window or to the fixed place, why each nearer place was passed over, and whether the app asked was built on Electron or Chromium. A dictation begun with Cleanup off writes a `[dictation]` line `cleanup skipped …` with the transcript's length, where one that was cleaned up writes `cleanup accepted …`; switching the setting writes a `[setup]` line `cleanup switched on` or `off`. To judge a slow microphone start, read the `[capture]` lines: `preparation after …` for each lookup ahead of a hold, `before this hold:` for what preceded a start (sleep, wake, lock, unlock, input changes), and `start stages:` for which part of the start took the time.

To judge a dictation that came back empty, follow the audio through three sets of numbers:

- **`[capture]`: was the rate right?** `input format:` is what the engine reported before the start and `first buffer …` what the buffers really came in. When the recording stops, the line `buffers=… claiming sampleRate=…; measured … frames per second` sets the rate the buffers claimed against the clock: the two agree within a few percent when the rate is right, and differ by the ratio of the rates when it is not. The device's own `sampleRate=` in `start stages:` may differ from the engine's, which converts between them. `PCM16Converter` goes by each buffer's own format, and writes `input format changed …` when a later buffer makes it start over.
- **`[dictation]`: was there anything to hear?** The `levels:` line counts `silent=` chunks, digital silence that no live microphone gives, and how many of them led the recording. `p90=` near `max=` means sound went on through the hold; near `median=`, the loudest was one bump.
- **`[transcription]`: what did xAI make of it?** `audio.done queued after … bytes=` should equal `capture ended … bytes=`. Each final result writes its character count and the stretch of audio it covers. `transcript.done` gives the closing event's own characters, which are often 0 when the finals carried the words, and the assembled count.

## Never

- **Never commit a secret.** No API keys, tokens or `.env` files, in code, tests, fixtures, docs or commit messages. Test keys are obvious fakes such as `test-key`.
- **Never commit a signing team ID.** `DEVELOPMENT_TEAM` stays `""` in `project.pbxproj`, and `local.mk` stays out of git.
- **Never log the key, audio, transcript text, clipboard contents, which keys were pressed, or an error message from the server,** which can quote any of those. Log stages, counts, sizes, durations, statuses and error kinds only. The rule and the helpers for it are in `Logging/VoicedLog.swift`; `LoggingTests.swift` checks them.
- **Never print or echo `XAI_API_KEY`.** If the person wants `make test-live` run with a key, they export it in their own shell; you never see or handle the value.
- **Never store the key anywhere but the Keychain,** and never send it anywhere but `api.x.ai`.
- **Never open audio input from a tool, a test or a command-line probe.** macOS looks the Microphone grant up for the app that owns your shell, and without it the call raises a permission prompt in that app's name and blocks until a person answers. Use `make microphone-check`.
- **Never read text, titles or values from another app, or the role of anything in it but the app itself, and never write to one.** Positions only, and the one read that switches on accessibility, as [The pill next to text](#the-pill-next-to-text) sets out.
- **Never add a network destination, analytics, or anything that writes audio or transcripts to disk** without the person asking for it and [`docs/privacy.md`](docs/privacy.md), with the README's Privacy section, saying so.
- **Never stage with `git add -A` blindly.** Look at `git status` first; `build/`, `snapshots/` and `local.mk` are ignored, and anything else unexpected should not go in.

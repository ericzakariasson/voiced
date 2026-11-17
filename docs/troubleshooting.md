# Troubleshooting

**macOS will not open Voiced: "Apple could not verify…".** You installed a download whose name ends in `-unsigned`, which is not signed with an Apple Developer ID. Click Done, open System Settings › Privacy & Security, scroll down to Security and click **Open Anyway** beside Voiced. The button shows for about an hour after macOS refused the app. In Terminal, `xattr -dr com.apple.quarantine /Applications/Voiced.app` does the same. After each update to another unsigned build, do this again, and grant Accessibility again as under "The hotkey does nothing" below.

**There is no Voiced icon in the menu bar.** A menu bar manager such as Bartender, Ice or Hidden Bar, or a full menu bar on a Mac with a notch, is hiding it. You never need the icon: open Voiced again while it is running and Settings comes up. Under Settings › Menu Bar Icon, **Show in Menu Bar** moves the icon to the right end of the menu bar, next to the system's icons. If it is still hidden after that, the manager has put it back in its hidden section: move Voiced to Shown in the manager's own settings. With Bartender, an icon under Always Hidden does not appear even when you click Bartender's icon.

**The hotkey does nothing.** Check Settings › Permissions. If Accessibility shows as allowed in System Settings but the hotkey is still dead, the grant belongs to an earlier ad hoc build: remove Voiced from Privacy & Security › Accessibility with the − button, or run `tccutil reset Accessibility com.ericzakariasson.Voiced`, then grant it again. If Voiced's menu says to quit and reopen it, do that. Password fields and other secure input block the hotkey by macOS design.

**macOS asks for my password to let Voiced use the Keychain.** The app was rebuilt with ad hoc signing, or updated from one unsigned download to another. Choose Always Allow, or [sign with your own team](building.md#sign-with-your-own-team-if-you-plan-to-rebuild) so it stops happening.

**"That key was rejected."** xAI did not accept the key. Check that you copied all of it and that the key is active at [console.x.ai](https://console.x.ai).

**The pill says the text is on the clipboard.** The paste keystroke could not be sent, usually because Accessibility is not granted. Press ⌘V yourself. On layouts where V is on another key (Dvorak without "QWERTY ⌘"), the keystroke may not paste.

**The pill does not go next to my text.** Next to Text relies on the app in front saying where its text cursor is. Chromium browsers and Electron apps, Cursor and Slack among them, do not until their accessibility support is on. Voiced switches it on at the first dictation into such an app. That dictation's pill starts at the bottom of the app's window, and moves to the text if the app says where it is while you are still holding the key; otherwise it stays there, and the next dictation goes by the text. One that runs from outside the standard application folders is left as it is, and keeps the pill at the bottom of its window. An app that is slow to answer is not waited for, and gets the fixed place.

**The orange microphone dot flickers while I type.** Right ⌥ types characters such as @ and { on some keyboard layouts, and the microphone starts the moment the hotkey goes down so that no speech is lost. Voiced drops the hold as soon as another key goes down, shows nothing and sends nothing, but the dot still blinks. Pick another hotkey if it bothers you.

**Fn as the hotkey opens the emoji picker.** Set System Settings › Keyboard › "Press 🌐 key to" to Do Nothing.

**`make` fails with "tool 'xcodebuild' requires Xcode".** The Command Line Tools are selected instead of Xcode. Run `sudo xcode-select -s /Applications/Xcode.app`, with the path of your Xcode if it is installed elsewhere, and open Xcode once so it can finish installing its components.

**Something else.** Watch the log while you dictate. It reports each stage with timings:

```sh
/usr/bin/log stream --level info --style compact --predicate 'subsystem == "com.ericzakariasson.Voiced"'
```

To read back what already happened, replace `stream --level info` with `show --last 10m --info`. Give the full path `/usr/bin/log`, because zsh has a builtin of the same name. What the log holds, and what it never holds, is listed under [Permissions and privacy](privacy.md#what-the-log-holds).

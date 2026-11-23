# Voiced in use: the film

A 35-second film of Voiced in use on a desktop, one app after another, made with [Remotion](https://www.remotion.dev): 1920 × 1200 (16:10), 60 frames a second, H.264, silent. The pill in it is the app's own, photographed from the app; the desktop and the four apps are mock-ups drawn for the film. This folder is its own project and nothing outside it depends on it.

## What happens in it

- **A team chat:** a colleague asks for a review, and the reply is dictated.
- **A code editor:** a coding agent is asked for a change.
- **An email app:** a reply to a message is dictated.
- **A notebook:** a line is added to a note.
- **The end:** the mark and the name.

In each app the view moves in on the field being written in, the pill appears by the line, its bars and clock run while the words are spoken, it says "Transcribing…" and then "Polishing…", and the cleaned-up text lands at the insertion point.

## Render

```sh
cd video
npm install
npm run render     # out/voiced-in-use.mp4
npm run studio     # preview and scrub in the browser
```

The render needs the app's pill in `public/pill/`, which is not kept in this repository; the next section says how it gets there. Without it the film renders with no pill, because it has no drawn one.

Needs Node.js 22.18 or later, or 23.6 or later in the 23 line: `npm run render` has Node read `src/script.ts` as it is, and those are the first versions that run TypeScript without a flag. This was rendered with Node 22.23. The first render downloads the headless Chrome that Remotion drives. Where that download is blocked, point Remotion at a Chrome you already have:

```sh
npm run render -- --browser-executable="$(which google-chrome)" --chrome-mode=chrome-for-testing
```

`npm run render` sets `KEYFRAMES` from `src/script.ts`. With it, `remotion.config.ts` tells the encoder to start a group of pictures as each app arrives and nowhere else, to use one quantizer throughout, and to use no B-frames, so that every frame of a stretch in which nothing moves comes out of the decoder as the same picture. It also renders in one browser tab (`--concurrency=1`): several tabs do not draw a soft shadow alike to the last pixel, and a still scene then alternates between two or three pictures.

Everything in `out/` is git-ignored: rendered films do not belong in the repository.

## The app's pill: plates and captures

The pill is not drawn here. The app photographs its own pill over pictures of the film, and those photographs are set into the frames. Three steps, the second on a Mac:

```sh
# 1. The plates: the film's frames with the view in, and no pill.
python3 plates.py out/plates

# 2. In the repository's root, on a Mac: the app's pill, photographed over them.
make pill-captures PLATES=video/out/plates

# 3. Back in video/: the pill cut out of each photograph, into public/pill/.
python3 pill-captures.py ../pill-captures/film out/plates ../pill-captures/menu-bar-item
```

- **A plate** is one whole frame of the film with the view in on the field being written in, without the pill and without the caption. Each scene has two: with the field still empty, and with the dictated text in it. `plates.json` beside them says where the app's rule puts the pill in each, how loud the voice is in each tenth of a second, and on which frame each thing happens. `plates.py` passes any further arguments on to Remotion, such as the two flags above.
- **The captures** are made by the app's own `make pill-captures`, which the repository's `AGENTS.md` describes. It builds the app, places the real pill over each plate by the app's own rule, runs a scripted dictation to the plate's timeline, and saves one picture for each frame of the film. It needs a display at two pixels to the point and no permission, and it uses no microphone. It repeats a take until each change shows on the frame the film names.
- **`pill-captures.py`** cuts the pill out of each picture: a pixel is the pill's where the picture differs from the plate that was behind it. Everything round the pill stays the film's own frame. It says so if the captures and the film's timeline disagree. Its third argument is optional: with the two pictures of the app's item in the menu bar, the film shows that item and not its own drawing of it. It needs ffmpeg and numpy.

Captures belong to the plates they were made over. When the film's pictures change, make the plates again and capture again; the render stops if the captures were made over plates that have the pill somewhere else than the film now does. The plates, the captures and `public/pill/` are git-ignored.

The type has grey edges, as a Mac draws it. For that the desktop is made anew on every frame: the renderer would otherwise draw it once and stretch that picture as the view moves in, which blurs it.

## The film in the README

The repository's README shows a film as an animated WebP, `docs/media/voiced-forks.webp`: 896 × 560 at 10 frames a second, silent, looping, with its film's timing. It is not this folder's film but another, of an agent forking Voiced, and `readme-webp.py` made it from that film's render as it would from this one's. GitHub plays a video in a README only from a file uploaded in the browser, and an animated image needs nobody to do that.

```sh
python3 readme-webp.py <film.mp4> ../docs/media/voiced-forks.webp
```

That needs ffmpeg, `cwebp` (the `webp` package) and numpy. The script says why it does not use ffmpeg's own animated WebP encoder, which leaves grey blocks behind after every fade. Each new copy adds about 1 MB to the repository's history for good, so make one only for a cut that ships.

## Where things are

| What | Where |
| --- | --- |
| The name, what is said and what lands in each app, and every time | `src/script.ts` |
| The film: the screen, the view moving in, the pill's captures, the caption, the end | `src/Film.tsx` |
| The wallpaper, the menu bar and the Dock | `src/Desktop.tsx` |
| The four apps | `src/apps/` |
| Every icon and picture | `src/Glyphs.tsx`, `src/apps/ChatGlyphs.tsx` |
| The rule that places the pill | `src/placement.ts` |
| How loud the made-up voice is | `src/voice.ts` |

The product's name is `PRODUCT_NAME` in `src/script.ts`. It is the name at the end and the name of the workspace in the team chat, so a rename is that one line.

## What is real and what is staged

- **The pill is the app's own,** not a drawing: frames of the real pill, photographed over this film's pictures at two pixels to the point, are set into the frame pixel for pixel.
- **The text lands on the frame the captures show it on,** two or three frames before the pill starts to leave: the app pastes, and then its pill goes. So what shows through the pill's glass is what the film shows round it.
- **The pill sits where the app puts it by default,** next to the text. `src/placement.ts` is a copy of the rule of `PillNearText` in `Packages/VoicedKit`. The insertion point is at the end of the text in every scene, so the app is told the box it gets may be that of the line above and keeps room for one more line under it. The email app and the notebook are taken to be built with AppKit, which gives the box of the line above: the pill's top edge ends 6 points under the line. The team chat and the code editor are taken to be built on Electron and to give the box of the line itself: the pill ends one line and 6 points under it. Where the pill sits is `PILL_PLACEMENT` in `src/script.ts`; the app's other setting keeps it in one place at the bottom of the screen.
- **The pill appears when audio arrives,** as it does in the app, and its clock counts from then. The view is all the way in by then and does not move until the pill has gone.
- **Apps built on Electron** say where their text is only once the app has switched their accessibility support on, which it does at the first dictation into them. That dictation's pill starts at the bottom of the app's window, and moves to the text if the app says where it is while the key is still held; otherwise it stays there. The team chat and the code editor show a later dictation, whose pill is by the text from the start.
- **The insertion point blinks,** lit for half a second and dark for half, and starts again lit when the text lands.
- **The item in the menu bar is the app's own.** The film as it has been published was given two pictures of it, taken from the app, idle and recording, and the item in its menu bar is their pixels, tinted like the bar's other marks. The item changes while the app listens, but the view is in on the field by then and the menu bar is out of the picture, so the film shows only the idle one. The app draws its item with one of the system's symbols. The film holds that symbol only as pixels of those pictures; no file of the system's typeface or symbols is in this repository or used by the renderer. A render that is given no pictures of the item draws shapes of the film's own in its place.
- **The caption under the screen** is the film's: it shows the words as they are spoken, fillers and all, because the film has no sound. The app shows no such thing. It is drawn outside the screen for that reason.
- **The view moving in** is the film's, as is the screen standing on a plain ground. While the view is in, the screen's edge cuts what is beside the field, as it does in any view that is moved in on a screen; the field being written in is whole in every scene.
- **What is said and what lands** is written for the film and is not the output of a real run. What lands is what the app's cleanup is told to make of it: punctuation and capitals fixed, "um", "uh" and "you know" removed, the words otherwise kept.
- **The times** are chosen: the text lands 1.15 s after the key is let go, inside the 0.85 to 2.65 s measured on a real Mac. The key is never shown.
- **The desktop and the four apps are mock-ups.** They are laid out the way a desktop and such apps are, and carry no other app's or company's name, logo, wordmark or artwork. The code editor's status bar names the language of its made-up code, TypeScript, which is a language and not an app. The app names are plain words ("Team Chat", "Code Editor", "Email", "Notebook"). The team chat's bar and sidebar are a warm brown that no well-known chat client has as its own. The menu bar has a plain shape where a system has its mark, the window buttons are plain red, yellow and green circles with nothing drawn in them, and the wallpaper is a gradient. Every icon and every picture of a person is drawn for the film. The people, the messages, the code and the note are made up, and the one email address is at example.com, which is reserved for examples.

## Rules this film keeps

- It shows nothing the app does not do: a dictation, and the cleaned-up text pasted where the insertion point is.
- No other app's name, icon, logo or artwork, and no real person or company.
- No icon set, and no file of the system's symbols: every glyph the film draws is drawn in `src/Glyphs.tsx` and `src/apps/ChatGlyphs.tsx`. The system's symbols are in the film only as pixels of Voiced's own pill and menu bar item.
- No photographs: the pictures of people are drawn figures.
- No screenshots of other apps. The only pictures taken from a screen are of Voiced's own pill and menu bar item, and they are not kept here.
- No sound.

## Fonts and emoji

All four are under the SIL Open Font License 1.1 and are installed from npm. No font file is kept in this repository.

| What | Used for | Package |
| --- | --- | --- |
| [Inter](https://rsms.me/inter/) | The desktop, the email app, the notebook, the code editor's interface, the caption and the name | `@fontsource-variable/inter` |
| [Lato](https://www.latofonts.com) | The text of the team chat | `@fontsource/lato` |
| [Noto Color Emoji](https://github.com/googlefonts/noto-emoji) | The three emoji in the team chat's reactions | `@fontsource/noto-color-emoji` |
| [JetBrains Mono](https://www.jetbrains.com/lp/mono/) | The code in the code editor | `@fontsource/jetbrains-mono` |

The letters on the pill are the system's typeface, and the marks on the pill and in the menu bar item are the system's symbols, as the app draws them. They are in the film only as pixels of the captures; no file of that typeface or of those symbols is here or in the renderer.

## Remotion's license

The files in this folder are under the repository's MIT license. Remotion itself is not: `npm install` fetches it under [its own license](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md), and that license is what applies to you when you render or change this video.

- **Free** if you are an individual, a for-profit organization with up to three employees, a non-profit, or evaluating Remotion without yet using it commercially. Commercial use is included.
- **A paid Company License** if you are a for-profit organization with more than three employees; pricing is at [remotion.dev/docs/license/pricing](https://www.remotion.dev/docs/license/pricing).
- **Either way** you may not sell, rent or relicense a derivative of Remotion's own code.

This film and the film in the README were rendered under the free license, by an individual. The rest of this repository does not use Remotion.

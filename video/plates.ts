// What the app's pill is captured over, as data: for each scene, where everything is in the frame
// while the view is in, and when each thing happens. `plates.py` runs this and renders the plates.
import { closeUps, FRAME } from "./src/Film";
import { apps } from "./src/apps";
import { FPS, moments, PASTE_LEAD_FRAMES, PILL_PLACEMENT } from "./src/script";

const frame = (seconds: number) => Math.round(seconds * FPS);
const round = (value: number) => Math.round(value * 1000) / 1000;
/** The app redraws the pill's bars once for each chunk of audio. */
const chunk = 0.1;
/** Room round the pill's box for its rise as it appears, in frame pixels. */
const roomRoundPill = 48;

const plates = moments.map((moment, index) => {
  const close = closeUps[index];
  const recording = moment.released - moment.listening;
  const { box, anchor, line } = close;
  return {
    app: moment.app,
    plate: `${moment.app}-before.png`,
    plateLanded: `${moment.app}-landed.png`,
    plateFrames: { before: frame(moment.listening), landed: frame(moment.inserted) - PASTE_LEAD_FRAMES },
    pixelsPerPoint: close.pointScale,
    pill: {
      side: close.side,
      anchor,
      box,
      topEdgeBelowLinePoints: (box.top - (line.top + line.height)) / close.pointScale,
      suggestedCaptureRect: {
        left: box.left - roomRoundPill,
        top: box.top - roomRoundPill,
        width: box.width + 2 * roomRoundPill,
        height: box.height + 2 * roomRoundPill,
      },
    },
    insertionPointLine: line,
    field: close.field,
    window: close.window,
    timeline: {
      appears: { seconds: round(moment.listening), frame: frame(moment.listening) },
      recordingSeconds: round(recording),
      transcribing: { seconds: round(moment.released), frame: frame(moment.released), lastsSeconds: round(moment.polishing - moment.released) },
      polishing: { seconds: round(moment.polishing), frame: frame(moment.polishing), lastsSeconds: round(moment.inserted - moment.polishing) },
      leaves: { seconds: round(moment.inserted), frame: frame(moment.inserted) },
      viewHeldStill: { fromFrame: frame(moment.zoomedIn), toFrame: frame(moment.out) - 1 },
    },
    level: {
      chunkSeconds: chunk,
      values: Array.from({ length: Math.ceil(recording / chunk) }, (_, at) => round(close.level(at * chunk - (moment.speaking - moment.listening)))),
    },
    spoken: moment.words.map((word) => ({ text: word.text, atSeconds: round(moment.speaking + word.at - moment.listening) })),
    landedText: moment.landed,
    appBuiltAs: apps[moment.app].built,
  };
});

console.log(
  JSON.stringify(
    {
      about:
        "Plates for capturing Voiced's real pill for the film. Each plate is one whole film frame at a scene's view when it is in, with no pill and no caption. All rectangles and points are in film pixels, origin top left, y down.",
      film: { ...FRAME, fps: FPS },
      placement: PILL_PLACEMENT,
      screenInFrame: closeUps[0].screen,
      greyTextEdges: true,
      notes: [
        "pixelsPerPoint is how many film pixels one point of the desktop is in the plate. It is exactly 2 in every scene, so a capture at 2x drops in 1:1.",
        "pill.anchor is the middle of the pill's bottom edge, where the app's rule (PillNearText) puts it. pill.box is the room the app keeps for the pill (192 x 44 points) standing on that anchor; the pill is narrower and is centred in it, bottom-aligned.",
        "insertionPointLine is the line the caret is on (zero width). The caret is at the end of the text in every scene, so the app marks the box it is given as one that may be a line up, and its rule keeps room for one more line under that box.",
        "appBuiltAs says which box the film takes the app to be given. appKit: the box of the line above; the pill's top edge ends 6 points under the caret's line. electron: the box of the caret's own line; the pill's top edge ends one line plus 6 points under it. pill.topEdgeBelowLinePoints gives the result.",
        "plate is the frame while the field is still empty: it is behind the pill until the text lands. plateLanded is the same view with the dictated text in the field: it is behind the pill from the frame the text lands on, while the pill leaves. The film lands its text on the frame the captures land theirs on; without captures, two frames before 'leaves'.",
        "The caret in the film blinks, half a second lit and half a second dark, and starts again lit on the frame the text lands. It is outside pill.box in every scene. Both plates show it lit; the film draws its own caret, so a capture is made over the plate as it is.",
        "timeline seconds and frames are film time. The view does not move between viewHeldStill.fromFrame and toFrame, which covers the whole time the pill is up.",
        "The pill appears when audio arrives ('appears'); its clock counts from then. Recording lasts recordingSeconds, then 'Transcribing…', then 'Polishing…', then it leaves as the text is pasted.",
        "level.values is the microphone level (0 to 1) for each 0.1 s chunk of audio from 'appears', as the film scripts it. It is made up from the spoken words, not a recording.",
        "pill.suggestedCaptureRect is pill.box with 48 pixels added on every side. The film cuts the pill out of each captured frame: a pixel belongs to the pill where the capture differs from the plate behind it. So within the rectangle everything that is not the pill must equal the plate, pixel for pixel in sRGB.",
        "greyTextEdges says that the plates' type has grey edges, as a Mac draws it, and that the film is to be rendered the same way with captures made over them.",
      ],
      plates,
    },
    null,
    2,
  ),
);

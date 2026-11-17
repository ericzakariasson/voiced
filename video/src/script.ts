// The film's script: the name, what is said and what lands in each app, and every moment in
// seconds. This file imports nothing, so that the render script can read the keyframe times
// from it with plain Node.

/** The product's name, as it stands at the end of the film. A rename is this one line. */
export const PRODUCT_NAME = "Voiced";

export const FPS = 60;

export type AppId = "chat" | "code" | "mail" | "notes";

type Line = {
  app: AppId;
  /**
   * The words as they are spoken, fillers and all. `|` is a pause, and `word/2` says how many
   * syllables a word has where it is not one.
   */
  spoken: string;
  /** What the app pastes: the same words, cleaned up. */
  landed: string;
};

const lines: Line[] = [
  {
    app: "chat",
    spoken: "yeah I can | um I'll have comments/2 for you by two",
    landed: "Yeah, I can. I'll have comments for you by two.",
  },
  {
    app: "code",
    spoken: "add a retry/2 to the upload/2 function/2 | uh three attempts/2 with backoff/2 | and write a test for it",
    landed: "Add a retry to the upload function, three attempts with backoff, and write a test for it.",
  },
  {
    app: "mail",
    spoken: "hi Dana/2 | ten works for me | I'll send the agenda/3 tonight/2",
    landed: "Hi Dana, ten works for me. I'll send the agenda tonight.",
  },
  {
    app: "notes",
    spoken: "follow/2 up with Priya/2 about/2 the pricing/2 page | you know | before/2 Friday/2",
    landed: "Follow up with Priya about the pricing page before Friday.",
  },
];

/**
 * Where the pill sits: by the line being written, which is the app's Next to Text setting, or at
 * the bottom centre of the screen, which is its Fixed Place. This is the one place that says.
 */
export const PILL_PLACEMENT: "nextToText" | "fixedPlace" = "nextToText";

const frames = (seconds: number) => Math.round(seconds * FPS);
/** `seconds`, moved to the nearest frame. */
const onFrame = (seconds: number) => frames(seconds) / FPS;

const syllable = 0.17;
const betweenWords = 0.04;
const pause = 0.26;
const fillers = new Set(["um", "uh"]);

export type SpokenWord = { text: string; at: number; syllables: number; length: number };

/** When each word is said, in seconds after the speaker starts, and how long the whole takes. */
const say = (spoken: string): { words: SpokenWord[]; length: number } => {
  const words: SpokenWord[] = [];
  let at = 0;
  for (const token of spoken.split(" ")) {
    if (token === "|") {
      at += pause;
      continue;
    }
    const [text, count] = token.split("/");
    const syllables = count ? Number(count) : 1;
    // A filler is drawn out.
    const length = fillers.has(text) ? 0.3 : syllables * syllable;
    words.push({ text, at, syllables, length });
    at += length + betweenWords;
  }
  return { words, length: at - betweenWords };
};

export type Moment = {
  app: AppId;
  landed: string;
  words: SpokenWord[];
  /** The app's window arrives. */
  in: number;
  zoomIn: number;
  zoomedIn: number;
  /** The key is down and audio arrives: the pill appears and its clock starts. */
  listening: number;
  speaking: number;
  /** The key is let go: "Transcribing…". */
  released: number;
  polishing: number;
  /** The text is pasted and the pill leaves. */
  inserted: number;
  /** The pill has gone and nothing moves until `out`. */
  still: number;
  /** The window leaves and the view draws back. */
  out: number;
  zoomedOut: number;
};

const firstIn = 0.2;
const windowTime = 0.3;

const build = (): Moment[] => {
  const moments: Moment[] = [];
  let start = firstIn;
  for (const line of lines) {
    const { words, length } = say(line.spoken);
    // The view is all the way in before the pill appears, and stays there until it has gone.
    const zoomIn = onFrame(start + 0.3);
    const listening = onFrame(start + 1.2);
    const speaking = onFrame(listening + 0.12);
    const released = onFrame(speaking + length + 0.3);
    const polishing = onFrame(released + 0.45);
    const inserted = onFrame(polishing + 0.7);
    const out = onFrame(inserted + 1.15);
    moments.push({
      app: line.app,
      landed: line.landed,
      words,
      in: onFrame(start),
      zoomIn,
      zoomedIn: onFrame(zoomIn + 0.85),
      listening,
      speaking,
      released,
      polishing,
      inserted,
      still: onFrame(inserted + 0.5),
      out,
      zoomedOut: onFrame(out + 0.6),
    });
    start = out + windowTime;
  }
  return moments;
};

export const moments = build();

/** How long a window takes to arrive or leave. */
export const windowFade = windowTime;

const last = moments[moments.length - 1];

/** The end: the desktop gives way to a plain card with the mark and the name. */
export const ending = {
  /** The card comes up over the desktop. */
  cardIn: onFrame(last.out + 0.2),
  cardUp: onFrame(last.out + 0.7),
  /** The mark and the name are fully there, and nothing moves from here on. */
  lockupIn: onFrame(last.out + 0.6),
  still: onFrame(last.out + 1.0),
  end: onFrame(last.out + 1.0 + 1.9),
};

export const DURATION_FRAMES = frames(ending.end);

/**
 * The text shows this many frames before the pill starts to leave: the app pastes, and then its
 * pill goes. The captures of the real pill say on which frame for each scene; this is what holds
 * where they do not.
 */
export const PASTE_LEAD_FRAMES = 2;

/** The insertion point is lit for this many frames and dark for as many, and starts again lit when text lands. */
export const CARET_BLINK_FRAMES = 30;

/**
 * The stretches in which nothing on screen moves, as first and last frame: after each pill has
 * gone, between one change of the insertion point and the next, and the end. The checks compare
 * every frame of each with its first. `lands` and `gone` are, for each scene, the frame the text
 * lands on and the first frame without the pill.
 */
export const holdsFor = (lands: number[], gone: number[]): [number, number][] => {
  const stretches: [number, number][] = [];
  moments.forEach((moment, index) => {
    const end = frames(moment.out) - 1;
    let from = gone[index];
    // The insertion point changes every CARET_BLINK_FRAMES after the text lands.
    for (let change = lands[index] + CARET_BLINK_FRAMES; from <= end; change += CARET_BLINK_FRAMES) {
      if (change <= from) {
        continue;
      }
      const to = Math.min(change - 1, end);
      if (to - from + 1 >= 6) {
        stretches.push([from, to]);
      }
      from = change;
    }
  });
  stretches.push([frames(ending.still), DURATION_FRAMES - 1]);
  return stretches;
};

/** The same with no captures: the text lands PASTE_LEAD_FRAMES before the pill leaves, and the pill is gone half a second after. */
export const holds = holdsFor(
  moments.map((moment) => frames(moment.inserted) - PASTE_LEAD_FRAMES),
  moments.map((moment) => frames(moment.still)),
);

/**
 * Where the encoder is told to start a new group of pictures, in seconds: at the start, as each
 * app arrives, and as the card comes up. With no keyframe inside a hold, a hold's frames come
 * out of the decoder alike.
 */
export const keyframes: number[] = [0, ...moments.slice(1).map((moment) => moment.in), ending.cardIn];

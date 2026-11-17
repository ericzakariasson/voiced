import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { placeNearText, Rect } from "./placement";
import { apps, desktop, dockReserve, menuBarHeight } from "./apps";
import { uiFont } from "./apps/types";
import { Dock, MenuBar, MenuBarItemPictures, Wallpaper } from "./Desktop";
import { AppId, CARET_BLINK_FRAMES, ending, FPS, Moment, moments, PASTE_LEAD_FRAMES, PILL_PLACEMENT, PRODUCT_NAME, windowFade } from "./script";
import { levelOf } from "./voice";
import { WaveformMark } from "./WaveformMark";

// The film: a desktop, and one app after another in which something is dictated. Each time the
// view moves in on the field being written in, the pill appears by the line, its bars and clock
// run while the words are spoken, and the cleaned-up text lands at the insertion point. It ends
// on the mark and the name.
//
// The desktop is shown as a screen standing on a plain ground. What is spoken is written under
// the screen as a caption, because the film has no sound; it is outside the screen because the
// app shows no such thing.

export const FRAME = { width: 1920, height: 1200 };
/** The screen within the frame: 16:10, with room under it for the caption. */
const screen = { left: 120, top: 34, width: 1680, height: 1050 };
const ground = "#f4f4f6";
/** Frame pixels to a point of the desktop, before the view moves in. */
const scale = screen.width / desktop.width;
/** A point of the desktop is this many frame pixels when the view is all the way in. */
export const CLOSE_UP_SCALE = 2;
/** How far the view moves in on the field. */
const closeUp = CLOSE_UP_SCALE / scale;

/** The part of the screen apps may use: under the menu bar, over the Dock. */
const visible: Rect = { left: 0, top: menuBarHeight, width: desktop.width, height: desktop.height - menuBarHeight - dockReserve };

const clocks: Record<AppId, string> = { chat: "10:43 AM", code: "11:20 AM", mail: "1:05 PM", notes: "4:12 PM" };

/** 0 before `from`, 1 after `to`, eased at both ends, and exactly 0 or 1 outside them. */
const ease = (time: number, from: number, to: number) =>
  interpolate(time, [from, to], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.inOut(Easing.cubic) });

const onDesktop = (app: AppId, rect: Rect): Rect => ({
  left: apps[app].window.left + rect.left,
  top: apps[app].window.top + rect.top,
  width: rect.width,
  height: rect.height,
});

/** The least room between the end of the field and the screen's edge while the view is in, in points. */
const fieldEndToEdge = 12;

/** Where the app's rule puts the pill in each app, and the point the view moves in on. */
const staging = moments.map((moment) => {
  const line = onDesktop(moment.app, apps[moment.app].line);
  const field = onDesktop(moment.app, apps[moment.app].field);
  // The box the app is given for the insertion point, which is at the end of the text in every
  // scene: the line above from an AppKit text view, the line itself from an Electron app.
  const reported = apps[moment.app].built === "appKit" ? { ...line, top: line.top - line.height } : line;
  return {
    pill:
      PILL_PLACEMENT === "nextToText"
        ? placeNearText(reported, field, visible, true)
        : // The app's fixed place until it is dragged: the bottom centre of the screen, 18 points up.
          { side: "fixed place" as const, x: visible.left + visible.width / 2, bottom: visible.top + visible.height - 18 },
    // A little right of the insertion point and above it, so that the text that lands and what
    // it answers are both in view; further right where that would leave the field's end out of
    // view, so that the screen's edge cuts nothing in the field.
    focus: { x: Math.max(line.left + 220, field.left + field.width + fieldEndToEdge - screen.width / 2 / CLOSE_UP_SCALE), y: line.top - 30 },
    level: levelOf(moment.words, moment.app),
  };
});

/** Where the desktop's top left corner is within the screen, and its scale, with the view `zoom` of the way in on `focus`. */
const viewOf = (zoom: number, focus: { x: number; y: number }) => {
  const factor = scale * (1 + (closeUp - 1) * zoom);
  // The point goes to the middle of the screen, as far as the desktop's edges allow. Whole
  // pixels, so that a point of the desktop lands on the frame's pixel grid when the view is in.
  const limit = (value: number, low: number) => Math.round(Math.min(0, Math.max(low, value)));
  return {
    factor,
    x: limit(screen.width / 2 - focus.x * factor, screen.width - desktop.width * factor),
    y: limit(screen.height / 2 - focus.y * factor, screen.height - desktop.height * factor),
  };
};

/**
 * For each moment, where things are in the frame while the view is all the way in, in frame
 * pixels: what the app's real pill is captured against.
 */
export const closeUps = moments.map((moment, index) => {
  const view = viewOf(1, staging[index].focus);
  const inFrame = (rect: Rect): Rect => ({
    left: screen.left + view.x + rect.left * view.factor,
    top: screen.top + view.y + rect.top * view.factor,
    width: rect.width * view.factor,
    height: rect.height * view.factor,
  });
  const { pill } = staging[index];
  return {
    app: moment.app,
    pointScale: view.factor,
    side: pill.side,
    /** The middle of the pill's bottom edge. */
    anchor: { x: screen.left + view.x + pill.x * view.factor, y: screen.top + view.y + pill.bottom * view.factor },
    /** The room the app keeps for the pill: 192 by 44 points, standing on the anchor. */
    box: inFrame({ left: pill.x - 96, top: pill.bottom - 44, width: 192, height: 44 }),
    line: inFrame(onDesktop(moment.app, apps[moment.app].line)),
    field: inFrame(onDesktop(moment.app, apps[moment.app].field)),
    window: inFrame(apps[moment.app].window),
    screen,
    level: staging[index].level,
  };
});

const reached = (frame: number, moment: number) => frame >= Math.round(moment * FPS);

const AppWindow: React.FC<{ moment: Moment; index: number; time: number; frame: number; lands: number }> = ({ moment, index, time, frame, lands }) => {
  const app = apps[moment.app];
  // The first window is there from the start; the last stays until the card covers it.
  const arrived = index === 0 ? 1 : ease(time, moment.in, moment.in + windowFade);
  const left = index === moments.length - 1 ? 0 : ease(time, moment.out, moment.out + windowFade);
  if (arrived === 0 || left === 1) {
    return null;
  }
  const landed = frame >= lands;
  // The insertion point blinks, lit for half a second and dark for half, and starts again lit
  // when the text lands.
  const since = landed ? frame - lands : frame - Math.round(moment.in * FPS);
  const caretShown = since < 0 || since % (2 * CARET_BLINK_FRAMES) < CARET_BLINK_FRAMES;
  return (
    <div
      style={{
        position: "absolute",
        ...app.window,
        borderRadius: 12,
        overflow: "hidden",
        // The shadow of a window in front: wide and soft, with a hairline round the window.
        boxShadow: "0 30px 70px rgba(0,0,0,0.36), 0 6px 16px rgba(0,0,0,0.1), 0 0 0 0.5px rgba(0,0,0,0.28)",
        opacity: arrived * (1 - left),
        transform: `translateY(${(1 - arrived) * 10}px) scale(${0.985 + 0.015 * arrived})`,
      }}
    >
      <app.Window text={landed ? moment.landed : null} caretShown={caretShown} />
    </div>
  );
};

/** The words as they are spoken, each appearing as it is said. Words not yet said keep their room. */
const Caption: React.FC<{ moment: Moment; frame: number; lands: number }> = ({ moment, frame, lands }) => {
  if (!reached(frame, moment.speaking + moment.words[0].at) || frame >= lands) {
    return null;
  }
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        top: screen.top + screen.height,
        bottom: 0,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div
        style={{
          color: "#1d1d1f",
          fontFamily: uiFont,
          fontSize: 34,
          lineHeight: "44px",
          fontWeight: 500,
          letterSpacing: -0.4,
          whiteSpace: "nowrap",
          display: "flex",
          gap: "0.27em",
        }}
      >
        {moment.words.map((word, index) => (
          <span key={index} style={{ visibility: reached(frame, moment.speaking + word.at) ? "visible" : "hidden" }}>
            {word.text}
          </span>
        ))}
      </div>
    </div>
  );
};

const Ending: React.FC<{ time: number }> = ({ time }) => {
  const card = ease(time, ending.cardIn, ending.cardUp);
  if (card === 0) {
    return null;
  }
  const lockup = ease(time, ending.lockupIn, ending.still);
  return (
    <AbsoluteFill style={{ background: ground, opacity: card, alignItems: "center", justifyContent: "center" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 40, opacity: lockup, color: "#0a0a0a" }}>
        <WaveformMark height={112} color="#0a0a0a" />
        <div style={{ fontFamily: uiFont, fontSize: 146, lineHeight: 1, fontWeight: 600, letterSpacing: -6, marginTop: -8 }}>{PRODUCT_NAME}</div>
      </div>
    </AbsoluteFill>
  );
};

/**
 * Frames of the app's real pill for one scene, captured on a Mac over that scene's plate at two
 * pixels to the point: PNGs named 0000.png, 0001.png and so on in `folder` under `public/`, one
 * for each frame of the film from the frame the pill appears on, each `width` by `height` pixels
 * and standing at `left`, `top` in the frame.
 */
export type PillCapture = {
  folder: string;
  frames: number;
  left: number;
  top: number;
  width: number;
  height: number;
  /** The frame, counted from the pill appearing, on which the text is seen to have landed behind the pill; null when it cannot be seen. */
  textLandsOnFrame?: number | null;
  /** Where the plate the captures were made over has the room for the pill, in frame pixels. */
  pillBoxInPlate?: { left: number; top: number };
};

/** Stops a render whose captures were made over a plate that the film no longer draws: the pill would stand in the wrong place. */
const checkPlates = (captures: Partial<Record<AppId, PillCapture>>) => {
  closeUps.forEach(({ app, box }) => {
    const plate = captures[app]?.pillBoxInPlate;
    if (plate && (plate.left !== box.left || plate.top !== box.top)) {
      throw new Error(
        `The captures for ${app} were made over a plate with the pill's room at ${plate.left}, ${plate.top}; the film now has it at ${box.left}, ${box.top}. Capture again over the film's current plates.`,
      );
    }
  });
};

export type FilmProps = {
  /**
   * Where the pill comes from. The film's pill is the app's own, from captures. `none` leaves it
   * out, which is how the plates the captures are made over are rendered. The film has no drawn pill.
   */
  pill: "captures" | "none";
  /** The captures for each scene; a scene without them has no pill. */
  captures?: Partial<Record<AppId, PillCapture>>;
  /** Pictures of the app's own item in the menu bar; the film's drawing of it stands in without them. */
  menuBarItem?: MenuBarItemPictures;
  /** Whether the caption of the spoken words is drawn. */
  caption: boolean;
  /**
   * Whether type has grey edges, as a Mac draws it, where the renderer's own are coloured. It
   * changes every piece of type on the desktop, so the pill's captures have to have been made
   * over plates rendered the same way; `pill-captures.py` sets it from the plates' own note.
   */
  greyText?: boolean;
};

export const Film: React.FC<FilmProps> = ({ pill, captures, menuBarItem, caption, greyText }) => {
  const frame = useCurrentFrame();
  const time = frame / FPS;

  // The frame the text lands on in each scene: the one the captures show it on, or a little
  // before the pill starts to leave.
  const lands = moments.map((moment) => {
    const seen = pill === "captures" ? captures?.[moment.app]?.textLandsOnFrame : null;
    return seen != null ? Math.round(moment.listening * FPS) + seen : Math.round(moment.inserted * FPS) - PASTE_LEAD_FRAMES;
  });

  if (pill === "captures" && captures) {
    checkPlates(captures);
  }

  // The app in front: the latest whose window has begun to arrive.
  let current = 0;
  moments.forEach((moment, index) => {
    if (index > 0 && reached(frame, moment.in)) {
      current = index;
    }
  });
  const front = apps[moments[current].app];

  // How far in the view is, and on which point. It is fully out whenever the point changes.
  let zoom = 0;
  let focus = staging[0].focus;
  moments.forEach((moment, index) => {
    const amount = ease(time, moment.zoomIn, moment.zoomedIn) * (1 - ease(time, moment.out, moment.zoomedOut));
    if (amount > 0) {
      zoom = amount;
      focus = staging[index].focus;
    }
  });
  const { factor, x, y } = viewOf(zoom, focus);

  return (
    <>
      <AbsoluteFill style={{ background: ground }}>
        <div
          style={{
            position: "absolute",
            ...screen,
            borderRadius: 16,
            overflow: "hidden",
            boxShadow: "0 30px 80px rgba(0,0,0,0.16), 0 0 0 1px rgba(0,0,0,0.1)",
          }}
        >
          <div
            // A layer the renderer is told will move is drawn once, and that picture is stretched
            // as the view moves in, which blurs it. Made anew on each frame, the layer is drawn at
            // the size it is shown at, and each frame is the picture a still of it would be.
            key={greyText ? frame : 0}
            style={{
              position: "absolute",
              left: 0,
              top: 0,
              width: desktop.width,
              height: desktop.height,
              transformOrigin: "0 0",
              transform: `translate(${x}px, ${y}px) scale(${factor})`,
              // Type set where its outlines say, without snapping to the pixel grid, as a Mac sets it.
              textRendering: "geometricPrecision",
              // The renderer smooths type with coloured edges only on a layer it expects to stay put,
              // so it is told this one will move.
              willChange: greyText ? "transform" : undefined,
            }}
          >
            <Wallpaper />
            {moments.map((moment, index) => (
              <AppWindow key={moment.app} moment={moment} index={index} time={time} frame={frame} lands={lands[index]} />
            ))}
            <MenuBar
              app={front.name}
              menus={front.menus}
              clock={clocks[front.id]}
              item={menuBarItem}
              // The app's item shows that it is listening from when audio arrives until the key is let go.
              listening={moments.some((moment) => reached(frame, moment.listening) && !reached(frame, moment.released))}
            />
            <Dock active={front.id} />
          </div>
        </div>
        {/* The app's real pill, pixel for pixel: it stands in the frame, not in the desktop. */}
        {(pill === "captures" ? moments : []).map((moment) => {
          const capture = captures?.[moment.app];
          const shot = frame - Math.round(moment.listening * FPS);
          if (!capture || shot < 0 || shot >= capture.frames) {
            return null;
          }
          return (
            <Img
              key={moment.app}
              src={staticFile(`${capture.folder}/${String(shot).padStart(4, "0")}.png`)}
              style={{ position: "absolute", left: capture.left, top: capture.top, width: capture.width, height: capture.height }}
            />
          );
        })}
        {(caption ? moments : []).map((moment, index) => (
          <Caption key={moment.app} moment={moment} frame={frame} lands={lands[index]} />
        ))}
        <Ending time={time} />
      </AbsoluteFill>
    </>
  );
};

import React from "react";
import { desktop, menuBarHeight } from "./apps";
import { chatTile } from "./apps/Chat";
import { uiFont } from "./apps/types";
import { Img, staticFile } from "remotion";
import { Battery, Glyph, GlyphName } from "./Glyphs";
import { AppId } from "./script";

// The desktop the apps stand on: a wallpaper, a menu bar and a Dock, in light mode. All of it is
// drawn for this film. It is laid out the way a desktop is, but it is no real system's: there is
// no maker's mark, the wallpaper is a plain gradient, and every icon is the film's own.

/** How strong the bar's marks are: black, this much of the way. */
const inkStrength = 0.86;
const ink = `rgba(0,0,0,${inkStrength})`;

export const Wallpaper: React.FC = () => (
  <div
    style={{
      position: "absolute",
      inset: 0,
      background: [
        "radial-gradient(ellipse 70% 60% at 12% 18%, rgba(255,214,186,0.9), rgba(255,214,186,0) 70%)",
        "radial-gradient(ellipse 65% 70% at 88% 12%, rgba(176,208,255,0.95), rgba(176,208,255,0) 70%)",
        "radial-gradient(ellipse 80% 70% at 78% 96%, rgba(203,186,255,0.85), rgba(203,186,255,0) 70%)",
        "radial-gradient(ellipse 70% 60% at 14% 98%, rgba(168,226,214,0.85), rgba(168,226,214,0) 70%)",
        "linear-gradient(160deg, #e9eef8, #f1ecf7)",
      ].join(", "),
    }}
  />
);

/**
 * The product's item in the menu bar. The app shows a system symbol there: a waveform, and a
 * filled disc with the waveform cut out of it while it is listening. The film shows the app's own
 * item, from pictures of it, when it is given them; these two drawings stand in when it is not.
 */
const lines = [0.32, 0.62, 1, 0.48, 0.82, 0.55, 0.28];

/**
 * The app's own item, as pixels: pictures of it idle and while it records, taken from the app at
 * two pixels to the point, white on nothing. `width` and `height` are the pictures' size in pixels.
 */
export type MenuBarItemPictures = {
  idle: string;
  recording: string;
  width: number;
  height: number;
  /** The most opaque the pictures get, 0 to 1: the system draws the item a little see-through. */
  peak: number;
};

/** How wide the mark is within its picture, in points: the room it takes among the bar's other marks. */
const markWidth = 14;

const MenuBarItem: React.FC<{ listening: boolean; pictures?: MenuBarItemPictures }> = ({ listening, pictures }) => {
  if (pictures) {
    const width = pictures.width / 2;
    const height = pictures.height / 2;
    return (
      <div style={{ width: markWidth, height: menuBarHeight, position: "relative" }}>
        <Img
          src={staticFile(listening ? pictures.recording : pictures.idle)}
          style={{
            position: "absolute",
            left: (markWidth - width) / 2,
            top: (menuBarHeight - height) / 2,
            width,
            height,
            // The picture is white; the bar's marks are its ink, and as strong at their strongest.
            filter: "brightness(0)",
            opacity: Math.min(1, inkStrength / pictures.peak),
          }}
        />
      </div>
    );
  }
  const size = 17;
  const tall = listening ? 9 : 13;
  return (
    <div
      style={{
        width: size,
        height: size,
        borderRadius: size,
        background: listening ? ink : "none",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 1,
      }}
    >
      {lines.map((share, index) => (
        <div key={index} style={{ width: 1.3, height: Math.max(1.3, tall * share), borderRadius: 1, background: listening ? "#f4f2f8" : ink }} />
      ))}
    </div>
  );
};

export const MenuBar: React.FC<{ app: string; menus: string[]; clock: string; listening: boolean; item?: MenuBarItemPictures }> = ({
  app,
  menus,
  clock,
  listening,
  item,
}) => (
  <div
    style={{
      position: "absolute",
      left: 0,
      top: 0,
      width: desktop.width,
      height: menuBarHeight,
      // Clear, as the menu bar of the system the app needs is: the wallpaper shows through.
      display: "flex",
      alignItems: "center",
      padding: "0 14px",
      boxSizing: "border-box",
      fontFamily: uiFont,
      fontSize: 13,
      color: ink,
      whiteSpace: "nowrap",
    }}
  >
    {/* Where a system keeps its own menu: here, a plain shape that is nobody's mark. */}
    <div style={{ width: 11, height: 11, borderRadius: 3.5, background: ink, transform: "rotate(45deg)", margin: "0 8px 0 4px" }} />
    <div style={{ marginLeft: 12, fontWeight: 650 }}>{app}</div>
    {menus.map((menu) => (
      <div key={menu} style={{ marginLeft: 18 }}>
        {menu}
      </div>
    ))}
    <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: 14 }}>
      <MenuBarItem listening={listening} pictures={item} />
      <Glyph name="wifi" size={17} color={ink} weight={1.6} />
      <Battery color={ink} />
      <Glyph name="search" size={15} color={ink} weight={1.7} />
      <div style={{ fontWeight: 500 }}>Tue Nov 17</div>
      <div style={{ fontWeight: 500, fontFeatureSettings: '"tnum"' }}>{clock}</div>
    </div>
  </div>
);

type Tile = { id: string; glyph?: GlyphName; background: string; color?: string };

const tiles: Tile[] = [
  { id: "files", glyph: "folder", background: "linear-gradient(180deg, #7d95b8, #56709a)" },
  { id: "browser", glyph: "globe", background: "linear-gradient(180deg, #4fb58c, #2f8f6a)" },
  { id: "chat", glyph: "bubble", background: chatTile },
  { id: "code", glyph: "brackets", background: "linear-gradient(180deg, #2f3540, #1b1f27)", color: "#7fd6c2" },
  { id: "mail", glyph: "envelope", background: "linear-gradient(180deg, #5b7be0, #3d5fc4)" },
  { id: "notes", glyph: "lines", background: "linear-gradient(180deg, #37ab99, #1f8a7a)" },
  { id: "calendar", background: "#ffffff" },
  { id: "settings", glyph: "gear", background: "linear-gradient(180deg, #a9adb6, #7d828c)" },
];

const tile = 46;

export const Dock: React.FC<{ active: AppId }> = ({ active }) => (
  <div
    style={{
      position: "absolute",
      left: "50%",
      bottom: 8,
      transform: "translateX(-50%)",
      height: tile + 16,
      padding: "0 8px",
      borderRadius: 20,
      background: "rgba(255,255,255,0.5)",
      boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.55), 0 0 0 0.5px rgba(0,0,0,0.12), 0 10px 30px rgba(0,0,0,0.12)",
      display: "flex",
      alignItems: "center",
      gap: 8,
      fontFamily: uiFont,
    }}
  >
    {tiles.map((entry) => (
      <div key={entry.id} style={{ position: "relative", width: tile, height: tile }}>
        <div
          style={{
            width: tile,
            height: tile,
            borderRadius: 11,
            background: entry.background,
            boxShadow: "0 1px 2px rgba(0,0,0,0.18), inset 0 0.5px 0 rgba(255,255,255,0.35)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            overflow: "hidden",
          }}
        >
          {entry.glyph ? (
            <Glyph name={entry.glyph} size={27} color={entry.color ?? "#ffffff"} weight={1.6} />
          ) : (
            // The calendar: a band and the day of the month.
            <div style={{ width: "100%", height: "100%" }}>
              <div style={{ height: 13, background: "#6657c9" }} />
              <div style={{ height: 33, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 22, fontWeight: 600, color: "#1d1d1f" }}>
                17
              </div>
            </div>
          )}
        </div>
        {entry.id === active ? (
          <div style={{ position: "absolute", left: tile / 2 - 2, bottom: -7, width: 4, height: 4, borderRadius: 2, background: "rgba(0,0,0,0.6)" }} />
        ) : null}
      </div>
    ))}
    <div style={{ width: 1, height: tile - 6, background: "rgba(0,0,0,0.14)" }} />
    <div
      style={{
        width: tile,
        height: tile,
        borderRadius: 11,
        background: "rgba(255,255,255,0.6)",
        boxShadow: "inset 0 0 0 1px rgba(0,0,0,0.08)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <Glyph name="trash" size={25} color="rgba(0,0,0,0.5)" weight={1.4} />
    </div>
  </div>
);

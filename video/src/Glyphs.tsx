import React from "react";

// Every icon of the desktop and its apps, drawn for this film as plain strokes on a 20 by 20
// grid. None is taken from a system symbol set, an icon set, or another app.

const paths = {
  folder: "M2.5 6A1.5 1.5 0 0 1 4 4.5h3.6l1.6 1.8H16a1.5 1.5 0 0 1 1.5 1.5v6.7A1.5 1.5 0 0 1 16 16H4a1.5 1.5 0 0 1-1.5-1.5z",
  file: "M5.5 3h6L15 6.500V16a1 1 0 0 1-1 1H5.5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM11.500 3v3.500H15",
  envelope: "M3 5.500h14v9H3zM3 6l7 5.200L17 6",
  inbox: "M3 11.500l2-6.500h10l2 6.500v4H3zM3 11.500h4l1 2h4l1-2h4",
  star: "M10 3l2.100 4.400 4.800.600-3.500 3.300.900 4.700L10 13.700 5.700 16l.900-4.700L3.100 8l4.800-.600z",
  trash: "M4.500 6h11M8 6V4.200h4V6M6 6l.700 10h6.600L14 6M8.600 8.800v4.600M11.400 8.800v4.600",
  archive: "M3 4.500h14v3.200H3zM4.200 7.700v7.800h11.600V7.700M8 10.500h4",
  reply: "M8.500 5l-5 4.500 5 4.500M3.500 9.500H11a5.500 5.500 0 0 1 5.500 5.500",
  forward: "M11.500 5l5 4.500-5 4.500M16.500 9.500H9A5.500 5.500 0 0 0 3.500 15",
  flag: "M5 17V3.500M5 4h9.500l-2 3 2 3H5",
  paperclip: "M14.500 9.500l-5 5a2.800 2.800 0 0 1-4-4l6-6a1.900 1.900 0 0 1 2.700 2.700l-5.800 5.800a1 1 0 0 1-1.400-1.400l5-5",
  pencil: "M4 16l.800-3.600 8.700-8.700 2.800 2.800-8.700 8.700zM12 5.200l2.800 2.800",
  compose: "M10.500 4H5.500A1.500 1.500 0 0 0 4 5.500v9A1.500 1.500 0 0 0 5.500 16h9a1.500 1.500 0 0 0 1.500-1.500v-5M9 11.200l.500-2.700 6-6 2.200 2.200-6 6z",
  sidebar: "M3 4.500h14v11H3zM7.500 4.500v11",
  search: "M9 3.500a5.500 5.500 0 1 0 0 11 5.500 5.500 0 0 0 0-11zM13.200 13.200L17 17",
  sparkle: "M9 3l1.600 4.400L15 9l-4.400 1.600L9 15l-1.600-4.400L3 9l4.400-1.600zM15.500 13l.600 1.400 1.400.600-1.400.600-.600 1.400-.600-1.400-1.400-.600 1.400-.600z",
  branch: "M6 6.500v7M6 3.500a1.500 1.500 0 1 0 0 3 1.500 1.500 0 0 0 0-3zM6 13.500a1.500 1.500 0 1 0 0 3 1.500 1.500 0 0 0 0-3zM14 3.500a1.500 1.500 0 1 0 0 3 1.500 1.500 0 0 0 0-3zM14 6.500V8a3 3 0 0 1-3 3H9a3 3 0 0 0-3 2.500",
  gear: "M10 7a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM10 2.500v2M10 15.500v2M2.500 10h2M15.500 10h2M4.700 4.700l1.400 1.400M13.900 13.900l1.400 1.400M4.700 15.300l1.400-1.400M13.900 6.100l1.400-1.400",
  wifi: "M3 8.200a10 10 0 0 1 14 0M5.500 11a6.400 6.400 0 0 1 9 0M8 13.700a2.900 2.900 0 0 1 4 0",
  globe: "M10 2.500a7.500 7.500 0 1 0 0 15 7.500 7.500 0 0 0 0-15zM2.500 10h15M10 2.500c2.300 2.200 3.400 4.700 3.400 7.500s-1.100 5.300-3.400 7.500C7.700 15.300 6.600 12.800 6.600 10S7.700 4.700 10 2.500z",
  bubble: "M4 5a1.500 1.500 0 0 1 1.500-1.500h9A1.500 1.500 0 0 1 16 5v6.500a1.500 1.500 0 0 1-1.500 1.500H9.700L6.300 16v-3h-.800A1.500 1.500 0 0 1 4 11.500z",
  brackets: "M7.500 5.500l-4 4.500 4 4.500M12.500 5.500l4 4.500-4 4.500",
  lines: "M5 6h10M5 10h10M5 14h6",
  chevronRight: "M8 5l5 5-5 5",
  chevronDown: "M5 8l5 5 5-5",
  plus: "M10 4.500v11M4.500 10h11",
  grid: "M4 4h5v5H4zM11 4h5v5h-5zM4 11h5v5H4zM11 11h5v5h-5z",
  list: "M4 5.500h12M4 10h12M4 14.500h12",
  share: "M10 3v9M6.500 6.500L10 3l3.500 3.500M4.500 10.500V16h11v-5.500",
  terminal: "M3 4.500h14v11H3zM6 8l2.500 2L6 12M10.500 12H14",
  check: "M4.500 10.500l3.500 3.500 7.500-8",
  arrowUp: "M10 16V4.500M5.500 9L10 4.500 14.500 9",
  plane: "M3.500 4l13.500 6-13.500 6 2.200-6zM5.700 10h5.800",
  tag: "M3.500 4.500h6l7 7-6 6-7-7zM7 8v.010",
  panel: "M3 4.500h14v11H3zM12.500 4.500v11",
  bold: "M6.500 4.500h4.300a2.700 2.700 0 0 1 0 5.400H6.500zM6.500 9.900h5a2.800 2.800 0 0 1 0 5.600h-5z",
  checklist: "M3.500 5.500l1.300 1.300 2.200-2.600M3.500 11.500l1.300 1.300L7 10.200M10 6h6.500M10 12h6.500",
  table: "M3 4.500h14v11H3zM3 8.500h14M3 12h14M8 4.500v11",
  image: "M3 4.500h14v11H3zM3 13l4-4 3.500 3.500 2.500-2 4 3.500M13 8v.010",
  lock: "M5.500 9h9v7.500h-9zM7.500 9V6.500a2.500 2.500 0 0 1 5 0V9",
  at: "M10 7a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM13 7v4.200a1.800 1.800 0 0 0 3.500-.600V10a6.500 6.500 0 1 0-2.700 5.300",
  dots: "M4.500 10v.010M10 10v.010M15.500 10v.010",
  clock: "M10 3a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM10 6v4.200l2.600 1.800",
} satisfies Record<string, string>;

export type GlyphName = keyof typeof paths;

export const Glyph: React.FC<{
  name: GlyphName;
  size: number;
  color: string;
  /** The stroke's width on the 20 point grid. */
  weight?: number;
  style?: React.CSSProperties;
}> = ({ name, size, color, weight = 1.5, style }) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 20 20"
    fill="none"
    stroke={color}
    strokeWidth={name === "dots" ? 2.2 : weight}
    strokeLinecap="round"
    strokeLinejoin="round"
    style={{ flexShrink: 0, display: "block", ...style }}
  >
    <path d={paths[name]} />
  </svg>
);

/** A battery, mostly full. */
export const Battery: React.FC<{ color: string }> = ({ color }) => (
  <svg width={26} height={13} viewBox="0 0 26 13" style={{ display: "block", flexShrink: 0 }}>
    <rect x="0.750" y="0.750" width="21.500" height="11.500" rx="3.200" fill="none" stroke={color} strokeOpacity="0.5" strokeWidth="1.200" />
    <rect x="2.500" y="2.500" width="15" height="8" rx="1.800" fill={color} />
    <path d="M24 4.500v4" stroke={color} strokeOpacity="0.5" strokeWidth="1.600" strokeLinecap="round" />
  </svg>
);

/** The colours people's pictures are drawn in: a ground and the figure on it. */
export const peopleColours = [
  { ground: "#e2725b", figure: "#fbe1d9" },
  { ground: "#2a9d8f", figure: "#d3f1ec" },
  { ground: "#7667d9", figure: "#e3defb" },
  { ground: "#d9992b", figure: "#fbecc9" },
  { ground: "#3b82c4", figure: "#dbeafa" },
  { ground: "#5f8f6b", figure: "#dcefdf" },
];

/** A person's picture: a plain figure, head and shoulders, on a ground of their colour. */
export const Avatar: React.FC<{ person: number; size: number; round?: boolean }> = ({ person, size, round }) => {
  const { ground, figure } = peopleColours[person % peopleColours.length];
  return (
    <div style={{ width: size, height: size, borderRadius: round ? size : Math.max(3, size * 0.16), overflow: "hidden", flexShrink: 0 }}>
      <svg width={size} height={size} viewBox="0 0 36 36" style={{ display: "block" }}>
        <rect width="36" height="36" fill={ground} />
        <circle cx="18" cy="14.500" r="6.500" fill={figure} />
        <path d="M5.500 36c0-7.600 5.600-12 12.500-12s12.500 4.400 12.500 12z" fill={figure} />
      </svg>
    </div>
  );
};

/** The colours of the three buttons at a window's top left: plain red, yellow and green. */
const buttonColours = ["#e5534b", "#f2b93b", "#3fb950"];

/** The three buttons at a window's top left: plain circles, with nothing drawn in them. */
export const WindowButtons: React.FC = () => (
  <div style={{ display: "flex", gap: 8 }}>
    {buttonColours.map((colour) => (
      <div key={colour} style={{ width: 12, height: 12, borderRadius: 6, background: colour, boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.12)" }} />
    ))}
  </div>
);

/**
 * What has been written in a field, with the insertion point after it. The insertion point stays
 * with the last word when the text wraps.
 */
export const Typed: React.FC<{ text: string | null; caretShown: boolean; color: string; caretHeight?: number; placeholder?: React.ReactNode }> = ({
  text,
  caretShown,
  color,
  caretHeight,
  placeholder,
}) => {
  if (!text) {
    return (
      <>
        <Caret shown={caretShown} color={color} height={caretHeight} />
        {placeholder}
      </>
    );
  }
  const cut = text.lastIndexOf(" ") + 1;
  return (
    <>
      {text.slice(0, cut)}
      <span style={{ whiteSpace: "nowrap" }}>
        {text.slice(cut)}
        <Caret shown={caretShown} color={color} height={caretHeight} after />
      </span>
    </>
  );
};

/** The insertion point. */
export const Caret: React.FC<{ shown: boolean; color: string; height?: number; after?: boolean }> = ({ shown, color, height = 18, after }) => (
  <span
    style={{
      display: "inline-block",
      width: 1.5,
      height,
      marginLeft: after ? 1 : 0,
      verticalAlign: -3.5,
      borderRadius: 0.75,
      background: color,
      opacity: shown ? 1 : 0,
    }}
  />
);

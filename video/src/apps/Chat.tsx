import React from "react";
import { Rect } from "../placement";
import { WindowButtons } from "../Glyphs";
import { PRODUCT_NAME } from "../script";
import {
  ArrowLeft,
  ArrowRight,
  BellGlyph,
  BubblesGlyph,
  BulletsGlyph,
  CaretDown,
  ChevronDown,
  ClockGlyph,
  CodeBlockGlyph,
  CodeGlyph,
  ComposeGlyph,
  DotsGlyph,
  FaceGlyph,
  HeadphonesGlyph,
  HelpGlyph,
  HomeGlyph,
  LayersGlyph,
  LinkGlyph,
  MentionGlyph,
  MessageGlyph,
  MicOutline,
  NumbersGlyph,
  PinGlyph,
  PlaneFilled,
  PlaneGlyph,
  PlusGlyph,
  QuoteGlyph,
  SearchGlyph,
  SlashGlyph,
  ThreadsGlyph,
  VideoGlyph,
} from "./ChatGlyphs";

// The team chat: a mock-up of a team chat's desktop client, laid out the way such clients are
// and at their sizes. A bar with a search field across the top, a rail down the left edge, a
// sidebar of channels and people, and the channel itself: its header and tabs, its messages, and
// the box to write in.
//
// Everything written in it is made up, the pictures of people are drawn figures, and every
// control is drawn in ChatGlyphs.tsx. Nothing in it is another app's name, logo or
// artwork. All lengths are in points.

export const chat = { width: 1000, height: 650 };

/** The team chat's own typeface, with emoji from an open set. */
const chatFont = '"Lato", "Noto Color Emoji", sans-serif';

/**
 * The colours of the team chat, chosen for the film. The bar, the rail and the sidebar are a warm
 * brown, which no well-known chat client has as its own; the pane with the messages is plain.
 */
const palette = {
  /** The bar across the top and the rail down the left edge. */
  frame: "#47251b",
  sidebar: "#5a3024",
  /** Text and icons on the frame and the sidebar: plain, sitting back, and further back. */
  onDark: "#ffffff",
  onDarkMuted: "rgba(255,255,255,0.74)",
  onDarkFaint: "rgba(255,255,255,0.52)",
  /** A quiet ground on the frame: the search field, a button. */
  onDarkBlock: "rgba(255,255,255,0.18)",
  /** The selected row of the sidebar. */
  selected: "#f6e8dc",
  onSelected: "#47251b",
  /** The count beside an unread row. */
  badge: "#d9534a",
  /** Someone who is here. */
  present: "#3fae78",
  /** The pane with the messages. */
  pane: "#ffffff",
  ink: "#1c1b1f",
  muted: "#66636b",
  faint: "rgba(28,27,31,0.5)",
  hairline: "rgba(28,27,31,0.13)",
  /** A quiet ground on the pane: a reaction, a round button. */
  block: "rgba(28,27,31,0.06)",
  /** Links and the count of replies. */
  link: "#1b6aae",
  /** A reaction the reader has added: its ground and its edge. */
  reacted: "#e4f1fb",
  reactedEdge: "#2b8bd0",
  /** The edge of the box being typed into. */
  field: "rgba(28,27,31,0.42)",
  /** Each person's picture: its ground and the figure drawn on it. */
  people: [
    { ground: "#e2725b", figure: "#fbe1d9" },
    { ground: "#2a9d8f", figure: "#d3f1ec" },
    { ground: "#7667d9", figure: "#e3defb" },
    { ground: "#d9992b", figure: "#fbecc9" },
    { ground: "#3b82c4", figure: "#dbeafa" },
    { ground: "#5f8f6b", figure: "#dcefdf" },
  ],
};

type ChatPalette = typeof palette;

/** The app's tile in the Dock, in the same brown. */
export const chatTile = "linear-gradient(180deg, #8b5240, #5a3024)";

const topBar = 38;
const rail = 64;
const sidebar = 210;
const paneLeft = rail + sidebar;
const channelHeader = 49;
const tabs = 37;

/** The parts of the box being typed into: its formatting row, its line of text, its action row. */
const formattingRow = 38;
const textPadding = 8;
const lineHeight = 22;
const actionRow = 40;

/** The box being typed into. */
export const field: Rect = {
  left: paneLeft + 20,
  top: chat.height - 24 - (formattingRow + textPadding * 2 + lineHeight + actionRow),
  width: chat.width - paneLeft - 40,
  height: formattingRow + textPadding * 2 + lineHeight + actionRow,
};

/** The line the insertion point is on, as the chat app would report it: it has no width. */
export const insertionPoint: Rect = {
  left: field.left + 12,
  top: field.top + formattingRow + textPadding,
  width: 0,
  height: lineHeight,
};

/** From the last message to the box. */
const messagesToField = 12;

const workspace = PRODUCT_NAME;
const channel = "website";
const people = ["Maya", "Jonas", "Priya", "Noor", "You", "Tomas"];
const me = 4;

type Reaction = { emoji: string; count: number; mine?: boolean };
type Message = {
  from: number;
  at: string;
  text: string;
  reactions?: Reaction[];
  thread?: { from: number[]; replies: number; last: string };
};

/** Yesterday's last message, most of which has scrolled out of sight. */
const earlier: Message = {
  from: 3,
  at: "4:47 PM",
  text: "The pricing mockups are in the shared folder.",
  reactions: [{ emoji: "\u{1F440}", count: 2 }],
};

const today: Message[] = [
  {
    from: 0,
    at: "10:38 AM",
    text: "Morning! The new homepage goes live Thursday.",
    reactions: [
      { emoji: "\u{1F389}", count: 3, mine: true },
      { emoji: "\u{1F680}", count: 2 },
    ],
  },
  {
    from: 2,
    at: "10:40 AM",
    text: "The hero image looks great.",
    thread: { from: [0, 5], replies: 2, last: "Last reply today at 10:41 AM" },
  },
  { from: 1, at: "10:42 AM", text: "Can you review the onboarding copy before the 3 PM sync?" },
];

const channels: { name: string; unread?: boolean; count?: number }[] = [
  { name: "general" },
  { name: "design", unread: true },
  { name: "website" },
  { name: "random" },
  { name: "support", unread: true, count: 2 },
];

const directs: { person: number; here: boolean; unread?: boolean; count?: number }[] = [
  { person: 0, here: true },
  { person: 1, here: true },
  { person: 2, here: false, unread: true, count: 1 },
  { person: 3, here: false },
];

/** A person's picture: a plain figure, head and shoulders, on a ground of their colour. */
const Picture: React.FC<{ colours: ChatPalette; person: number; size: number }> = ({ colours, person, size }) => {
  const { ground, figure } = colours.people[person];
  return (
    <div style={{ width: size, height: size, borderRadius: Math.max(3, size * 0.16), overflow: "hidden", flexShrink: 0 }}>
      <svg width={size} height={size} viewBox="0 0 36 36" style={{ display: "block" }}>
        <rect width="36" height="36" fill={ground} />
        <circle cx="18" cy="14.5" r="6.5" fill={figure} />
        <path d="M5.5 36c0-7.6 5.6-12 12.5-12s12.5 4.4 12.5 12z" fill={figure} />
      </svg>
    </div>
  );
};

/** Here or away: a filled dot or a ring, at the corner of a picture. */
const Presence: React.FC<{ colours: ChatPalette; here: boolean; ground: string; size?: number }> = ({ colours, here, ground, size = 9 }) => (
  <div
    style={{
      position: "absolute",
      right: -3,
      bottom: -3,
      width: size,
      height: size,
      borderRadius: size,
      boxSizing: "border-box",
      background: here ? colours.present : ground,
      border: here ? "none" : `1.5px solid ${colours.onDarkMuted}`,
      boxShadow: `0 0 0 2px ${ground}`,
    }}
  />
);

const Badge: React.FC<{ colours: ChatPalette; count: number }> = ({ colours, count }) => (
  <div
    style={{
      marginLeft: "auto",
      minWidth: 18,
      height: 18,
      padding: "0 6px",
      boxSizing: "border-box",
      borderRadius: 9,
      background: colours.badge,
      color: "#ffffff",
      fontSize: 12,
      fontWeight: 700,
      lineHeight: "18px",
      textAlign: "center",
    }}
  >
    {count}
  </div>
);

const TopBar: React.FC<{ colours: ChatPalette }> = ({ colours }) => (
  <div style={{ position: "absolute", left: 0, top: 0, width: "100%", height: topBar, background: colours.frame }}>
    <div style={{ position: "absolute", left: 14, top: 13 }}>
      <WindowButtons />
    </div>
    <div style={{ position: "absolute", left: 230, top: 0, height: topBar, display: "flex", alignItems: "center", gap: 10 }}>
      <ArrowLeft size={16} color={colours.onDarkMuted} />
      <ArrowRight size={16} color={colours.onDarkFaint} />
      <ClockGlyph size={16} color={colours.onDarkMuted} />
    </div>
    <div
      style={{
        position: "absolute",
        left: 314,
        top: 6,
        width: 372,
        height: 26,
        boxSizing: "border-box",
        padding: "0 9px",
        borderRadius: 6,
        background: colours.onDarkBlock,
        display: "flex",
        alignItems: "center",
        gap: 7,
        fontSize: 13,
        color: colours.onDarkMuted,
      }}
    >
      <SearchGlyph size={14} color={colours.onDarkMuted} />
      Search {workspace}
    </div>
    <HelpGlyph size={17} color={colours.onDarkMuted} style={{ position: "absolute", right: 14, top: 10.5 }} />
  </div>
);

const Rail: React.FC<{ colours: ChatPalette }> = ({ colours }) => {
  const places: { name: string; icon: React.ReactNode; here?: boolean }[] = [
    { name: "Home", icon: <HomeGlyph size={18} color={colours.onDark} />, here: true },
    { name: "DMs", icon: <BubblesGlyph size={18} color={colours.onDark} /> },
    { name: "Activity", icon: <BellGlyph size={18} color={colours.onDark} /> },
    { name: "More", icon: <DotsGlyph size={18} color={colours.onDark} /> },
  ];
  const tile: React.CSSProperties = { width: 36, height: 36, borderRadius: 9, display: "flex", alignItems: "center", justifyContent: "center" };
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        top: topBar,
        width: rail,
        bottom: 0,
        background: colours.frame,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
      }}
    >
      <div style={{ ...tile, marginTop: 4, background: colours.selected, color: colours.onSelected, fontSize: 18, fontWeight: 900 }}>
        {workspace[0]}
      </div>
      <div style={{ marginTop: 14, display: "flex", flexDirection: "column", alignItems: "center", gap: 9 }}>
        {places.map((place) => (
          <div key={place.name} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 3 }}>
            <div style={{ ...tile, background: place.here ? colours.onDarkBlock : "none" }}>{place.icon}</div>
            <div style={{ fontSize: 10.5, fontWeight: 700, lineHeight: "13px", color: colours.onDark }}>{place.name}</div>
          </div>
        ))}
      </div>
      <div style={{ marginTop: "auto", marginBottom: 14, display: "flex", flexDirection: "column", alignItems: "center", gap: 12 }}>
        <div style={{ ...tile, borderRadius: 18, background: colours.onDarkBlock }}>
          <PlusGlyph size={17} color={colours.onDark} />
        </div>
        <div style={{ position: "relative" }}>
          <Picture colours={colours} person={me} size={36} />
          <Presence colours={colours} here ground={colours.frame} size={11} />
        </div>
      </div>
    </div>
  );
};

const Sidebar: React.FC<{ colours: ChatPalette }> = ({ colours }) => {
  const row: React.CSSProperties = {
    height: 28,
    margin: "0 8px",
    padding: "0 8px",
    borderRadius: 6,
    display: "flex",
    alignItems: "center",
    gap: 8,
    color: colours.onDarkMuted,
  };
  const unread: React.CSSProperties = { color: colours.onDark, fontWeight: 900 };
  const section: React.CSSProperties = { height: 28, padding: "0 12px", marginTop: 12, display: "flex", alignItems: "center", gap: 4, color: colours.onDarkMuted };
  const mark: React.CSSProperties = { width: 16, textAlign: "center", flexShrink: 0 };
  return (
    <div
      style={{
        position: "absolute",
        left: rail,
        top: topBar,
        width: sidebar,
        bottom: 0,
        background: colours.sidebar,
        borderTopLeftRadius: 8,
        fontSize: 15,
      }}
    >
      <div style={{ height: channelHeader, padding: "0 12px 0 16px", display: "flex", alignItems: "center", gap: 4, color: colours.onDark }}>
        <span style={{ fontSize: 18, fontWeight: 900 }}>{workspace}</span>
        <ChevronDown size={14} color={colours.onDark} />
        <div
          style={{
            marginLeft: "auto",
            width: 30,
            height: 30,
            borderRadius: 8,
            background: colours.onDarkBlock,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <ComposeGlyph size={17} color={colours.onDark} />
        </div>
      </div>

      <div style={row}>
        <ThreadsGlyph size={16} color={colours.onDarkMuted} />
        Threads
      </div>
      <div style={row}>
        <HeadphonesGlyph size={16} color={colours.onDarkMuted} />
        Calls
      </div>
      <div style={row}>
        <PlaneGlyph size={16} color={colours.onDarkMuted} />
        Drafts &amp; sent
      </div>

      <div style={section}>
        <CaretDown size={12} color={colours.onDarkMuted} />
        Channels
      </div>
      {channels.map((item) => (
        <div
          key={item.name}
          style={{
            ...row,
            ...(item.unread ? unread : null),
            ...(item.name === channel ? { background: colours.selected, color: colours.onSelected } : null),
          }}
        >
          <span style={mark}>#</span>
          {item.name}
          {item.count ? <Badge colours={colours} count={item.count} /> : null}
        </div>
      ))}
      <div style={row}>
        <div style={{ ...mark, height: 16, borderRadius: 4, background: colours.onDarkBlock, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <PlusGlyph size={11} color={colours.onDarkMuted} />
        </div>
        Add channels
      </div>

      <div style={section}>
        <CaretDown size={12} color={colours.onDarkMuted} />
        Direct messages
      </div>
      {directs.map((item) => (
        <div key={item.person} style={{ ...row, ...(item.unread ? unread : null) }}>
          <div style={{ position: "relative", width: 20, height: 20, marginRight: 2, flexShrink: 0 }}>
            <Picture colours={colours} person={item.person} size={20} />
            <Presence colours={colours} here={item.here} ground={colours.sidebar} />
          </div>
          {people[item.person]}
          {item.count ? <Badge colours={colours} count={item.count} /> : null}
        </div>
      ))}
    </div>
  );
};

const Header: React.FC<{ colours: ChatPalette }> = ({ colours }) => {
  const button: React.CSSProperties = {
    height: 28,
    boxSizing: "border-box",
    borderRadius: 6,
    border: `1px solid ${colours.hairline}`,
    display: "flex",
    alignItems: "center",
  };
  const tab: React.CSSProperties = { height: tabs, boxSizing: "border-box", display: "flex", alignItems: "center", gap: 5, color: colours.muted };
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: paneLeft,
          right: 0,
          top: topBar,
          height: channelHeader,
          boxSizing: "border-box",
          padding: "0 16px 0 20px",
          display: "flex",
          alignItems: "center",
          gap: 8,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 4, fontSize: 18, fontWeight: 900 }}>
          # {channel}
          <ChevronDown size={14} color={colours.muted} />
        </div>
        {/* Who is in the channel: three pictures and a count. */}
        <div style={{ ...button, marginLeft: "auto", padding: "0 8px 0 3px", fontSize: 13, fontWeight: 700, color: colours.muted }}>
          {[0, 1, 2].map((person, index) => (
            <div key={person} style={{ marginLeft: index ? -6 : 0, borderRadius: 5, boxShadow: `0 0 0 2px ${colours.pane}`, zIndex: 3 - index }}>
              <Picture colours={colours} person={person} size={22} />
            </div>
          ))}
          <span style={{ marginLeft: 7 }}>8</span>
        </div>
        <div style={{ ...button, width: 30, justifyContent: "center" }}>
          <HeadphonesGlyph size={16} color={colours.muted} />
        </div>
        <DotsGlyph size={18} color={colours.muted} upright />
      </div>
      <div
        style={{
          position: "absolute",
          left: paneLeft,
          right: 0,
          top: topBar + channelHeader,
          height: tabs,
          boxSizing: "border-box",
          padding: "0 20px",
          display: "flex",
          alignItems: "center",
          gap: 18,
          borderBottom: `1px solid ${colours.hairline}`,
          fontSize: 13,
          fontWeight: 700,
        }}
      >
        <div style={{ ...tab, color: colours.ink, borderBottom: `2px solid ${colours.ink}`, paddingTop: 2 }}>
          <MessageGlyph size={15} color={colours.ink} />
          Messages
        </div>
        <div style={tab}>
          <LayersGlyph size={15} color={colours.muted} />
          Files
        </div>
        <div style={tab}>
          <PinGlyph size={15} color={colours.muted} />
          Pins
        </div>
        <PlusGlyph size={14} color={colours.muted} />
      </div>
    </>
  );
};

const Row: React.FC<{ colours: ChatPalette; message: Message; last?: boolean }> = ({ colours, message, last }) => (
  <div style={{ flexShrink: 0, padding: `8px 20px ${last ? 0 : 8}px`, display: "flex", gap: 8 }}>
    <div style={{ marginTop: 3 }}>
      <Picture colours={colours} person={message.from} size={36} />
    </div>
    <div>
      <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
        <span style={{ fontWeight: 900 }}>{people[message.from]}</span>
        <span style={{ fontSize: 12, color: colours.muted }}>{message.at}</span>
      </div>
      <div>{message.text}</div>
      {message.reactions ? (
        <div style={{ marginTop: 4, display: "flex", gap: 4 }}>
          {message.reactions.map((reaction) => (
            <div
              key={reaction.emoji}
              style={{
                height: 24,
                boxSizing: "border-box",
                padding: "0 7px",
                borderRadius: 12,
                background: reaction.mine ? colours.reacted : colours.block,
                border: `1px solid ${reaction.mine ? colours.reactedEdge : "transparent"}`,
                display: "flex",
                alignItems: "center",
                gap: 4,
                fontSize: 12,
                fontWeight: reaction.mine ? 700 : 400,
                color: reaction.mine ? colours.link : colours.muted,
                lineHeight: "22px",
              }}
            >
              <span style={{ fontSize: 14 }}>{reaction.emoji}</span>
              {reaction.count}
            </div>
          ))}
        </div>
      ) : null}
      {message.thread ? (
        <div style={{ marginTop: 4, height: 28, display: "flex", alignItems: "center", gap: 4, fontSize: 13 }}>
          {message.thread.from.map((person) => (
            <Picture key={person} colours={colours} person={person} size={24} />
          ))}
          <span style={{ marginLeft: 4, fontWeight: 700, color: colours.link }}>{message.thread.replies} replies</span>
          <span style={{ marginLeft: 2, color: colours.muted }}>{message.thread.last}</span>
        </div>
      ) : null}
    </div>
  </div>
);

const Messages: React.FC<{ colours: ChatPalette }> = ({ colours }) => (
  <div
    style={{
      position: "absolute",
      left: paneLeft,
      right: 0,
      top: topBar + channelHeader + tabs,
      bottom: chat.height - field.top + messagesToField,
      overflow: "hidden",
      display: "flex",
      flexDirection: "column",
      justifyContent: "flex-end",
    }}
  >
    <Row colours={colours} message={earlier} />
    <div style={{ flexShrink: 0, height: 40, position: "relative" }}>
      <div style={{ position: "absolute", left: 0, right: 0, top: 20, height: 1, background: colours.hairline }} />
      <div
        style={{
          position: "absolute",
          left: "50%",
          top: 6,
          transform: "translateX(-50%)",
          height: 28,
          boxSizing: "border-box",
          padding: "0 10px 0 14px",
          borderRadius: 14,
          border: `1px solid ${colours.hairline}`,
          background: colours.pane,
          display: "flex",
          alignItems: "center",
          gap: 3,
          fontSize: 13,
          fontWeight: 700,
        }}
      >
        Today
        <ChevronDown size={13} color={colours.ink} />
      </div>
    </div>
    {today.map((message, index) => (
      <Row key={message.at} colours={colours} message={message} last={index === today.length - 1} />
    ))}
  </div>
);

const Gap: React.FC<{ colours: ChatPalette }> = ({ colours }) => (
  <div style={{ width: 1, height: 18, margin: "0 4px", background: colours.hairline }} />
);

const Field: React.FC<{ colours: ChatPalette; text: string | null; caretShown: boolean }> = ({ colours, text, caretShown }) => {
  const quiet = colours.muted;
  const cell: React.CSSProperties = { width: 28, height: 28, display: "flex", alignItems: "center", justifyContent: "center", color: quiet, fontSize: 15 };
  const icon = { size: 17, color: quiet };
  return (
    <div
      style={{
        position: "absolute",
        ...field,
        boxSizing: "border-box",
        borderRadius: 8,
        border: `1px solid ${colours.field}`,
        background: colours.pane,
      }}
    >
      <div style={{ position: "absolute", left: 6, top: 0, height: formattingRow, display: "flex", alignItems: "center", opacity: 0.8 }}>
        <div style={{ ...cell, fontWeight: 900 }}>B</div>
        <div style={{ ...cell, fontStyle: "italic" }}>I</div>
        <div style={{ ...cell, textDecoration: "underline", textUnderlineOffset: 2 }}>U</div>
        <div style={{ ...cell, textDecoration: "line-through" }}>S</div>
        <Gap colours={colours} />
        <div style={cell}>
          <LinkGlyph {...icon} />
        </div>
        <Gap colours={colours} />
        <div style={cell}>
          <NumbersGlyph {...icon} />
        </div>
        <div style={cell}>
          <BulletsGlyph {...icon} />
        </div>
        <Gap colours={colours} />
        <div style={cell}>
          <QuoteGlyph {...icon} />
        </div>
        <Gap colours={colours} />
        <div style={cell}>
          <CodeGlyph {...icon} />
        </div>
        <div style={cell}>
          <CodeBlockGlyph {...icon} />
        </div>
      </div>

      <div
        style={{
          position: "absolute",
          left: insertionPoint.left - field.left - 1,
          top: insertionPoint.top - field.top - 1,
          height: lineHeight,
          whiteSpace: "nowrap",
        }}
      >
        {/* The text is pasted, so it is simply there. */}
        {text}
        <span
          style={{
            display: "inline-block",
            width: 1.5,
            height: 18,
            marginLeft: text ? 1 : 0,
            verticalAlign: -3.5,
            borderRadius: 0.75,
            background: colours.ink,
            opacity: caretShown ? 1 : 0,
          }}
        />
        {text ? null : <span style={{ color: colours.faint }}>Message #{channel}</span>}
      </div>

      <div style={{ position: "absolute", left: 6, bottom: 0, height: actionRow, display: "flex", alignItems: "center" }}>
        <div style={{ ...cell, borderRadius: 14, background: colours.block, marginRight: 4 }}>
          <PlusGlyph size={15} color={quiet} />
        </div>
        <div style={{ ...cell, fontSize: 14, fontWeight: 700, textDecoration: "underline", textUnderlineOffset: 2 }}>Aa</div>
        <div style={cell}>
          <FaceGlyph {...icon} />
        </div>
        <div style={cell}>
          <MentionGlyph {...icon} />
        </div>
        <Gap colours={colours} />
        <div style={cell}>
          <VideoGlyph {...icon} />
        </div>
        <div style={cell}>
          <MicOutline {...icon} />
        </div>
        <Gap colours={colours} />
        <div style={cell}>
          <SlashGlyph {...icon} />
        </div>
      </div>

      {/* The send button, quiet until there is something to send. */}
      <div
        style={{
          position: "absolute",
          right: 6,
          bottom: 6,
          width: 34,
          height: 28,
          borderRadius: 6,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          // The sidebar's brown: the window's own colour.
          background: text ? colours.sidebar : "none",
        }}
      >
        <PlaneFilled size={16} color={text ? "#ffffff" : colours.faint} />
      </div>
    </div>
  );
};

/**
 * The window. `text` is what has been written in the box, or null while it is empty, and
 * `caretShown` whether the caret is in the lit half of its blink.
 */
export const ChatWindow: React.FC<{ text: string | null; caretShown: boolean }> = ({ text, caretShown }) => {
  const colours = palette;
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        top: 0,
        width: chat.width,
        height: chat.height,
        borderRadius: 10,
        overflow: "hidden",
        background: colours.frame,
        color: colours.ink,
        fontFamily: chatFont,
        fontSize: 15,
        lineHeight: `${lineHeight}px`,
      }}
    >
      <div style={{ position: "absolute", left: paneLeft, top: topBar, right: 0, bottom: 0, background: colours.pane }} />
      <TopBar colours={colours} />
      <Rail colours={colours} />
      <Sidebar colours={colours} />
      <Header colours={colours} />
      <Messages colours={colours} />
      <Field colours={colours} text={text} caretShown={caretShown} />
    </div>
  );
};

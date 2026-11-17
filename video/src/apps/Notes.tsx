import React from "react";
import { Rect } from "../placement";
import { Glyph, GlyphName, Typed, WindowButtons } from "../Glyphs";
import { AppProps, ui, uiFont } from "./types";

// The notes app: a mock-up with folders down the side, the list of notes, and the open note.
// The notes are made up, and nothing here is another app's name, logo or artwork. All lengths
// are in points.

export const size = { width: 980, height: 640 };

/** A unified toolbar, as tall as a Mac's. */
const toolbar = 52;
const sidebar = 170;
const list = 250;
const editorLeft = sidebar + list;
const textLeft = editorLeft + 44;
const bullet = 16;
const lineHeight = 24;

/** The note's lines, by their distance from the top of the window. */
const titleTop = 96;
const firstLine = 150;

/** The open note, all of which can be typed into. */
export const field: Rect = { left: editorLeft, top: toolbar, width: size.width - editorLeft, height: size.height - toolbar };

type NoteLine = { text: string; heading?: boolean; gap?: number };
const note: NoteLine[] = [
  { text: "Pricing page", heading: true },
  { text: "Annual toggle is easy to miss" },
  { text: "Add a comparison table under the plans" },
  { text: "Next steps", heading: true, gap: 14 },
  { text: "Share the new mockups on Thursday" },
];

/** Where each line of the note starts, and where the line being dictated goes: after the last. */
const tops: number[] = [];
let top = firstLine;
for (const entry of note) {
  top += entry.gap ?? 0;
  tops.push(top);
  top += lineHeight;
}
export const line: Rect = { left: textLeft + bullet, top, width: 0, height: lineHeight };

const accent = "#1f8a7a";

const folders: { name: string; count: number; selected?: boolean }[] = [
  { name: "All Notes", count: 42 },
  { name: "Work", count: 18, selected: true },
  { name: "Personal", count: 11 },
  { name: "Recipes", count: 6 },
  { name: "Travel", count: 4 },
];

type Entry = { title: string; at: string; preview: string; selected?: boolean; group?: string };
const notes: Entry[] = [
  { title: "1:1 with Priya", at: "10:40 AM", preview: "Pricing page", selected: true, group: "Today" },
  { title: "Launch checklist", at: "9:12 AM", preview: "Homepage, pricing, email" },
  { title: "Reading list", at: "Tuesday", preview: "Three pieces on onboarding", group: "Previous 7 Days" },
  { title: "Offsite ideas", at: "Monday", preview: "Cabin, hike, long dinner" },
  { title: "Hiring plan", at: "Sunday", preview: "Two designers, one writer" },
];

export const NotesWindow: React.FC<AppProps> = ({ text, caretShown }) => {
  const tool = (name: GlyphName) => <Glyph name={name} size={17} color={ui.muted} />;
  return (
    <div style={{ position: "absolute", inset: 0, background: ui.window, color: ui.ink, fontFamily: uiFont, fontSize: 13, lineHeight: "18px" }}>
      <div style={{ position: "absolute", left: 0, top: 0, width: sidebar, bottom: 0, background: ui.sidebar, borderRight: `1px solid ${ui.hairline}`, boxSizing: "border-box" }}>
        <div style={{ position: "absolute", left: 20, top: 20 }}>
          <WindowButtons />
        </div>
        <div style={{ marginTop: toolbar + 6 }}>
          <div style={{ padding: "0 16px", height: 24, fontSize: 11, fontWeight: 600, color: ui.faint, display: "flex", alignItems: "center" }}>Folders</div>
          {folders.map((folder) => (
            <div
              key={folder.name}
              style={{
                height: 28,
                margin: "0 8px",
                padding: "0 8px",
                borderRadius: 6,
                display: "flex",
                alignItems: "center",
                gap: 8,
                background: folder.selected ? ui.selected : "none",
                fontWeight: folder.selected ? 600 : 400,
              }}
            >
              <Glyph name="folder" size={16} color={accent} weight={1.4} />
              {folder.name}
              <span style={{ marginLeft: "auto", fontSize: 12, fontWeight: 400, color: ui.muted }}>{folder.count}</span>
            </div>
          ))}
        </div>
        <div style={{ position: "absolute", left: 16, bottom: 14, display: "flex", alignItems: "center", gap: 6, color: ui.muted }}>
          <Glyph name="plus" size={14} color={ui.muted} />
          New Folder
        </div>
      </div>

      <div style={{ position: "absolute", left: sidebar, top: 0, right: 0, height: toolbar, borderBottom: `1px solid ${ui.hairline}`, boxSizing: "border-box", background: ui.bar }}>
        <div style={{ position: "absolute", left: 16, top: 0, height: toolbar, display: "flex", alignItems: "center", gap: 16 }}>
          {tool("list")}
          {tool("grid")}
        </div>
        <div style={{ position: "absolute", left: list - 34, top: 0, height: toolbar, display: "flex", alignItems: "center" }}>{tool("trash")}</div>
        <div style={{ position: "absolute", left: list + 20, top: 0, height: toolbar, display: "flex", alignItems: "center", gap: 18 }}>
          {tool("compose")}
          <div style={{ width: 1, height: 18, background: ui.hairline }} />
          {tool("bold")}
          {tool("checklist")}
          {tool("table")}
          {tool("image")}
        </div>
        <div style={{ position: "absolute", right: 14, top: 0, height: toolbar, display: "flex", alignItems: "center", gap: 16 }}>
          {tool("lock")}
          {tool("share")}
          <div style={{ width: 150, height: 26, boxSizing: "border-box", padding: "0 8px", borderRadius: 7, background: ui.block, display: "flex", alignItems: "center", gap: 6, color: ui.faint }}>
            <Glyph name="search" size={14} color={ui.faint} />
            Search
          </div>
        </div>
      </div>

      <div style={{ position: "absolute", left: sidebar, top: toolbar, width: list, bottom: 0, borderRight: `1px solid ${ui.hairline}`, boxSizing: "border-box" }}>
        {notes.map((entry) => (
          <React.Fragment key={entry.title}>
            {entry.group ? (
              <div style={{ height: 34, padding: "12px 20px 0", boxSizing: "border-box", fontSize: 12, fontWeight: 600, color: ui.muted }}>{entry.group}</div>
            ) : null}
            <div
              style={{
                height: 58,
                margin: "0 8px",
                padding: "10px 12px 0",
                boxSizing: "border-box",
                borderRadius: 8,
                background: entry.selected ? "rgba(31,138,122,0.16)" : "none",
                boxShadow: entry.selected ? "none" : `0 1px 0 ${ui.hairline}`,
              }}
            >
              <div style={{ fontWeight: 600 }}>{entry.title}</div>
              {/* One line, ending in an ellipsis when the preview is longer than the row. */}
              <div style={{ color: ui.muted, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                <span style={{ color: ui.ink }}>{entry.at}</span>&nbsp;&nbsp;{entry.preview}
              </div>
            </div>
          </React.Fragment>
        ))}
      </div>

      {/* The open note. */}
      <div style={{ position: "absolute", left: editorLeft, right: 0, top: toolbar + 14, textAlign: "center", fontSize: 12, color: ui.faint }}>Today at 10:40 AM</div>
      <div style={{ position: "absolute", left: textLeft, top: titleTop, fontSize: 26, lineHeight: "32px", fontWeight: 700 }}>1:1 with Priya</div>
      {note.map((entry, index) => (
        <div
          key={entry.text}
          style={{
            position: "absolute",
            left: textLeft,
            top: tops[index],
            height: lineHeight,
            display: "flex",
            fontSize: 15,
            lineHeight: `${lineHeight}px`,
            fontWeight: entry.heading ? 600 : 400,
          }}
        >
          {entry.heading ? null : <span style={{ width: bullet, color: ui.muted }}>•</span>}
          {entry.text}
        </div>
      ))}
      <div style={{ position: "absolute", left: textLeft, top: line.top, width: bullet, fontSize: 15, lineHeight: `${lineHeight}px`, color: ui.muted }}>•</div>
      {/* The caret stands a point left of where the text begins, as it does before a first letter. */}
      <div style={{ position: "absolute", left: line.left - (text ? 0 : 1), top: line.top, fontSize: 15, lineHeight: `${lineHeight}px`, whiteSpace: "nowrap" }}>
        <Typed text={text} caretShown={caretShown} color={ui.ink} />
      </div>
    </div>
  );
};

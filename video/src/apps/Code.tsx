import React from "react";
import { Rect } from "../placement";
import { Glyph, GlyphName, Typed, WindowButtons } from "../Glyphs";
import { AppProps, codeFont, ui, uiFont } from "./types";

// The code editor: a mock-up of an editor with a coding agent beside the code. A file tree, a
// file of TypeScript, and a panel in which the agent is asked for changes. The project, the
// code and the conversation are made up, and nothing here is another app's name, logo or
// artwork. All lengths are in points.

export const size = { width: 1060, height: 664 };

const titleBar = 38;
const statusBar = 24;
const activity = 44;
const explorer = 180;
const panel = 330;
const panelLeft = size.width - panel;
const tabs = 34;

/** The box the agent is asked in. */
export const field: Rect = { left: panelLeft + 12, top: size.height - statusBar - 12 - 108, width: panel - 24, height: 108 };
export const line: Rect = { left: field.left + 12, top: field.top + 10, width: 0, height: 20 };

const accent = "#2f6fdd";
const syntax = { keyword: "#a033b8", string: "#2f7d4f", call: "#2563b0", type: "#b0621a", number: "#b0621a", plain: ui.ink };

const code = [
  'import { api } from "./api";',
  "",
  "const CHUNK = 5 * 1024 * 1024;",
  "",
  "export async function uploadFile(file: File) {",
  "  const session = await api.createSession(file.name);",
  "",
  "  for (let at = 0; at < file.size; at += CHUNK) {",
  "    const part = file.slice(at, at + CHUNK);",
  "    await uploadPart(session.id, part, at);",
  "  }",
  "",
  "  return api.complete(session.id);",
  "}",
  "",
  "async function uploadPart(id: string, part: Blob, at = 0) {",
  "  const sent = await api.put(`/parts/${id}`, part, { at });",
  "  if (!sent.ok) {",
  "    throw new Error(`Upload failed at byte ${at}`);",
  "  }",
  "}",
];

const token = /(`[^`]*`|"[^"]*"|\b(?:import|from|const|export|async|function|for|let|await|return|if|throw|new)\b|\b(?:File|Blob|Error|string|number)\b|\b\d+\b|\b[A-Za-z_]\w*(?=\())/g;
const keywords = new Set(["import", "from", "const", "export", "async", "function", "for", "let", "await", "return", "if", "throw", "new"]);
const types = new Set(["File", "Blob", "Error", "string", "number"]);

const colourOf = (part: string): string => {
  if (part.startsWith("`") || part.startsWith('"')) {
    return syntax.string;
  }
  if (keywords.has(part)) {
    return syntax.keyword;
  }
  if (types.has(part)) {
    return syntax.type;
  }
  if (/^\d+$/.test(part)) {
    return syntax.number;
  }
  return /^[A-Za-z_]\w*$/.test(part) ? syntax.call : syntax.plain;
};

const CodeLine: React.FC<{ text: string }> = ({ text }) => (
  <>
    {text.split(token).map((part, index) =>
      // Every second part is a match of `token`.
      index % 2 === 1 ? (
        <span key={index} style={{ color: colourOf(part) }}>
          {part}
        </span>
      ) : (
        part
      ),
    )}
  </>
);

type Entry = { name: string; depth: number; folder?: boolean; open?: boolean; selected?: boolean };
const tree: Entry[] = [
  { name: "src", depth: 0, folder: true, open: true },
  { name: "api.ts", depth: 1 },
  { name: "queue.ts", depth: 1 },
  { name: "upload.ts", depth: 1, selected: true },
  { name: "tests", depth: 0, folder: true, open: true },
  { name: "upload.test.ts", depth: 1 },
  { name: "package.json", depth: 0 },
  { name: "README.md", depth: 0 },
  { name: "tsconfig.json", depth: 0 },
];

const Chip: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div
    style={{
      height: 22,
      padding: "0 7px",
      borderRadius: 6,
      background: ui.block,
      display: "flex",
      alignItems: "center",
      gap: 3,
      fontSize: 12,
      fontWeight: 500,
      color: ui.muted,
    }}
  >
    {children}
  </div>
);

export const CodeWindow: React.FC<AppProps> = ({ text, caretShown }) => {
  const side: GlyphName[] = ["file", "search", "branch", "terminal"];
  return (
    <div style={{ position: "absolute", inset: 0, background: ui.window, color: ui.ink, fontFamily: uiFont, fontSize: 13, lineHeight: "20px" }}>
      <div
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          right: 0,
          height: titleBar,
          background: ui.bar,
          borderBottom: `1px solid ${ui.hairline}`,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: 13,
          fontWeight: 500,
          color: ui.muted,
        }}
      >
        <div style={{ position: "absolute", left: 14 }}>
          <WindowButtons />
        </div>
        uploader
        <div style={{ position: "absolute", right: 14, display: "flex", gap: 12 }}>
          <Glyph name="sidebar" size={16} color={ui.muted} />
          <Glyph name="panel" size={16} color={ui.ink} />
        </div>
      </div>

      <div
        style={{
          position: "absolute",
          left: 0,
          top: titleBar,
          width: activity,
          bottom: statusBar,
          background: ui.sidebar,
          borderRight: `1px solid ${ui.hairline}`,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 18,
          paddingTop: 14,
          boxSizing: "border-box",
        }}
      >
        {side.map((name, index) => (
          <Glyph key={name} name={name} size={19} color={index === 0 ? ui.ink : ui.faint} />
        ))}
        <Glyph name="gear" size={19} color={ui.faint} style={{ marginTop: "auto", marginBottom: 14 }} />
      </div>

      <div
        style={{
          position: "absolute",
          left: activity,
          top: titleBar,
          width: explorer,
          bottom: statusBar,
          background: ui.sidebar,
          borderRight: `1px solid ${ui.hairline}`,
          boxSizing: "border-box",
        }}
      >
        <div style={{ height: 34, padding: "0 14px", display: "flex", alignItems: "center", fontSize: 11, fontWeight: 600, letterSpacing: 0.6, color: ui.muted }}>
          UPLOADER
        </div>
        {tree.map((entry) => (
          <div
            key={entry.name}
            style={{
              height: 24,
              margin: "0 6px",
              paddingLeft: 6 + entry.depth * 14,
              borderRadius: 5,
              display: "flex",
              alignItems: "center",
              gap: 5,
              background: entry.selected ? ui.selected : "none",
              color: entry.selected ? ui.ink : ui.muted,
            }}
          >
            {entry.folder ? <Glyph name="chevronDown" size={11} color={ui.faint} /> : <div style={{ width: 11 }} />}
            <Glyph name={entry.folder ? "folder" : "file"} size={14} color={entry.selected ? ui.ink : ui.faint} weight={1.4} />
            {entry.name}
          </div>
        ))}
      </div>

      <div style={{ position: "absolute", left: activity + explorer, top: titleBar, right: panel, bottom: statusBar }}>
        <div style={{ height: tabs, display: "flex", background: ui.bar, borderBottom: `1px solid ${ui.hairline}`, boxSizing: "border-box" }}>
          {["upload.ts", "api.ts"].map((name, index) => (
            <div
              key={name}
              style={{
                padding: "0 14px",
                display: "flex",
                alignItems: "center",
                gap: 6,
                borderRight: `1px solid ${ui.hairline}`,
                background: index === 0 ? ui.window : "none",
                color: index === 0 ? ui.ink : ui.muted,
                // The open file's tab runs into the editor below it.
                marginBottom: index === 0 ? -1 : 0,
              }}
            >
              <Glyph name="file" size={13} color={index === 0 ? syntax.call : ui.faint} weight={1.4} />
              {name}
            </div>
          ))}
        </div>
        <div style={{ height: 26, padding: "0 16px", display: "flex", alignItems: "center", gap: 4, fontSize: 12, color: ui.muted }}>
          src
          <Glyph name="chevronRight" size={10} color={ui.faint} />
          upload.ts
          <Glyph name="chevronRight" size={10} color={ui.faint} />
          uploadFile
        </div>
        <div style={{ fontFamily: codeFont, fontSize: 12, lineHeight: "20px", whiteSpace: "pre" }}>
          {code.map((text, index) => (
            <div key={index} style={{ display: "flex", height: 20 }}>
              <span style={{ width: 34, textAlign: "right", marginRight: 14, color: ui.faint }}>{index + 1}</span>
              <span>
                <CodeLine text={text} />
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* The agent's panel. */}
      <div style={{ position: "absolute", left: panelLeft, top: titleBar, width: panel, bottom: statusBar, borderLeft: `1px solid ${ui.hairline}`, boxSizing: "border-box" }}>
        <div style={{ height: tabs, padding: "0 12px", display: "flex", alignItems: "center", gap: 7, borderBottom: `1px solid ${ui.hairline}`, boxSizing: "border-box", fontWeight: 600 }}>
          <Glyph name="sparkle" size={15} color={accent} weight={1.4} />
          Agent
          <div style={{ marginLeft: "auto", display: "flex", gap: 12 }}>
            <Glyph name="plus" size={15} color={ui.muted} />
            <Glyph name="clock" size={15} color={ui.muted} />
            <Glyph name="dots" size={15} color={ui.muted} />
          </div>
        </div>
        <div style={{ padding: "14px 14px 0", display: "flex", flexDirection: "column", gap: 12 }}>
          <div style={{ alignSelf: "flex-end", maxWidth: 250, padding: "8px 11px", borderRadius: 10, background: ui.block }}>
            Why does a large upload fail on a slow connection?
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 12, color: ui.muted }}>
            <Glyph name="check" size={13} color={ui.faint} />
            Read upload.ts and api.ts
          </div>
          <div>
            <span style={{ fontFamily: codeFont, fontSize: 12, padding: "1px 4px", borderRadius: 4, background: ui.block }}>uploadPart</span> sends
            each part once. When one request drops, the whole upload stops.
          </div>
        </div>
      </div>

      <div
        style={{
          position: "absolute",
          ...field,
          boxSizing: "border-box",
          borderRadius: 10,
          border: `1px solid ${text ? accent : "rgba(0,0,0,0.22)"}`,
          background: ui.window,
          boxShadow: "0 1px 3px rgba(0,0,0,0.06)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: line.left - 1,
          top: line.top,
          width: field.width - 24,
          fontSize: 13.5,
          lineHeight: `${line.height}px`,
        }}
      >
        <Typed text={text} caretShown={caretShown} color={ui.ink} caretHeight={17} placeholder={<span style={{ color: ui.faint }}>Ask the agent…</span>} />
      </div>
      <div style={{ position: "absolute", left: field.left + 8, right: size.width - field.left - field.width + 8, top: field.top + field.height - 32, height: 24, display: "flex", alignItems: "center", gap: 6 }}>
        <Chip>
          <Glyph name="sparkle" size={12} color={ui.muted} weight={1.4} />
          Agent
          <Glyph name="chevronDown" size={10} color={ui.faint} />
        </Chip>
        <Chip>
          Auto
          <Glyph name="chevronDown" size={10} color={ui.faint} />
        </Chip>
        <Glyph name="paperclip" size={15} color={ui.faint} style={{ marginLeft: "auto" }} />
        <div style={{ width: 24, height: 24, borderRadius: 12, background: text ? accent : ui.block, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <Glyph name="arrowUp" size={14} color={text ? "#ffffff" : ui.faint} weight={1.8} />
        </div>
      </div>

      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          height: statusBar,
          background: ui.bar,
          borderTop: `1px solid ${ui.hairline}`,
          boxSizing: "border-box",
          padding: "0 12px",
          display: "flex",
          alignItems: "center",
          gap: 14,
          fontSize: 11.5,
          color: ui.muted,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
          <Glyph name="branch" size={12} color={ui.muted} weight={1.4} />
          main
        </div>
        <div style={{ marginLeft: "auto" }}>Ln 16, Col 1</div>
        <div>Spaces: 2</div>
        <div>TypeScript</div>
      </div>
    </div>
  );
};

import React from "react";
import { Rect } from "../placement";
import { Avatar, Glyph, GlyphName, Typed, WindowButtons } from "../Glyphs";
import { AppProps, ui, uiFont } from "./types";

// The mail app: a mock-up with mailboxes down the side, the list of messages, and the open
// message with a reply being written under it. The people, the addresses (example.com is
// reserved for examples) and the messages are made up, and nothing here is another app's name,
// logo or artwork. All lengths are in points.

export const size = { width: 1060, height: 664 };

/** A unified toolbar, as tall as a Mac's. */
const toolbar = 52;
const sidebar = 186;
const list = 300;
const paneLeft = sidebar + list;
const padding = 24;

const replyTop = 344;
const replyHeader = 36;
const replyFooter = 44;

/** The body of the reply. */
export const field: Rect = { left: paneLeft + padding, top: replyTop + replyHeader, width: size.width - paneLeft - 2 * padding, height: 138 };
export const line: Rect = { left: field.left + 16, top: field.top + 12, width: 0, height: 22 };

const accent = "#3d5fc4";

const boxes: { name: string; glyph: GlyphName; count?: number; selected?: boolean }[] = [
  { name: "Inbox", glyph: "inbox", count: 3, selected: true },
  { name: "Starred", glyph: "star" },
  { name: "Drafts", glyph: "pencil", count: 1 },
  { name: "Sent", glyph: "plane" },
  { name: "Archive", glyph: "archive" },
  { name: "Bin", glyph: "trash" },
];

const labels = [
  { name: "Work", colour: "#3d5fc4" },
  { name: "Travel", colour: "#2a9d8f" },
  { name: "Receipts", colour: "#d9992b" },
];

type Item = { from: string; at: string; subject: string; preview: string; unread?: boolean; selected?: boolean };
const items: Item[] = [
  { from: "Dana", at: "9:58 AM", subject: "Thursday review", preview: "Could we move Thursday's review to 10? The room is free then, and…", selected: true },
  { from: "Tomas", at: "9:31 AM", subject: "Draft agenda", preview: "Here is the draft for Thursday. Add anything I missed.", unread: true },
  { from: "Noor", at: "Yesterday", subject: "Photos from the offsite", preview: "I put the full set in the shared album. A few favourites…", unread: true },
  { from: "Billing", at: "Yesterday", subject: "Your October receipt", preview: "Thanks for your payment. Your receipt is attached." },
  { from: "Priya", at: "Monday", subject: "Re: Pricing page", preview: "Agreed. Let's keep the toggle and test the copy." },
  { from: "Maya", at: "Monday", subject: "Homepage launch", preview: "We go live Thursday morning. The checklist is inside." },
  { from: "Jonas", at: "Sunday", subject: "Onboarding copy", preview: "Second pass attached. The welcome screen is shorter now." },
];

const body = ["Hi Sam,", "", "Could we move Thursday's review to 10? The room is free then, and Tomas can join.", "", "Thanks,", "Dana"];

export const MailWindow: React.FC<AppProps> = ({ text, caretShown }) => {
  const tool = (name: GlyphName, color = ui.muted) => <Glyph name={name} size={17} color={color} />;
  return (
    <div style={{ position: "absolute", inset: 0, background: ui.window, color: ui.ink, fontFamily: uiFont, fontSize: 13, lineHeight: "18px" }}>
      <div style={{ position: "absolute", left: 0, top: 0, width: sidebar, bottom: 0, background: ui.sidebar, borderRight: `1px solid ${ui.hairline}`, boxSizing: "border-box" }}>
        <div style={{ position: "absolute", left: 20, top: 20 }}>
          <WindowButtons />
        </div>
        <div style={{ marginTop: toolbar + 6 }}>
          <div style={{ padding: "0 16px", height: 24, fontSize: 11, fontWeight: 600, color: ui.faint, display: "flex", alignItems: "center" }}>Mailboxes</div>
          {boxes.map((box) => (
            <div
              key={box.name}
              style={{
                height: 28,
                margin: "0 8px",
                padding: "0 8px",
                borderRadius: 6,
                display: "flex",
                alignItems: "center",
                gap: 8,
                background: box.selected ? ui.selected : "none",
                fontWeight: box.selected ? 600 : 400,
              }}
            >
              <Glyph name={box.glyph} size={16} color={box.selected ? accent : ui.muted} weight={1.4} />
              {box.name}
              {box.count ? <span style={{ marginLeft: "auto", fontSize: 12, fontWeight: 400, color: ui.muted }}>{box.count}</span> : null}
            </div>
          ))}
          <div style={{ padding: "0 16px", height: 24, marginTop: 14, fontSize: 11, fontWeight: 600, color: ui.faint, display: "flex", alignItems: "center" }}>Labels</div>
          {labels.map((label) => (
            <div key={label.name} style={{ height: 28, margin: "0 8px", padding: "0 8px", display: "flex", alignItems: "center", gap: 8 }}>
              <div style={{ width: 16, display: "flex", justifyContent: "center" }}>
                <div style={{ width: 9, height: 9, borderRadius: 5, background: label.colour }} />
              </div>
              {label.name}
            </div>
          ))}
        </div>
      </div>

      {/* The toolbar over the list and the open message. */}
      <div style={{ position: "absolute", left: sidebar, top: 0, right: 0, height: toolbar, borderBottom: `1px solid ${ui.hairline}`, boxSizing: "border-box", background: ui.bar }}>
        <div style={{ position: "absolute", left: 16, top: 0, height: toolbar, display: "flex", alignItems: "center", gap: 6, fontSize: 15, fontWeight: 700 }}>
          Inbox
          <span style={{ fontSize: 12, fontWeight: 400, color: ui.muted, marginLeft: 4 }}>3 unread</span>
        </div>
        <div style={{ position: "absolute", left: list - 34, top: 0, height: toolbar, display: "flex", alignItems: "center" }}>{tool("compose")}</div>
        <div style={{ position: "absolute", left: list + padding, top: 0, height: toolbar, display: "flex", alignItems: "center", gap: 18 }}>
          {tool("archive")}
          {tool("trash")}
          {tool("flag")}
          <div style={{ width: 1, height: 18, background: ui.hairline }} />
          {tool("reply", accent)}
          {tool("forward")}
        </div>
        <div
          style={{
            position: "absolute",
            right: 14,
            top: 13,
            width: 190,
            height: 26,
            boxSizing: "border-box",
            padding: "0 8px",
            borderRadius: 7,
            background: ui.block,
            display: "flex",
            alignItems: "center",
            gap: 6,
            color: ui.faint,
          }}
        >
          <Glyph name="search" size={14} color={ui.faint} />
          Search
        </div>
      </div>

      <div style={{ position: "absolute", left: sidebar, top: toolbar, width: list, bottom: 0, paddingTop: 6, borderRight: `1px solid ${ui.hairline}`, boxSizing: "border-box", overflow: "hidden" }}>
        {items.map((item) => (
          <div
            key={item.subject}
            style={{
              height: 78,
              margin: "0 8px",
              padding: "9px 10px 0 22px",
              boxSizing: "border-box",
              borderRadius: 8,
              position: "relative",
              background: item.selected ? "rgba(61,95,196,0.13)" : "none",
              boxShadow: item.selected ? "none" : `0 1px 0 ${ui.hairline}`,
            }}
          >
            {item.unread ? <div style={{ position: "absolute", left: 8, top: 14, width: 8, height: 8, borderRadius: 4, background: accent }} /> : null}
            <div style={{ display: "flex", alignItems: "baseline" }}>
              <span style={{ fontWeight: 600 }}>{item.from}</span>
              <span style={{ marginLeft: "auto", fontSize: 12, color: ui.muted }}>{item.at}</span>
            </div>
            <div>{item.subject}</div>
            <div style={{ color: ui.muted, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{item.preview}</div>
          </div>
        ))}
      </div>

      {/* The open message. */}
      <div style={{ position: "absolute", left: paneLeft + padding, top: toolbar + 22, right: padding }}>
        <div style={{ fontSize: 20, lineHeight: "26px", fontWeight: 700 }}>Thursday review</div>
        <div style={{ marginTop: 12, display: "flex", alignItems: "center", gap: 10 }}>
          <Avatar person={0} size={36} round />
          <div>
            <div>
              <span style={{ fontWeight: 600 }}>Dana</span> <span style={{ color: ui.muted }}>dana@example.com</span>
            </div>
            <div style={{ color: ui.muted }}>To: Sam</div>
          </div>
          <div style={{ marginLeft: "auto", alignSelf: "flex-start", fontSize: 12, color: ui.muted }}>Today at 9:58 AM</div>
        </div>
        <div style={{ marginTop: 16, fontSize: 14.5, lineHeight: "22px" }}>
          {body.map((paragraph, index) => (
            <div key={index} style={{ minHeight: paragraph ? 0 : 12 }}>
              {paragraph}
            </div>
          ))}
        </div>
      </div>

      {/* The reply. */}
      <div
        style={{
          position: "absolute",
          left: field.left,
          top: replyTop,
          width: field.width,
          height: replyHeader + field.height + replyFooter,
          boxSizing: "border-box",
          borderRadius: 10,
          border: `1px solid ${text ? "rgba(61,95,196,0.6)" : "rgba(0,0,0,0.18)"}`,
          boxShadow: "0 1px 4px rgba(0,0,0,0.06)",
        }}
      >
        <div style={{ height: replyHeader, padding: "0 14px", display: "flex", alignItems: "center", gap: 8, borderBottom: `1px solid ${ui.hairline}`, boxSizing: "border-box", color: ui.muted }}>
          <Glyph name="reply" size={15} color={ui.muted} />
          To:
          <div style={{ height: 22, padding: "0 8px 0 3px", borderRadius: 11, background: ui.block, display: "flex", alignItems: "center", gap: 5, color: ui.ink }}>
            <Avatar person={0} size={16} round />
            Dana
          </div>
          <span style={{ marginLeft: "auto", fontSize: 12 }}>Re: Thursday review</span>
        </div>
        <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: replyFooter, padding: "0 12px", boxSizing: "border-box", display: "flex", alignItems: "center", gap: 14 }}>
          <div style={{ height: 28, padding: "0 14px", borderRadius: 7, background: text ? accent : "rgba(61,95,196,0.45)", color: "#ffffff", fontWeight: 600, display: "flex", alignItems: "center", gap: 6 }}>
            Send
            <Glyph name="plane" size={14} color="#ffffff" />
          </div>
          <Glyph name="paperclip" size={16} color={ui.muted} />
          <Glyph name="bold" size={16} color={ui.muted} />
          <Glyph name="image" size={16} color={ui.muted} />
          <Glyph name="trash" size={16} color={ui.muted} style={{ marginLeft: "auto" }} />
        </div>
      </div>
      <div style={{ position: "absolute", left: line.left - 1, top: line.top, width: field.width - 32, fontSize: 14.5, lineHeight: `${line.height}px` }}>
        <Typed text={text} caretShown={caretShown} color={ui.ink} placeholder={<span style={{ color: ui.faint }}>Write your reply</span>} />
      </div>
    </div>
  );
};

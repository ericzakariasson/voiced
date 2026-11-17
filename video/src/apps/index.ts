import { AppId } from "../script";
import { chat, ChatWindow, field as chatField, insertionPoint as chatLine } from "./Chat";
import { CodeWindow, field as codeField, line as codeLine, size as codeSize } from "./Code";
import { field as mailField, line as mailLine, MailWindow, size as mailSize } from "./Mail";
import { field as notesField, line as notesLine, NotesWindow, size as notesSize } from "./Notes";
import { App } from "./types";

/** The desktop, in points. */
export const desktop = { width: 1280, height: 800 };
/** A menu bar as tall as a Mac's without a camera housing. */
export const menuBarHeight = 24;
/** The Dock and the gap under it: the part of the screen apps leave free at the bottom. */
export const dockReserve = 76;

/** A window of this size, centred across the desktop, `top` points down it. */
const placed = (size: { width: number; height: number }, top: number) => ({
  left: (desktop.width - size.width) / 2,
  top,
  width: size.width,
  height: size.height,
});

// The apps are made up, and so are their names: plain words for what each one is.
export const apps: Record<AppId, App> = {
  chat: {
    id: "chat",
    built: "electron",
    name: "Team Chat",
    menus: ["File", "Edit", "View", "Go", "Window", "Help"],
    window: placed({ width: chat.width, height: chat.height }, 50),
    field: chatField,
    line: chatLine,
    Window: ChatWindow,
  },
  code: {
    id: "code",
    built: "electron",
    name: "Code Editor",
    menus: ["File", "Edit", "Selection", "View", "Go", "Run", "Window", "Help"],
    window: placed(codeSize, 44),
    field: codeField,
    line: codeLine,
    Window: CodeWindow,
  },
  mail: {
    id: "mail",
    built: "appKit",
    name: "Email",
    menus: ["File", "Edit", "View", "Mailbox", "Message", "Window", "Help"],
    window: placed(mailSize, 44),
    field: mailField,
    line: mailLine,
    Window: MailWindow,
  },
  notes: {
    id: "notes",
    built: "appKit",
    name: "Notebook",
    menus: ["File", "Edit", "Format", "View", "Window", "Help"],
    window: placed(notesSize, 56),
    field: notesField,
    line: notesLine,
    Window: NotesWindow,
  },
};

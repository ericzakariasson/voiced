import React from "react";
import { Rect } from "../placement";
import { AppId } from "../script";

/** What every app's window is given: what has been written in its field, and the caret's blink. */
export type AppProps = { text: string | null; caretShown: boolean };

/** One app of the desktop. Rectangles are in points; `field` and `line` are within the window. */
export type App = {
  id: AppId;
  /** The app's name in the menu bar, and its menus. Made up, like the app. */
  name: string;
  menus: string[];
  /** Where the window stands on the desktop. */
  window: Rect;
  /** The field being typed into. */
  field: Rect;
  /** The line the insertion point is on. It has no width. */
  line: Rect;
  /**
   * How the app is built, which decides the box Voiced is given for an insertion point at the
   * end of a text, as it is in every scene. An AppKit text view gives the box of the line above
   * (`FocusedTextLocator`: "AppKit reports it one line higher than it is"). An app built on
   * Electron is taken to give the box of the line itself. Either way the app is told the box may
   * be one line up, and keeps room for one more line under it.
   */
  built: "appKit" | "electron";
  Window: React.FC<AppProps>;
};

export const uiFont = '"Inter Variable", sans-serif';
export const codeFont = '"JetBrains Mono", monospace';

/** The colours the plain light apps share. */
export const ui = {
  window: "#ffffff",
  sidebar: "#f2f2f4",
  bar: "#f7f7f8",
  ink: "#1d1d1f",
  muted: "#6b6b70",
  faint: "#a1a1a6",
  hairline: "rgba(0,0,0,0.1)",
  block: "rgba(0,0,0,0.05)",
  selected: "rgba(0,0,0,0.07)",
};

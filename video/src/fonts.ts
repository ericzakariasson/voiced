import "@fontsource-variable/inter/wght.css";
import "@fontsource/lato/400.css";
import "@fontsource/lato/700.css";
import "@fontsource/lato/900.css";
import "@fontsource/jetbrains-mono/400.css";
import "@fontsource/noto-color-emoji/emoji-400.css";
import { continueRender, delayRender } from "remotion";

// Inter is the film's typeface. The team chat has its own, Lato, and its emoji are Noto Color
// Emoji; the code in the code editor is set in JetBrains Mono. Frames wait until every face used
// is ready, so no frame is ever drawn in a fallback font.
const faces = [
  ...[250, 300, 350, 400, 500, 600, 700].map((weight) => `${weight} 32px "Inter Variable"`),
  ...[400, 700, 900].map((weight) => `${weight} 32px "Lato"`),
  '400 32px "JetBrains Mono"',
];
const emoji = "\u{1F389}\u{1F680}\u{1F440}";

export const loadFonts = () => {
  if (typeof document === "undefined") {
    return;
  }
  const handle = delayRender("Loading fonts");
  Promise.all([...faces.map((face) => document.fonts.load(face)), document.fonts.load('32px "Noto Color Emoji"', emoji)])
    .then(() => document.fonts.ready)
    .then(() => continueRender(handle))
    .catch(() => continueRender(handle));
};

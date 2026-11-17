import React from "react";
import { Composition } from "remotion";
import { Film, FRAME } from "./Film";
import { loadFonts } from "./fonts";
import { DURATION_FRAMES, FPS } from "./script";

loadFonts();

// One film: Voiced in use on a desktop, one app after another. Its props name the captures of
// the app's pill; `npm run render` passes the ones `pill-captures.py` wrote.
export const Root: React.FC = () => (
  <Composition
    id="VoicedInUse"
    component={Film}
    fps={FPS}
    durationInFrames={DURATION_FRAMES}
    width={FRAME.width}
    height={FRAME.height}
    defaultProps={{ pill: "captures", caption: true, greyText: true }}
  />
);

// Where the pill goes in the app's Next to Text placement, for an insertion point the app in
// front reports exactly. This is a copy of the rule of `PillNearText` in
// Packages/VoicedKit/Sources/VoicedKit/Presentation/PillNearText.swift: below the line being
// edited when the screen has room there, above the line when it has not, never over the line;
// centred on the insertion point, moved sideways only as far as it takes to stay within the
// left and right edges of the field being typed into, and then to stay fully on the screen.
//
// The copy leaves out what the film does not show: an app that gives no field (the app then
// keeps the pill on the insertion point), what the app does when there is room neither below
// nor above (it places the pill by the field, then in the window, then at the fixed place;
// here it goes straight to the bottom centre of the screen), and the app's refusals of an
// insertion point it cannot use, with its allowance for a box that may be one line up.
//
// Lengths are in the app's points. Unlike AppKit, y grows downwards here, as it does in CSS.

export type Rect = { left: number; top: number; width: number; height: number };

/** `PillNearText.gap`: air between the pill and the line it sits by. */
const gap = 6;
/** `PillPlacement.height`, `.margin` and `.halfWidth`: the room the app keeps for the pill. */
const pillHeight = 44;
const margin = 8;
const halfWidth = 96;
/** `PillPlacement.defaultLift`: how far above the bottom of the screen the fixed place is. */
const defaultLift = 18;

export type PillPlace = {
  side: "below" | "above" | "fixed place";
  /** The middle of the pill's bottom edge. */
  x: number;
  bottom: number;
};

/** As near to `x` as the pill can be centred between `left` and `right`; their middle if it cannot fit. */
const centred = (x: number, left: number, right: number) =>
  left + halfWidth <= right - halfWidth ? Math.min(Math.max(x, left + halfWidth), right - halfWidth) : (left + right) / 2;

/**
 * `mayBeOneLineUp` is what the app's `FocusedTextLocator` says of a box it got for an insertion
 * point at the very end of a text, where an app can only be asked about an empty stretch or the
 * character before: the box may be that of the line above, so the rule keeps room for one more
 * line under it.
 */
export const placeNearText = (line: Rect, field: Rect, visible: Rect, mayBeOneLineUp = false): PillPlace => {
  const visibleBottom = visible.top + visible.height;
  const visibleRight = visible.left + visible.width;
  // Within the field first, with no margin, then on the screen: the screen's edges have the last word.
  const withinField = centred(line.left + line.width / 2, field.left, field.left + field.width);
  const x = centred(withinField, visible.left + margin, visibleRight - margin);

  const below = line.top + line.height + (mayBeOneLineUp ? line.height : 0) + gap + pillHeight;
  if (below <= visibleBottom - margin) {
    return { side: "below", x, bottom: below };
  }
  const above = line.top - gap;
  if (above - pillHeight >= visible.top + margin) {
    return { side: "above", x, bottom: above };
  }
  return { side: "fixed place", x: (visible.left + visibleRight) / 2, bottom: visibleBottom - defaultLift };
};

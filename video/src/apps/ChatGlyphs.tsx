import React from "react";

// The controls of the chat window, drawn here as plain strokes on a 20 by 20 grid. None is taken
// from a system symbol set, an icon set, or another app.

type GlyphProps = { size: number; color: string; style?: React.CSSProperties };

const Stroked: React.FC<GlyphProps & { weight?: number; children: React.ReactNode }> = ({ size, color, style, weight = 1.5, children }) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 20 20"
    fill="none"
    stroke={color}
    strokeWidth={weight}
    strokeLinecap="round"
    strokeLinejoin="round"
    style={{ flexShrink: 0, ...style }}
  >
    {children}
  </svg>
);

const Filled: React.FC<GlyphProps & { children: React.ReactNode }> = ({ size, color, style, children }) => (
  <svg width={size} height={size} viewBox="0 0 20 20" fill={color} style={{ flexShrink: 0, ...style }}>
    {children}
  </svg>
);

export const ArrowLeft: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M16 10H4.5M9.5 5l-5 5 5 5" />
  </Stroked>
);

export const ArrowRight: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M4 10h11.5M10.5 5l5 5-5 5" />
  </Stroked>
);

export const ClockGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <circle cx="10" cy="10" r="7" />
    <path d="M10 6v4.2l2.6 1.8" />
  </Stroked>
);

export const SearchGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <circle cx="9" cy="9" r="5.5" />
    <path d="M13.2 13.2L17 17" />
  </Stroked>
);

export const HelpGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <circle cx="10" cy="10" r="7.5" />
    <path d="M7.9 8.1a2.2 2.2 0 1 1 3.3 1.9c-.8.5-1.2 1-1.2 1.8M10 14.3v.1" />
  </Stroked>
);

export const HomeGlyph: React.FC<GlyphProps> = ({ size, color, style }) => (
  <Filled size={size} color={color} style={style}>
    <path d="M10.7 2.8a1 1 0 0 0-1.4 0L2.9 8.9a1 1 0 0 0-.3.7V16a1.4 1.4 0 0 0 1.4 1.4h3.6v-4.6a1 1 0 0 1 1-1h2.8a1 1 0 0 1 1 1v4.6H16a1.4 1.4 0 0 0 1.4-1.4V9.6a1 1 0 0 0-.3-.7z" />
  </Filled>
);

export const BubblesGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M3 5.3A1.8 1.8 0 0 1 4.8 3.5h6.4A1.8 1.8 0 0 1 13 5.3v3.9a1.8 1.8 0 0 1-1.8 1.8H7.6l-2.8 2.4V11A1.8 1.8 0 0 1 3 9.2z" />
    <path d="M15.4 8h.3A1.8 1.8 0 0 1 17.5 9.8v3a1.8 1.8 0 0 1-1.8 1.8v2.1L13.2 14.6h-2.4" />
  </Stroked>
);

export const BellGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M5.5 13.5V9a4.5 4.5 0 0 1 9 0v4.5l1.4 1.6H4.1z" />
    <path d="M8.4 17.2a1.7 1.7 0 0 0 3.2 0" />
  </Stroked>
);

export const DotsGlyph: React.FC<GlyphProps & { upright?: boolean }> = ({ size, color, style, upright }) => (
  <Filled size={size} color={color} style={{ ...style, transform: upright ? "rotate(90deg)" : undefined }}>
    <circle cx="4.5" cy="10" r="1.5" />
    <circle cx="10" cy="10" r="1.5" />
    <circle cx="15.5" cy="10" r="1.5" />
  </Filled>
);

export const PlusGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M10 4.5v11M4.5 10h11" />
  </Stroked>
);

export const ComposeGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M10.5 4H5.5A1.5 1.5 0 0 0 4 5.5v9A1.5 1.5 0 0 0 5.5 16h9a1.5 1.5 0 0 0 1.5-1.5v-5" />
    <path d="M9 11.2l.5-2.7 6-6 2.2 2.2-6 6z" />
  </Stroked>
);

export const ThreadsGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M3.5 5A1.5 1.5 0 0 1 5 3.5h10A1.5 1.5 0 0 1 16.5 5v7a1.5 1.5 0 0 1-1.5 1.5H9.2l-3.4 3v-3H5A1.5 1.5 0 0 1 3.5 12z" />
    <path d="M7 7.3h6M7 10h3.8" />
  </Stroked>
);

export const HeadphonesGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M4 12.5V10a6 6 0 0 1 12 0v2.5" />
    <path d="M4 11.5h2v5H5.2A1.2 1.2 0 0 1 4 15.3zM16 11.5h-2v5h.8a1.2 1.2 0 0 0 1.2-1.2z" />
  </Stroked>
);

export const PlaneGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M3.5 4l13.5 6-13.5 6 2.2-6zM5.7 10h5.8" />
  </Stroked>
);

export const PlaneFilled: React.FC<GlyphProps> = ({ size, color, style }) => (
  <Filled size={size} color={color} style={style}>
    <path d="M3.3 3.1a.7.7 0 0 0-1 .8l1.5 5.2 6.7.9-6.7.9-1.5 5.2a.7.7 0 0 0 1 .8l14-6.3a.7.7 0 0 0 0-1.2z" />
  </Filled>
);

export const CaretDown: React.FC<GlyphProps> = ({ size, color, style }) => (
  <Filled size={size} color={color} style={style}>
    <path d="M5.5 7.5h9L10 13.5z" />
  </Filled>
);

export const ChevronDown: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M5.5 8l4.5 4.5L14.5 8" />
  </Stroked>
);

export const MessageGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M4 5a1.5 1.5 0 0 1 1.5-1.5h9A1.5 1.5 0 0 1 16 5v6.5a1.5 1.5 0 0 1-1.5 1.5H9.7L6.3 16v-3h-.8A1.5 1.5 0 0 1 4 11.5z" />
  </Stroked>
);

export const LayersGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M10 3.5l6.5 3.5L10 10.5 3.5 7z" />
    <path d="M3.5 10.5L10 14l6.5-3.5" />
  </Stroked>
);

export const PinGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M7.8 3.5h4.4l-.5 4.8 2.6 2.7H5.7l2.6-2.7zM10 11v5.5" />
  </Stroked>
);

export const LinkGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M8.6 11.4a3 3 0 0 0 4.2 0l2.3-2.3a3 3 0 0 0-4.2-4.2l-.8.8" />
    <path d="M11.4 8.6a3 3 0 0 0-4.2 0l-2.3 2.3a3 3 0 0 0 4.2 4.2l.8-.8" />
  </Stroked>
);

export const NumbersGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M8.5 5.5h8M8.5 10h8M8.5 14.5h8" />
    <path d="M3.8 4.6l1-.6v3M3.6 9h1.7L3.6 11.3h1.9M3.6 13.3h1.7l-1 1.2a1 1 0 1 1-.9 1.5" strokeWidth="1" />
  </Stroked>
);

export const BulletsGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M8.5 5.5h8M8.5 10h8M8.5 14.5h8" />
    <path d="M4.5 5.5v.01M4.5 10v.01M4.5 14.5v.01" strokeWidth="2.2" />
  </Stroked>
);

export const QuoteGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M4.5 4.5v11" strokeWidth="2.2" />
    <path d="M8.5 6.5h8M8.5 10h8M8.5 13.5h5" />
  </Stroked>
);

export const CodeGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <path d="M7.5 6l-4 4 4 4M12.5 6l4 4-4 4" />
  </Stroked>
);

export const CodeBlockGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <rect x="3.5" y="4" width="13" height="12" rx="1.8" />
    <path d="M8.5 8l-2 2 2 2M11.5 8l2 2-2 2" />
  </Stroked>
);

export const FaceGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <circle cx="10" cy="10" r="7" />
    <path d="M7 11.8a3.5 3.5 0 0 0 6 0" />
    <path d="M7.7 8v.01M12.3 8v.01" strokeWidth="2" />
  </Stroked>
);

export const MentionGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <circle cx="10" cy="10" r="3" />
    <path d="M13 7v4.2a1.8 1.8 0 0 0 3.5-.6V10a6.5 6.5 0 1 0-2.7 5.3" />
  </Stroked>
);

export const VideoGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <rect x="3" y="6" width="10" height="8" rx="1.8" />
    <path d="M13 9.2l4-2.4v6.4l-4-2.4" />
  </Stroked>
);

export const MicOutline: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <rect x="7.8" y="3" width="4.4" height="8.5" rx="2.2" />
    <path d="M5.3 9.5a4.7 4.7 0 0 0 9.4 0M10 14.2V17" />
  </Stroked>
);

export const SlashGlyph: React.FC<GlyphProps> = (props) => (
  <Stroked {...props}>
    <rect x="3.5" y="3.5" width="13" height="13" rx="2.2" />
    <path d="M11.5 6.8l-3 6.4" />
  </Stroked>
);

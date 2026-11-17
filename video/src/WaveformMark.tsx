import React from "react";

// Voiced's mark, five bars of a waveform, with the proportions of `WaveformMark` in
// Voiced/Views/GlassComponents.swift.
export const markBars = [0.36, 0.72, 1, 0.56, 0.3];

const barWidth = 0.13;

/** The mark is this many times wider than it is tall. */
export const markAspect = barWidth * (markBars.length * 2 - 1);

export const WaveformMark: React.FC<{
  height: number;
  color: string;
  /** Each bar's height as a share of the mark's; the mark's own shape when left out. */
  bars?: number[];
  style?: React.CSSProperties;
}> = ({ height, color, bars = markBars, style }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: height * barWidth,
      height,
      ...style,
    }}
  >
    {bars.map((bar, index) => (
      <div
        key={index}
        style={{
          width: height * barWidth,
          height: Math.max(height * barWidth, height * bar),
          borderRadius: height * barWidth,
          background: color,
        }}
      />
    ))}
  </div>
);

import { random } from "remotion";
import { SpokenWord } from "./script";

// The microphone level the pill's bars follow, made from the words of the script: what the app's
// `LevelMeter` reports for speech, full on the loud syllables, less between them, flat in the
// pauses. It is made up, not a recording.

/** The level, 0 to 1, `time` seconds after the speaker starts saying `words`. */
export const levelOf = (words: SpokenWord[], seed: string) => {
  const peaks = words.flatMap((word, wordIndex) =>
    Array.from({ length: word.syllables }, (_, syllable) => ({
      at: word.at + (word.length / word.syllables) * (syllable + 0.5),
      loudness:
        syllable === 0
          ? 0.8 + 0.2 * random(`${seed}-${wordIndex}-${syllable}`)
          : 0.5 + 0.2 * random(`${seed}-${wordIndex}-${syllable}`),
    })),
  );
  return (time: number): number => {
    let level = 0;
    for (const peak of peaks) {
      const distance = (time - peak.at) / 0.085;
      level = Math.max(level, peak.loudness * Math.exp(-distance * distance));
    }
    return level < 0.06 ? 0 : Math.min(1, level);
  };
};

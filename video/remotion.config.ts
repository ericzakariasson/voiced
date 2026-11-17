import { Config } from "@remotion/cli/config";

Config.setEntryPoint("src/index.ts");
Config.setVideoImageFormat("png");
Config.setCodec("h264");
Config.setPixelFormat("yuv420p");
Config.setColorSpace("bt709");
Config.setCrf(16);
Config.setOverwriteOutput(true);

// KEYFRAMES, a list of times in seconds, is set by `npm run render`. It tells the encoder
// to start a group of pictures at those times and nowhere else, to use one quantizer throughout
// in place of a quality target, and to use no B-frames. A stretch in which nothing moves then
// comes out of the decoder as the same picture in every frame: with a quality target the encoder
// goes on refining a still picture for many frames, and a keyframe in the middle redraws it.
const keyframes = process.env.KEYFRAMES;
if (keyframes) {
  Config.overrideFfmpegCommand(({ type, args }) => {
    if (type !== "pre-stitcher") {
      return args;
    }
    const crf = args.indexOf("-crf");
    const kept = crf < 0 ? args : [...args.slice(0, crf), ...args.slice(crf + 2)];
    const output = kept.indexOf("-y");
    return [...kept.slice(0, output), "-qp", "16", "-bf", "0", "-force_key_frames", keyframes, "-g", "100000", "-sc_threshold", "0", ...kept.slice(output)];
  });
}

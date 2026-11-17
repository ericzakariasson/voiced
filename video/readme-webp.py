#!/usr/bin/env python3
"""Make the animated WebP that the repository's README shows, from a rendered film.

    python3 readme-webp.py out/voiced-in-use.mp4 ../docs/media/voiced-in-use.webp

Needs ffmpeg, cwebp (the `webp` package) and numpy.

Why not ffmpeg's libwebp_anim or img2webp: libwebp's animation encoder compares each frame with the
frame before it and skips blocks that changed by less than a threshold. In a slow fade every step
is under the threshold, so blocks are left behind at whatever value they last had and never
refreshed: a window came out as a patchwork of grey and white. Here every block is compared
with the picture it was last encoded from, so nothing can drift.
"""

import os
import struct
import subprocess
import sys
import tempfile

import numpy as np

# The film's 16:10, and both a whole number of blocks.
WIDTH, HEIGHT = 896, 560
FPS = 10
QUALITY = "75"
# A VP8 macroblock. Blocks of this size, at offsets that are multiples of it, are each either
# wholly redrawn or wholly left alone, so no colour bleeds in from the part that is left alone.
BLOCK = 16
# H.264 leaves up to 3 levels of noise in a picture that stands still.
PIXEL_THRESHOLD = 4
# A slow fade moves every pixel of a block by less than the pixel threshold; its mean shows it.
MEAN_THRESHOLD = 0.75
# The end of a fade can leave a block under both thresholds: a thin line a few levels off. So a
# block that has been left alone for this many frames since it was redrawn is looked at once more,
# and redrawn if this many of its pixels are still 2 levels or more from the film.
SETTLE_FRAMES = 4
SETTLE_PIXELS = 6


def source_frames(film):
    scale = f"fps={FPS},scale={WIDTH}:{HEIGHT}:flags=lanczos"
    ffmpeg = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-i", film, "-vf", scale, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        stdout=subprocess.PIPE,
    )
    size = WIDTH * HEIGHT * 3
    while True:
        raw = ffmpeg.stdout.read(size)
        if len(raw) < size:
            break
        yield np.frombuffer(raw, np.uint8).reshape(HEIGHT, WIDTH, 3)
    if ffmpeg.wait() != 0:
        raise SystemExit("ffmpeg could not read the film")


def per_block(values):
    return values.reshape(HEIGHT // BLOCK, BLOCK, WIDTH // BLOCK, BLOCK, *values.shape[2:])


def changed_blocks(frame, shown):
    """The blocks that no longer show the film, and those that are off by only a little."""
    difference = np.abs(frame.astype(np.int16) - shown).max(axis=2)
    by_pixel = per_block(difference > PIXEL_THRESHOLD).any(axis=(1, 3))
    means = np.abs(per_block(frame).mean(axis=(1, 3)) - per_block(shown).mean(axis=(1, 3)))
    slightly_off = per_block(difference >= 2).sum(axis=(1, 3)) >= SETTLE_PIXELS
    return by_pixel | (means.max(axis=2) > MEAN_THRESHOLD), slightly_off


def encode(pixels, mask, folder):
    """The VP8 data, with its alpha plane when part of the rectangle is left alone."""
    height, width = mask.shape
    picture = os.path.join(folder, "frame.pnm")
    with open(picture, "wb") as file:
        if mask.all():
            file.write(b"P6\n%d %d\n255\n" % (width, height))
            file.write(pixels.tobytes())
        else:
            alpha = np.where(mask, 255, 0).astype(np.uint8)
            file.write(
                b"P7\nWIDTH %d\nHEIGHT %d\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB_ALPHA\nENDHDR\n" % (width, height)
            )
            file.write(np.dstack([pixels, alpha]).tobytes())
    encoded = os.path.join(folder, "frame.webp")
    command = ["cwebp", "-quiet", "-q", QUALITY, "-m", "6", "-sharp_yuv", "-alpha_q", "100"]
    if not mask.all():
        # The loop filter would smooth a redrawn block's edge toward the blocks left alone.
        command += ["-f", "0"]
    subprocess.run(command + [picture, "-o", encoded], check=True)
    with open(encoded, "rb") as file:
        data = file.read()
    chunks, at = b"", 12
    while at < len(data):
        kind, size = data[at : at + 4], struct.unpack("<I", data[at + 4 : at + 8])[0]
        end = at + 8 + size + (size & 1)
        if kind in (b"ALPH", b"VP8 "):
            chunks += data[at:end]
        at = end
    return chunks


def u24(value):
    return struct.pack("<I", value)[:3]


def main(film, output):
    frame_ms = 1000 // FPS
    shown = None
    frames = []
    count = 0
    with tempfile.TemporaryDirectory() as folder:
        for frame in source_frames(film):
            count += 1
            if shown is None:
                blocks = np.ones((HEIGHT // BLOCK, WIDTH // BLOCK), bool)
                shown = frame.astype(np.int16)
                left_alone = np.full(blocks.shape, SETTLE_FRAMES + 1)
            else:
                blocks, slightly_off = changed_blocks(frame, shown)
                left_alone = np.where(blocks, 0, left_alone + 1)
                blocks |= (left_alone == SETTLE_FRAMES) & slightly_off
                if not blocks.any():
                    frames[-1]["ms"] += frame_ms
                    continue
            rows, columns = np.where(blocks.any(axis=1))[0], np.where(blocks.any(axis=0))[0]
            top, bottom = int(rows[0]) * BLOCK, (int(rows[-1]) + 1) * BLOCK
            left, right = int(columns[0]) * BLOCK, (int(columns[-1]) + 1) * BLOCK
            mask = np.repeat(np.repeat(blocks, BLOCK, axis=0), BLOCK, axis=1)[top:bottom, left:right]
            pixels = np.ascontiguousarray(frame[top:bottom, left:right])
            data = encode(pixels, mask, folder)
            shown[top:bottom, left:right][mask] = pixels[mask]
            frames.append({"x": left, "y": top, "width": right - left, "height": bottom - top, "ms": frame_ms, "data": data})

    # VP8X: animation and alpha. ANIM: a white background, and 0 for looping without end.
    body = b"WEBP"
    body += b"VP8X" + struct.pack("<I", 10) + bytes([0x12, 0, 0, 0]) + u24(WIDTH - 1) + u24(HEIGHT - 1)
    body += b"ANIM" + struct.pack("<I", 6) + bytes([255, 255, 255, 255]) + struct.pack("<H", 0)
    for frame in frames:
        # Nothing is disposed of; a frame with an alpha plane is blended over what is there.
        flags = 0x00 if frame["data"][:4] == b"ALPH" else 0x02
        payload = (
            u24(frame["x"] // 2)
            + u24(frame["y"] // 2)
            + u24(frame["width"] - 1)
            + u24(frame["height"] - 1)
            + u24(frame["ms"])
            + bytes([flags])
            + frame["data"]
        )
        body += b"ANMF" + struct.pack("<I", len(payload)) + payload + (b"\0" if len(payload) & 1 else b"")
    with open(output, "wb") as file:
        file.write(b"RIFF" + struct.pack("<I", len(body)) + body)

    total = sum(frame["ms"] for frame in frames)
    print(f"{output}: {8 + len(body)} bytes, {len(frames)} frames from {count}, {total / 1000} s")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])

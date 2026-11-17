#!/usr/bin/env python3
"""Sets the app's real pill into the film.

Takes the frames of the real pill, captured on a Mac over the film's plates, and cuts the pill
out of each: a pixel belongs to the pill where the capture differs from the plate that was behind
it. What is left of each frame is made transparent, so that everything round the pill stays the
film's own picture. The cut-out frames go to public/pill/<scene>/, and public/pill/captures.json
names them to the film (npm run render passes it as the film's props).

    python3 pill-captures.py <captures folder> <plates folder> [<menu bar item folder>]

<captures folder> holds one folder per scene (chat, code, mail, notes) with 0000.png onwards and
a capture.json: the "film" folder that the app's `make pill-captures PLATES=<plates folder>`
writes. <plates folder> holds <scene>-before.png, <scene>-landed.png and plates.json, as
plates.py writes them.
<menu bar item folder> holds idle.png and recording.png, pictures of the app's item in the menu
bar; with them the film shows the app's own item and not its drawing of it.
Needs ffmpeg and numpy. Nothing is written outside public/pill/, which is git-ignored.
"""
import json
import os
import shutil
import subprocess
import sys

import numpy as np

FRAME = (1920, 1200)


def decode(path, width, height, pattern=False):
    """The RGB pixels of an image, or of a numbered run of them, as rows of frames."""
    source = ["-framerate", "60", "-i", path] if pattern else ["-i", path]
    raw = subprocess.run(["ffmpeg", "-v", "error", *source, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.uint8).reshape(-1, height, width, 3)


def menu_bar_item(folder, out):
    """Copies the pictures of the menu bar item and says where they are and how large."""
    os.makedirs(os.path.join(out, "menu-bar-item"))
    sizes = set()
    for name in ("idle", "recording"):
        shutil.copyfile(os.path.join(folder, f"{name}.png"), os.path.join(out, "menu-bar-item", f"{name}.png"))
        size = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "stream=width,height", "-of", "csv=p=0", os.path.join(folder, f"{name}.png")],
            capture_output=True, check=True, text=True,
        ).stdout.strip()
        sizes.add(size)
    assert len(sizes) == 1, f"the two pictures of the menu bar item differ in size: {sizes}"
    width, height = (int(part) for part in sizes.pop().split(","))
    peak = 0
    for name in ("idle", "recording"):
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", os.path.join(folder, f"{name}.png"), "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
            capture_output=True, check=True,
        ).stdout
        peak = max(peak, int(np.frombuffer(raw, dtype=np.uint8).reshape(height, width, 4)[:, :, 3].max()))
    assert peak > 0, "the pictures of the menu bar item are empty"
    return {
        "idle": "pill/menu-bar-item/idle.png",
        "recording": "pill/menu-bar-item/recording.png",
        "width": width,
        "height": height,
        "peak": round(peak / 255, 4),
    }


def main(captures, plates, out, item=None):
    notes = json.load(open(os.path.join(plates, "plates.json")))
    timeline = {plate["app"]: plate for plate in notes["plates"]}
    props = {}
    problems = []
    for scene in ("chat", "code", "mail", "notes"):
        about = json.load(open(os.path.join(captures, scene, "capture.json")))
        rect = about["rectangleInFilmPixels"]
        left, top, width, height = rect["left"], rect["top"], rect["width"], rect["height"]
        frames = decode(os.path.join(captures, scene, "%04d.png"), width, height, pattern=True)
        if len(frames) != about["frames"]:
            problems.append(f"{scene}: {len(frames)} frames found, capture.json says {about['frames']}")
        behind = {
            name: decode(os.path.join(plates, f"{scene}-{name}.png"), *FRAME)[0][top : top + height, left : left + width]
            for name in ("before", "landed")
        }
        box = about["pillDrawnWithinInRectangle"]
        outside = np.ones((height, width), dtype=bool)
        outside[box["top"] : box["top"] + box["height"], box["left"] : box["left"] + box["width"]] = False

        cut = np.zeros((len(frames), height, width, 4), dtype=np.uint8)
        lands = None
        for index, frame in enumerate(frames):
            # Which plate was behind this frame: the one it equals everywhere outside the pill.
            differs = {name: (frame != plate).any(axis=2) for name, plate in behind.items()}
            stray = {name: int((differs[name] & outside).sum()) for name in behind}
            name = "before" if stray["before"] == 0 else "landed"
            if stray[name] != 0:
                problems.append(f"{scene} frame {index}: {stray[name]} pixels outside the pill differ from both plates")
            if name == "landed" and lands is None and stray["before"] != 0:
                lands = index
            cut[index, :, :, :3] = frame
            cut[index, :, :, 3] = np.where(differs[name], 255, 0)

        folder = os.path.join(out, scene)
        os.makedirs(folder)
        subprocess.run(
            ["ffmpeg", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{width}x{height}", "-framerate", "60", "-i", "-", "-start_number", "0", os.path.join(folder, "%04d.png")],
            input=cut.tobytes(),
            check=True,
        )

        # What the film's timeline expects of the captures, in frames from the pill appearing.
        film = timeline[scene]["timeline"]
        first = film["appears"]["frame"]
        changes = about["frameOnWhichEachChangeShowsCountedFromThePillAppearing"]["captured"]
        expected = {"transcribing": film["transcribing"]["frame"] - first, "polishing": film["polishing"]["frame"] - first, "leaves": film["leaves"]["frame"] - first}
        if about["firstFrameIsFilmFrame"] != first:
            problems.append(f"{scene}: the captures start on film frame {about['firstFrameIsFilmFrame']}, the film's pill appears on {first}")
        for change, at in expected.items():
            if changes[change] != at:
                problems.append(f"{scene}: {change} shows on frame {changes[change]} of the captures, the film has it on {at}")
        covered = cut[:, :, :, 3] > 0
        rows = np.where(covered.any(axis=(0, 2)))[0]
        columns = np.where(covered.any(axis=(0, 1)))[0]
        empty = [index for index in range(len(frames)) if not covered[index].any()]
        print(
            f"{scene}: {len(frames)} frames from film frame {first}; the pill's pixels lie within x {left + columns.min()}-{left + columns.max()}, "
            f"y {top + rows.min()}-{top + rows.max()}; the text lands on frame {lands} of the captures"
            + (f"; frames with no pill at all: {empty}" if empty else "")
        )
        room = timeline[scene]["pill"]["box"]
        props[scene] = {
            "folder": f"pill/{scene}",
            "frames": len(frames),
            "left": left,
            "top": top,
            "width": width,
            "height": height,
            "textLandsOnFrame": lands,
            "pillBoxInPlate": {"left": room["left"], "top": room["top"]},
        }

    # The film is rendered the way the plates behind the captures were.
    film = {"pill": "captures", "caption": True, "greyText": bool(notes.get("greyTextEdges", False)), "captures": props}
    if item:
        film["menuBarItem"] = menu_bar_item(item, out)
    json.dump(film, open(os.path.join(out, "captures.json"), "w"), indent=2)
    for problem in problems:
        print("PROBLEM:", problem)
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    here = os.path.dirname(os.path.abspath(__file__))
    target = os.path.join(here, "public", "pill")
    shutil.rmtree(target, ignore_errors=True)
    os.makedirs(target)
    sys.exit(main(sys.argv[1], sys.argv[2], target, sys.argv[3] if len(sys.argv) == 4 else None))

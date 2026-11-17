#!/usr/bin/env python3
"""Makes the plates the app's real pill is captured over.

    python3 plates.py <folder> [flags for remotion, such as --browser-executable=…]

A plate is a frame of the film with the view in on the field being written in, and no pill and no
caption. Each scene (chat, code, mail, notes) gets two: <scene>-before.png, with the field still
empty, and <scene>-landed.png, with the dictated text in it. plates.json says where the pill goes
in each and when each thing happens. The app's `make pill-captures PLATES=<folder>` reads the
folder and photographs its pill over the plates; pill-captures.py sets the result into the film.
Needs the packages of `npm install`.
"""
import json
import os
import subprocess
import sys

PROPS = json.dumps({"pill": "none", "caption": False, "greyText": True})


def main(folder, flags):
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "out")
    os.makedirs(folder, exist_ok=True)
    os.makedirs(out, exist_ok=True)
    script = os.path.join(out, "plates.cjs")
    # The film's own source says where everything is; it is bundled so that plain Node can run it.
    subprocess.run(
        ["npx", "esbuild", "plates.ts", "--bundle", "--platform=node", "--loader:.css=empty", "--log-level=error", f"--outfile={script}"],
        cwd=here, check=True,
    )
    described = subprocess.run(["node", script], cwd=here, check=True, capture_output=True, text=True).stdout
    bundle = os.path.join(out, "plates-bundle")
    subprocess.run(["npx", "remotion", "bundle", "src/index.ts", "--out-dir", bundle, "--log=error"], cwd=here, check=True)
    for plate in json.loads(described)["plates"]:
        for name, frame in ((plate["plate"], plate["plateFrames"]["before"]), (plate["plateLanded"], plate["plateFrames"]["landed"])):
            subprocess.run(
                ["npx", "remotion", "still", bundle, "VoicedInUse", os.path.join(os.path.abspath(folder), name), f"--frame={frame}", f"--props={PROPS}", "--log=error", *flags],
                cwd=here, check=True,
            )
            print(name, "is film frame", frame)
    with open(os.path.join(folder, "plates.json"), "w") as file:
        file.write(described)
    print("plates.json")


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1].startswith("-"):
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2:])

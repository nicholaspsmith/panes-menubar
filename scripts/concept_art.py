#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith
"""Three Gemini concept variants of Major Pane (spec "Process and gates", step 2),
through the Menumon site's art/gen_icons.py (its key, model choice and
post-processing). Writes art/mascot/major-pane-{a,b,c}-raw.png and the
background-removed major-pane-{a,b,c}.png. They guide the pixel art and are
never shipped. Needs ../widgets.nicksmith.software beside this repo."""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SITE = REPO.parent / "widgets.nicksmith.software"
sys.path.insert(0, str(SITE / "art"))
import gen_icons  # noqa: E402

OUT = REPO / "art/mascot"
BASE = ("an original cartoon action-hero army commander called Major Pane, not based on any existing game, "
        "film or toy character: a blond flat-top haircut, a huge square jaw, dark wraparound sunglasses, a thick "
        "neck, a black tank top, olive-green trousers and combat boots, chest out, standing at attention and "
        "facing slightly to the viewer's left, holding a small square window pane marked with a 4x4 grid in one "
        "hand at his side like a riot shield")
VARIANTS = {
    "a": BASE + "; chunky chibi proportions, the head about half the body height, a confident closed-mouth smirk",
    "b": BASE + "; stockier and broader, a wide grin showing teeth, one eyebrow raised above the sunglasses",
    "c": BASE + "; leaner and taller, a stern straight mouth, dog tags, the pane held up on the forearm",
}


def main():
    style = json.loads((SITE / "art/prompts.json").read_text())["style"]
    key = gen_icons._key()
    model = gen_icons.pick_model(key)
    OUT.mkdir(parents=True, exist_ok=True)
    for letter, subject in VARIANTS.items():
        print(f"generating {letter} with {model} ...", flush=True)
        raw = gen_icons.generate(model, key, f"{style} Subject: {subject}.")
        (OUT / f"major-pane-{letter}-raw.png").write_bytes(raw)
        gen_icons.postprocess(raw, size=512).save(OUT / f"major-pane-{letter}.png", optimize=True)
        print(f"  wrote art/mascot/major-pane-{letter}.png")


if __name__ == "__main__":
    main()

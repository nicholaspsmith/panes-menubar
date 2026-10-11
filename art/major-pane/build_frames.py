#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith
"""Draw Major Pane's frames and write frames.json. Python 3 stdlib only.

Major Pane is an original character drawn from scratch for Panes (spec "Character",
IP rule). Every pixel below is hand-placed: each part is a set of rows at absolute
grid coordinates, and a pose is the parts composed with a few whole-row moves
(squash for a breath, lean for the bark). The art is CC BY-NC 4.0 (art/LICENSE).

    python3 build_frames.py && python3 render.py
"""
import json
import os

W, H = 29, 22

PALETTE = {
    "K": "#1E1A24",  # outline
    "P": "#10141E",  # the pane's frame, in shadow (right and bottom)
    "r": "#4A5A78",  # the pane's frame where the light catches it (top and left)
    "B": "#28324A",  # the pane's inner bezel
    "S": "#F2B98A",  # skin
    "h": "#FBD3AE",  # skin highlight (the light comes from the viewer's left)
    "s": "#C98A5E",  # skin shade
    "d": "#9C6540",  # skin deep shade: under the jaw, the smirk
    "Y": "#F4D35E",  # the flat-top
    "L": "#FBE98F",  # hair highlight
    "y": "#C9A63A",  # hair shade
    "G": "#15151C",  # shades
    "g": "#3A4A6A",  # the shades' reflection
    "W": "#FAF6EE",  # glints, the "!" of the bark, the glass's gleam
    "T": "#3A3A44",  # tank top
    "p": "#1E2A40",  # the glass's cells, unlit (lit at render time)
    "q": "#2A3A58",  # the top row of cells, catching the light (lit at render time)
    "l": "#34466A",  # the faint 4x4 grid between cells (lit with its cell at render time)
}
PANE = {"p": "cell", "q": "cell", "l": "cell"}

# ------------------------------------------------------------------ helpers


def blank():
    return [["."] * W for _ in range(H)]


def put(G, rows, dx=0, dy=0):
    """rows: {y: [(x, "pixels"), ...]}; a space leaves the pixel alone, "." clears it."""
    for y, segs in rows.items():
        for x, s in segs:
            for i, c in enumerate(s):
                X, Y = x + i + dx, y + dy
                if c != " " and 0 <= X < W and 0 <= Y < H:
                    G[Y][X] = c


def squash(G, row, n=1):
    """Drop n rows at `row` and let everything above sink: the breath."""
    for _ in range(n):
        for y in range(row, 0, -1):
            G[y] = G[y - 1][:]
        G[0] = ["."] * W


def lean(G, below, dx):
    """Shift every row above `below` sideways: the bark's push forward."""
    for y in range(below):
        row = G[y]
        G[y] = (["."] * dx + row[:W - dx]) if dx > 0 else (row[-dx:] + ["."] * (-dx))


# ------------------------------------------------------------------ parts
# He holds the pane in front of him like a riot shield, and the pane is the
# size of Panes's old screen-grid glyph: 23x14 with a 19x11 glass ruled into a
# faint 4x4 grid (cells 4x2, lines between them). His head shows above it
# (x 8…19, facing the viewer's left: smirk and glints left of centre, the light
# from the left) and a fist grips each side edge. No legs: the pane runs to the
# bottom of the 29x22 canvas.

HAIR = {0: [(11, "KKKKKK")],
        1: [(9, "KKLYYYYyKK")],
        2: [(8, "KLLYYYYYYyyK")]}
HEAD = {3: [(8, "KhSSSSSSSSsK")],
        4: [(8, "KSGgWGGGgWGK")],         # wraparound shades: reflection and a glint on each lens
        5: [(8, "KhGGGGGGGGsK")],
        6: [(8, "KhSddSSSSSsK")],         # the smirk, left of centre, soft
        7: [(9, "KsSSSSSSSdK")]}          # the square jaw, resting on the pane's top edge
BODY = {8: [(8, "KKTsssssTKK")],          # shoulders and straps: seen only when the pane is lowered
        9: [(6, "KSKTTTTTTTTTKSK")]}
GLINT_LEFT = {4: [(10, "WgGGGGWgG")]}       # the stare: glints slide to the front
MOUTH_OPEN = {6: [(10, "dKKd")], 7: [(10, "KKKK")]}
BANG = {0: [(5, "W")], 1: [(5, "W")], 2: [(5, "W")], 3: [(5, "W")], 5: [(5, "W")]}


def pane(y0, x0=3):
    """The shield: a frame lit along the top and left and in shadow on the right
    and bottom, an inner bezel, and a 19x11 glass of 4x4 cells (4x2 each) with
    faint lines between them, the top row of cells catching the light and a gleam
    in the corner. Corners are open so it reads rounded."""
    rows = {y0: [(x0 + 1, "r" * 21)]}
    for r in range(11):
        line = r in (2, 5, 8)
        field = []
        for c in range(19):
            if line or c in (4, 9, 14):
                field.append("l")
            else:
                field.append("q" if r < 2 else "p")
        if r == 0:
            field[0] = field[1] = "W"
        if r == 1:
            field[0] = "W"
        rows[y0 + 1 + r] = [(x0, "rB" + "".join(field) + "BP")]
    rows[y0 + 12] = [(x0, "r" + "B" * 21 + "P")]
    rows[y0 + 13] = [(x0 + 1, "P" * 21)]
    return rows


def right_fist(y0):
    """His right fist (viewer's right) wrapped round the pane's edge, the thumb over its frame."""
    return {y0: [(25, "KKK")], y0 + 1: [(24, "KhSSK")], y0 + 2: [(24, "KSSsK")], y0 + 3: [(25, "KsK")]}


def left_fist(y0):
    return {y0: [(1, "KKK")], y0 + 1: [(0, "KhSSK")], y0 + 2: [(0, "KSSsK")], y0 + 3: [(1, "KsK")]}


# The salute: the free (viewer's left) hand leaves the pane's edge, rises, and
# comes up from behind the shield to the shades.
ARM_HALF = {8: [(0, "KhSSK")], 9: [(0, "KhSsK")], 10: [(1, "KsK")]}          # drawn in front of the pane
ARM_UP = {4: [(4, "KhSSK")], 5: [(4, "KhSsK")], 6: [(5, "KSsK")], 7: [(5, "KSsK")],
          8: [(5, "KSsK")]}                                                  # drawn behind the pane


def figure(arm=None, mouth_open=False, bang=False, glint=None, pane_y=8, breath=0, push=0):
    g = blank()
    for part in (BODY, HAIR, HEAD):
        put(g, part)
    if glint:
        put(g, glint)
    if mouth_open:
        put(g, MOUTH_OPEN)
    if push:
        lean(g, 8, push)                # the head pushes forward
    if breath:
        squash(g, 8, breath)            # the head settles a row towards the shield
    if bang:
        put(g, BANG)
    if arm is ARM_UP:
        put(g, arm)                     # the forearm disappears behind the pane
    put(g, pane(pane_y))
    put(g, right_fist(pane_y + 4))
    if arm is ARM_HALF:
        put(g, arm)
    elif arm is None:
        put(g, left_fist(pane_y + 4))
    return ["".join(r) for r in g]


STATES = {
    "idle": {"fps": 4, "loop": True, "frames": [
        figure(), figure(), figure(breath=1), figure(breath=1),
        figure(), figure(glint=GLINT_LEFT), figure(glint=GLINT_LEFT), figure()]},
    "salute": {"fps": 8, "loop": False, "frames": [
        figure(arm=ARM_HALF), figure(arm=ARM_UP), figure(arm=ARM_UP), figure(arm=ARM_UP),
        figure(arm=ARM_UP), figure(arm=ARM_HALF), figure()]},
    "bark": {"fps": 8, "loop": False, "frames": [
        figure(mouth_open=True, bang=True, push=-1), figure(mouth_open=True, bang=True, push=-1),
        figure(mouth_open=True, push=-1), figure(mouth_open=True, bang=True, push=-1), figure(), figure()]},
    "at_ease": {"fps": 2, "loop": True, "frames": [
        figure(pane_y=10), figure(pane_y=10, breath=1)]},
}


def main():
    doc = {"width": W, "height": H, "palette": PALETTE, "pane": PANE, "states": STATES}
    used = {c for st in STATES.values() for fr in st["frames"] for row in fr for c in row if c != "."}
    assert used <= set(PALETTE), used - set(PALETTE)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "frames.json")
    with open(out, "w") as f:
        json.dump(doc, f, indent=1)
        f.write("\n")
    print(f"wrote {out}: {len(PALETTE)} colours, {sum(len(s['frames']) for s in STATES.values())} frames")


if __name__ == "__main__":
    main()

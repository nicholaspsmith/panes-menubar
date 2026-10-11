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

W, H = 22, 22

PALETTE = {
    "K": "#1E1A24",  # outline
    "P": "#10141E",  # the pane's frame
    "S": "#F2B98A",  # skin
    "h": "#FBD3AE",  # skin highlight (the light comes from the viewer's left)
    "s": "#C98A5E",  # skin shade
    "d": "#9C6540",  # skin deep shade: under the jaw, the smirk
    "Y": "#F4D35E",  # the flat-top
    "L": "#FBE98F",  # hair highlight
    "y": "#C9A63A",  # hair shade
    "G": "#15151C",  # shades
    "g": "#3A4A6A",  # the shades' reflection
    "W": "#FAF6EE",  # glints, the "!" of the bark, the pane's highlight
    "T": "#3A3A44",  # tank-top straps
    "O": "#6B7A3A",  # trousers
    "o": "#4B5628",  # trousers shade
    "M": "#3B2A1E",  # boots
    "m": "#5E4634",  # boots highlight
    "p": "#1E2A40",  # the pane's cells, unlit (lit at render time)
    "q": "#2A3A58",  # the pane's cells near the top, catching the light (lit at render time)
    "r": "#4A5A78",  # the pane's rim where the light catches it (top and left)
}
PANE = {"p": "cell", "q": "cell"}

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
# He holds the pane in front of him like a riot shield: the head shows above
# it (x 5…16, facing the viewer's left: smirk and glints left of centre, the
# light from the left), the boots below, and a fist grips each side edge.
# Canvas 22x22; the pane is 16x11 at x 3…18 with a 14x9 field of cells.

HAIR = {0: [(8, "KKKKKK")],
        1: [(6, "KKLYYYYyKK")],
        2: [(5, "KLLYYYYYYyyK")]}
HEAD = {3: [(5, "KhSSSSSSSSsK")],
        4: [(5, "KSGgWGGGgWGK")],         # wraparound shades: reflection and a glint on each lens
        5: [(5, "KSGGGGGGGGsK")],
        6: [(5, "KhSSSSSSSSsK")],
        7: [(5, "KhSddSSSSSsK")],         # the smirk, left of centre, soft
        8: [(6, "KsSSSSSSdK")],           # the jaw, rounded off at the corners
        9: [(6, "KTsssssssTK")]}          # shoulders and tank-top straps, seen when the pane drops
GLINT_LEFT = {4: [(7, "WgGGGGWgG")]}        # the stare: glints slide to the front
MOUTH_OPEN = {7: [(7, "dKKd")], 8: [(7, "KKKK")]}
BANG = {0: [(2, "W")], 1: [(2, "W")], 2: [(2, "W")], 3: [(2, "W")], 5: [(2, "W")]}

LEGS = {20: [(6, "KOOoKKOOoK")], 21: [(5, "KMmmMKKMmmMK")]}
LEGS_APART = {21: [(3, "KMmMK......KMmMK")]}


def pane(y0, x0=3):
    """The shield: a dark frame with open corners round a 14x9 field of cells,
    the top rows catching the light, a highlight streak top left."""
    rows = {y0: [(x0 + 1, "r" * 14)], y0 + 10: [(x0 + 1, "P" * 14)]}
    for r in range(9):
        field = ["q" if r < 3 else "p"] * 14
        if r == 0:
            field[1] = field[2] = "W"
        if r == 1:
            field[1] = "W"
        rows[y0 + 1 + r] = [(x0, "r" + "".join(field) + "P")]
    return rows


def right_fist(y0):
    """His right fist (viewer's right) wrapped round the pane's edge, the thumb over its face."""
    return {y0: [(18, "KKK")], y0 + 1: [(17, "KhSSK")], y0 + 2: [(17, "KSSsK")], y0 + 3: [(18, "KsK")]}


def fists(y0):
    """Both fists gripping the pane's side edges, four rows tall."""
    f = right_fist(y0)
    f[y0].append((1, "KKK")); f[y0 + 1].append((0, "KhSSK")); f[y0 + 2].append((0, "KSSsK")); f[y0 + 3].append((1, "KsK"))
    return f


# the free (viewer's left) hand leaves the pane and comes up to the shades
ARM_UP = {4: [(0, "KhSSK")], 5: [(0, "KhSsK")], 6: [(1, "KSsK")], 7: [(1, "KSsK")], 8: [(1, "KSsK")],
          9: [(1, "KSsK")], 10: [(1, "KSsK")], 11: [(1, "KSsK")], 12: [(1, "KKKK")]}
ARM_HALF = {9: [(0, "KhSSK")], 10: [(0, "KhSsK")], 11: [(1, "KSsK")], 12: [(1, "KKKK")]}


def figure(arm=None, mouth_open=False, bang=False, glint=None, pane_y=9, legs=LEGS, breath=0, push=0):
    g = blank()
    for part in (HAIR, HEAD, legs):
        put(g, part)
    if glint:
        put(g, glint)
    if mouth_open:
        put(g, MOUTH_OPEN)
    if push:
        lean(g, 10, push)               # the head pushes forward
    if breath:
        squash(g, 9, breath)            # the head settles a row towards the shield
    if bang:
        put(g, BANG)
    put(g, pane(pane_y))
    if arm:
        put(g, right_fist(pane_y + 4))
        put(g, arm)
    else:
        put(g, fists(pane_y + 4))
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
        figure(pane_y=10, legs=LEGS_APART), figure(pane_y=10, legs=LEGS_APART, breath=1)]},
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

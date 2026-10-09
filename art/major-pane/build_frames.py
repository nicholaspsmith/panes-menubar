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

W, H = 20, 22

PALETTE = {
    "K": "#1E1A24",  # outline
    "S": "#F2B98A",  # skin
    "s": "#C98A5E",  # skin shade: neck, the far cheek, fists
    "Y": "#F4D35E",  # the flat-top
    "G": "#15151C",  # shades
    "W": "#FAF6EE",  # glint on the shades, the "!" of the bark, the pane's highlight
    "T": "#3A3A44",  # tank top
    "t": "#26262E",  # tank top shade
    "O": "#6B7A3A",  # trousers
    "o": "#4B5628",  # trousers shade
    "M": "#3B2A1E",  # boots, belt
    "p": "#1E2A40",  # the pane's cells, unlit (lit at render time)
}
PANE = {"p": "cell"}

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
# it (x 5…14, facing the viewer's left: smirk and glints left of centre), the
# boots below, and a fist grips each side edge. Canvas 20x22; the pane is
# 14x12 at x 3…16 with a 12x10 field of cells.

HAIR = {0: [(7, "KKKKKKKK")], 1: [(6, "KYYYYYYYYK")], 2: [(5, "KYYYYYYYYYK")]}
HEAD = {3: [(5, "KSSSSSSSSSK")],
        4: [(5, "KGGGGGGGGGK")],          # shades, one wraparound band
        5: [(5, "KSSSSSSSSsK")],
        6: [(5, "KSKKKSSSSsK")],          # the smirk, left of centre
        7: [(5, "KSSSSSSSSsK")],          # the jaw, behind the pane's top edge
        8: [(6, "KsssssssK")]}            # neck and shoulders, seen only when the pane drops
GLINT = {4: [(7, "W"), (12, "W")]}
GLINT_LEFT = {4: [(6, "W"), (11, "W")]}
MOUTH_OPEN = {6: [(6, "SKKKKSSSsK")], 7: [(6, "SKKKKSSSsK")]}
BANG = {0: [(2, "W")], 1: [(2, "W")], 2: [(2, "W")], 4: [(2, "W")]}          # the "!" of the bark

LEGS = {19: [(5, "KOOOKOOOK")], 20: [(4, "KMMMMKMMMMK")], 21: [(4, "KKKKKKKKKKK")]}
LEGS_APART = {20: [(3, "KMMMMK.KMMMMK")], 21: [(3, "KKKKKK.KKKKKK")]}


def pane(y0, x0=3):
    """The shield: a one-pixel frame round a 12x10 field of cells, a highlight top left."""
    rows = {y0: [(x0, "K" * 14)], y0 + 11: [(x0, "K" * 14)]}
    for y in range(y0 + 1, y0 + 11):
        rows[y] = [(x0, "K" + "p" * 12 + "K")]
    rows[y0 + 1] = [(x0, "KW" + "p" * 11 + "K")]
    return rows


def right_fist(y0):
    """His right fist (viewer's right) wrapped round the pane's edge, the thumb over its face."""
    return {y0: [(16, "KKK")], y0 + 1: [(15, "KSSSK")], y0 + 2: [(15, "KSSsK")], y0 + 3: [(16, "KsK")]}


def fists(y0):
    """Both fists gripping the pane's side edges, four rows tall."""
    f = right_fist(y0)
    f[y0].append((1, "KKK")); f[y0 + 1].append((0, "KSSSK")); f[y0 + 2].append((0, "KSSsK")); f[y0 + 3].append((1, "KsK"))
    return f


# the free (viewer's left) hand leaves the pane and comes up to the shades
ARM_UP = {3: [(0, "KSSSK")], 4: [(0, "KSSSK")], 5: [(1, "KSSK")], 6: [(1, "KSSK")], 7: [(1, "KSSK")],
          8: [(1, "KSSK")], 9: [(1, "KSSK")], 10: [(1, "KSSK")], 11: [(1, "KKKK")]}
ARM_HALF = {8: [(0, "KSSSK")], 9: [(0, "KSSSK")], 10: [(1, "KSSK")], 11: [(1, "KKKK")]}


def figure(arm=None, mouth_open=False, bang=False, glint=GLINT, pane_y=7, legs=LEGS, breath=0, push=0):
    g = blank()
    for part in (HAIR, HEAD, legs):
        put(g, part)
    put(g, glint)
    if mouth_open:
        put(g, MOUTH_OPEN)
    if push:
        lean(g, 9, push)                # the head pushes forward
    if breath:
        squash(g, 8, breath)            # the head settles a row towards the shield
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
        figure(pane_y=8, legs=LEGS_APART), figure(pane_y=8, legs=LEGS_APART, breath=1)]},
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

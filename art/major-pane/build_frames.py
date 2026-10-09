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

W, H = 30, 22

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
# He stands at x 2…18 facing the viewer's left (the smirk and the glints sit
# left of centre); the pane hangs from his right hand (viewer's right) at x 19…28.

HAIR = {0: [(7, "KKKKKKKK")], 1: [(6, "KYYYYYYYYK")], 2: [(5, "KYYYYYYYYYK")]}
HEAD = {3: [(5, "KSSSSSSSSSK")],
        4: [(5, "KGGGGGGGGGK")],          # shades, one wraparound band
        5: [(5, "KGGGGGGGGGK")],
        6: [(5, "KSSSSSSSSsK")],
        7: [(5, "KSKKKSSSSsK")],          # the smirk, left of centre
        8: [(5, "KSSSSSSSSsK")],          # the jaw stays full width
        9: [(6, "KKKKKKKKK")],            # chin: square with a one-pixel chamfer
        10: [(8, "KsssK")]}               # neck
GLINT = {4: [(7, "W"), (12, "W")]}          # a glint on each lens
GLINT_LEFT = {4: [(6, "W"), (11, "W")]}     # the stare: glints slide to the front
MOUTH_OPEN = {7: [(6, "SKKKKSSSsK")], 8: [(6, "SKKKKSSSsK")]}
BANG = {0: [(2, "W")], 1: [(2, "W")], 2: [(2, "W")], 4: [(2, "W")]}          # the "!" of the bark

TORSO = {11: [(4, "KKTTTTTTTTTKK")],
         12: [(2, "KSSKTTTTTTTTTKSSK")],
         13: [(2, "KSSKTTTTTTTTtKSSK")],
         14: [(2, "KSSKTTTTTTTttKSSK")],
         15: [(2, "KSsKMMMYMMMKKSsK")],   # belt with a brass buckle
         16: [(2, "KssKOOOOOOOOOKssK")]}  # fists either side of the waistband
LEGS = {17: [(6, "KOOOKOOOK")], 18: [(6, "KOOOKOOOK")], 19: [(6, "KOoOKOoOK")],
        20: [(5, "KMMMMKMMMMK")], 21: [(5, "KKKKKKKKKKK")]}
LEGS_APART = {17: [(4, "KOOOK.KOOOK")], 18: [(4, "KOOOK.KOOOK")], 19: [(4, "KOoOK.KOoOK")],
              20: [(3, "KMMMMK.KMMMMK")], 21: [(3, "KKKKKK.KKKKKK")]}

# the free (viewer's left) arm: lowered is part of TORSO; these replace it
_CLEAR_ARM = {y: [(2, "...")] for y in range(12, 17)}
ARM_UP = dict(_CLEAR_ARM)
ARM_UP.update({4: [(0, "KSSSK")], 5: [(0, "KSSSK")], 6: [(1, "KSSK")], 7: [(1, "KSSK")], 8: [(1, "KSSK")],
               9: [(1, "KSSK")], 10: [(1, "KSSK")], 11: [(1, "KSSKK")], 12: [(2, "KKK")]})
ARM_HALF = dict(_CLEAR_ARM)
ARM_HALF.update({9: [(0, "KSSSK")], 10: [(0, "KSSSK")], 11: [(1, "KSSKK")], 12: [(2, "KKK")]})


def pane(y0, x0=19):
    """A 10x10 window: a one-pixel frame round an 8x8 of cells, a highlight top left."""
    rows = {y0: [(x0, "KKKKKKKKKK")], y0 + 9: [(x0, "KKKKKKKKKK")]}
    for y in range(y0 + 1, y0 + 9):
        rows[y] = [(x0, "K" + "p" * 8 + "K")]
    rows[y0 + 1] = [(x0, "KW" + "p" * 7 + "K")]
    return rows


def figure(arm=None, mouth_open=False, bang=False, glint=GLINT, pane_y=9, legs=LEGS, breath=0, push=0):
    g = blank()
    for part in (HAIR, HEAD, TORSO, legs):
        put(g, part)
    put(g, glint)
    if mouth_open:
        put(g, MOUTH_OPEN)
    if arm:
        put(g, arm)
    if push:
        lean(g, 11, push)               # head and shoulders forward
    if bang:
        put(g, BANG)
    put(g, pane(pane_y))
    if breath:
        squash(g, 11, breath)           # the chest rises: the head sinks a row into the shoulders
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
        figure(pane_y=12, legs=LEGS_APART), figure(pane_y=12, legs=LEGS_APART, breath=1)]},
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

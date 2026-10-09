#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith
"""A crude stand-in for Major Pane so the pipeline lands before the real art
passes the review gate (spec "Process and gates", step 3). Never shipped.
Writes art/major-pane/placeholder/frames.json. Python 3 stdlib only."""
import json
from pathlib import Path

W, H = 30, 22
OUT = Path(__file__).resolve().parents[1] / "art/major-pane/placeholder/frames.json"
PALETTE = {"K": "#1E1A24", "S": "#F2B98A", "Y": "#F4D35E", "T": "#3A3A44", "O": "#6B7A3A", "p": "#1E2A40"}


def blank():
    return [["."] * W for _ in range(H)]


def put(g, rows, dx=0, dy=0):
    """rows: {y: [(x, "pixels"), ...]}; a space leaves the pixel alone."""
    for y, segs in rows.items():
        for x, s in segs:
            for i, c in enumerate(s):
                X, Y = x + i + dx, y + dy
                if c != " " and 0 <= X < W and 0 <= Y < H:
                    g[Y][X] = c


def box(x, y, w, h, fill, edge="K"):
    rows = {y: [(x, edge * w)], y + h - 1: [(x, edge * w)]}
    for yy in range(y + 1, y + h - 1):
        rows[yy] = [(x, edge + fill * (w - 2) + edge)]
    return rows


def figure(head_dy=0, arm_up=False, mouth_open=False, pane_dy=0, legs_apart=False):
    g = blank()
    put(g, box(5, 0, 10, 2, "Y"), dy=head_dy)            # flat-top
    put(g, box(5, 1, 10, 8, "S"), dy=head_dy)            # head
    put(g, {3: [(6, "KKKKKKKK")]}, dy=head_dy)           # shades
    if mouth_open:
        put(g, {6: [(8, "KKKK")], 7: [(8, "KKKK")]}, dy=head_dy)
    put(g, box(4, 9, 12, 7, "T"))                        # tank top
    put(g, {y: [(2, "KSK"), (15, "KSK")] for y in range(10, 15)})   # arms down
    if arm_up:
        put(g, {y: [(2, "...")] for y in range(10, 15)})
        put(g, {y: [(1, "KSK")] for y in range(3, 10)})
        put(g, {2: [(1, "KKK")]})
    if legs_apart:
        put(g, box(4, 15, 5, 7, "O")); put(g, box(11, 15, 5, 7, "O"))
    else:
        put(g, box(6, 15, 4, 7, "O")); put(g, box(10, 15, 4, 7, "O"))
    put(g, box(18, 8, 10, 10, "p"), dy=pane_dy)          # the pane: 8x8 of cells inside a 10x10 box
    return ["".join(r) for r in g]


def main():
    states = {
        "idle": {"fps": 4, "loop": True, "frames": [figure(), figure(head_dy=1)]},
        "salute": {"fps": 8, "loop": False, "frames": [figure(arm_up=True), figure(arm_up=True), figure()]},
        "bark": {"fps": 8, "loop": False, "frames": [figure(mouth_open=True), figure(mouth_open=True), figure()]},
        "at_ease": {"fps": 2, "loop": True, "frames": [figure(pane_dy=4, legs_apart=True), figure(pane_dy=4, legs_apart=True, head_dy=1)]},
    }
    doc = {"width": W, "height": H, "palette": PALETTE, "pane": {"p": "cell"}, "states": states}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(doc, indent=1) + "\n")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()

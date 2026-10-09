#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith
"""Render Major Pane's pixel-art frames (frames.json) to PNGs. Python 3 stdlib only.

Writes into art/major-pane/out/:
  frames/<state>-<n>@1x.png, @2x, @8x   every frame, transparent background
  contact-sheet.png                     every frame of every state, 4x, light + dark strips
  contact-sheet-animated.png            APNG: every state animating at 4x on light + dark strips
  menubar-1x.png, menubar-2x.png       first frame of each state at true size on light + dark bars
  pane-states.png                       idle with none / a quarter / a half / all cells lit
  app-icon-1024.png                     idle frame 1, a quarter lit, nearest-neighbour on the dark tile

Pane pixels (frames.json "pane") take the lit colour when their cell is lit;
the Swift renderer (PanesGlyph) is the truth for the app, this is for review.
"""
import json
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
LIGHT_BAR = (236, 236, 238)
DARK_BAR = (40, 40, 44)
LIT = (0xFF, 0xD1, 0x66)
CELL_SETS = {
    "none": set(),
    "quarter": {(c, r) for c in range(2) for r in range(2)},
    "half": {(c, r) for c in range(2) for r in range(4)},
    "all": {(c, r) for c in range(4) for r in range(4)},
}
STATES = ("idle", "salute", "bark", "at_ease")


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------- PNG / APNG


def _chunk(kind, data):
    c = struct.pack(">I", len(data)) + kind + data
    return c + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def _raw(pixels, w, h):
    rows = []
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            row.extend(pixels[y * w + x])
        rows.append(bytes(row))
    return zlib.compress(b"".join(rows), 9)


def write_png(path, pixels, w, h):
    data = b"\x89PNG\r\n\x1a\n"
    data += _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    data += _chunk(b"IDAT", _raw(pixels, w, h))
    data += _chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def write_apng(path, frames, w, h, delay_ms):
    data = b"\x89PNG\r\n\x1a\n"
    data += _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    data += _chunk(b"acTL", struct.pack(">II", len(frames), 0))
    seq = 0
    for i, px in enumerate(frames):
        data += _chunk(b"fcTL", struct.pack(">IIIIIHHBB", seq, w, h, 0, 0, delay_ms, 1000, 0, 0))
        seq += 1
        z = _raw(px, w, h)
        if i == 0:
            data += _chunk(b"IDAT", z)
        else:
            data += _chunk(b"fdAT", struct.pack(">I", seq) + z)
            seq += 1
    data += _chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


# ---------------------------------------------------------------- frames


def load():
    with open(os.path.join(HERE, "frames.json")) as f:
        doc = json.load(f)
    W, H = doc["width"], doc["height"]
    assert set(doc["states"]) == set(STATES), f"states must be exactly {STATES}"
    assert set(doc["pane"]) <= set(doc["palette"]), "pane characters must be in the palette"
    for state, spec in doc["states"].items():
        for i, fr in enumerate(spec["frames"]):
            assert len(fr) == H, f"{state}[{i}] has {len(fr)} rows"
            for r, row in enumerate(fr):
                assert len(row) == W, f"{state}[{i}] row {r} is {len(row)} wide"
                for ch in row:
                    assert ch == "." or ch in doc["palette"], f"{state}[{i}] unknown char {ch!r}"
    assert "." not in doc["palette"]
    assert len(doc["palette"]) <= 12, "palette over 12 colours"
    return doc


def pane_box(doc, rows):
    pts = [(x, y) for y, row in enumerate(rows) for x, c in enumerate(row) if c in doc["pane"]]
    if not pts:
        return None
    x0, x1 = min(x for x, _ in pts), max(x for x, _ in pts)
    y0, y1 = min(y for _, y in pts), max(y for _, y in pts)
    return x0, y0, x1 - x0 + 1, y1 - y0 + 1


def grey(rgb):
    l = (rgb[0] * 299 + rgb[1] * 587 + rgb[2] * 114) // 1000
    return (l, l, l)


def frame_rgba(doc, state, rows, lit=frozenset(), greyed=False):
    """Frame -> flat list of RGB (None = transparent), as the Swift renderer colours it."""
    pal = {k: hex_rgb(v) for k, v in doc["palette"].items()}
    box = pane_box(doc, rows)
    out = []
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                out.append(None)
                continue
            if ch in doc["pane"] and box:
                bx, by, bw, bh = box
                cell = (min(3, (x - bx) * 4 // max(bw, 1)), min(3, (y - by) * 4 // max(bh, 1)))
                c = LIT if cell in lit else pal[ch]
            else:
                c = pal[ch]
            out.append(grey(c) if greyed else c)
    return out


def shown(doc, state, rows):
    """A state as the sheets show it: a quarter lit, at_ease greyed."""
    return frame_rgba(doc, state, rows, CELL_SETS["quarter"], greyed=(state == "at_ease"))


def scale(px, w, h, s, bg=None):
    out = []
    for y in range(h * s):
        sy = y // s
        for x in range(w * s):
            p = px[sy * w + x // s]
            if p is None:
                out.append(bg + (255,) if bg else (0, 0, 0, 0))
            else:
                out.append(p + (255,))
    return out


def blit(canvas, cw, src, sw, sh, ox, oy):
    for y in range(sh):
        for x in range(sw):
            p = src[y * sw + x]
            if p[3]:
                canvas[(oy + y) * cw + ox + x] = p


# ---------------------------------------------------------------- outputs


def render_frames(doc):
    d = os.path.join(OUT, "frames")
    os.makedirs(d, exist_ok=True)
    W, H = doc["width"], doc["height"]
    n = 0
    for state in STATES:
        for i, rows in enumerate(doc["states"][state]["frames"]):
            px = shown(doc, state, rows)
            for s in (1, 2, 8):
                write_png(os.path.join(d, f"{state}-{i + 1}@{s}x.png"), scale(px, W, H, s), W * s, H * s)
                n += 1
    return n


def contact_sheet(doc, s=4, pad=8):
    W, H = doc["width"], doc["height"]
    maxf = max(len(doc["states"][st]["frames"]) for st in STATES)
    cell_w, cell_h = W * s + pad, H * s + pad
    cw = pad + 2 * maxf * cell_w + pad
    ch = pad + len(STATES) * cell_h
    canvas = [(255, 255, 255, 255)] * (cw * ch)
    for r, st in enumerate(STATES):
        for i, rows in enumerate(doc["states"][st]["frames"]):
            px = shown(doc, st, rows)
            for k, bg in enumerate((LIGHT_BAR, DARK_BAR)):
                blit(canvas, cw, scale(px, W, H, s, bg), W * s, H * s, pad + (k * maxf + i) * cell_w, pad + r * cell_h)
    write_png(os.path.join(OUT, "contact-sheet.png"), canvas, cw, ch)


def animated_sheet(doc, s=4, pad=8, tick_ms=125, ticks=48):
    W, H = doc["width"], doc["height"]
    cols = 2
    cell_w, cell_h = W * s + pad, H * s + pad
    cw = pad + cols * 2 * cell_w + pad
    rows_n = (len(STATES) + cols - 1) // cols
    ch = pad + rows_n * cell_h
    cache, frames = {}, []
    for t in range(ticks):
        canvas = [(255, 255, 255, 255)] * (cw * ch)
        sec = t * tick_ms / 1000.0
        for idx, st in enumerate(STATES):
            spec = doc["states"][st]
            n = len(spec["frames"])
            k = int(sec * spec["fps"])
            k = k % n if spec["loop"] else min(k, n - 1)
            c, r = idx % cols, idx // cols
            for b, bg in enumerate((LIGHT_BAR, DARK_BAR)):
                key = (st, k, b)
                if key not in cache:
                    cache[key] = scale(shown(doc, st, spec["frames"][k]), W, H, s, bg)
                blit(canvas, cw, cache[key], W * s, H * s, pad + (c * 2 + b) * cell_w, pad + r * cell_h)
        frames.append(canvas)
    write_apng(os.path.join(OUT, "contact-sheet-animated.png"), frames, cw, ch, tick_ms)


def menubar_strips(doc):
    W, H = doc["width"], doc["height"]
    for s in (1, 2):
        bar_h, gap = 24 * s, 8 * s
        cw = gap + len(STATES) * (W * s + gap)
        canvas = []
        for bg in (LIGHT_BAR, DARK_BAR):
            strip = [bg + (255,)] * (cw * bar_h)
            for i, st in enumerate(STATES):
                img = scale(shown(doc, st, doc["states"][st]["frames"][0]), W, H, s)
                blit(strip, cw, img, W * s, H * s, gap + i * (W * s + gap), (bar_h - H * s) // 2)
            canvas += strip
        write_png(os.path.join(OUT, f"menubar-{s}x.png"), canvas, cw, bar_h * 2)


def pane_states(doc, s=4, pad=8):
    W, H = doc["width"], doc["height"]
    rows = doc["states"]["idle"]["frames"][0]
    cw = pad + len(CELL_SETS) * (W * s + pad)
    ch = H * s + 2 * pad
    canvas = [DARK_BAR + (255,)] * (cw * ch)
    for i, (name, cells) in enumerate(CELL_SETS.items()):
        blit(canvas, cw, scale(frame_rgba(doc, "idle", rows, cells), W, H, s, DARK_BAR), W * s, H * s, pad + i * (W * s + pad), pad)
    write_png(os.path.join(OUT, "pane-states.png"), canvas, cw, ch)


def app_icon(doc, size=1024):
    rows = doc["states"]["idle"]["frames"][0]
    W = doc["width"]
    pts = [(x, y) for y, row in enumerate(rows) for x, c in enumerate(row) if c != "."]
    x0, x1 = min(x for x, _ in pts), max(x for x, _ in pts)
    y0, y1 = min(y for _, y in pts), max(y for _, y in pts)
    cw, chh = x1 - x0 + 1, y1 - y0 + 1
    px = frame_rgba(doc, "idle", rows, CELL_SETS["quarter"])
    crop = [px[y * W + x] for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]
    inset, body = 100, 824
    s = (body - 160) // max(cw, chh)
    img = scale(crop, cw, chh, s)
    radius = body * 0.225
    top, bot = hex_rgb("#2B2E35"), hex_rgb("#15171B")
    canvas = []
    for y in range(size):
        t = min(1, max(0, (y - inset) / body))
        bg = tuple(round(top[i] + (bot[i] - top[i]) * t) for i in range(3))
        for x in range(size):
            lx = min(max(x + 0.5, inset + radius), inset + body - radius)
            ly = min(max(y + 0.5, inset + radius), inset + body - radius)
            d = ((x + 0.5 - lx) ** 2 + (y + 0.5 - ly) ** 2) ** 0.5
            a = max(0.0, min(1.0, radius - d + 0.5))
            if x + 0.5 < inset or x + 0.5 > inset + body or y + 0.5 < inset or y + 0.5 > inset + body:
                a = 0.0
            canvas.append(bg + (round(a * 255),))
    blit(canvas, size, img, cw * s, chh * s, (size - cw * s) // 2, (size - chh * s) // 2)
    write_png(os.path.join(OUT, "app-icon-1024.png"), canvas, size, size)


def main():
    doc = load()
    os.makedirs(OUT, exist_ok=True)
    n = render_frames(doc)
    contact_sheet(doc)
    animated_sheet(doc)
    menubar_strips(doc)
    pane_states(doc)
    app_icon(doc)
    print(f"wrote {n} frame PNGs, contact sheets, pane states and app icon to {OUT}")


if __name__ == "__main__":
    sys.exit(main())

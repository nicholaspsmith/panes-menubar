#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith
"""Major Pane's frames (art/major-pane/…/frames.json) -> Sources/PanesGlyph/MajorPaneFrames.swift.

  gen_major_pane_frames.py INPUT             regenerate from INPUT (a file in this repo)
  gen_major_pane_frames.py                   regenerate from the source MajorPaneFrames.swift names
  gen_major_pane_frames.py --check           exit 1 if the committed Swift is stale
  gen_major_pane_frames.py --validate INPUT  only check INPUT against the format

Format (spec "Art format"): {"width", "height", "palette": {char: "#RRGGBB"},
"pane": {char: "cell"}, "states": {name: {"fps", "loop", "frames": [[rows]]}}}.
Exactly those five keys. "." is transparent; pane characters are the cells the
renderer lights. At most 24 palette colours. States: exactly idle, salute, bark,
at_ease. Canvas 1 to 64 each way. Python 3.9, stdlib only."""
from __future__ import annotations
import hashlib
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "Sources/PanesGlyph/MajorPaneFrames.swift"
STATES = ("idle", "salute", "bark", "at_ease")
PANE_ROLES = ("cell",)
TOP_KEYS = ("width", "height", "palette", "pane", "states")
MAX_COLOURS = 24
HEX = re.compile(r"#[0-9A-Fa-f]{6}")


class FramesError(ValueError):
    pass


def _fail(msg):
    raise FramesError(msg)


def _pixel_char(k) -> bool:
    return isinstance(k, str) and len(k) == 1 and "!" <= k <= "~" and k != "."


def validate(data) -> None:
    if not isinstance(data, dict):
        _fail("the top level must be an object")
    unknown = sorted(set(data) - set(TOP_KEYS))
    if unknown:
        _fail("unknown keys: " + ", ".join(unknown))
    w, h = data.get("width"), data.get("height")
    if not all(isinstance(v, int) and not isinstance(v, bool) and 1 <= v <= 64 for v in (w, h)):
        _fail("width and height must be integers from 1 to 64")
    pal = data.get("palette")
    if not isinstance(pal, dict) or not pal:
        _fail("palette must be a non-empty object")
    for k, v in pal.items():
        if not _pixel_char(k):
            _fail(f"palette key {k!r} must be one character (printable ASCII, not '.')")
        if not (isinstance(v, str) and HEX.fullmatch(v)):
            _fail(f"palette colour for {k!r} must be #RRGGBB")
    if len(pal) > MAX_COLOURS:
        _fail(f"palette has {len(pal)} colours; the most is {MAX_COLOURS}")
    if "pane" not in data:
        _fail("missing pane (use {} for none)")
    pane = data["pane"]
    if not isinstance(pane, dict):
        _fail("pane must be an object")
    for k, v in pane.items():
        if k not in pal:
            _fail(f"pane key {k!r} is not in the palette")
        if v not in PANE_ROLES:
            _fail(f"pane role {v!r} for {k!r} must be one of {PANE_ROLES}")
    states = data.get("states")
    if not isinstance(states, dict):
        _fail("states must be an object")
    missing = [s for s in STATES if s not in states]
    if missing:
        _fail("missing states: " + ", ".join(missing))
    extra = sorted(set(states) - set(STATES))
    if extra:
        _fail("unknown states: " + ", ".join(extra))
    for name in STATES:
        clip = states[name]
        if not isinstance(clip, dict):
            _fail(f"{name}: must be an object")
        fps = clip.get("fps")
        if isinstance(fps, bool) or not isinstance(fps, (int, float)) or not 0 < fps <= 30:
            _fail(f"{name}: fps must be a number in (0, 30]")
        if not isinstance(clip.get("loop"), bool):
            _fail(f"{name}: loop must be true or false")
        frames = clip.get("frames")
        if not isinstance(frames, list) or not frames:
            _fail(f"{name}: needs at least one frame")
        for i, fr in enumerate(frames):
            if not isinstance(fr, list) or len(fr) != h:
                _fail(f"{name} frame {i}: needs {h} rows")
            for y, row in enumerate(fr):
                if not isinstance(row, str) or len(row) != w:
                    _fail(f"{name} frame {i} row {y}: needs {w} characters")
                bad = sorted({c for c in row if c != "." and c not in pal})
                if bad:
                    _fail(f"{name} frame {i} row {y}: characters not in the palette: {''.join(bad)}")


def swift_str(s: str) -> str:
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ord(ch) < 0x20 or ord(ch) == 0x7F:
            out.append("\\u{%x}" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def hexnum(color: str) -> str:
    return "0x" + color[1:].upper()


def render(data, source: str, digest: str) -> str:
    validate(data)
    lines = [
        "// Generated by scripts/gen_major_pane_frames.py. Do not edit: change the JSON and regenerate.",
        f"// source: {source}",
        f"// sha256: {digest}",
        "// The art is CC BY-NC 4.0 (art/LICENSE, NOTICE); the code around it is MPL-2.0.",
        "",
        '/// Major Pane\'s pixel frames, compiled in (spec "Art format").',
        "public enum MajorPaneFrames {",
        f"    public static let width = {data['width']}",
        f"    public static let height = {data['height']}",
        "    public static let palette: [Character: UInt32] = [",
    ]
    for k in sorted(data["palette"]):
        lines.append(f"        {swift_str(k)}: {hexnum(data['palette'][k])},")
    lines.append("    ]")
    lines.append("    public static let pane: Set<Character> = [" + ", ".join(swift_str(k) for k in sorted(data["pane"])) + "]")
    lines.append("    public static let clips: [String: MajorPaneClip] = [")
    for s in STATES:
        c = data["states"][s]
        lines.append(f"        {swift_str(s)}: MajorPaneClip(fps: {float(c['fps'])!r}, loop: {'true' if c['loop'] else 'false'}, frames: [")
        for fr in c["frames"]:
            lines.append("            [")
            for row in fr:
                lines.append(f"                {swift_str(row)},")
            lines.append("            ],")
        lines.append("        ]),")
    lines.append("    ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


def source_of(swift_text: str):
    m = re.search(r"^// source: (.+)$", swift_text, re.M)
    return m.group(1) if m else None


def generate(rel: str) -> str:
    raw = (REPO / rel).read_bytes()
    return render(json.loads(raw), rel, hashlib.sha256(raw).hexdigest())


def _in_repo(arg: str) -> str:
    """INPUT as a repo-relative path: the Swift header records it, and the check re-reads it."""
    try:
        return Path(arg).resolve().relative_to(REPO).as_posix()
    except ValueError:
        _fail(f"{arg}: INPUT must be a file inside this repo")


def _shown(path: Path) -> str:
    try:
        return path.relative_to(REPO).as_posix()
    except ValueError:
        return str(path)


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    check = "--check" in args
    only_validate = "--validate" in args
    args = [a for a in args if a not in ("--check", "--validate")]
    try:
        if only_validate:
            if not args:
                print("gen_major_pane_frames: --validate needs an INPUT", file=sys.stderr)
                return 2
            validate(json.loads(Path(args[0]).read_text()))
            print(f"{args[0]}: valid")
            return 0
        if args:
            rel = _in_repo(args[0])
        else:
            rel = source_of(OUT.read_text()) if OUT.exists() else None
            if not rel:
                print("gen_major_pane_frames: give an INPUT; MajorPaneFrames.swift names no source", file=sys.stderr)
                return 2
        text = generate(rel)
    except (OSError, ValueError) as e:
        print(f"gen_major_pane_frames: {e}", file=sys.stderr)
        return 1
    if check:
        if not OUT.exists() or OUT.read_text() != text:
            print(f"gen_major_pane_frames: {_shown(OUT)} is stale; run scripts/gen_major_pane_frames.py", file=sys.stderr)
            return 1
        return 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text)
    print(f"wrote {_shown(OUT)} from {rel}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

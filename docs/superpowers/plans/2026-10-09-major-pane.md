# Major Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Panes its mascot, Major Pane: hand-placed pixel art with four clips, a pane whose 4×4 cells show where the front window sits, playing in the menu bar and rendered into the app icon, README and site.

**Architecture:** Polly's pipeline (parity repo) copied into panes-menubar: Python draws `frames.json`, a generator compiles it into Swift, `PanesGlyph` renders frames as whole-pixel bitmaps and decides which pane cells are lit, a pure driver picks the pose from the clock, and a small controller in the app owns one timer. The site's renderers compile the same PanesGlyph files, with a pixel-art flag so nothing is ever interpolated.

**Tech Stack:** Swift 5.9 package (macOS 13+, AppKit, XCTest), Python 3 stdlib for the art tools, the Menumon site's bash/Swift renderers, Gemini via the site's `art/gen_icons.py` for concept art only.

**Spec:** `docs/superpowers/specs/2026-10-09-major-pane-design.md` (in this repo). Two refinements made while planning, recorded in the spec by Task 1: the app icon is produced by the site's `app-icons.swift` with a pixel-art flag (there is no Swift `iconBitmap`; the preview shows the icon pose on a CSS tile), and the preview shows a row of idle frames with none / a quarter / a half / all cells lit instead of a selector.

## Global Constraints

- Repo: `/Users/nicholassmith/Code/panes-menubar`, branch `major-pane` (already exists, holds the spec). Every push is a release: the branch is pushed only in Task 11, with `## [0.6.0] - <date>` at the top of `CHANGELOG.md`. Never tag by hand, never `gh pr merge --admin`, merge with plain `gh pr merge --merge` once `release / check` is green.
- Swift tools 5.9, `platforms: [.macOS(.v13)]`, bundle id `com.nicholaspsmith.Panes`. Tests run with `swift test` from the repo root; the full suite must stay green at every commit.
- Art format: exactly the keys `width`, `height`, `palette`, `pane`, `states`; canvas 1…64 each way; at most 24 palette colours (raised from 12 at the Task 10 gate); `.` transparent; pane role `cell` only; states exactly `idle`, `salute`, `bark`, `at_ease`; fps in (0, 30].
- Python tools are Python 3 standard library only (`/usr/bin/python3`, 3.9), except `scripts/concept_art.py`, which uses the site's PIL through `art/gen_icons.py`.
- Licence: code MPL-2.0 (existing `LICENSE`); art CC BY-NC 4.0 in `art/LICENSE` plus a top-level `NOTICE`. Every new Swift/Python/bash file starts with the repo's MPL header comment (copy it from `Sources/PanesGlyph/ScreenGridIcon.swift`).
- IP rule (binding, from the spec): art drawn from scratch, nothing recognisable as Duke Nukem, Sarge or any existing character, no sprite sheets downloaded or committed.
- The name is **Major Pane**. "Payne" is never written anywhere.
- Other repos touched: `/Users/nicholassmith/Code/widgets.nicksmith.software` (Task 8, Task 11). Nothing in StatusItemKit or parity changes.
- Do not launch Apollo Monitor. Do not hand-edit `~/Applications/Panes.app` (parity owns it). Do not run `sudo`.

## Review Focus

1. The front window is on a different display from the icon's: the pane must light nothing rather than the wrong cells. → Task 4, `testLitCellsIgnoreWindowsOffTheDisplay`.
2. A frame with no pane pixels at all (the artist moved the pane off canvas or forgot it): the renderer must draw the frame, lighting nothing, never trap. → Task 4, `testFrameWithoutAPaneDrawsAndLightsNothing`.
3. A one-shot clip the art draws as a single frame: it must count as finished at once and never leave the driver stuck on it. → Task 5, `testOneFrameOneShotFinishesAtOnce`.
4. The wall clock steps back during a salute (NTP, wake): the salute must end and the idle resume, not freeze. → Task 5, `testClockSteppingBackEndsAOneShot`.
5. Reduce Motion is switched on in the middle of a bark: the next pose is the static steady frame, the pending bark is dropped, and no frame timer is scheduled. → Task 5, `testReduceMotionClearsEverythingPlaying`.

---

## File structure

**panes-menubar**
- `art/LICENSE`, `NOTICE` — the art licence and notice (Task 2).
- `art/major-pane/build_frames.py` — the real art, every pixel in code → `art/major-pane/frames.json` (Task 10).
- `art/major-pane/render.py` — review renders into `art/major-pane/out/` (Task 10).
- `art/major-pane/placeholder/frames.json` — crude stand-in, from `scripts/placeholder_frames.py` (Task 2).
- `art/mascot/major-pane-{a,b,c}-raw.png`, `-{a,b,c}.png` — Gemini concept variants (Task 9).
- `scripts/gen_major_pane_frames.py` — JSON → `Sources/PanesGlyph/MajorPaneFrames.swift` (Task 2).
- `scripts/placeholder_frames.py` (Task 2), `scripts/concept_art.py` (Task 9).
- `Sources/PanesGlyph/MajorPaneArt.swift` — `MajorPaneClip`, `MajorPaneArt`, the JSON loader (Task 1).
- `Sources/PanesGlyph/MajorPaneFrames.swift` — generated (Task 2).
- `Sources/PanesGlyph/Animator.swift` — `ClipTiming`, `Animator` (Task 3).
- `Sources/PanesGlyph/MajorPaneRenderer.swift` — `MajorPanePose`, `MajorPaneRenderer`, `PaneCells` (Task 4).
- `Sources/PanesGlyph/MascotDriver.swift` — `MascotState`, `MascotDriver` (Task 5).
- `Sources/PanesGlyph/MajorPanePreview.swift`, `Sources/MajorPaneRender/main.swift` (Task 6).
- `Sources/Panes/MascotController.swift`, `Sources/Panes/main.swift` (Task 7).
- `Tests/PanesGlyphTests/MajorPaneArtTests.swift`, `AnimatorTests.swift`, `MajorPaneRendererTests.swift`, `MascotDriverTests.swift`, `MajorPanePreviewTests.swift`.
- `Package.swift`, `README.md`, `CHANGELOG.md`, `docs/*.png`, `Resources/bundle/AppIcon.icns`.

**widgets.nicksmith.software** (Task 8)
- `art/glyphs/render-glyphs.sh`, `art/glyphs/app-icons.sh` — copy the new PanesGlyph files in.
- `art/glyphs/app-icons.swift`, `art/glyphs/anim.swift`, `art/glyphs/main.swift` — Major Pane replaces the grid for Panes; `pixelArt` flag.
- `site/daemons.json` — nature, alts, blurb.

---

### Task 1: The art format in Swift (`MajorPaneArt`)

**Files:**
- Create: `Sources/PanesGlyph/MajorPaneArt.swift`
- Create: `Tests/PanesGlyphTests/MajorPaneArtTests.swift`
- Modify: `docs/superpowers/specs/2026-10-09-major-pane-design.md` (the two refinements named under **Spec** above)

**Interfaces:**
- Produces:
  - `public struct MajorPaneClip: Equatable { let fps: Double; let loop: Bool; let frames: [[String]] }`
  - `public struct MajorPaneArt: Equatable { width, height: Int; palette: [Character: UInt32]; pane: Set<Character>; clips: [String: MajorPaneClip] }`, `static let stateNames = ["idle", "salute", "bark", "at_ease"]`, `static let maxColours = 12`, `init(width:height:palette:pane:clips:)`, `init(json: Data) throws`, `func clip(_ state: String) -> MajorPaneClip`.
  - `public struct MajorPaneArtError: Error, CustomStringConvertible`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/PanesGlyphTests/MajorPaneArtTests.swift
// (MPL header)
import XCTest
@testable import PanesGlyph

final class MajorPaneArtTests: XCTestCase {
    /// The smallest valid art at any size: every state is one solid frame of `fill`.
    func canvas(_ w: Int, _ h: Int, fill: Character = "K") -> [String: Any] {
        let solid = Array(repeating: String(repeating: fill, count: w), count: h)
        let clip: [String: Any] = ["fps": 4, "loop": true, "frames": [solid]]
        return ["width": w, "height": h, "palette": ["K": "#000000"], "pane": [String: String](),
                "states": Dictionary(uniqueKeysWithValues: MajorPaneArt.stateNames.map { ($0, clip) })]
    }
    func data(_ o: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: o) }
    func edited(_ base: [String: Any], _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var o = base; edit(&o); return try data(o)
    }
    func refused(_ json: Data, _ needle: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try MajorPaneArt(json: json), file: file, line: line) { e in
            XCTAssertTrue("\(e)".contains(needle), "got: \(e)", file: file, line: line)
        }
    }

    func testLoadsAtItsOwnSizeWithItsClips() throws {
        let art = try MajorPaneArt(json: data(canvas(30, 22)))
        XCTAssertEqual(art.width, 30); XCTAssertEqual(art.height, 22)
        XCTAssertEqual(art.palette["K"], 0x000000)
        XCTAssertEqual(Set(art.clips.keys), Set(MajorPaneArt.stateNames))
        XCTAssertEqual(art.clip("idle").frames[0].count, 22)
        XCTAssertEqual(art.clip("idle").fps, 4); XCTAssertTrue(art.clip("idle").loop)
    }

    func testPaneCharactersAreKept() throws {
        let json = try edited(canvas(6, 4)) { o in
            o["palette"] = ["K": "#000000", "p": "#1E2A40"]
            o["pane"] = ["p": "cell"]
        }
        XCTAssertEqual(try MajorPaneArt(json: json).pane, ["p"])
    }

    func testUnknownStateFallsBackToIdle() throws {
        let art = try MajorPaneArt(json: data(canvas(3, 2)))
        XCTAssertEqual(art.clip("dance"), art.clip("idle"))
    }

    func testArtWithNoClipsAnswersWithABlankFrameOfItsOwnSize() {
        let art = MajorPaneArt(width: 3, height: 2, palette: [:], pane: [], clips: [:])
        XCTAssertEqual(art.clip("idle").frames, [["...", "..."]])
    }

    func testRefusesWhatTheGeneratorRefuses() throws {
        let base = canvas(4, 3)
        refused(try edited(base) { $0["extra"] = 1 }, "unknown keys: extra")
        refused(try edited(base) { $0["pane"] = nil }, "missing pane")
        refused(try edited(base) { $0["width"] = 0 }, "width and height must be integers from 1 to 64")
        refused(try edited(base) { $0["width"] = 4.0 }, "width and height must be integers from 1 to 64")
        refused(try edited(base) { $0["palette"] = ["KK": "#000000"] }, "one printable ASCII character")
        refused(try edited(base) { $0["palette"] = ["K": "#00000"] }, "must be #RRGGBB")
        refused(try edited(base) { $0["pane"] = ["z": "cell"] }, "pane key z is not in the palette")
        refused(try edited(base) { $0["pane"] = ["K": "perch"] }, "pane role perch for K must be \"cell\"")
        refused(try edited(base) { var s = $0["states"] as! [String: Any]; s["bark"] = nil; $0["states"] = s }, "missing states: bark")
        refused(try edited(base) { var s = $0["states"] as! [String: Any]; s["bob"] = s["idle"]; $0["states"] = s }, "unknown states: bob")
        refused(try edited(base) { var s = $0["states"] as! [String: Any]; var c = s["idle"] as! [String: Any]
            c["fps"] = 31; s["idle"] = c; $0["states"] = s }, "idle: fps must be a number in (0, 30]")
        refused(try edited(base) { var s = $0["states"] as! [String: Any]; var c = s["idle"] as! [String: Any]
            c["frames"] = [["KKKK", "KKKK"]]; s["idle"] = c; $0["states"] = s }, "idle frame 0: needs 3 rows")
        refused(try edited(base) { var s = $0["states"] as! [String: Any]; var c = s["idle"] as! [String: Any]
            c["frames"] = [["KKK", "KKKK", "KKKK"]]; s["idle"] = c; $0["states"] = s }, "idle frame 0 row 0: needs 4 characters")
        refused(try edited(base) { var s = $0["states"] as! [String: Any]; var c = s["idle"] as! [String: Any]
            c["frames"] = [["KKKZ", "KKKK", "KKKK"]]; s["idle"] = c; $0["states"] = s }, "character not in the palette: Z")
        refused(try edited(base) { $0["palette"] = Dictionary(uniqueKeysWithValues: "ABCDEFGHIJKLM".map { (String($0), "#000000") }) },
                "palette has 13 colours; the most is 12")
        refused(Data("[]".utf8), "the top level must be an object")
        refused(Data("nope".utf8), "not JSON")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter MajorPaneArtTests 2>&1 | tail -5`
Expected: compile error, `cannot find 'MajorPaneArt' in scope`.

- [ ] **Step 3: Implement `MajorPaneArt`**

```swift
// Sources/PanesGlyph/MajorPaneArt.swift
// (MPL header)
import Foundation

/// One state's animation: rows of palette characters per frame, "." transparent.
public struct MajorPaneClip: Equatable {
    public let fps: Double
    public let loop: Bool
    public let frames: [[String]]
    public init(fps: Double, loop: Bool, frames: [[String]]) {
        self.fps = fps; self.loop = loop; self.frames = frames
    }
}

public struct MajorPaneArtError: Error, CustomStringConvertible {
    public let description: String
}

/// Major Pane as data (spec "Art format"). The app draws `shipped`, compiled in
/// from MajorPaneFrames.swift; `init(json:)` reads the same format at run time
/// for previews and the drift test. The canvas is whatever the art says it is.
public struct MajorPaneArt: Equatable {
    /// The four clips every art must draw, and no others.
    public static let stateNames = ["idle", "salute", "bark", "at_ease"]
    /// Palette entries, "." (transparent) not counted.
    public static let maxColours = 12
    static let topLevelKeys: Set<String> = ["width", "height", "palette", "pane", "states"]

    public let width: Int
    public let height: Int
    public let palette: [Character: UInt32]
    /// Characters whose pixels are the pane's cells: coloured at render time.
    public let pane: Set<Character>
    public let clips: [String: MajorPaneClip]

    public init(width: Int, height: Int, palette: [Character: UInt32], pane: Set<Character>,
                clips: [String: MajorPaneClip]) {
        self.width = width; self.height = height; self.palette = palette; self.pane = pane; self.clips = clips
    }

    /// The clip for a state; an unknown name gets idle. Art with no clips at
    /// all gets a single blank frame, never a trap.
    public func clip(_ state: String) -> MajorPaneClip {
        if let c = clips[state] ?? clips["idle"] ?? clips.values.first { return c }
        let blank = Array(repeating: String(repeating: ".", count: max(width, 0)), count: max(height, 0))
        return MajorPaneClip(fps: 1, loop: false, frames: [blank])
    }

    private struct Raw: Decodable {
        struct Clip: Decodable { let fps: Double; let loop: Bool; let frames: [[String]] }
        let width: Int
        let height: Int
        let palette: [String: String]
        let pane: [String: String]
        let states: [String: Clip]
    }

    /// Reads the format scripts/gen_major_pane_frames.py validates, with the same rules.
    public init(json: Data) throws {
        func fail(_ m: String) -> MajorPaneArtError { MajorPaneArtError(description: m) }
        let top: [String: Any]
        do {
            guard let o = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
                throw fail("the top level must be an object")
            }
            top = o
        } catch let e as MajorPaneArtError { throw e } catch { throw fail("not JSON: \(error.localizedDescription)") }
        let unknown = top.keys.filter { !MajorPaneArt.topLevelKeys.contains($0) }.sorted()
        guard unknown.isEmpty else { throw fail("unknown keys: " + unknown.joined(separator: ", ")) }
        guard top["pane"] != nil else { throw fail("missing pane (use {} for none)") }
        for key in ["width", "height"] {
            if let n = top[key] as? NSNumber, CFNumberIsFloatType(n) { throw fail("width and height must be integers from 1 to 64") }
        }
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: json)
        } catch let DecodingError.keyNotFound(key, _) {
            throw fail("missing \(key.stringValue)")
        } catch let DecodingError.typeMismatch(_, ctx), let DecodingError.valueNotFound(_, ctx), let DecodingError.dataCorrupted(ctx) {
            let at = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            throw fail(at.isEmpty ? ctx.debugDescription : "\(at): \(ctx.debugDescription)")
        }
        let w = raw.width, h = raw.height
        guard (1...64).contains(w), (1...64).contains(h) else { throw fail("width and height must be integers from 1 to 64") }
        guard !raw.palette.isEmpty else { throw fail("palette must be a non-empty object") }
        var palette: [Character: UInt32] = [:]
        for (key, value) in raw.palette {
            guard let ch = MajorPaneArt.pixelCharacter(key) else {
                throw fail("palette key \(key) must be one printable ASCII character other than \".\"")
            }
            guard let rgb = MajorPaneArt.hexColor(value) else { throw fail("palette colour for \(key) must be #RRGGBB") }
            palette[ch] = rgb
        }
        guard palette.count <= MajorPaneArt.maxColours else {
            throw fail("palette has \(palette.count) colours; the most is \(MajorPaneArt.maxColours)")
        }
        var pane = Set<Character>()
        for (key, role) in raw.pane {
            guard let ch = MajorPaneArt.pixelCharacter(key), palette[ch] != nil else { throw fail("pane key \(key) is not in the palette") }
            guard role == "cell" else { throw fail("pane role \(role) for \(key) must be \"cell\"") }
            pane.insert(ch)
        }
        let missing = MajorPaneArt.stateNames.filter { raw.states[$0] == nil }
        guard missing.isEmpty else { throw fail("missing states: " + missing.joined(separator: ", ")) }
        let extra = raw.states.keys.filter { !MajorPaneArt.stateNames.contains($0) }.sorted()
        guard extra.isEmpty else { throw fail("unknown states: " + extra.joined(separator: ", ")) }
        var clips: [String: MajorPaneClip] = [:]
        for name in MajorPaneArt.stateNames {
            let c = raw.states[name]!
            guard c.fps > 0, c.fps <= 30 else { throw fail("\(name): fps must be a number in (0, 30]") }
            guard !c.frames.isEmpty else { throw fail("\(name): needs at least one frame") }
            for (i, frame) in c.frames.enumerated() {
                guard frame.count == h else { throw fail("\(name) frame \(i): needs \(h) rows") }
                for (y, row) in frame.enumerated() {
                    guard row.unicodeScalars.count == w else { throw fail("\(name) frame \(i) row \(y): needs \(w) characters") }
                    for s in row.unicodeScalars where s != "." && palette[Character(s)] == nil {
                        throw fail("\(name) frame \(i) row \(y): character not in the palette: \(s)")
                    }
                }
            }
            clips[name] = MajorPaneClip(fps: c.fps, loop: c.loop, frames: c.frames)
        }
        self.init(width: w, height: h, palette: palette, pane: pane, clips: clips)
    }

    /// One printable ASCII character, not space and not ".".
    static func pixelCharacter(_ s: String) -> Character? {
        let scalars = Array(s.unicodeScalars)
        guard scalars.count == 1, let c = scalars.first, c.value > 0x20, c.value < 0x7F, c != "." else { return nil }
        return Character(c)
    }

    /// "#RRGGBB" only.
    static func hexColor(_ s: String) -> UInt32? {
        let bytes = Array(s.utf8)
        guard bytes.count == 7, bytes[0] == UInt8(ascii: "#") else { return nil }
        var v: UInt32 = 0
        for b in bytes.dropFirst() {
            let d: UInt32
            switch b {
            case 48...57: d = UInt32(b) - 48
            case 65...70: d = UInt32(b) - 55
            case 97...102: d = UInt32(b) - 87
            default: return nil
            }
            v = v << 4 | d
        }
        return v
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed N tests, with 0 failures` (the whole suite: PanesCoreTests and PanesGlyphTests).

- [ ] **Step 5: Record the two refinements in the spec**

In `docs/superpowers/specs/2026-10-09-major-pane-design.md`, under **Renderer (PanesGlyph)**:
- Replace the `iconBitmap(size:)` sentence with: "The app icon is rendered by the site's `app-icons.swift` from `image(art:pose:scales:)` with a large scale and no interpolation (its `pixelArt` flag); PanesGlyph has no icon drawing of its own."
- Replace "with a selector for the pane's lit cells (none, quarter, half, all) and the app icon" with "a row of idle frame 0 with none, a quarter, a half and all cells lit, and the icon pose at 32x on a dark CSS tile".
- Under `MajorPaneRender`: drop `icon OUT.png [SIZE] [--frames F]`; keep `preview`.

- [ ] **Step 6: Commit**

```bash
git add Sources/PanesGlyph/MajorPaneArt.swift Tests/PanesGlyphTests/MajorPaneArtTests.swift docs/superpowers/specs/2026-10-09-major-pane-design.md
git commit -m "Major Pane: the art format in Swift (MajorPaneArt, loader, validation)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Generator, placeholder art, compiled frames, licence files

**Files:**
- Create: `scripts/gen_major_pane_frames.py`, `scripts/placeholder_frames.py`
- Create: `art/major-pane/placeholder/frames.json` (generated), `Sources/PanesGlyph/MajorPaneFrames.swift` (generated)
- Create: `art/LICENSE`, `NOTICE`
- Modify: `Sources/PanesGlyph/MajorPaneArt.swift` (add `shipped`)
- Test: `Tests/PanesGlyphTests/MajorPaneArtTests.swift` (drift test)

**Interfaces:**
- Consumes: `MajorPaneArt`, `MajorPaneClip` (Task 1).
- Produces: `public enum MajorPaneFrames { static let width, height: Int; palette: [Character: UInt32]; pane: Set<Character>; clips: [String: MajorPaneClip] }`; `MajorPaneArt.shipped`.
- CLI: `scripts/gen_major_pane_frames.py [INPUT] [--check] [--validate INPUT]`; `scripts/placeholder_frames.py` writes `art/major-pane/placeholder/frames.json`.

- [ ] **Step 1: Write the failing drift test**

Append to `MajorPaneArtTests`:

```swift
    /// …/panes-menubar/Tests/PanesGlyphTests/X.swift → …/panes-menubar
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testCompiledFramesMatchTheirSourceJSON() throws {
        let swift = try String(contentsOf: Self.repo.appendingPathComponent("Sources/PanesGlyph/MajorPaneFrames.swift"), encoding: .utf8)
        let line = try XCTUnwrap(swift.split(separator: "\n").first { $0.hasPrefix("// source: ") })
        let file = Self.repo.appendingPathComponent(String(line.dropFirst("// source: ".count)))
        let fromSource = try MajorPaneArt(json: Data(contentsOf: file))
        XCTAssertEqual(fromSource, MajorPaneArt.shipped,
                       "MajorPaneFrames.swift is out of sync with \(file.lastPathComponent); run scripts/gen_major_pane_frames.py")
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter MajorPaneArtTests 2>&1 | tail -5`
Expected: compile error `type 'MajorPaneArt' has no member 'shipped'`.

- [ ] **Step 3: Write the placeholder drawer**

```python
#!/usr/bin/env python3
# (MPL header as a # comment block)
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
```

- [ ] **Step 4: Write the generator**

`scripts/gen_major_pane_frames.py`, adapted from parity's `menubar/scripts/gen_polly_frames.py` (read it at `/Users/nicholassmith/Code/parity/menubar/scripts/gen_polly_frames.py` for the parts not shown here; the structure is identical):

```python
#!/usr/bin/env python3
# (MPL header)
"""Major Pane's frames (art/major-pane/…/frames.json) -> Sources/PanesGlyph/MajorPaneFrames.swift.

  gen_major_pane_frames.py INPUT             regenerate from INPUT (a file in this repo)
  gen_major_pane_frames.py                   regenerate from the source MajorPaneFrames.swift names
  gen_major_pane_frames.py --check           exit 1 if the committed Swift is stale
  gen_major_pane_frames.py --validate INPUT  only check INPUT against the format

Format (spec "Art format"): {"width", "height", "palette": {char: "#RRGGBB"},
"pane": {char: "cell"}, "states": {name: {"fps", "loop", "frames": [[rows]]}}}.
Exactly those five keys. "." is transparent; pane characters are the cells the
renderer lights. At most 12 palette colours. States: exactly idle, salute, bark,
at_ease. Canvas 1 to 64 each way. Python 3.9, stdlib only."""
from __future__ import annotations
import hashlib, json, re, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "Sources/PanesGlyph/MajorPaneFrames.swift"
STATES = ("idle", "salute", "bark", "at_ease")
PANE_ROLES = ("cell",)
TOP_KEYS = ("width", "height", "palette", "pane", "states")
MAX_COLOURS = 12
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
```

Then copy `source_of`, `generate`, `_in_repo`, `_shown` and `main` from gen_polly_frames.py verbatim, replacing every `gen_polly_frames` with `gen_major_pane_frames`, `PollyFrames.swift` with `MajorPaneFrames.swift` and `menubar/scripts/` with `scripts/`.

- [ ] **Step 5: Generate, add `shipped`, write the licence files**

Run:
```bash
chmod +x scripts/gen_major_pane_frames.py scripts/placeholder_frames.py
python3 scripts/placeholder_frames.py
python3 scripts/gen_major_pane_frames.py --validate art/major-pane/placeholder/frames.json
python3 scripts/gen_major_pane_frames.py art/major-pane/placeholder/frames.json
python3 scripts/gen_major_pane_frames.py --check && echo in-sync
```
Expected: `valid`, `wrote Sources/PanesGlyph/MajorPaneFrames.swift from art/major-pane/placeholder/frames.json`, `in-sync`.

Add to `MajorPaneArt` (after `topLevelKeys`):
```swift
    public static let shipped = MajorPaneArt(width: MajorPaneFrames.width, height: MajorPaneFrames.height,
                                             palette: MajorPaneFrames.palette, pane: MajorPaneFrames.pane,
                                             clips: MajorPaneFrames.clips)
```

`art/LICENSE`: the full Creative Commons Attribution-NonCommercial 4.0 International legal code, fetched from https://creativecommons.org/licenses/by-nc/4.0/legalcode.txt (`curl -fsSL … -o art/LICENSE`; check it starts with "Attribution-NonCommercial 4.0 International").

`NOTICE`:
```
Panes is Mozilla Public License 2.0 (LICENSE).

The Major Pane artwork — everything under art/, the generated
Sources/PanesGlyph/MajorPaneFrames.swift, Resources/bundle/AppIcon.icns and the
pictures under docs/ — is Copyright (c) 2026 Nicholas Smith and licensed under
Creative Commons Attribution-NonCommercial 4.0 International (art/LICENSE).
It may not be used commercially. Major Pane is an original character.
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: 0 failures, including `testCompiledFramesMatchTheirSourceJSON`.

- [ ] **Step 7: Commit**

```bash
git add scripts/gen_major_pane_frames.py scripts/placeholder_frames.py art/major-pane/placeholder/frames.json Sources/PanesGlyph/MajorPaneFrames.swift Sources/PanesGlyph/MajorPaneArt.swift Tests/PanesGlyphTests/MajorPaneArtTests.swift art/LICENSE NOTICE
git commit -m "Major Pane: frame generator, placeholder art, compiled frames, art licence

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Clip timing (`Animator`)

**Files:**
- Create: `Sources/PanesGlyph/Animator.swift`
- Test: `Tests/PanesGlyphTests/AnimatorTests.swift`

**Interfaces:**
- Produces: `public struct ClipTiming: Equatable { fps: Double; loop: Bool; count: Int }`; `public enum Animator { static func frame(elapsed: TimeInterval, timing: ClipTiming) -> (index: Int, done: Bool); static func nextChange(elapsed:timing:) -> TimeInterval?; static let minimumDelay = 1.0/60; static let boundarySlack = 0.002 }`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/PanesGlyphTests/AnimatorTests.swift
// (MPL header)
import XCTest
@testable import PanesGlyph

final class AnimatorTests: XCTestCase {
    func testLoopsOrHolds() {
        let loop = ClipTiming(fps: 4, loop: true, count: 4)
        XCTAssertEqual(Animator.frame(elapsed: 0, timing: loop).index, 0)
        XCTAssertEqual(Animator.frame(elapsed: 0.26, timing: loop).index, 1)
        XCTAssertEqual(Animator.frame(elapsed: 1.0, timing: loop).index, 0)
        XCTAssertFalse(Animator.frame(elapsed: 9, timing: loop).done)
        let once = ClipTiming(fps: 6, loop: false, count: 3)
        XCTAssertEqual(Animator.frame(elapsed: 0.2, timing: once).index, 1)
        XCTAssertFalse(Animator.frame(elapsed: 0.34, timing: once).done)
        XCTAssertEqual(Animator.frame(elapsed: 0.5, timing: once).index, 2)
        XCTAssertTrue(Animator.frame(elapsed: 0.5, timing: once).done)
    }

    func testOneFrameClipsAreDoneAtOnce() {
        XCTAssertTrue(Animator.frame(elapsed: 0, timing: ClipTiming(fps: 4, loop: false, count: 1)).done)
        XCTAssertFalse(Animator.frame(elapsed: 0, timing: ClipTiming(fps: 4, loop: true, count: 1)).done)
        XCTAssertNil(Animator.nextChange(elapsed: 0, timing: ClipTiming(fps: 4, loop: true, count: 1)))
    }

    func testNeverTrapsOnBadNumbers() {
        let once = ClipTiming(fps: 6, loop: false, count: 3)
        XCTAssertEqual(Animator.frame(elapsed: .infinity, timing: once).index, 2)
        XCTAssertTrue(Animator.frame(elapsed: 1e300, timing: once).done)
        XCTAssertEqual(Animator.frame(elapsed: .nan, timing: ClipTiming(fps: 6, loop: true, count: 3)).index, 0)
        XCTAssertEqual(Animator.frame(elapsed: -5, timing: once).index, 0)
        XCTAssertEqual(Animator.frame(elapsed: 1, timing: ClipTiming(fps: .infinity, loop: false, count: 3)).index, 2)
        XCTAssertNil(Animator.nextChange(elapsed: 1, timing: ClipTiming(fps: .infinity, loop: true, count: 3)))
    }

    func testNextChangeIsTheNextBoundaryAtTheClipsFps() {
        let loop = ClipTiming(fps: 4, loop: true, count: 2)
        XCTAssertEqual(Animator.nextChange(elapsed: 0, timing: loop)!, 0.25 + Animator.boundarySlack, accuracy: 1e-9)
        XCTAssertEqual(Animator.nextChange(elapsed: 0.1, timing: loop)!, 0.15 + Animator.boundarySlack, accuracy: 1e-9)
        XCTAssertEqual(Animator.nextChange(elapsed: 0.2499, timing: loop)!, Animator.minimumDelay, accuracy: 1e-9)
        let once = ClipTiming(fps: 4, loop: false, count: 2)
        XCTAssertEqual(Animator.nextChange(elapsed: 0.3, timing: once)!, 0.2 + Animator.boundarySlack, accuracy: 1e-9)
        XCTAssertNil(Animator.nextChange(elapsed: 0.6, timing: once))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AnimatorTests 2>&1 | tail -3`
Expected: `cannot find 'ClipTiming' in scope`.

- [ ] **Step 3: Implement**

```swift
// Sources/PanesGlyph/Animator.swift
// (MPL header)
import Foundation

/// A clip's timing, from the art (fps, loop, frame count).
public struct ClipTiming: Equatable {
    public var fps: Double
    public var loop: Bool
    public var count: Int
    public init(fps: Double, loop: Bool, count: Int) { self.fps = fps; self.loop = loop; self.count = count }
}

/// Which frame a clip shows at a time, and when it next changes. Pure.
public enum Animator {
    /// The frame `elapsed` seconds into a clip. A clip that doesn't loop holds
    /// its last frame, and `done` says it has finished.
    public static func frame(elapsed: TimeInterval, timing: ClipTiming) -> (index: Int, done: Bool) {
        guard timing.count > 1, timing.fps > 0 else { return (0, !timing.loop) }
        let ticks = (max(0, elapsed) * timing.fps).rounded(.down)
        // Int(_:) traps on NaN, infinity and huge values. A clip that far in has long finished.
        guard ticks.isFinite, ticks < 1e15 else { return timing.loop ? (0, false) : (timing.count - 1, true) }
        let n = Int(ticks)
        if timing.loop { return (n % timing.count, false) }
        return (min(n, timing.count - 1), n >= timing.count)
    }

    /// Added past a frame boundary, so a timer that fires a hair early still lands on the new frame.
    public static let boundarySlack: TimeInterval = 0.002
    /// The menu bar is never redrawn faster than this, whatever the art says.
    public static let minimumDelay: TimeInterval = 1.0 / 60

    /// Seconds from `elapsed` until the clip's frame next changes; nil when it never will
    /// (one frame, no usable fps, a one-shot that has finished). A one-shot's last boundary
    /// is the one where it finishes, so whoever draws it can settle it then.
    public static func nextChange(elapsed: TimeInterval, timing: ClipTiming) -> TimeInterval? {
        guard timing.count > 1, timing.fps > 0, timing.fps.isFinite else { return nil }
        let e = max(0, elapsed)
        let ticks = (e * timing.fps).rounded(.down)
        guard ticks.isFinite, ticks < 1e15 else { return nil }
        if !timing.loop && ticks >= Double(timing.count) { return nil }
        let boundary = (ticks + 1) / timing.fps
        return max(boundary - e + boundarySlack, minimumDelay)
    }
}
```

- [ ] **Step 4: Run the suite**

Run: `swift test 2>&1 | tail -3` → 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/PanesGlyph/Animator.swift Tests/PanesGlyphTests/AnimatorTests.swift
git commit -m "Major Pane: clip timing (Animator)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: The renderer and the pane's cells

**Files:**
- Create: `Sources/PanesGlyph/MajorPaneRenderer.swift`
- Test: `Tests/PanesGlyphTests/MajorPaneRendererTests.swift`

**Interfaces:**
- Consumes: `MajorPaneArt`, `MajorPaneClip`; `GridCell`, `LayoutGrid` from PanesCore.
- Produces:
  - `public struct MajorPanePose: Equatable { state: String; frame: Int; lit: Set<GridCell>; active: Bool }` with `init(state:frame:lit:active:)` (defaults `0`, `[]`, `true`).
  - `public enum PaneCells { static func lit(windows: [CGRect], visible: CGRect) -> Set<GridCell>; static let quarter, half, all: Set<GridCell> }` — `windows` back to front as `WindowMap.windows` returns them; the last is the front.
  - `public enum MajorPaneRenderer { static let litCell: UInt32 = 0xFFD166; static func cells(art:pose:) -> [[UInt32?]]; static func bitmap(art:pose:scale:) -> NSBitmapImageRep; static func image(art:pose:scales: [Int] = [1, 2, 3]) -> NSImage; static func greyed(_:) -> UInt32 }`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/PanesGlyphTests/MajorPaneRendererTests.swift
// (MPL header)
import AppKit
import XCTest
import PanesCore
@testable import PanesGlyph

final class MajorPaneRendererTests: XCTestCase {
    /// 6x5: an outline K at (0,0), skin S at (1,0), a 4x4 pane of p at x 2…5, y 1…4.
    let art = MajorPaneArt(
        width: 6, height: 5, palette: ["K": 0x000000, "S": 0xF2B98A, "p": 0x1E2A40], pane: ["p"],
        clips: ["idle": MajorPaneClip(fps: 4, loop: true, frames: [["KS....", "..pppp", "..pppp", "..pppp", "..pppp"]]),
                "salute": MajorPaneClip(fps: 8, loop: false, frames: [["KS....", "......", "......", "......", "......"]]),
                "bark": MajorPaneClip(fps: 8, loop: false, frames: [["KS....", "..pppp", "..pppp", "..pppp", "..pppp"]]),
                "at_ease": MajorPaneClip(fps: 2, loop: true, frames: [["KS....", "..pppp", "..pppp", "..pppp", "..pppp"]])])
    func cell(_ c: Int, _ r: Int) -> GridCell { GridCell(column: c, row: r) }

    func testPaletteColoursFollowTheMap() {
        let cells = MajorPaneRenderer.cells(art: art, pose: .init(state: "idle"))
        XCTAssertEqual(cells.count, 5); XCTAssertEqual(cells[0].count, 6)
        XCTAssertEqual(cells[0][0], 0x000000); XCTAssertEqual(cells[0][1], 0xF2B98A); XCTAssertNil(cells[0][2])
    }

    func testPanePixelsAreUnlitByDefaultAndLitByTheirCell() {
        let none = MajorPaneRenderer.cells(art: art, pose: .init(state: "idle"))
        XCTAssertEqual(none[1][2], 0x1E2A40)
        let lit = MajorPaneRenderer.cells(art: art, pose: .init(state: "idle", lit: [cell(0, 0), cell(3, 3)]))
        XCTAssertEqual(lit[1][2], MajorPaneRenderer.litCell)       // column 0, row 0 → top-left pane pixel
        XCTAssertEqual(lit[4][5], MajorPaneRenderer.litCell)       // column 3, row 3 → bottom-right
        XCTAssertEqual(lit[1][3], 0x1E2A40)                        // column 1, row 0 stays dark
    }

    func testCellsScaleToThePanesBox() {
        // An 8x8 pane: each cell is a 2x2 block.
        var frame = ["KS........"] + Array(repeating: "..pppppppp", count: 8)
        frame.append("..........")
        let big = MajorPaneArt(width: 10, height: 10, palette: art.palette, pane: ["p"],
                               clips: ["idle": MajorPaneClip(fps: 4, loop: true, frames: [frame])])
        let lit = MajorPaneRenderer.cells(art: big, pose: .init(state: "idle", lit: [cell(1, 2)]))
        for (x, y) in [(4, 5), (5, 5), (4, 6), (5, 6)] { XCTAssertEqual(lit[y][x], MajorPaneRenderer.litCell, "(\(x),\(y))") }
        XCTAssertEqual(lit[5][3], 0x1E2A40); XCTAssertEqual(lit[4][4], 0x1E2A40)
    }

    func testFrameWithoutAPaneDrawsAndLightsNothing() {
        let cells = MajorPaneRenderer.cells(art: art, pose: .init(state: "salute", lit: PaneCells.all))
        XCTAssertEqual(cells[0][0], 0x000000)
        XCTAssertTrue(cells[1...4].allSatisfy { $0.allSatisfy { $0 == nil } })
    }

    func testInactiveGreysEveryPixelByLuminance() {
        let grey = MajorPaneRenderer.cells(art: art, pose: .init(state: "at_ease", lit: PaneCells.all, active: false))
        XCTAssertEqual(grey[0][1], MajorPaneRenderer.greyed(0xF2B98A))
        XCTAssertEqual(grey[1][2], MajorPaneRenderer.greyed(MajorPaneRenderer.litCell))
        XCTAssertEqual(MajorPaneRenderer.greyed(0xFFFFFF), 0xFFFFFF)
        XCTAssertEqual(MajorPaneRenderer.greyed(0xFF0000), 0x4C4C4C)   // 299/1000 of 255 = 76
    }

    func testFrameIndexIsClampedToTheClip() {
        XCTAssertEqual(MajorPaneRenderer.cells(art: art, pose: .init(state: "idle", frame: 9)),
                       MajorPaneRenderer.cells(art: art, pose: .init(state: "idle", frame: 0)))
    }

    func testBitmapIsWholePixelBlocksAtEveryScale() {
        for scale in [1, 2, 3] {
            let rep = MajorPaneRenderer.bitmap(art: art, pose: .init(state: "idle", lit: [cell(0, 0)]), scale: scale)
            XCTAssertEqual(rep.pixelsWide, 6 * scale); XCTAssertEqual(rep.pixelsHigh, 5 * scale)
            XCTAssertEqual(rep.size, NSSize(width: 6, height: 5))
            for dy in 0..<scale { for dx in 0..<scale {
                XCTAssertEqual(rep.colorAt(x: 2 * scale + dx, y: 1 * scale + dy)!.redComponent, 1, accuracy: 0.01)
                XCTAssertEqual(rep.colorAt(x: 2 * scale + dx, y: 1 * scale + dy)!.alphaComponent, 1)
                XCTAssertEqual(rep.colorAt(x: 2 * scale + dx, y: 0 * scale + dy)!.alphaComponent, 0)
            } }
        }
    }

    func testImageCarriesOneBitmapPerScale() {
        let img = MajorPaneRenderer.image(art: art, pose: .init(state: "idle"))
        XCTAssertEqual(img.size, NSSize(width: 6, height: 5))
        XCTAssertEqual(img.representations.count, 3)
        XCTAssertEqual(MajorPaneRenderer.image(art: art, pose: .init(state: "idle"), scales: [1, 2, 32]).representations.map(\.pixelsWide), [6, 12, 192])
        XCTAssertFalse(img.isTemplate)
    }

    // MARK: PaneCells

    let visible = CGRect(x: 0, y: 37, width: 1512, height: 945)
    func testLitCellsFollowTheFrontWindow() {
        let grid = LayoutGrid()
        let half = grid.frame(for: GridSelection(cell(0, 0), cell(1, 3)), in: visible)
        XCTAssertEqual(PaneCells.lit(windows: [half], visible: visible), PaneCells.half)
        let quarter = grid.frame(for: GridSelection(cell(0, 0), cell(1, 1)), in: visible)
        XCTAssertEqual(PaneCells.lit(windows: [half, quarter], visible: visible), PaneCells.quarter)  // the last is the front
        XCTAssertEqual(PaneCells.lit(windows: [visible], visible: visible), PaneCells.all)
        XCTAssertEqual(PaneCells.lit(windows: [], visible: visible), [])
    }

    func testLitCellsIgnoreWindowsOffTheDisplay() {
        XCTAssertEqual(PaneCells.lit(windows: [CGRect(x: 5000, y: 100, width: 800, height: 600)], visible: visible), [])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter MajorPaneRendererTests 2>&1 | tail -3`
Expected: `cannot find 'MajorPaneRenderer' in scope`.

- [ ] **Step 3: Implement**

```swift
// Sources/PanesGlyph/MajorPaneRenderer.swift
// (MPL header)
import AppKit
import PanesCore

public struct MajorPanePose: Equatable {
    public var state: String
    public var frame: Int
    /// The pane's lit cells (column 0…3, row 0…3; row 0 is the top).
    public var lit: Set<GridCell>
    /// False without Accessibility: the whole glyph goes grey.
    public var active: Bool
    public init(state: String, frame: Int = 0, lit: Set<GridCell> = [], active: Bool = true) {
        self.state = state; self.frame = frame; self.lit = lit; self.active = active
    }
}

/// Which pane cells the front window lights (spec "The pane's cells").
public enum PaneCells {
    /// `windows` back to front, as `WindowMap.windows` returns them; the last is the front.
    public static func lit(windows: [CGRect], visible: CGRect) -> Set<GridCell> {
        guard let front = windows.last else { return [] }
        return LayoutGrid().cells(coveredBy: front, in: visible)
    }
    public static let all = Set(LayoutGrid().cells)
    public static let half = Set(LayoutGrid().cells.filter { $0.column < 2 })
    public static let quarter = Set(LayoutGrid().cells.filter { $0.column < 2 && $0.row < 2 })
}

/// Major Pane's pixels → bitmaps. Every art pixel becomes a whole block of
/// device pixels, written directly, so nothing is ever interpolated.
public enum MajorPaneRenderer {
    /// A lit cell: the amber the grid glyph gives the front window.
    public static let litCell: UInt32 = 0xFFD166

    /// The bounding box of the pane's pixels in a frame, nil when it has none.
    static func paneBox(_ frame: [String], pane: Set<Character>) -> (x: Int, y: Int, w: Int, h: Int)? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for (y, row) in frame.enumerated() {
            for (x, c) in row.enumerated() where pane.contains(c) {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }

    /// The colour of every art pixel for a pose: always `art.height` rows of `art.width`.
    /// A pane pixel is lit or dark by the 4×4 cell its position in the pane's box falls in.
    public static func cells(art: MajorPaneArt, pose: MajorPanePose) -> [[UInt32?]] {
        let clip = art.clip(pose.state)
        let frame = clip.frames.isEmpty ? [] : clip.frames[min(max(pose.frame, 0), clip.frames.count - 1)]
        let box = paneBox(frame, pane: art.pane)
        let width = max(art.width, 0), height = max(art.height, 0)
        return (0..<height).map { y in
            let row = y < frame.count ? Array(frame[y]) : []
            return (0..<width).map { x -> UInt32? in
                guard x < row.count, row[x] != "." else { return nil }
                var c: UInt32?
                if art.pane.contains(row[x]), let box {
                    let cell = GridCell(column: min(3, (x - box.x) * 4 / max(box.w, 1)), row: min(3, (y - box.y) * 4 / max(box.h, 1)))
                    c = pose.lit.contains(cell) ? litCell : art.palette[row[x]]
                } else {
                    c = art.palette[row[x]]
                }
                if !pose.active, let v = c { c = greyed(v) }
                return c
            }
        }
    }

    /// Greyed by luminance (Rec. 601).
    public static func greyed(_ c: UInt32) -> UInt32 {
        let r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF
        let l = (r * 299 + g * 587 + b * 114) / 1000
        return (l << 16) | (l << 8) | l
    }

    static func blank(_ w: Int, _ h: Int) -> NSBitmapImageRep {
        let w = max(w, 1), h = max(h, 1)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
        memset(rep.bitmapData!, 0, rep.bytesPerRow * h)
        return rep
    }

    static func fill(_ rep: NSBitmapImageRep, x: Int, y: Int, size: Int, color: UInt32) {
        let x0 = max(x, 0), x1 = min(x + size, rep.pixelsWide), y0 = max(y, 0), y1 = min(y + size, rep.pixelsHigh)
        guard x0 < x1, y0 < y1, let data = rep.bitmapData else { return }
        let r = UInt8((color >> 16) & 0xFF), g = UInt8((color >> 8) & 0xFF), b = UInt8(color & 0xFF)
        for py in y0..<y1 {
            var p = data + py * rep.bytesPerRow + x0 * 4
            for _ in x0..<x1 { p[0] = r; p[1] = g; p[2] = b; p[3] = 255; p += 4 }
        }
    }

    /// One pose, `scale` device pixels per art pixel; its point size is the art's grid.
    public static func bitmap(art: MajorPaneArt, pose: MajorPanePose, scale: Int) -> NSBitmapImageRep {
        let scale = max(scale, 1)
        let rep = blank(art.width * scale, art.height * scale)
        for (y, line) in cells(art: art, pose: pose).enumerated() {
            for (x, c) in line.enumerated() { if let c { fill(rep, x: x * scale, y: y * scale, size: scale, color: c) } }
        }
        let out = rep.retagging(with: .sRGB) ?? rep
        out.size = NSSize(width: art.width, height: art.height)
        return out
    }

    /// The status-item image: one bitmap per scale, all of one point size. AppKit
    /// draws the one that matches the bar's backing scale, 1:1. The site passes
    /// a large extra scale for the app icon.
    public static func image(art: MajorPaneArt, pose: MajorPanePose, scales: [Int] = [1, 2, 3]) -> NSImage {
        let image = NSImage(size: NSSize(width: art.width, height: art.height))
        for s in scales { image.addRepresentation(bitmap(art: art, pose: pose, scale: s)) }
        image.isTemplate = false
        return image
    }
}
```

- [ ] **Step 4: Run the suite**

Run: `swift test 2>&1 | tail -3` → 0 failures. If `testInactiveGreysEveryPixelByLuminance`'s `0xFF0000 → 0x4C4C4C` fails, check the arithmetic (255×299/1000 = 76 = 0x4C); fix the code, not the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/PanesGlyph/MajorPaneRenderer.swift Tests/PanesGlyphTests/MajorPaneRendererTests.swift
git commit -m "Major Pane: renderer (whole-pixel bitmaps, pane cells lit from the front window, greyed when inactive)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: The pose driver (`MascotDriver`)

**Files:**
- Create: `Sources/PanesGlyph/MascotDriver.swift`
- Test: `Tests/PanesGlyphTests/MascotDriverTests.swift`

**Interfaces:**
- Consumes: `ClipTiming`, `Animator` (Task 3).
- Produces: `public enum MascotState: String, CaseIterable { case idle, salute, bark, atEase = "at_ease" }`; `public struct MascotDriver { init(now: Date); mutating func update(active: Bool, now: Date); mutating func salute(now: Date); mutating func bark(now: Date); mutating func pose(now:timing:reduceMotion:) -> (state: MascotState, frame: Int); func nextFrameDelay(now:timing:reduceMotion:) -> TimeInterval?; var steady: MascotState; var playing: MascotState?; var pendingBark: Bool }`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/PanesGlyphTests/MascotDriverTests.swift
// (MPL header)
import XCTest
@testable import PanesGlyph

final class MascotDriverTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    /// idle loops 2 frames at 4 fps (0.5 s); salute 4 frames at 8 fps (0.5 s); bark 2 frames at 8 fps (0.25 s); at_ease 2 at 2 fps.
    func timing(_ s: MascotState) -> ClipTiming {
        switch s {
        case .idle: return ClipTiming(fps: 4, loop: true, count: 2)
        case .salute: return ClipTiming(fps: 8, loop: false, count: 4)
        case .bark: return ClipTiming(fps: 8, loop: false, count: 2)
        case .atEase: return ClipTiming(fps: 2, loop: true, count: 2)
        }
    }
    func pose(_ d: inout MascotDriver, _ s: Double, reduce: Bool = false) -> (state: MascotState, frame: Int) {
        d.pose(now: at(s), timing: timing, reduceMotion: reduce)
    }

    func testIdleLoopsFromWhenItStarted() {
        var d = MascotDriver(now: t0)
        XCTAssertEqual(pose(&d, 0).state, .idle); XCTAssertEqual(pose(&d, 0).frame, 0)
        XCTAssertEqual(pose(&d, 0.3).frame, 1)
        XCTAssertEqual(pose(&d, 0.5).frame, 0)
    }

    func testSalutePlaysOnceThenIdleResumes() {
        var d = MascotDriver(now: t0)
        d.salute(now: at(1))
        XCTAssertEqual(pose(&d, 1).state, .salute); XCTAssertEqual(pose(&d, 1.3).frame, 2)
        XCTAssertEqual(pose(&d, 1.6).state, .idle)
        XCTAssertNil(d.playing)
    }

    func testACueDuringAnyOneShotIsSkipped() {
        var d = MascotDriver(now: t0)
        d.bark(now: at(1))
        d.salute(now: at(1.1))
        XCTAssertEqual(pose(&d, 1.1).state, .bark)
        XCTAssertEqual(pose(&d, 1.3).state, .idle)       // bark is 0.25 s; no salute follows
    }

    func testABarkDuringASaluteWaitsAndThenPlays() {
        var d = MascotDriver(now: t0)
        d.salute(now: at(1))
        d.bark(now: at(1.2))
        XCTAssertEqual(pose(&d, 1.2).state, .salute)
        XCTAssertTrue(d.pendingBark)
        XCTAssertEqual(pose(&d, 1.55).state, .bark)      // salute ended at 1.5
        XCTAssertFalse(d.pendingBark)
        XCTAssertEqual(pose(&d, 1.9).state, .idle)
    }

    func testOnlyOneBarkIsEverQueued() {
        var d = MascotDriver(now: t0)
        d.bark(now: at(1)); d.bark(now: at(1.05)); d.bark(now: at(1.1))
        XCTAssertEqual(pose(&d, 1.3).state, .bark)        // the queued one
        XCTAssertEqual(pose(&d, 1.6).state, .idle)        // and no third
    }

    func testAtEaseIsTheSteadyPoseAndNothingPlaysThere() {
        var d = MascotDriver(now: t0)
        d.salute(now: at(1))
        d.update(active: false, now: at(1.1))
        XCTAssertEqual(pose(&d, 1.1).state, .atEase); XCTAssertNil(d.playing); XCTAssertFalse(d.pendingBark)
        d.salute(now: at(2)); d.bark(now: at(2))
        XCTAssertEqual(pose(&d, 2).state, .atEase)
        XCTAssertEqual(pose(&d, 2.6).frame, 1)            // the at_ease loop runs from 1.1
        d.update(active: true, now: at(3))
        XCTAssertEqual(pose(&d, 3).state, .idle); XCTAssertEqual(pose(&d, 3).frame, 0)
    }

    func testOneFrameOneShotFinishesAtOnce() {
        var d = MascotDriver(now: t0)
        d.salute(now: at(1))
        let one: (MascotState) -> ClipTiming = { $0 == .salute ? ClipTiming(fps: 8, loop: false, count: 1) : self.timing($0) }
        XCTAssertEqual(d.pose(now: at(1), timing: one, reduceMotion: false).state, .idle)
        XCTAssertNil(d.playing)
    }

    func testClockSteppingBackEndsAOneShot() {
        var d = MascotDriver(now: t0)
        d.salute(now: at(100))
        XCTAssertEqual(pose(&d, 50).state, .idle)
        XCTAssertNil(d.playing)
        XCTAssertEqual(pose(&d, 50).frame, 0)             // idle restarts from now, never from the future
    }

    func testReduceMotionClearsEverythingPlaying() {
        var d = MascotDriver(now: t0)
        d.salute(now: at(1)); d.bark(now: at(1.1))
        XCTAssertEqual(pose(&d, 1.2, reduce: true).state, .idle)
        XCTAssertEqual(pose(&d, 1.2, reduce: true).frame, 0)
        XCTAssertNil(d.playing); XCTAssertFalse(d.pendingBark)
        XCTAssertNil(d.nextFrameDelay(now: at(1.2), timing: timing, reduceMotion: true))
    }

    func testNextFrameDelayFollowsWhatPlays() {
        var d = MascotDriver(now: t0)
        XCTAssertEqual(d.nextFrameDelay(now: at(0.1), timing: timing, reduceMotion: false)!, 0.15 + Animator.boundarySlack, accuracy: 1e-6)
        d.salute(now: at(1))
        XCTAssertEqual(d.nextFrameDelay(now: at(1), timing: timing, reduceMotion: false)!, 0.125 + Animator.boundarySlack, accuracy: 1e-6)
        let still: (MascotState) -> ClipTiming = { _ in ClipTiming(fps: 4, loop: true, count: 1) }
        var s = MascotDriver(now: t0)
        XCTAssertNil(s.nextFrameDelay(now: at(0), timing: still, reduceMotion: false))
        _ = s.pose(now: at(0), timing: still, reduceMotion: false)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter MascotDriverTests 2>&1 | tail -3` → `cannot find 'MascotDriver' in scope`.

- [ ] **Step 3: Implement**

```swift
// Sources/PanesGlyph/MascotDriver.swift
// (MPL header)
import Foundation

public enum MascotState: String, CaseIterable {
    case idle, salute, bark
    case atEase = "at_ease"
}

/// Which clip plays and when (spec "What he does"). The steady pose is idle
/// or at ease. Two things play once over idle: the salute (minute cue) and the
/// bark (a window moved). A one-shot never interrupts another: a cue during a
/// one-shot is skipped; a bark during a one-shot waits (one at most) and plays
/// after. Under Reduce Motion every pose is its frame 0. Pure: the app owns
/// the clock and the timer.
public struct MascotDriver {
    public private(set) var steady: MascotState = .idle
    public private(set) var steadySince: Date
    public private(set) var playing: MascotState?
    public private(set) var playingSince: Date?
    public private(set) var pendingBark = false

    public init(now: Date) { steadySince = now }

    private static func once(_ t: ClipTiming) -> ClipTiming { ClipTiming(fps: t.fps, loop: false, count: t.count) }

    public mutating func update(active: Bool, now: Date) {
        let new: MascotState = active ? .idle : .atEase
        guard new != steady else { return }
        steady = new
        steadySince = now
        playing = nil; playingSince = nil; pendingBark = false
    }

    /// The minute cue: only an idle Major Pane with nothing playing salutes.
    public mutating func salute(now: Date) {
        guard steady == .idle, playing == nil else { return }
        playing = .salute; playingSince = now
    }

    /// A window moved: bark now, or after whatever plays.
    public mutating func bark(now: Date) {
        guard steady == .idle else { return }
        if playing == nil { playing = .bark; playingSince = now } else { pendingBark = true }
    }

    public mutating func pose(now: Date, timing: (MascotState) -> ClipTiming, reduceMotion: Bool) -> (state: MascotState, frame: Int) {
        if reduceMotion {
            playing = nil; playingSince = nil; pendingBark = false
            return (steady, 0)
        }
        // The wall clock can step back (NTP, a manual change, wake): a one-shot dated
        // in the future is over, and the steady clip starts again from now.
        if let start = playingSince, start > now { playing = nil; playingSince = nil }
        if steadySince > now { steadySince = now }
        if let state = playing, let start = playingSince {
            let t = MascotDriver.once(timing(state))
            let f = Animator.frame(elapsed: now.timeIntervalSince(start), timing: t)
            if !f.done { return (state, f.index) }
            playing = nil; playingSince = nil
            // The one-shot ended on the steady clip's frame 0; count the idle from its end, not this draw.
            let length = t.count > 1 && t.fps > 0 && t.fps.isFinite ? Double(t.count) / t.fps : 0
            steadySince = min(start.addingTimeInterval(length), now)
            if pendingBark {
                pendingBark = false
                playing = .bark; playingSince = now
                return pose(now: now, timing: timing, reduceMotion: false)
            }
        }
        return (steady, Animator.frame(elapsed: now.timeIntervalSince(steadySince), timing: timing(steady)).index)
    }

    /// How long until the frame on show changes without new input; nil when nothing moves.
    /// A finished one-shot that no `pose` has settled yet is due at once.
    public func nextFrameDelay(now: Date, timing: (MascotState) -> ClipTiming, reduceMotion: Bool) -> TimeInterval? {
        if reduceMotion { return nil }
        if let state = playing, let start = playingSince, start <= now {
            return Animator.nextChange(elapsed: now.timeIntervalSince(start), timing: MascotDriver.once(timing(state))) ?? Animator.minimumDelay
        }
        if playing != nil { return Animator.minimumDelay }
        return Animator.nextChange(elapsed: now.timeIntervalSince(min(steadySince, now)), timing: timing(steady))
    }
}
```

- [ ] **Step 4: Run the suite** → 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/PanesGlyph/MascotDriver.swift Tests/PanesGlyphTests/MascotDriverTests.swift
git commit -m "Major Pane: pose driver (idle/at ease, salute and bark played once, one queued bark, Reduce Motion)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: The review preview and its command

**Files:**
- Create: `Sources/PanesGlyph/MajorPanePreview.swift`, `Sources/MajorPaneRender/main.swift`
- Modify: `Package.swift`
- Test: `Tests/PanesGlyphTests/MajorPanePreviewTests.swift`

**Interfaces:**
- Consumes: `MajorPaneArt`, `MajorPaneRenderer`, `MajorPanePose`, `PaneCells`.
- Produces: `public enum MajorPanePreview { static func html(art: MajorPaneArt) -> String }`; executable `major-pane-render preview OUT.html [--frames FILE]`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PanesGlyphTests/MajorPanePreviewTests.swift
// (MPL header)
import XCTest
@testable import PanesGlyph

final class MajorPanePreviewTests: XCTestCase {
    func testPreviewShowsEveryClipTheLitRowAndTheIcon() {
        let html = MajorPanePreview.html(art: MajorPaneArt.shipped)
        XCTAssertTrue(html.contains("<title>Major Pane Preview</title>"))
        for name in MajorPaneArt.stateNames { XCTAssertTrue(html.contains("<h2>\(name)</h2>"), name) }
        XCTAssertEqual(html.components(separatedBy: "class=\"zoom\"").count - 1, 4)
        XCTAssertEqual(html.components(separatedBy: "class=\"lit\"").count - 1, 4)   // none, quarter, half, all
        XCTAssertTrue(html.contains("class=\"icon\""))
        XCTAssertTrue(html.contains(".pt { width: \(MajorPaneArt.shipped.width)px; height: \(MajorPaneArt.shipped.height)px; }"))
        XCTAssertFalse(html.contains("Payne"))
    }
}
```

- [ ] **Step 2: Run to verify failure** → `cannot find 'MajorPanePreview' in scope`.

- [ ] **Step 3: Implement the preview**

```swift
// Sources/PanesGlyph/MajorPanePreview.swift
// (MPL header)
import AppKit

/// The review-gate page (spec "Process and gates", step 5): every clip animating
/// at its fps at menu-bar size on a light and a dark bar and 8x enlarged, a row
/// of idle frame 0 with none, a quarter, a half and all cells lit, and the
/// icon pose at 32x on a dark tile.
public enum MajorPanePreview {
    static func png(_ rep: NSBitmapImageRep) -> String {
        "data:image/png;base64," + (rep.representation(using: .png, properties: [:]) ?? Data()).base64EncodedString()
    }
    static func number(_ v: Double) -> String { v.rounded() == v && abs(v) < 1e9 ? String(Int(v)) : String(v) }

    public static func html(art: MajorPaneArt) -> String {
        var cards = "", data: [String] = []
        for name in MajorPaneArt.stateNames {
            let clip = art.clip(name)
            let frames = clip.frames.indices.map {
                "\"" + png(MajorPaneRenderer.bitmap(art: art, pose: MajorPanePose(state: name, frame: $0, lit: PaneCells.quarter, active: name != "at_ease"), scale: 2)) + "\""
            }.joined(separator: ",")
            data.append("\"\(name)\":{\"fps\":\(number(clip.fps)),\"loop\":\(clip.loop),\"frames\":[\(frames)]}")
            let n = clip.frames.count
            cards += """
            <section class="card"><h2>\(name)</h2><p>\(n) frame\(n == 1 ? "" : "s") · \(number(clip.fps)) fps · \(clip.loop ? "loops" : "plays once")</p>
            <div class="bars"><div class="bar light"><img class="pt" data-state="\(name)" alt=""></div><div class="bar dark"><img class="pt" data-state="\(name)" alt=""></div></div>
            <img class="zoom" data-state="\(name)" alt="\(name), enlarged"></section>

            """
        }
        let lit = [("none", Set<GridCell>()), ("quarter", PaneCells.quarter), ("half", PaneCells.half), ("all", PaneCells.all)].map { label, cells in
            "<figure><img class=\"lit pt\" src=\"\(png(MajorPaneRenderer.bitmap(art: art, pose: MajorPanePose(state: "idle", lit: cells), scale: 2)))\" alt=\"\"><figcaption>\(label)</figcaption></figure>"
        }.joined()
        let icon = png(MajorPaneRenderer.bitmap(art: art, pose: MajorPanePose(state: "idle", lit: PaneCells.quarter), scale: 32))
        return template(cards: cards, lit: lit, data: "{" + data.joined(separator: ",") + "}", icon: icon, width: art.width, height: art.height)
    }

    static func template(cards: String, lit: String, data: String, icon: String, width: Int, height: Int) -> String {
        #"""
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Major Pane Preview</title>
        <style>
        :root { --bg: #f5f5f3; --fg: #1d1d1f; --muted: #6e6e73; --card: #ffffff; --line: #d9d9de; }
        @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #161618; --fg: #f2f2f2; --muted: #a1a1a6; --card: #232326; --line: #3a3a3d; } }
        :root[data-theme="dark"] { --bg: #161618; --fg: #f2f2f2; --muted: #a1a1a6; --card: #232326; --line: #3a3a3d; }
        body { margin: 0; padding: 24px 16px; background: var(--bg); color: var(--fg); font: 15px/1.4 -apple-system, system-ui, sans-serif; }
        h1 { font-size: 22px; margin: 0 0 4px; } .lede { color: var(--muted); margin: 0 0 20px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 16px; }
        .card { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 14px; min-width: 0; }
        .card h2 { font-size: 15px; margin: 0; font-family: ui-monospace, monospace; }
        .card p { color: var(--muted); margin: 2px 0 10px; font-size: 13px; }
        .bars { display: flex; gap: 8px; margin-bottom: 8px; align-items: center; }
        .bar { flex: 1; height: \#(max(24, height + 2))px; border-radius: 6px; display: flex; align-items: center; justify-content: center; }
        .light { background: #e8e8e8; } .dark { background: #262626; }
        img { image-rendering: pixelated; }
        .pt { width: \#(width)px; height: \#(height)px; }
        .zoom { width: \#(width * 8)px; aspect-ratio: \#(width) / \#(height); height: auto; max-width: 100%; display: block; margin: 0 auto; }
        .row { display: flex; gap: 24px; flex-wrap: wrap; margin: 8px 0 24px; } figure { margin: 0; text-align: center; color: var(--muted); font-size: 12px; }
        .row img { width: \#(width * 4)px; height: \#(height * 4)px; background: #262626; padding: 8px; border-radius: 8px; }
        .tile { width: 256px; height: 256px; border-radius: 56px; background: linear-gradient(#2B2E35, #15171B); display: flex; align-items: center; justify-content: center; }
        .icon { width: \#(width * 6)px; height: \#(height * 6)px; }
        </style></head><body>
        <h1>Major Pane Preview</h1>
        <p class="lede">Every clip as Panes draws it: menu-bar size on a light and a dark bar (a quarter lit; at_ease greyed), and enlarged 8×. Then idle with the pane none / a quarter / a half / all lit, and the icon pose.</p>
        <div class="grid">
        \#(cards)</div>
        <h2>The pane</h2><div class="row">\#(lit)</div>
        <h2>App icon pose</h2><div class="tile"><img class="icon" src="\#(icon)" alt="Major Pane, the app icon pose"></div>
        <script>
        const clips = \#(data);
        for (const [name, c] of Object.entries(clips)) {
          const imgs = document.querySelectorAll(`img[data-state="${name}"]`);
          let i = 0; const show = () => { for (const im of imgs) im.src = c.frames[i]; };
          show();
          if (c.frames.length > 1) setInterval(() => { i = c.loop ? (i + 1) % c.frames.length : Math.min(i + 1, c.frames.length - 1); if (!c.loop && i === c.frames.length - 1) setTimeout(() => { i = 0; show(); }, 1500); show(); }, 1000 / c.fps);
        }
        </script>
        </body></html>
        """#
    }
}
```

Add `import PanesCore` at the top (for `GridCell`).

- [ ] **Step 4: The executable**

`Package.swift`: add `.executable(name: "major-pane-render", targets: ["MajorPaneRender"])` to `products` and `.executableTarget(name: "MajorPaneRender", dependencies: ["PanesGlyph"])` to `targets`.

```swift
// Sources/MajorPaneRender/main.swift
// (MPL header)
import Foundation
import PanesGlyph

/// major-pane-render preview OUT.html [--frames FRAMES.json]
/// Renders the review page from the compiled art, or from a frames file.
let args = Array(CommandLine.arguments.dropFirst())
func usage() -> Never {
    FileHandle.standardError.write(Data("usage: major-pane-render preview OUT.html [--frames FRAMES.json]\n".utf8))
    exit(2)
}
guard args.count >= 2, args[0] == "preview" else { usage() }
var art = MajorPaneArt.shipped
if let i = args.firstIndex(of: "--frames") {
    guard i + 1 < args.count else { usage() }
    do { art = try MajorPaneArt(json: Data(contentsOf: URL(fileURLWithPath: args[i + 1]))) }
    catch { FileHandle.standardError.write(Data("major-pane-render: \(error)\n".utf8)); exit(1) }
}
let out = URL(fileURLWithPath: args[1])
do { try Data(MajorPanePreview.html(art: art).utf8).write(to: out) } catch { FileHandle.standardError.write(Data("major-pane-render: \(error)\n".utf8)); exit(1) }
print("wrote \(out.path)")
```

- [ ] **Step 5: Run the suite and the command**

Run: `swift test 2>&1 | tail -3` → 0 failures.
Run: `swift run -c release major-pane-render preview /private/tmp/claude-501/-Users-nicholassmith/032abe3e-761c-413d-af07-f61be99c0d32/scratchpad/mp-preview.html && grep -c 'class="zoom"' /private/tmp/claude-501/-Users-nicholassmith/032abe3e-761c-413d-af07-f61be99c0d32/scratchpad/mp-preview.html`
Expected: `wrote …/mp-preview.html` then `4`. Don't open it.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/PanesGlyph/MajorPanePreview.swift Sources/MajorPaneRender/main.swift Tests/PanesGlyphTests/MajorPanePreviewTests.swift
git commit -m "Major Pane: review preview page and major-pane-render

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: The app: controller, icon style, wiring

**Files:**
- Create: `Sources/Panes/MascotController.swift`
- Modify: `Sources/Panes/main.swift`

**Interfaces:**
- Consumes: `MajorPaneArt.shipped`, `MajorPaneRenderer.image`, `MajorPanePose`, `PaneCells.lit`, `MascotDriver`, `MascotState`, `ClipTiming`, `Animator`; `StatusItemController.setIcon`, `MinuteCue`, `IconAnimation` from StatusItemKit.
- Produces: `MascotController(status:)` with `start()`, `enabled: Bool`, `show(active:lit:)`, `salute()`, `bark()`; `UserDefaults` key `IconStyle` ∈ {`major-pane` (default), `grid`}.

- [ ] **Step 1: Write `MascotController`**

```swift
// Sources/Panes/MascotController.swift
// (MPL header)
import AppKit
import PanesCore
import PanesGlyph
import StatusItemKit

/// Draws Major Pane in the status item: the steady pose, the salute and the bark,
/// at the playing clip's own fps on one re-aimed one-shot timer, parked while
/// the displays sleep, under Reduce Motion, or while the grid icon is chosen.
@MainActor
final class MascotController {
    private let status: StatusItemController
    private let art = MajorPaneArt.shipped
    private var driver: MascotDriver
    private var lit = Set<GridCell>()
    private var active = true
    private var asleep = false
    private var drawn: MajorPanePose?
    private var frameTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    /// False while the grid icon is chosen: nothing is drawn or scheduled.
    var enabled = false {
        didSet { guard enabled != oldValue else { return }; drawn = nil; redraw() }
    }

    init(status: StatusItemController) {
        self.status = status
        driver = MascotDriver(now: Date())
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.redraw() }
        })
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setAsleep(true) }
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setAsleep(false) }
            })
        }
        redraw()
    }

    /// The trust state and the front window's cells, from every icon refresh.
    func show(active: Bool, lit: Set<GridCell>) {
        self.active = active
        self.lit = lit
        driver.update(active: active, now: Date())
        redraw()
    }

    func salute() { driver.salute(now: Date()); redraw() }
    func bark() { driver.bark(now: Date()); redraw() }

    private func setAsleep(_ value: Bool) {
        guard asleep != value else { return }
        asleep = value
        redraw()
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func timing(_ s: MascotState) -> ClipTiming {
        let c = art.clip(s.rawValue)
        return ClipTiming(fps: c.fps, loop: c.loop, count: c.frames.count)
    }

    /// Draw the pose for now and aim the timer at the next frame boundary.
    private func redraw() {
        frameTimer?.invalidate(); frameTimer = nil
        guard enabled else { return }
        let now = Date(), reduce = reduceMotion || asleep
        let p = driver.pose(now: now, timing: { self.timing($0) }, reduceMotion: reduce)
        let pose = MajorPanePose(state: p.state.rawValue, frame: p.frame, lit: lit, active: active)
        if pose != drawn {
            drawn = pose
            status.setIcon(MajorPaneRenderer.image(art: art, pose: pose))
        }
        guard let delay = driver.nextFrameDelay(now: now, timing: { self.timing($0) }, reduceMotion: reduce) else { return }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.redraw() }
        }
        RunLoop.main.add(t, forMode: .common)       // keeps playing while a menu is open
        frameTimer = t
    }
}
```

- [ ] **Step 2: Wire it into `main.swift`**

In `App`:

```swift
    /// Major Pane, when he is the icon (Settings ▸ Icon).
    private var mascot: MascotController?
    private static let iconStyleKey = "IconStyle"
    /// "major-pane" (default) or "grid".
    private var iconStyle: String {
        get { UserDefaults.standard.string(forKey: Self.iconStyleKey) ?? "major-pane" }
        set { UserDefaults.standard.set(newValue, forKey: Self.iconStyleKey) }
    }
    private var mascotChosen: Bool { iconStyle == "major-pane" }
```

In `applicationDidFinishLaunching`, right after `yieldClient.start()` (before anything can call `refreshIcon`):
```swift
        let mascot = MascotController(status: status)
        mascot.enabled = mascotChosen
        mascot.start()
        self.mascot = mascot
```
Change `mover.onMoved`:
```swift
        mover.onMoved = { [weak self] in
            self?.refreshIcon(force: true)
            if self?.mascotChosen == true { self?.mascot?.bark() }
        }
```
Change the cue: `minuteCue = MinuteCue { [weak self] in self?.minuteCueFired() }` and add:
```swift
    /// Panes's slot in the Menumon minute cue: Major Pane salutes, or the grid's tiles slide.
    private func minuteCueFired() {
        if mascotChosen { mascot?.salute() } else { slideTiles() }
    }
```
Replace `refreshIcon`:
```swift
    private func refreshIcon(force: Bool = false) {
        guard let status, slide?.isRunning != true else { return }
        let m = iconModel()
        var sig = Hasher()
        sig.combine(WindowMap.signature(m.windows + [m.display]))
        sig.combine(m.active)
        sig.combine(iconStyle)
        let s = sig.finalize()
        guard force || s != iconSignature else { return }
        iconSignature = s
        if mascotChosen {
            mascot?.show(active: m.active, lit: PaneCells.lit(windows: m.windows, visible: visibleFrameOfIconDisplay()))
        } else {
            status.setIcon(ScreenGridIcon.image(m))
        }
    }

    /// The visible frame (AX coordinates) of the display the icon draws, the one `iconModel()` picks.
    private func visibleFrameOfIconDisplay() -> CGRect {
        let m = iconModel()
        return Screens.displays.first { $0.frame == m.display }?.visibleFrame ?? m.display
    }
```
(`iconModel()` is called twice on a refresh; that is a window-list read, fine at 1.5 s. If you prefer, make `iconModel()` return the display index too.)

The Icon submenu, inside the `SettingsMenu.addFooter` closure before `Preferences…`:
```swift
            let icon = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
            let pick = NSMenu()
            for (title, style) in [("Major Pane", "major-pane"), ("Screen Grid", "grid")] {
                let item = self.actionItem(title, #selector(self.chooseIcon(_:)))
                item.representedObject = style
                item.state = self.iconStyle == style ? .on : .off
                pick.addItem(item)
            }
            icon.submenu = pick
            sub.addItem(icon)
```
And the selector, with the menu selectors:
```swift
    @objc private func chooseIcon(_ sender: NSMenuItem) {
        iconStyle = sender.representedObject as? String ?? "major-pane"
        slide?.cancel(); slide = nil
        mascot?.enabled = mascotChosen
        refreshIcon(force: true)
    }
```

- [ ] **Step 3: Build, launch-check, look**

Run: `swift build 2>&1 | grep -E "error|warning: unused" ; scripts/build-app.sh 2>&1 | tail -2`
Expected: no errors; `build/Panes.app` assembled.
Run: `../StatusItemKit/scripts/release/smoke-launch.sh build/Panes.app 5`
Expected: `✓ Panes stayed up for 5 s`. (This is the launch check added 2026-10-08; a crash prints the backtrace. Note: it launches a second copy beside the running Panes for 5 s, which is expected.)
Then quit the running Panes gracefully and run the new build to see him: `osascript -e 'tell application "Panes" to quit'; open build/Panes.app`. Look at the bar with StatusItemKit's capture script if needed (`../StatusItemKit/scripts/capture-menu.sh`, see memory note: its initial Escape interrupts Claude Code, so prefer `screencapture -R` of the bar's right end and Read the PNG). Check: the placeholder figure shows; it breathes (two frames); open Settings ▸ Icon ▸ Screen Grid → the grid returns; back to Major Pane → he returns; tile a window with ⌥⌘← → the pane lights the left half and he barks.
Afterwards relaunch the installed copy: `osascript -e 'tell application "Panes" to quit'; open ~/Applications/Panes.app`.

- [ ] **Step 4: Run the suite** → 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/Panes/MascotController.swift Sources/Panes/main.swift
git commit -m "Major Pane in the menu bar: idle, salute on the cue, bark on a move, at ease without Accessibility; Settings ▸ Icon keeps the grid

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: The site's renderers draw Major Pane

**Files (in `/Users/nicholassmith/Code/widgets.nicksmith.software`):**
- Modify: `art/glyphs/render-glyphs.sh`, `art/glyphs/app-icons.sh`, `art/glyphs/app-icons.swift`, `art/glyphs/anim.swift`, `art/glyphs/main.swift`, `site/daemons.json`

**Interfaces:**
- Consumes: `MajorPaneArt.shipped`, `MajorPaneRenderer.image(art:pose:scales:)`, `MajorPanePose`, `PaneCells`, `Animator`, `ClipTiming`, `ScreenGridIcon` (the alternate icon).

- [ ] **Step 1: Copy the new sources into both renderers**

`render-glyphs.sh`, after the `sed … ScreenGridIcon.swift` line:
```bash
for f in MajorPaneArt MajorPaneFrames MajorPaneRenderer Animator; do
  sed '/^import PanesCore$/d' "$code/panes-menubar/Sources/PanesGlyph/$f.swift" > "$work/panes/$f.swift"
done
```
`app-icons.sh`: add `Grid.swift` to the PanesCore copy list (`{WindowMap,Geometry,FrameCalculator,WindowAction,Grid}.swift`) and the same `for` loop writing into `$work/src/`. Update the two "Panes has no character" comments to "Panes's icon is Major Pane (pixel art from its own PanesGlyph); the screen grid stays as its alternate icon."

- [ ] **Step 2: `app-icons.swift`**

- `struct App { let id, name: String; var pixelArt = false; let glyph: () -> NSImage }`.
- `func icon(_ glyph: NSImage, ink: NSRect, px: Int, pixelArt: Bool = false)`: the draw hint becomes `[.interpolation: pixelArt ? NSImageInterpolation.none : .high]`; every call site passes `pixelArt: app.pixelArt`.
- Replace the Panes entry:
```swift
    // Major Pane at attention, the pane a quarter lit, as the menu bar shows him with a quarter-tiled window in front.
    App(id: "panes", name: "Panes", pixelArt: true) { majorPane(.idle, frame: 0, lit: PaneCells.quarter) },
```
- Add after `PanesSample`:
```swift
enum MascotState: String { case idle, salute, bark, atEase = "at_ease" }
/// Major Pane with a 32x bitmap, so the icon upscales in whole pixels.
func majorPane(_ state: MascotState, frame: Int, lit: Set<GridCell>, active: Bool = true) -> NSImage {
    MajorPaneRenderer.image(art: MajorPaneArt.shipped, pose: MajorPanePose(state: state.rawValue, frame: frame, lit: lit, active: active), scales: [1, 2, 32])
}
func majorPaneTiming(_ state: MascotState) -> ClipTiming {
    let c = MajorPaneArt.shipped.clip(state.rawValue)
    return ClipTiming(fps: c.fps, loop: false, count: c.frames.count)
}
func majorPaneLength(_ state: MascotState) -> TimeInterval {
    let t = majorPaneTiming(state); return Double(t.count) / t.fps
}
```
(`MascotState` is not in the copied files, so it is declared here.)
- Replace the "panes" `Anim`: the salute.
```swift
    "panes": Anim(length: majorPaneLength(.salute)) { t in
        guard let t else { return majorPane(.idle, frame: 0, lit: PaneCells.quarter) }
        return majorPane(.salute, frame: Animator.frame(elapsed: t, timing: majorPaneTiming(.salute)).index, lit: PaneCells.quarter)
    },
```

- [ ] **Step 3: `anim.swift` (README animation = the bark) and `main.swift` (strip, hero icon)**

`anim.swift`: keep `PanesSample` and `panes(_:tiling:)`, add the same `MascotState`/`majorPane`/`majorPaneTiming`/`majorPaneLength` helpers (copy them), and replace the two Panes blocks:
```swift
// Panes: Major Pane barks the order and the pane relights to the window's new tile: a half, then a quarter.
animation("panes", length: majorPaneLength(.bark)) { t in
    func at(_ lit: Set<GridCell>) -> NSImage {
        guard let t else { return majorPane(.idle, frame: 0, lit: lit) }
        return majorPane(.bark, frame: Animator.frame(elapsed: t, timing: majorPaneTiming(.bark)).index, lit: lit)
    }
    return pill([at(PaneCells.half), at(PaneCells.quarter)])
}
…
// Panes on the hero bar: Major Pane salutes.
heroStrip("panes", frames: heroFrames(majorPaneLength(.salute)) { t in
    majorPane(.salute, frame: Animator.frame(elapsed: t, timing: majorPaneTiming(.salute)).index, lit: PaneCells.half)
}, seconds: majorPaneLength(.salute))
```
`main.swift`: add the helpers too; `save(majorPane(.idle, frame: 0, lit: PaneCells.half), "icon-panes.png")`; the strip:
```swift
// Panes: Major Pane with the pane unlit (a free window or none), a quarter, a half and all of it lit (maximized),
// at ease and greyed without Accessibility, then the screen grid, the alternate icon.
strip([majorPane(.idle, frame: 0, lit: []), majorPane(.idle, frame: 0, lit: PaneCells.quarter), majorPane(.idle, frame: 0, lit: PaneCells.half),
       majorPane(.idle, frame: 0, lit: PaneCells.all), majorPane(.atEase, frame: 0, lit: [], active: false), panes(panesHalves)], "states-panes.png")
```
Note `pill`/`strip` draw the `NSImage` at point size on a bitmap at `glyphScale` (3 or 6): AppKit picks the matching rep (3x exists; for 6x it scales the 3x rep). Set `NSGraphicsContext.current?.imageInterpolation = .none` inside `pill` and `strip` before drawing when the image is pixel art: simplest is to add the line unconditionally right after `NSGraphicsContext.current = …` in both functions — the vector glyphs are already rasterised at the right scale, so nothing else changes. Verify by diffing another app's strip before and after (`cmp` the PNGs); if any changes, scope the line to Panes's calls instead.

- [ ] **Step 4: `site/daemons.json`**

For `"id": "panes"`: `"nature": "Major Pane"`; `"stripalt": "Major Pane in the menu bar: at attention with his pane unlit, a quarter lit, a half lit and all of it lit, at ease and greyed without Accessibility, then the screen-grid icon"`; `"animalt": "Major Pane barking an order, the pane lighting the half and then the quarter where the window landed"`; in `blurb` replace the last sentence with "Its mascot is Major Pane, a pixel-art commander of windows whose pane lights the cells your front window fills; the old screen-grid glyph is one menu choice away."

- [ ] **Step 5: Render with the placeholder and check the pipeline**

Run (from the site repo): `art/glyphs/render-glyphs.sh 2>&1 | tail -4`
Expected: `glyphs placed` and `app icons placed`. Then look (Read) at `/Users/nicholassmith/Code/panes-menubar/docs/menubar-icon.png`, `docs/animation.png`, `docs/mascot.png` and `site/img/mascots/anim/panes.png`: the crude placeholder should be crisp (hard pixel edges) at every size, never blurred. If the icon is blurred, the `.none` hint or the 32x rep is missing.
Other repos' `docs/*.png` may be rewritten byte-identically or with drift; `git -C ~/Code/<repo> status` each and `git checkout -- docs` anything outside panes-menubar and the site (this task changes nothing there).
Do **not** deploy. Do not commit the panes-menubar images yet (Task 11 re-renders with the real art).

- [ ] **Step 6: Commit the site (its own branch, no deploy)**

```bash
cd /Users/nicholassmith/Code/widgets.nicksmith.software && git checkout -b major-pane
git add art/glyphs/render-glyphs.sh art/glyphs/app-icons.sh art/glyphs/app-icons.swift art/glyphs/anim.swift art/glyphs/main.swift site/daemons.json
git commit -m "Panes's card, strip and icon are Major Pane (pixel art, no interpolation); the grid stays as the alternate

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
(The regenerated `site/img/*` and `site/*.html` are committed in Task 11 with the real art.)

---

### Task 9: Concept pass: three Gemini variants, Nick picks one (REVIEW GATE)

**Files:**
- Create: `scripts/concept_art.py`, `art/mascot/major-pane-{a,b,c}-raw.png`, `art/mascot/major-pane-{a,b,c}.png`

- [ ] **Step 1: The script**

```python
#!/usr/bin/env python3
# (MPL header)
"""Three Gemini concept variants of Major Pane (spec "Process and gates", step 2),
through the Menumon site's art/gen_icons.py (its key, model choice and
post-processing). Writes art/mascot/major-pane-{a,b,c}-raw.png and the
background-removed major-pane-{a,b,c}.png. They guide the pixel art and are
never shipped. Needs ../widgets.nicksmith.software beside this repo."""
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
    import json
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
```

Run: `python3 scripts/concept_art.py` (the key is read from the site's `.env`). Expected: three pairs of PNGs. If Gemini returns 429s, the site's `_post` retries by itself; if the key is rejected, stop and tell Nick (do not create accounts or keys).

- [ ] **Step 2: Show Nick and STOP**

Read the three processed PNGs yourself first: any that is recognisably Duke Nukem (the exact red tank top + blond flat-top + shades + cigar silhouette) or Sarge gets regenerated with the prompt tightened ("no cigar, not red") before it is shown. Then load the `artifact-design` skill and publish one private artifact titled "Major Pane Concepts" (icon `soldier`) with the three images side by side as data URIs, labelled A, B, C, on a dark page, plus one line: "Pick one, or say what to mix." Give Nick the link and **wait**. Do not start Task 10 until he picks.

- [ ] **Step 3: Commit**

```bash
git add scripts/concept_art.py art/mascot
git commit -m "Major Pane: Gemini concept variants A–C (guide only, never shipped)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: The real pixel art (REVIEW GATE)

**Files:**
- Create: `art/major-pane/build_frames.py`, `art/major-pane/render.py`, `art/major-pane/frames.json`, `art/major-pane/out/*` (not committed except what Task 11 names)
- Modify: `Sources/PanesGlyph/MajorPaneFrames.swift` (regenerated from the real art), `.gitignore` (add `art/major-pane/out/`)

**Interfaces:**
- Produces: `art/major-pane/frames.json` in the Task 2 format, 30×22, ≤12 colours, the four clips.

- [ ] **Step 1: `render.py`**

Copy `/Users/nicholassmith/Code/parity/art/polly/render.py` to `art/major-pane/render.py` and adapt (keep the PNG/APNG writers, `scale`, `blit`, `render_frames`, `contact_sheet`, `animated_sheet`, `menubar_strips` as they are, apart from the renames below):
- Docstring: Major Pane; drop the `preview.html` embedding (`embed_preview`) entirely.
- Remove `STATE_COLOURS`; add `LIT = hex_rgb("#FFD166")` and `CELL_SETS = {"none": set(), "quarter": {(0,0),(1,0),(0,1),(1,1)}, "half": {(c, r) for c in range(2) for r in range(4)}, "all": {(c, r) for c in range(4) for r in range(4)}}`.
- `load()` reads `frames.json` next to the script and also asserts `set(doc["pane"]) <= set(doc["palette"])` and `set(doc["states"]) == {"idle", "salute", "bark", "at_ease"}`.
- `frame_rgba(doc, state, rows, lit=frozenset(), grey=False)`: a pixel whose char is in `doc["pane"]` takes `LIT` when its cell (computed from the pane pixels' bounding box in `rows`, `col = (x - x0) * 4 // w`, `row = (y - y0) * 4 // h`, clamped to 3) is in `lit`, else the palette colour; when `grey`, every colour becomes its Rec. 601 luminance. The contact sheets and strips render every state with `lit = CELL_SETS["quarter"]`, `grey = (state == "at_ease")`.
- New `pane_states(doc)`: idle frame 0 at 4x with none / quarter / half / all, side by side on the dark bar → `out/pane-states.png`.
- `app_icon(doc)`: the idle frame 0 with a quarter lit, cropped to everything drawn, nearest-neighbour upscaled onto Menumon's dark tile: gradient top `#2B2E35` to bottom `#15171B`, same rounded-rect maths as Polly's. (The real icon comes from the site's `app-icons.swift`; this one is for the contact sheet and the artifact.)
- `main()`: `render_frames`, `contact_sheet`, `animated_sheet`, `menubar_strips`, `pane_states`, `app_icon`.

Add `art/major-pane/out/` to `.gitignore`.

- [ ] **Step 2: `build_frames.py`, first pass**

Copy the helpers `blank`, `put`, `over`, `squash`, `lean` from `/Users/nicholassmith/Code/parity/art/polly/build_frames.py` (W, H = 30, 22). Then the parts. This is the starting figure; Steps 3–4 iterate it against the renders and the chosen concept variant. Every pixel is hand-placed: no image is traced.

```python
PALETTE = {
    "K": "#1E1A24",  # outline
    "S": "#F2B98A",  # skin
    "s": "#C98A5E",  # skin shade (under the jaw, the neck)
    "Y": "#F4D35E",  # flat-top
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

# He stands at x 2…17 facing the viewer's left; the pane hangs from his right hand (viewer's right) at x 18…27.
HAIR = {0: [(6, "KKKKKKKK")], 1: [(5, "KYYYYYYYYK")]}
HEAD = {2: [(5, "KSSSSSSSSK")], 3: [(5, "KGGGGGGGGK")], 4: [(5, "KSSSSSSSsK")], 5: [(6, "KSSSSSSsK")],
        6: [(6, "KSKKKKSsK")], 7: [(7, "KSSSSsK")], 8: [(8, "KsssK")]}
GLINT = {3: [(7, "W")]}
MOUTH_OPEN = {6: [(6, "KSKKKKSsK")], 7: [(7, "KKssKsK")], 8: [(8, "KsssK")]}
BANG = {0: [(2, "W")], 1: [(2, "W")], 2: [(2, "W")], 4: [(2, "W")]}          # the "!" of the bark
TORSO = {9: [(5, "KKKTTTTTTKKK")], 10: [(4, "KSKTTTTTTTTKSK")], 11: [(4, "KSKTTTTTTTtKSK")],
         12: [(4, "KSKTTTTTTTtKSK")], 13: [(4, "KSKTTTTTTttKSK")], 14: [(4, "KSKKKMMMMKKKSK")], 15: [(4, "KKKOOOOOOOOKKK")]}
ARM_UP = {y: [(4, "..K")] for y in range(10, 15)}                               # clears the lowered left arm
ARM_UP.update({3: [(2, "KSSK")], 4: [(1, "KSK")], 5: [(1, "KSK")], 6: [(1, "KSK")], 7: [(2, "KSK")], 8: [(2, "KSK")], 9: [(3, "KK")]})
ARM_HALF = {y: [(4, "..K")] for y in range(10, 15)}
ARM_HALF.update({7: [(1, "KSK")], 8: [(1, "KSK")], 9: [(1, "KSK")], 10: [(2, "KSK")], 11: [(2, "KSK")], 12: [(3, "KK")]})
LEGS = {16: [(7, "KOOOKOOOK")], 17: [(7, "KOOOKOOOK")], 18: [(7, "KOoOKOoOK")], 19: [(7, "KMMMKMMMK")],
        20: [(6, "KMMMMKMMMMK")], 21: [(6, "KKKKKKKKKKK")]}
LEGS_APART = {16: [(5, "KOOOK.KOOOK")], 17: [(5, "KOOOK.KOOOK")], 18: [(5, "KOoOK.KOoOK")], 19: [(5, "KMMMK.KMMMK")],
              20: [(4, "KMMMMK.KMMMMK")], 21: [(4, "KKKKKK.KKKKKK")]}


def pane(y0):
    rows = {y0: [(18, "KKKKKKKKKK")], y0 + 9: [(18, "KKKKKKKKKK")]}
    for y in range(y0 + 1, y0 + 9):
        rows[y] = [(18, "K" + "p" * 8 + "K")]
    rows[y0 + 1] = [(18, "KW" + "p" * 7 + "K")]
    return rows


def figure(arm=None, mouth_open=False, bang=False, glint=False, pane_y=8, legs=LEGS, breath=0):
    g = blank()
    for part in (HAIR, HEAD, TORSO, legs):
        put(g, part)
    if glint: put(g, GLINT)
    if mouth_open: put(g, MOUTH_OPEN)
    if bang: put(g, BANG)
    if arm: put(g, arm)
    put(g, pane(pane_y))
    if breath: squash(g, 9, breath)           # chest rises: the head sinks a row onto the torso
    return ["".join(r) for r in g]
```
Clips:
```python
STATES = {
    "idle": {"fps": 4, "loop": True, "frames": [figure(), figure(), figure(breath=1), figure(breath=1), figure(), figure(glint=True), figure(), figure()]},
    "salute": {"fps": 8, "loop": False, "frames": [figure(arm=ARM_HALF), figure(arm=ARM_UP), figure(arm=ARM_UP), figure(arm=ARM_UP), figure(arm=ARM_UP), figure(arm=ARM_HALF), figure()]},
    "bark": {"fps": 8, "loop": False, "frames": [figure(mouth_open=True, bang=True), figure(mouth_open=True, bang=True), figure(mouth_open=True), figure(mouth_open=True, bang=True), figure(), figure()]},
    "at_ease": {"fps": 2, "loop": True, "frames": [figure(pane_y=12, legs=LEGS_APART), figure(pane_y=12, legs=LEGS_APART, breath=1)]},
}
```
`main()` writes `frames.json` (`{"width": W, "height": H, "palette": PALETTE, "pane": PANE, "states": STATES}`, `indent=1`) and prints the colour count.

- [ ] **Step 3: Iterate**

Loop until it reads right:
1. `python3 art/major-pane/build_frames.py && python3 art/major-pane/render.py`
2. Read `art/major-pane/out/contact-sheet.png`, `menubar-2x.png`, `pane-states.png`, `app-icon-1024.png`.
3. Check at 1x (the 2x strip is the honest view): the flat-top, the shades band, the jaw, the tank top, the pane and its grid all read; the salute's arm reaches the brow; the bark's open mouth and "!" read; at ease is clearly a different stance with the pane down. Match the chosen concept variant's proportions and mood (not its details). Adjust rows, re-render.
4. Keep the palette ≤ 12 and the outline unbroken around the figure.
Then `python3 scripts/gen_major_pane_frames.py --validate art/major-pane/frames.json`.

- [ ] **Step 4: Compile it in and preview through PanesGlyph**

Run:
```bash
python3 scripts/gen_major_pane_frames.py art/major-pane/frames.json
swift test 2>&1 | tail -3
swift run -c release major-pane-render preview /private/tmp/claude-501/-Users-nicholassmith/032abe3e-761c-413d-af07-f61be99c0d32/scratchpad/mp-preview.html
```
Expected: compiled frames from `art/major-pane/frames.json`, 0 failures (the drift test now checks the real art), the page written.

- [ ] **Step 5: STOP. Nick reviews.**

Load the `artifact-design` skill if not loaded; publish the preview HTML as a private artifact titled "Major Pane Preview" (icon `soldier`). Ask Nick to confirm (a) it reads as an original character, nothing recognisable from a game or film (the IP rule), (b) the look and each clip. Changes go back to Step 3. Do not continue to Task 11 without his yes.

- [ ] **Step 6: Commit**

```bash
git add .gitignore art/major-pane/build_frames.py art/major-pane/render.py art/major-pane/frames.json Sources/PanesGlyph/MajorPaneFrames.swift
git commit -m "Major Pane: the art (hand-placed pixels, four clips) compiled in

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: Release Panes 0.6.0, deploy the site, close #2

**Files:**
- Modify: `README.md`, `CHANGELOG.md`, `docs/menubar-icon.png`, `docs/animation.png`, `docs/mascot.png`, `Resources/bundle/AppIcon.icns` (rendered)
- Site: regenerated `site/img/**`, `site/*.html`
- `~/.claude/CLAUDE.md` (the minute-animations note)

- [ ] **Step 1: README**

- Line 3 alt: "Panes's app icon: Major Pane at attention, his pane a quarter lit". Line 5 alt: "Major Pane in the menu bar: at attention with his pane unlit, a quarter lit, a half lit and all of it lit, at ease and greyed without Accessibility, then the screen-grid icon".
- Version line → `**Version 0.6.0**`.
- Rename `## The menu-bar icon` to `## Major Pane` and rewrite its first two paragraphs:

> Panes's mascot is **Major Pane**, a commander of windows: blond flat-top, square jaw, dark shades, tank top, chest out, holding his pane at his side like a riot shield. He is SNES-era pixel art, hand-placed on a 30×22 grid with twelve colours, drawn in whole pixels at the bar's backing scale so nothing is ever blurred. The pane is a 4×4 window grid, and its cells light to show where the front window sits: eight for a half, four for a quarter, all sixteen when it is maximized, none when it floats free or there is no window.
>
> He stands at attention (a slow breath, a glint on the shades) and, in Panes's turn in the Menumon minute cue, snaps a salute. When Panes moves a window he barks the order and the pane relights to its new tile. Without Accessibility he stands at ease, pane lowered, greyed out. Under Reduce Motion he holds still. **Settings ▸ Icon** swaps him for the screen-grid glyph below.

- Keep the grid's paragraphs after that, starting "**The screen grid**, the alternate icon, is a little display…" (the existing text, with "Panes has no character, but" removed from the cue paragraph; the slide now plays only when the grid is chosen).
- Animation alt: "Major Pane barking an order, the pane lighting the half and then the quarter where the window landed".
- Under **Develop**, after the `scripts/make-icon.sh` line, add:
```sh
python3 art/major-pane/build_frames.py && python3 art/major-pane/render.py   # the art → frames.json, review renders in art/major-pane/out/
scripts/gen_major_pane_frames.py art/major-pane/frames.json                 # → Sources/PanesGlyph/MajorPaneFrames.swift (a test fails if stale)
swift run major-pane-render preview out.html [--frames FILE]                 # every clip animating, the review page
```
and a sentence: "The art is drawn in `build_frames.py`, every pixel in code; `render.py` makes contact sheets and an animated sheet to check it; the generator compiles it into Swift. Concept sketches in `art/mascot/` are guide only."
- **License** section: add "The Major Pane artwork (`art/`, the generated frames, the icon and the pictures in `docs/`) is [CC BY-NC 4.0](art/LICENSE): see [NOTICE](NOTICE). It may not be used commercially."

- [ ] **Step 2: CHANGELOG**

At the top, below the preamble:
```
## [0.6.0] - <today, YYYY-MM-DD>
### Added
- Major Pane, Panes's mascot: a pixel-art commander of windows in the menu bar. His pane's 4×4 cells light to show where the front window sits; he salutes in the Menumon minute cue, barks when Panes moves a window, and stands at ease, greyed, without Accessibility.
- Settings ▸ Icon: Major Pane (default) or the screen grid.
### Changed
- The grid's tile-slide animation now plays only when the grid is the chosen icon.
- The app icon and README pictures are Major Pane.
```

- [ ] **Step 3: Render the real images and the icon**

From the site repo (branch `major-pane`): `art/glyphs/render-glyphs.sh 2>&1 | tail -3`. Read `docs/mascot.png`, `docs/menubar-icon.png`, `docs/animation.png` in panes-menubar: crisp, the real art. Revert drift in any other repo's `docs/` (`git -C … checkout -- docs`). Rebuild: `scripts/build-app.sh` and look at `build/Panes.app/Contents/Resources/AppIcon.icns` via `qlmanage -t -s 256 -o <scratchpad> build/Panes.app/Contents/Resources/AppIcon.icns` and Read the PNG.

- [ ] **Step 4: Commit, push, PR, merge**

```bash
cd /Users/nicholassmith/Code/panes-menubar
git add README.md CHANGELOG.md docs Resources/bundle/AppIcon.icns
git commit -m "0.6.0: Major Pane

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin major-pane
gh pr create --title "0.6.0: Major Pane" --body "$(cat <<'EOF'
Closes #2.

Panes gets its mascot: Major Pane, hand-placed pixel art drawn in whole pixels, with four clips (idle, salute on the minute cue, bark after a move, at ease without Accessibility). His pane's 4×4 cells light where the front window sits. Settings ▸ Icon keeps the screen grid as the alternate.

Spec: docs/superpowers/specs/2026-10-09-major-pane-design.md. Art under CC BY-NC 4.0 (art/LICENSE, NOTICE).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
gh pr checks --watch
```
`release / check` now also builds the app on a macOS runner and launch-checks it (added 2026-10-08); expect several minutes. When green: `gh pr merge --merge`, then `git checkout main && git pull` and confirm `git describe --tags` says `v0.6.0`. If the check fails, read the log (`gh run view --log-failed`), fix on the branch, push again; never `--admin`.

- [ ] **Step 5: Site deploy**

```bash
cd /Users/nicholassmith/Code/widgets.nicksmith.software
python3 scripts/build-pages.py
git add -A site art/glyphs && git commit -m "Menumon: Major Pane on Panes's card, page, strip and the hero bar

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git checkout main && git merge --ff-only major-pane && git push
npm run deploy 2>&1 | tail -3
```
Then `curl -sI https://menumon.nicksmith.software/img/mascots/panes.png | head -1` → `HTTP/2 200` (give propagation ~20 s), and check the Panes card on https://menumon.nicksmith.software says "Major Pane".

- [ ] **Step 6: Install and verify**

Parity builds from origin and installs on both Macs within its interval; `parity-ctl sync '{"repo": "panes-menubar"}'` runs it now. Then `parity-ctl state | python3 -c "import sys,json; a=json.load(sys.stdin)['apps']; print({k:v for k,v in a.items() if 'anes' in k})"` → both Macs `0.6.0`, state `in sync`. Confirm Panes relaunched here (`pgrep -x Panes`) and the bar shows Major Pane. Confirm `gh issue view 2 -R nicholaspsmith/panes-menubar` is closed.

- [ ] **Step 7: Notes**

In `~/.claude/CLAUDE.md`, in the StatusItemKit paragraph, replace "Its glyph is a colourful screen grid, not a character (a "Major Pane" character is ticket #2)." with "Its mascot is **Major Pane** (0.6.0, 2026-10): pixel art in the app's own `PanesGlyph` (Polly's pipeline: `art/major-pane/build_frames.py` → `frames.json` → `scripts/gen_major_pane_frames.py` → `MajorPaneFrames.swift`), his pane's cells lit from the front window; the screen grid is the alternate icon (Settings ▸ Icon)." In the minute-animations note, replace "Panes's windows slide into their tiles (Panes 0.5.0; …). The Major Pane character (panes-menubar#2) is still unpicked." with "Major Pane salutes (Panes 0.6.0; the grid's tile slide only when the grid icon is chosen)."
Delete the merged branches: `git branch -d major-pane` in both repos and `git push origin --delete major-pane` in each (two commands, not one line).

---

## Self-review

- **Spec coverage:** Character/IP/licence → Tasks 2, 9, 10, 11. Clip table → Task 5 (driver), Task 7 (cue, onMoved, trust), Task 10 (frames). Pane cells → Task 4 (`PaneCells`, renderer). Art format → Tasks 1, 2. Renderer → Task 4. Animator → Task 3. Preview + render target → Task 6. App wiring + Icon submenu + launch safety → Task 7. Site and images → Tasks 8, 11. Process gates → Tasks 9, 10. Out of scope untouched.
- **Placeholders:** none; the art task is iterative by nature and says exactly what to render, look at, and judge.
- **Type consistency:** `MajorPanePose(state:frame:lit:active:)`, `PaneCells.lit(windows:visible:)`, `MajorPaneRenderer.image(art:pose:scales:)`, `MascotDriver.pose(now:timing:reduceMotion:)`, `ClipTiming(fps:loop:count:)` are used identically in Tasks 4–8. `MascotState.atEase.rawValue == "at_ease"` matches the art's state name.
- **Review Focus:** each of the five has its named test in Task 4 or Task 5.

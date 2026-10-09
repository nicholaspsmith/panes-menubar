# Major Pane: Panes's mascot

Closes panes-menubar#2. Approved in conversation 2026-10-09; this is the
written design.

## Why

Every Menumon app has a character. Panes has had a bare glyph, a display with
its windows drawn where they sit. Major Pane gives it one, built the way
Parity's Polly was built: hand-placed 16-bit pixel art, per-state clips, an
app icon from the same frame data, a review gate before any of it ships.

## Character

**Major Pane** (the pun on *pane* is the name; "Payne" is never written).
An action-hero commander of windows: no hat, a blond flat-top, square jaw,
dark shades, thick neck, black tank top, olive trousers and boots, chest out.
He faces the viewer's left, like Polly. In his left hand, held at his side like
a riot shield, is **the pane**: a window with a 4x4 grid on it. The pane is
what makes him Panes's: its cells light to show where the front window sits.

- **Art direction:** original SNES-era pixel art. A canvas of about 30x22
  (the art's own `width` and `height`; nothing assumes a size), dark 1 px
  outlines, at most 12 palette colours with two-tone shading, chunky cartoon
  proportions (big head, big jaw). Hand-placed pixels, like Polly.
- **IP rule (binding):** drawn from scratch. It must not copy, trace or adapt
  any game or film character, and must not be recognisable as Duke Nukem,
  Sarge from *Small Soldiers* or anyone else: no signature details (no
  sunglasses-and-cigar grin, no "Hail to the king"), only the genre's
  conventions (flat-top, shades, tank top). No third-party sprite sheet is
  ever downloaded, stored or committed. Frames are designed per state.
- **Licence:** the code stays MPL-2.0. The art (`art/major-pane/`, the
  generated `MajorPaneFrames.swift`, the rendered icons and README pictures)
  is CC BY-NC 4.0: `art/LICENSE` carries the licence, a top-level `NOTICE`
  says the art may not be used commercially, and the README's License section
  says both.

## What he does

| Moment | Clip | Plays |
|---|---|---|
| Accessibility granted | `idle` | loops, about 4 fps: a slow breath, an occasional blink, a hard stare to the left |
| Panes's minute-cue slot (`MinuteCue`, :00 and :30) | `salute` | once: a snapped salute with the free hand, back to idle |
| A window was moved by Panes (`mover.onMoved`) | `bark` | once: mouth open, a small "!" burst; the pane relights to the window's new tile |
| No Accessibility (`active == false`) | `at_ease` | loops, about 2 fps: feet apart, pane lowered to the ground, a slow sway; the whole glyph greyed by luminance |
| Reduce Motion | frame 0 of the steady pose (`idle`, or `at_ease` without Accessibility) | static |

A one-shot never interrupts another: a cue that lands during a bark is
skipped, a move during a salute relights the pane but the bark waits for the
salute to end and then plays. Nothing plays while the icon style is the grid.

**The pane's cells.** Sixteen cells, from PanesCore's existing
`Grid.cells(coveredBy:in:)` on the front window's frame in the display's
visible area: a half lights eight, a quarter four, a maximised window all
sixteen. A free-floating window lights the cells it covers (that is what the
function returns). No front window, or no window on the display: none lit.
Lit is Panes's accent (the `front` amber of the grid glyph, as a palette
entry), unlit is dark glass. The cells are data, not art: the art only marks
which pixels are cells.

## Art format

Polly's format with one addition. `art/major-pane/frames.json`:

```
{"width": W, "height": H,
 "palette": {char: "#RRGGBB"},            at most 12 entries, "." is transparent
 "pane":    {char: "cell"},                pixels whose colour is decided at render time
 "states":  {name: {"fps", "loop", "frames": [[rows]]}}}
```

Exactly those five keys. `pane` replaces Polly's `perch`: a `cell` pixel's
row and column within the pane's bounding box map it to one of the 4x4
cells (the box is divided evenly; the art draws cells as 2x2 blocks, so a
10x10 pane with a 1 px outline). Required states: `idle`, `salute`, `bark`,
`at_ease`; no other names. Every frame is `height` rows of `width` chars.

Files, mirroring Parity:

- `art/major-pane/build_frames.py` draws every pixel in code (parts at
  absolute coordinates, poses composed with whole-row moves) and writes
  `frames.json`. Python 3 stdlib only.
- `art/major-pane/render.py` renders `out/`: every frame at 1x/2x/8x, a
  contact sheet, an animated APNG contact sheet, light and dark menu-bar
  strips, the 1024 px app icon. For review and the README; the Swift
  renderer is the truth for the app.
- `scripts/gen_major_pane_frames.py` validates the format and writes
  `Sources/PanesGlyph/MajorPaneFrames.swift`; `--check` fails when the Swift
  is stale. A PanesGlyph test runs the check so drift fails `swift test`.
- `art/major-pane/placeholder/frames.json`: a crude stand-in drawn by
  `scripts/placeholder_frames.py`, so the whole pipeline lands and is tested
  before the real art passes the review gate. The placeholder is never
  released: the release task replaces it.

## Renderer (PanesGlyph)

- `MajorPaneArt`: the format as Swift (`shipped` compiled in from
  `MajorPaneFrames.swift`; `init(json:)` for previews and the drift test).
- `MajorPanePose`: `state`, `frame`, `lit: Set<GridCell>` (or the 16 cells
  as a bitmask), `active`.
- `MajorPaneRenderer.cells(art:pose:) -> [[UInt32?]]` gives every art
  pixel's colour: palette colour, a pane cell's lit/unlit colour, greyed by
  luminance (Rec. 601) when inactive. `bitmap(art:pose:scale:)` writes each
  art pixel as a whole block of `scale` device pixels, nothing interpolated;
  `image(art:pose:)` wraps the 1x and 2x bitmaps as an `NSImage` of
  `width` x `height` points. The app icon is rendered by the site's
  `app-icons.swift` from `image(art:pose:scales:)` with a large scale and no
  interpolation (its `pixelArt` flag); PanesGlyph has no icon drawing of its
  own.
- `Animator.frame(elapsed:timing:)` and `nextChange(elapsed:timing:)`, pure,
  as in Parity's `Motion.swift`: the frame index for a clip at a time, and
  when it next changes. A one-shot holds its last frame and reports `done`.
- `MajorPanePreview.html(art:)`: the review-gate page, every present clip
  animating at 1x on a light and a dark bar and 8x enlarged, a row of idle
  frame 0 with none, a quarter, a half and all cells lit, and the icon pose at
  32x on a dark CSS tile.
- A new `MajorPaneRender` executable target (`swift run major-pane-render`):
  `preview OUT.html [--frames F]`.
  The README's mention of `panes-render-icons` (the site's renderer, which
  lives in widgets.nicksmith.software) stays as it is.

Tests (PanesGlyphTests): the pixel map of a hand-built 6x4 art renders to
exactly its palette colours; pane cells take lit/unlit by `lit`; inactive
greys every non-cell pixel; `Animator` frame/loop/one-shot/done boundaries;
the generated Swift matches `frames.json`; the preview lists every clip.

## App wiring (Panes target)

- **Icon style** in Settings ▸ **Icon**: *Major Pane* (default) and *Screen
  grid*, stored in `UserDefaults` key `iconStyle` ("major-pane" / "grid"),
  checkmarked like Menu Crane's Icon submenu. Switching redraws at once.
- A `MascotController` owns the clip timer (fires at the playing clip's own
  fps via `Animator.nextChange`, never faster than 60 Hz, nothing scheduled
  when the frame will not change), the steady pose (`idle` or `at_ease` from
  the trust state), the one-shot queue (salute from the minute cue, bark from
  `onMoved`), the lit cells (recomputed from the front window on every
  refresh and on `onMoved`), and Reduce Motion. The grid style keeps its
  existing `slideTiles` cue and `refreshIcon`; the two never run together.
- `refreshIcon` is safe to call before the controller exists (the Menu Crane
  1.3.0 lesson: optionals and ordered creation, and the launch smoke test in
  `release / check` guards it).

## Site and images

- `widgets.nicksmith.software/art/glyphs/render-glyphs.sh` already compiles
  PanesGlyph; it picks up the new files. `app-icons.swift` gains a
  per-app `pixelArt` flag so Panes's tile and card animation upscale with
  `.none` interpolation; `App(id: "panes")` draws Major Pane; the card
  animation (`Anim "panes"`) is the salute, the README `docs/animation.png`
  the bark; the strip shows idle with no / a quarter / a half / all cells lit,
  at ease, and the screen grid as the alternate icon.
- `site/daemons.json`: `nature` "The Glazier" becomes "Major Pane"; the
  blurb, strip/anim alts and mascot alt change to match.
- `scripts/make-icon.sh` keeps producing `Resources/bundle/AppIcon.icns` and
  `docs/mascot.png` through the site's `app-icons.sh`.
- README: mascot picture and animation at the top, a "Major Pane" section
  replacing "The menu-bar icon"'s first paragraphs (the grid becomes the
  alternate icon), the art pipeline under Develop, the licence split.

## Process and gates

1. Spec (this file) reviewed by Nick, then the implementation plan.
2. **Concept pass:** three Gemini variants (A, B, C) of the action-hero look
   through the site's `art/gen_icons.py` with a Major Pane prompt, saved to
   `art/mascot/`; Nick picks one. They guide the pixel art and are not
   shipped anywhere.
3. Pipeline lands on the placeholder: format, generator, renderer, animator,
   controller, icon style, tests, site flag. Nothing released yet.
4. Real pixel art in `build_frames.py`, iterated against `render.py`'s
   contact sheets.
5. **Review gate:** the preview rendered by PanesGlyph's own renderer is
   published as a private artifact; Nick confirms it reads as an original
   character (IP rule) and approves the look and the clips. Changes go back
   to step 4.
6. Release: Panes 0.6.0 (CHANGELOG, README, `make-icon.sh`), site re-render
   and deploy, issue #2 closed. Parity installs it on both Macs.

## Out of scope

- Reactions to display changes, the held grid overlay, or drags (nothing in
  the approved table).
- Moving the art into StatusItemKit's `CharacterIcon` (Polly's precedent:
  the app owns its own art).
- Any change to the window-management behaviour.

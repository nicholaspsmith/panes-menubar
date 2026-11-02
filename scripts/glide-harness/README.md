# Glide harness

Tools for measuring what a Panes glide looks like **on screen**, frame by
frame, as numbers (never images). From issue #19; used for #19 and #21.

| File | What it is |
|---|---|
| `TileTest.swift` | A solid magenta window (`com.nicholassmith.tiletest`) with a Window menu, so Move & Resize works. Verbatim from #19. |
| `edges.swift` | The edge recorder from #19, verbatim. Replays a glide variant on TileTest, or presses ⌘⌥+key and records what the real Panes does. |
| `appglide.swift` | The same recorder for **any** app's window, plus the window's AX frame timeline. |
| `refresh.swift` | Holds the main display at another refresh rate (e.g. 60 Hz on a 120 Hz ProMotion panel) until it exits. |
| `fpsprobe.swift` | Checks how many distinct frames a second the capture can see, using a bar that moves on every display-link tick in a still window. |
| `build.sh` | Builds all of them into `build/glide-harness/`. |

## Build

```sh
scripts/glide-harness/build.sh
```

That gives `build/glide-harness/TileTest.app`, `edges`, `appglide`,
`refresh` and `fpsprobe`. `build/` is ignored by git.

## Permissions

- **Screen Recording** for the terminal app that runs `edges` or
  `appglide --capture` (System Settings ▸ Privacy & Security ▸ Screen &
  System Audio Recording). The recorders use ScreenCaptureKit and keep only
  the magenta pixels' extent along two scan lines.
- **Accessibility** for the same terminal: both tools set the test window's
  frame and post ⌘⌥ key events.

## Only one Panes at a time

Every build of Panes claims the same ⌘⌥ keys. Quit the running one first
(`osascript -e 'quit app "Panes"'`), then open the build you want to measure.
An old build can be launched straight from its bundle (`open path/to/Panes.app`)
without touching `~/Applications/Panes.app` (parity owns that link).

## edges (TileTest only)

```sh
open build/glide-harness/TileTest.app
build/glide-harness/edges <variant> x y w h  x y w h
```

The two rectangles are frames A and B in AX points (top-left origin). The scan
lines run through the middle of their intersection, so pick frames that
overlap.

- `<variant>` replays a glide between A and B itself, three times each way:
  `panes`, `inout`, `long`, `smooth`, `mid`, `sizefirst`, `env`, `dl`,
  combined with `+` (for example `long+inout+dl`). Add `+trace` for every
  captured frame.
- `key:<keycode>` sets A, waits 0.6 s, then presses ⌘⌥+key four times, 0.9 s
  apart, and reports what Panes did. Keycodes: 8 = C, 46 = M, 51 = ⌫.
  Example, ⌥⌘C from the box on a 1496×967 pt display:
  `edges key:8 248 184 1000 626 248 28 1000 939`.

Per glide it prints when the first change reached the screen, how many
distinct frames were shown, backward moves of the top/bottom edge and the
biggest jump between two shown frames. It reads only the top and bottom
edges.

TileTest must be the frontmost app: `edges` presses keys blindly.

## appglide (any app)

```sh
build/glide-harness/appglide <bundle-id | pid:N> <keys> [options]
```

- `<keys>`: comma-separated keycodes, each pressed with ⌘⌥ in turn, e.g.
  `8,8,8,8` (box ↔ column) or `46,51,46,51` (maximize, restore).
- `--start box|x,y,w,h`: frame set before the first press (default: the ⌥⌘C
  box for a 1000 pt column). The scan lines go through its centre.
- `--idle S`: seconds to wait after setting the start frame (default 10), so
  press 1 is "the first press after S seconds idle".
- `--gap S`: seconds recorded per press (default 1.0).
- `--capture`: also record on-screen edges. **The window's content must be
  #ff00ff**: a page with `background:#ff00ff` in a browser, a VS Code colour
  theme override, and so on. The top edge is then the top of the content, not
  of the window.
- `--no-ax`: don't sample AX during presses (to check that sampling does not
  change what reaches the screen).
- `--title T`: refuse to run unless the focused window's title contains T.
- `--trace`: print every distinct frame.
- `--costs N`: how many position+size sets to time for setCost (default 10).
- `--probe`: after the idle, time two back-to-back AX reads, to see whether
  the app itself is slow to answer after a pause. This warms the app, so
  press 1 then no longer starts from idle.

It first brings the app forward (AX `AXFrontmost`), times N position+size sets
(the same pair of calls whose time Panes keeps as `setCost`), sets the start
frame and waits. **Before every press it checks that the window is still the
focused window of the frontmost app and stops otherwise**, so Panes can never
be sent to someone else's window.

Per press it prints two timelines, each with first and last change (ms after
the key went down), distinct frames, backward edge moves and the biggest jump
over all four edges:

- **AX**: the window's position and size, read in one round trip
  (`AXUIElementCopyMultipleAttributeValues`) as fast as the app answers. This
  is when the app *applied* each step, not when it reached the screen. A
  sample can fall between Panes's position set and its size set. That
  half-applied frame is real (the app held it), and it shows up as backward
  moves of the bottom/right edge. "slowest" is the longest single read, which
  shows when the app's main thread was busy.
- **screen** (`--capture`): the magenta content's edges on screen, i.e. what
  was actually shown.

Keeping a test window safe:

- **Browsers**: serve a magenta page locally
  (`python3 -m http.server --bind 127.0.0.1`). Open a Chromium browser as a
  separate instance with its own profile:
  `open -na Helium --args --user-data-dir=<dir> --no-first-run --app=http://127.0.0.1:8765/magenta.html`.
  Safari: `open -a Safari <url>` and `--title`.
- **VS Code**: run a separate instance,
  `Code --user-data-dir <dir> --extensions-dir <dir> --new-window`, with a
  `settings.json` that paints the workbench magenta
  (`workbench.colorCustomizations`) and turns on `chat.disableAIFeatures` (or
  a sign-in sheet covers the window). The user-data-dir path must be short:
  the IPC socket inside it is limited to 103 characters.

## refresh

```sh
build/glide-harness/refresh 60 &   # ... measure ...; kill %1
```

Switches the main display to the same resolution at 60 Hz with
`kCGConfigureForAppOnly`. macOS restores the previous mode as soon as the
process exits, so the change never persists.

## fpsprobe

```sh
build/glide-harness/fpsprobe 3
```

For 3 s it moves a magenta bar 2 pt on every display-link tick, in a small
floating window at the centre of the main display, and counts the distinct
positions the capture saw. If that reaches the display's rate but a resizing
window doesn't, the limit is the resize path, not the capture. Run it with
nothing else magenta on that row.

## Limits

- On a 1496×967 pt built-in 120 Hz panel, the capture saw at most about 60
  distinct frames a second of a *resizing* window. So did Panes's 120 Hz
  steps. Whether the compositor or ScreenCaptureKit drops the rest can't be
  told from here.
- The capture sees only magenta. Title bars and toolbars are invisible to it,
  so a real app's top edge is its content's top.
- AX sampling competes with Panes for the app's main thread. Compare a
  `--no-ax` run before trusting the screen numbers of a sampled run.

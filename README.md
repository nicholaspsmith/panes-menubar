# Panes

<p align="center"><img src="docs/mascot.png" width="160" alt="Panes's app icon: a small display with windows tiled on it"></p>

A standalone macOS menu-bar app that arranges windows: **global shortcuts**
for halves, quarters, maximize, center, restore and next display; a **4×4
layout grid** in the menu; and **edge snapping** when you drag a window to a
display edge. A replacement for Rectangle.

Its shortcuts are taken by a `CGEventTap` before any app sees them, so an
app that claims the same keys (iTerm2 and ⌥⌘M, say) cannot get in the way,
which is what goes wrong when window shortcuts are set in System Settings.

Built on [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit) (the
menu-bar shell) and [HotkeyKit](https://github.com/nicholaspsmith/HotkeyKit)
(the global key-tap engine). Part of
[Menumon](https://menumon.nicksmith.software).

**Version 0.1.0** · [Changelog](https://github.com/nicholaspsmith/panes-menubar/releases)

## Requirements

- macOS 13+ (tested on Apple Silicon, macOS 27)
- Accessibility permission (to move windows and intercept keys)
- Sibling checkouts of `StatusItemKit` and `HotkeyKit` next to this repo (to build)

## What it does

| Shortcut (default) | Action |
|--------------------|--------|
| `⌥⌘←` / `⌥⌘→` | left / right half |
| `⌥⌘↑` / `⌥⌘↓` | top / bottom half |
| `⌥⌘U` / `⌥⌘I` | top-left / top-right quarter |
| `⌥⌘J` / `⌥⌘K` | bottom-left / bottom-right quarter |
| `⌥⌘M` | maximize (the visible frame: below the menu bar, beside the Dock) |
| `⌥⌘C` | center, keeping the size |
| `⌥⌘⌫` | restore: undo the last move Panes made to this window (again for the one before) |
| `⌃⌥⌘→` | move to the next display, keeping the window's relative frame |

Each acts on the focused window of the frontmost app. A shortcut is
swallowed only when it applies: with no movable window in front, nothing to
restore, or a single display for Next Display, the key passes through to the
app. Rebind any of them in **Settings ▸ Preferences…** (Esc cancels a
recording; a shortcut shared by two actions is flagged in red).

<p align="center"><img src="docs/preferences.png" width="500" alt="The Preferences window: one row per action with its shortcut, Record and Reset"></p>

### The menu

![The open menu](docs/menu.png)

- **The layout grid**: the display the front window is on, cut into 4×4
  cells at its visible frame's aspect ratio. Click a cell and the window fills
  it; drag across cells and the selection highlights as you go, and the
  window fills it on release (a 2×4 drag from the top-left is the left half).
  Cells under the front window are shaded in the accent colour, cells under
  other windows on that display lightly. The menu closes once the window is
  told where to go.
- **The actions**, each showing its shortcut; clicking one applies it to the
  window that was in front when the menu opened. Greyed when they do not
  apply.
- **⚠ Grant Accessibility…**: shown only until Panes is trusted.
- **⚠ macOS Edge Tiling Is On…**: shown when Edge Snapping is on and so is
  macOS's own tiling (`com.apple.WindowManager` `EnableTilingByEdgeDrag` /
  `EnableTopTilingByEdgeDrag`; unset means on). Opens Desktop & Dock.
- **Settings ▸** (StatusItemKit's `SettingsMenu`)
  - **Edge Snapping**: on by default.
  - **Preferences…** (⌘,): rebind the shortcuts.
  - **Start at Login**, then the version.
- **Quit Panes** (⌘Q).

### Edge snapping

Drag a window by its title bar to a display edge: left or right for that
half, the top to maximize, within 40 pt of a corner for that quarter (the
bottom edge snaps only at its corners). A translucent preview shows the
target while the cursor is there; release to snap, or move away to cancel.
An edge another display sits against is not an edge, so dragging a window
across to the next display never snaps on the way.

### Animation

Every move (shortcut, grid, snap, restore) glides there: an ease-out over
0.18 s, a little quicker than macOS's own tiling, stepping at 120 Hz. It is
time-driven, so an app slow to apply Accessibility sets gets fewer, larger
steps rather than a late stutter, and one too slow for four steps jumps
straight there. Reduce Motion jumps every time. Each move ends with an exact
size, position, size, then a re-read: a window that refuses the size (a
minimum width, a terminal snapping to cells) is nudged back against the edges
its target hugged, so a too-wide right half stays flush right.

## The menu-bar icon

![The menu-bar icon](docs/menubar-icon.png)

A little display in the Menumon glyph style (shaded bezel on a stand, dark
glass, ink outlines), shaped like the display the icon sits on, with a faint
4×4 grid. Every window on that display is drawn on it as a small tile at its
true scaled position and size, whether or not it fits the grid, back to front
with outlines so overlaps read; the frontmost window is amber, the others
soft blues, greens and lilacs. Shown above on a dark and a light bar, empty,
with two halves, three tiles, three free windows (one hanging off the edge)
and maximized. The glass greys out while Accessibility is not granted.

The window list comes from `CGWindowListCopyWindowInfo` (bounds only, which
needs neither Accessibility nor Screen Recording). The icon redraws when an
app activates, the Space or the displays change, after Panes moves a window,
and on a 1.5 s poll that redraws only when the bounds list has changed.

## Character

TODO (Nick): Panes has no mascot yet; the icon is a plain screen grid for
now. When one is chosen, add it to StatusItemKit's `CharacterIcon` and
`MinuteCue.order` like the others, and replace `docs/mascot.png`.

## How it works

- **HotkeyKit** owns the key tap. Arrow keys (and Home/End, Page Up/Down,
  Forward Delete) always carry the fn flag, and HotkeyKit matches modifiers
  exactly, so each binding on one of those keys is registered twice, with and
  without fn. While Preferences records a shortcut, the tap lets keys through
  to the recorder. The tap is re-created every 6 s to stay ahead of taps other
  apps add later.
- **Accessibility** (`AXUIElement`) reads and sets the focused window's
  position and size (messaging timeout 0.3 s, so a hung app cannot stall the
  tap). Only standard windows and dialogs whose position is settable, not
  minimized and not full screen, are moved. `AXEnhancedUserInterface` is
  switched off on the app during a move and put back (it makes Chromium and
  Electron apps animate every set). Restore history is keyed by the window's
  `CGWindowID` (`_AXUIElementGetWindow`).
- **Coordinates**: all frame math happens in AX space (origin at the top-left
  of the primary display, y down, so a display left of the primary has negative
  x and one above it negative y). `NSScreen` frames and the cursor are flipped
  in once with the primary display's height.
- **Edge snapping** uses global mouse monitors (no permission needed for mouse
  events). A press on a window becomes a snap drag once that window has moved
  without changing size, which tells a title-bar drag from a resize or a drag
  inside the content.
- **PanesCore** holds the testable logic: frames for every action on any
  display layout, the relative move between displays, the fit-after-refusal
  nudge, snap zones, restore history, the grid, the frame interpolation and
  pacing, the icon's window mapping and pixel alignment, bindings and their
  formatting. **PanesGlyph** draws the icon, shared by the app and
  `panes-render-icons`.

## Install

```sh
./install.sh
```

Builds `Panes.app`, symlinks it into `~/Applications`, and launches it. Grant
**Accessibility** when prompted.

### Make the Accessibility grant survive rebuilds (recommended)

An ad-hoc signed build gets a new code hash on every rebuild, and macOS drops
the Accessibility grant. Create a stable local signing identity **once**; the
build script uses it whenever it exists:

```sh
../StatusItemKit/scripts/setup-signing.sh   # one-time, idempotent
./install.sh                                # rebuild signs with it
```

**If the shortcuts stop working after a rebuild**, the grant went stale:
re-approve Panes in System Settings ▸ Privacy & Security ▸ Accessibility. If it
is already on but inert, clear the stale entry and re-grant:

```sh
tccutil reset Accessibility com.nicholaspsmith.Panes
open ~/Applications/Panes.app
```

### Start at Login (optional)

Toggle it from **Settings ▸ Start at Login** in the menu, or from the shell:

```sh
"$HOME/Applications/Panes.app/Contents/MacOS/Panes" --login on       # or: off, status
```

### Coming from Rectangle

Quit Rectangle (and remove it from Login Items) before relying on Panes: both
would take the same keys and both would snap at the edges. Clear any window
shortcuts set in System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ App
Shortcuts too, and turn off macOS's own edge tiling in Desktop & Dock (the
menu warns while it is on).

## Develop

```sh
swift build                    # compile
swift test                     # PanesCore unit tests
swift run panes-render-icons   # docs/menubar-icon.png, docs/mascot.png, Resources/bundle/AppIcon.icns
```

## Releasing

Every push to `main` is a release. Before pushing, add a dated
`## [X.Y.Z] - YYYY-MM-DD` section to the top of [`CHANGELOG.md`](CHANGELOG.md)
(minor for features, patch for fixes; turn a waiting `## [Unreleased]` into
it). When it reaches `main`, GitHub tags `vX.Y.Z` and publishes the section as
a release titled `vX.Y.Z`. Without a new version:

- a push is refused locally by the `pre-push` hook;
- a pull request **cannot merge** — `release / check` is required on `main`;
- a push that reaches `main` anyway fails the release workflow.

The one exception is `[no release]` in the tip commit's message, for changes
nothing a user runs (setup, CI, developer docs): it passes every check with no
version bump and no tag. Never tag or create a release by hand, and never
`gh pr merge --admin` past a failing check — fix the PR. After merging,
`git pull` for the tag, rebuild (the menu's version row is stamped from it),
and update the version line at the top of this README. `install.sh` re-arms
the hook on a fresh clone. See
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one)
for the whole rule.

## The menu-bar suite

A suite of macOS menu-bar apps that share one framework, one build-and-sign
script and one installer, built to sit in the same bar: consistent menus, a
common **Icon** picker, and cooperative hiding so no icon strands another.

| App | What it does |
|---|---|
| [Claude Usage](https://github.com/nicholaspsmith/claude-usage-menubar) | Claude Code plan limits, resets, and live agent sessions |
| [Apollo Monitor](https://github.com/nicholaspsmith/apollo-monitor-menubar) | Apollo audio-interface monitor level |
| [Battery Time](https://github.com/nicholaspsmith/battery-time-menubar) | Time remaining, power mode, and 24h usage |
| [VPN & DNS](https://github.com/nicholaspsmith/vpn-dns-menubar) | An iguana for Mullvad + Tailscale state, with a DNS watcher |
| [Mac Daddy](https://github.com/nicholaspsmith/mac-daddy-menubar) | Kills media trackers, trashes stale downloads, reaps hung processes, watches the UA mixer engine, and sweats as your process count climbs |
| [KeyLight](https://github.com/nicholaspsmith/keylight-menubar) | Ctrl+brightness keys remapped to keyboard backlight |
| [Monitor Lizard](https://github.com/nicholaspsmith/monitor-lizard-menubar) | External-monitor brightness, contrast and resolution, Night Shift, and the built-in screen from dimmer than macOS allows to XDR |
| [Homestead](https://github.com/nicholaspsmith/home-assistant-menubar) | Home Assistant dashboards and device controls in the menu |
| [SoundChain](https://github.com/nicholaspsmith/soundchain-menubar) | One chain of Audio Unit effects over all system audio |
| [Menu Crane](https://github.com/nicholaspsmith/menu-crane) | A ⌘Space launcher for apps, arithmetic, unit conversions and emoji |
| **Panes** | Window shortcuts, a layout grid and edge snapping |
| [MacRecorder](https://github.com/nicholaspsmith/MacRecorder) | Screen recording with system audio |
| [Barn](https://github.com/nicholaspsmith/menubar-barn) | macOS 26 and earlier only: hides a block of status icons by width (on macOS 27, use System Settings ▸ Menu Bar) |

| Framework | |
|---|---|
| [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit) | Status-item lifecycle, polling, menus, meter and mascot icons, the shared Icon picker |
| [HotkeyKit](https://github.com/nicholaspsmith/HotkeyKit) | CGEventTap engine for intercepting and remapping global keys |

Install the whole suite on a fresh Mac with
[macOS Dev Environment Setup](https://github.com/nicholaspsmith/MacOS-Dev-Environment-Setup):

```bash
git clone https://github.com/nicholaspsmith/MacOS-Dev-Environment-Setup.git
cd MacOS-Dev-Environment-Setup && ./bootstrap.sh --all
```

## License

Copyright (c) 2026 Nicholas Smith. Licensed under the
[Mozilla Public License 2.0](LICENSE). You may use, modify, sell and
redistribute this software, including inside proprietary products, provided
the copyright notice and license stay on these files and any modified
versions of them are made available under the same license.

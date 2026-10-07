# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

## [0.3.1] - 2026-10-07

- Clicking a window in Mission Control or App Exposé no longer snaps it (to full screen when the pointer was near the top): presses on the system's own overview are never treated as window drags

## [0.3.0] - 2026-10-06

- ⌥⌘ + arrows combine like Windows 11: ⌥⌘← then ⌥⌘↑ tiles the window to the top-left quarter, ⌥⌘→ from there to top-right, and ⌥⌘→ again widens it to the right half
- Hold ⌥⌘ on its own for a moment and a grid fades in over the front window's display, covering exactly the area below the menu bar. Click a cell or drag across cells and the window fills it, as in the menu; the app you were in keeps focus. Letting go or pressing any key puts it away (the key still does what it always does, so ⌥⌘Esc is still Force Quit), and quick ⌥⌘ shortcuts and cell-key chords never bring it up
- Hold ⌥⌘⇧ for half-cells, on the grid and in the menu alike (the menu's half-cells were on ⌥⌘ before)
- Ticking a checkbox in the menu no longer closes it: Settings ▸ Edge Snapping and Grid on Hold ⌥⌘ stay open
- Settings ▸ Grid on Hold ⌥⌘ turns it off; Preferences sets how long to hold

## [0.2.0] - 2026-10-06

- ⌥⌘C centres the window at the screen's proportions; pressing it again steps its size up (50%, 66%, 80%, full) and then back down, over and over
- Cell keys: the menu's grid cells are labelled 1 2 3 4 / 5 6 7 8 / 9 A B D / E F G H (no C: ⌥⌘C stays Center). Hold ⌥⌘, press one cell's key and let go to fill that cell, or two keys to fill the rectangle between them (1 then 8 is the top half). A preview shows the target while you hold the keys. The other ⌥⌘ shortcuts still act at once. This takes over ⌥⌘D (Dock hiding) and ⌥⌘H (Hide Others); Settings ▸ Preferences… can move cell keys to ⌃⌥, ⌃⌥⌘ or ⇧⌘
- Hold ⌥⌘ while the menu is open and its grid splits into half-cells (8×8): click or drag across them the same way. Let go to return to 4×4

## [0.1.0] - 2026-10-06

- First release: a keyboard and edge-snap window manager in the menu bar, to replace Rectangle
- Shortcuts for left, right, top and bottom halves (⌥⌘ + arrows), the four quarters (⌥⌘[ ] ; ', laid out like the corners they fill; browsers keep ⌥⌘I, J, U and K for their developer tools), Maximize (⌥⌘M), Center (⌥⌘C), Restore (⌥⌘⌫, undoes the last move Panes made to that window) and Next Display (⌥⌘N). Panes takes them before the front app sees them, so app shortcuts such as iTerm2's no longer get in the way, but only when there is a window to act on; otherwise the keys pass through
- Rebind any shortcut in Settings ▸ Preferences…
- A 4×4 grid at the top of the menu, shaped like your display: click a cell to fill it, or drag across cells to fill the rectangle they make. Cells under the front window are shaded in the accent colour, cells under other windows lightly
- Drag a window by its title bar to a display's left or right edge for a half, the top edge to maximize, or a corner for a quarter; a preview shows where it will land. Settings ▸ Edge Snapping turns it off, and the menu warns when macOS's own edge tiling is on
- Windows glide into place, a little quicker than macOS's own tiling; Reduce Motion moves them at once
- The menu-bar icon is a small display showing where every window on it sits

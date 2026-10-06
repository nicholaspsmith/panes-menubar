# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

## [0.1.0] - 2026-10-06

- First release: a keyboard and edge-snap window manager in the menu bar, to replace Rectangle
- Shortcuts for left, right, top and bottom halves (⌥⌘ + arrows), the four quarters (⌥⌘U, I, J, K), Maximize (⌥⌘M), Center (⌥⌘C), Restore (⌥⌘⌫, undoes the last move Panes made to that window) and Next Display (⌃⌥⌘→). Panes takes them before the front app sees them, so app shortcuts such as iTerm2's no longer get in the way, but only when there is a window to act on; otherwise the keys pass through
- Rebind any shortcut in Settings ▸ Preferences…
- A 4×4 grid at the top of the menu, shaped like your display: click a cell to fill it, or drag across cells to fill the rectangle they make. Cells under the front window are shaded in the accent colour, cells under other windows lightly
- Drag a window by its title bar to a display's left or right edge for a half, the top edge to maximize, or a corner for a quarter; a preview shows where it will land. Settings ▸ Edge Snapping turns it off, and the menu warns when macOS's own edge tiling is on
- Windows glide into place, a little quicker than macOS's own tiling; Reduce Motion moves them at once
- The menu-bar icon is a small display showing where every window on it sits

# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

## [1.12.1] - 2026-11-03

- Fixed alignment of status dots in keep-open menu rows so titles line up with other items.
- Prevented long keep-open menu rows with status dots from being clipped at the end.

## [1.12.0] - 2026-11-03

### Changed

- The menu's **Settings…** is now **Preferences…** (⌘,), and its window is **Panes Preferences**, as in Mac Daddy and the other Menumon apps. Same General and Shortcuts tabs; Esc or ⌘W now closes it.
- Every line you cannot click (status lines, the resolution submenu's HiDPI and Low resolution headings) stays greyed, including lines that appear when a section unfolds.
- The menu's rows and the Preferences window now come from StatusItemKit, shared with the other Menumon apps. Needs StatusItemKit 0.38.0.

## [1.11.2] - 2026-11-02

- The Apollo Monitor icon now displays the current level in grey when it cannot be controlled (e.g., due to missing permissions or connectivity issues), instead of appearing dark.

## [1.11.1] - 2026-11-02

### Changed

- Panes watches the keyboard through one event tap instead of two: the grid on hold ⌥⌘ now listens on the same tap as the shortcuts. Shortcuts and the grid behave as before. Needs HotkeyKit 1.1.0.

## [1.11.0] - 2026-11-02

### Removed

- The Pie and Wedge icons. If either was your icon, Panes now shows Arc.

## [1.10.0] - 2026-11-02

### Changed

- The Settings window's icon picker is a row of tiles that show each icon as it would look in the menu bar, not a list of names. The meters and Armonitor are drawn at 65% brightness so their shapes tell apart.

## [1.9.0] - 2026-11-02

### Changed

- Every setting now lives in one Settings window (Settings…, ⌘,), as in Mac Daddy. The General tab has Start at Login, Edge Snapping, Brightness Keys, the menu-bar icon and its colour, and Grid on Hold ⌥⌘ with its delay. The Shortcuts tab rebinds the window actions. The menu's Settings and Icon submenus are gone.

## [1.8.0] - 2026-11-02

### Changed

- The display and Night Shift sections start folded, like Shortcuts. Open one and Panes remembers it.

## [1.7.0] - 2026-11-02

### Changed

- Clicking an item no longer closes the menu: pick a grid cell, an action, an icon or a resolution and the menu stays open, the grid's shading following the window. Quit and the items ending in "…" (they open a window) still close it.
- Each display's section and the Night Shift section fold under their headings, like Shortcuts. Panes remembers which are open.
- Section headings show a chevron pointing down while folded and up while open, as in Homestead.
- Night Shift's on/off checkbox, now inside its section, is called Enabled.

### Fixed

- The "On at …" / "Off at …" schedule line is grey information, as the display names were, instead of an item that highlighted and did nothing.

## [1.6.0] - 2026-11-02

- The layout grid in the menu is 40% taller, so its cells are easier to hit.

## [1.5.0] - 2026-11-02

- Panes now appears in the menu bar one second faster.

## [1.4.0] - 2026-11-02

### Removed

- Cell keys: holding ⌥⌘ and typing a cell's key no longer moves the window, and the Cell Keys setting is gone from Preferences. Panes no longer takes ⌥⌘D (Dock hiding) or ⌥⌘H (Hide Others) from macOS.

### Changed

- The grid on hold ⌥⌘ numbers its 16 cells straight through in hex, 1 to F then 10, with no letter skipped.

## [1.3.0] - 2026-11-02

### Added

- Holding ⌥⌘⇧ numbers the 8×8 half-cell grid: 1 to 40 in hex, row by row from the top-left, in a smaller font than the 4×4 grid's cell keys.

## [1.2.0] - 2026-11-02

### Changed

- The window actions in the menu fold under one **Shortcuts** row. Click it to show the four groups below it, in place, and again to hide them; it starts folded each time the menu opens.

## [1.1.1] - 2026-11-01

### Fixed

- The menu's grid now lines up with the separators above and below it, filling the menu's width.

## [1.1.0] - 2026-11-01

- The minute cue no longer waits for Monitor Lizard, so the apps after it each move up a second
- The minute-cue comment now describes what Panes does on the cue

## [1.0.1] - 2026-11-01

### Changed

- The grid in the menu is centred.
- The grid in the menu always shows the finer 8×8 grid, and no longer changes when you hold ⌥⌘⇧.

## [1.0.0] - 2026-11-01

### Added

- Panes now does Monitor Lizard's job too: a section per display with brightness, contrast and resolution, the keyboard's brightness keys on an external monitor, Dim and XDR Brightness on the built-in screen, and Night Shift with its schedule. When it starts, Panes quits Monitor Lizard if it's running, turns off its login item, and (once) brings over its settings.
- Icon ▸ also offers Armonitor (Monitor Lizard's character) and the Arc, Gauge, Pie and Wedge meters of the main display's brightness, beside the Screen Grid and Major Pane.
- When the built-in screen's preset can't brighten past full, a line under XDR Brightness says which preset to pick: Apple XDR Display (P3-1600 nits).

### Changed

- The Screen Grid is now the default icon.
- Armonitor is Panes's mascot and app icon.
- Night Shift's schedule asks for Location only when its saved place is missing or older than 30 days, and keeps that place if Location is denied.
- ⌥⌘C's column is at least 1000 pt wide.
- Glides step at the display's refresh rate.
- Panes needs macOS 14 or later.
- Brightness Keys moved into Settings ▸.

### Fixed

- XDR Brightness works on M5 Macs.
- A glide always finishes, even if its display sleeps mid-move.
- Armonitor's full-screen lap now skips when Reduce Motion is on.

## [0.14.0] - 2026-10-20

### Changed

- Icon ▸ (Major Pane / Screen Grid) moves out of Settings ▸ into the main menu, directly below Settings and above Quit Panes. Settings keeps Edge Snapping, Grid on Hold ⌥⌘, Preferences…, Start at Login and the version. Needs StatusItemKit 0.35.0 (`SettingsMenu.addFooter(belowSettings:)`)

## [0.13.1] - 2026-10-20

- `install.sh` now hands the install to parity on a Mac parity syncs, instead of building a second copy of the app that macOS could launch in place of parity's. `PARITY=off ./install.sh` still builds it locally.

## [0.13.0] - 2026-10-20

- Menu bar icons now update with significantly less CPU usage, reducing background activity while animations play.

## [0.12.0] - 2026-10-15

- The menu bar owl icon now supports custom pupil colors, allowing users to choose their preferred color instead of the default green-to-red gradient.

## [0.11.0] - 2026-10-15

- Carol now sleeps in the menu bar, with her eyes closing, body breathing, and Zs floating above her.

## [0.10.0] - 2026-10-15

- Carol's head no longer gets cut off during her once-a-minute run, as her head movement now stays within the icon's boundaries.
- Carol can now walk with a rolling hump motion that is slower and distinct from her run, with smooth easing in and out.
- Carol's walking animation is optimized to cache poses, ensuring smooth performance with minimal resource usage.

## [0.9.0] - 2026-10-15
### Changed
- `⌥⌘C` now makes the window half the screen's width, centred, at full height; pressing it again centres it both ways at two thirds of the height, and further presses alternate between the two. It no longer steps through 50%, 66%, 80% and 100% sizes.
- Every glide is smoother: it eases in and out over 0.26 s instead of starting fast over 0.18 s. Growing a centred window to full height or to the whole screen, and back, no longer jumps at the start; measured frame by frame, the window now moves about 30 points between frames (45 at worst), down from up to 217.

## [0.8.5] - 2026-10-14
### Fixed
- Moving a window out of a tile macOS put it in (the green button's menu, Window ▸ Fill or Move & Resize), for example from the left half to the right half or to the centre, no longer first shrinks it back to its earlier size: it glides straight there. macOS forgets the tile by itself once the window leaves it, so Panes only runs Return to Previous Size when the window stays inside the tile.

## [0.8.4] - 2026-10-13
### Fixed
- A window you tiled with macOS's own tiling (the green button's menu, Window ▸ Fill or Move & Resize) no longer jumps back into that tile when Mission Control closes or a display wakes after Panes has moved it: Panes now takes it out of the macOS tile (Return to Previous Size) before moving it

## [0.8.3] - 2026-10-11
### Fixed
- Switching back to Major Pane in Settings ▸ Icon no longer plays a bark that was waiting when you switched away; he comes back standing at ease or idle, with the pane lit from the front window as it is now.

## [0.8.2] - 2026-10-11
### Changed
- Major Pane's pane is now as big as the old screen-grid icon, with a faint 4×4 grid on the glass so the lit cells line up with Panes's grid. His head and fists show around it; his legs no longer do.

## [0.8.1] - 2026-10-10
### Fixed
- Major Pane's pane lights the cells of the frontmost app's window, and only when that window is on the icon's display; a window in front on another display lights nothing instead of the wrong cells.
- The icon is redrawn only when its pixels change, so an idle Major Pane no longer wakes the menu bar four times a second.
- A stray merge marker in this changelog.

## [0.8.0] - 2026-10-09
### Added
- Major Pane, Panes's mascot: a pixel-art commander of windows in the menu bar, his pane held in front of him like a riot shield. Its 4×4 cells light to show where the front window sits; he salutes in the Menumon minute cue, barks when Panes moves a window, and stands at ease, greyed, without Accessibility.
- Settings ▸ Icon: Major Pane (default) or the screen grid.
### Changed
- The grid's tile-slide animation now plays only when the grid is the chosen icon.
- The app icon and README pictures are Major Pane.

## [0.7.0] - 2026-10-09

- No user-visible changes.

## [0.6.0] - 2026-10-08

- No user-visible changes.

## [0.5.0] - 2026-10-08

- The icon animates like the other Menumon glyphs: twice a minute the windows on the display bunch up in the middle and slide out into their tiles, the front one glowing as it lands, taking Panes's turn in the cue after Menu Crane. Skipped under Reduce Motion and on an empty display

## [0.4.0] - 2026-10-07

- No user-visible changes.

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

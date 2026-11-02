# Panes absorbs Monitor Lizard — design

Date: 2026-11-01. Tracks panes-menubar #15. Status: draft for Nick's review.

## Intent

One menu-bar app for everything about the screen: how windows are laid out
(Panes today) and how the displays look (Monitor Lizard today). One icon in
the bar, one Accessibility grant, one key tap, one display model. Monitor
Lizard is retired: its repo goes private, is archived on GitHub, and moves to
`~/Code-archive/`. Every other open issue in both repos is dealt with in the
same effort.

## Decisions Nick made

- **Panes is the app that carries on** (as #15 recommended): name *Panes*,
  repo `panes-menubar`, bundle id `com.nicholaspsmith.Panes`.
- **Monitor Lizard is sunset**: final release pointing at Panes, then the
  GitHub repo is made **private** and **archived**, and the local clone moves
  to `~/Code-archive/monitor-lizard-menubar`.
- **Default icon is the Screen Grid** (the icon that shows how the windows
  are laid out). **Every icon from both apps is an option.**
- **Remove Monitor Lizard from the Menumon site** (widgets.nicksmith.software)
  and **from the projects on nicksmith.software**, where **Panes takes its
  place** (Panes is not listed there today).
- **Armonitor (the monitor lizard) becomes Panes's mascot and logo**: the app
  icon (`AppIcon.icns`), the README mascot picture, the Menumon card/tile and
  the nicksmith.software logo. Major Pane remains an icon option only.
- **parity gets a "retire" feature** to take an app off every Mac, rather than
  hand-deleting the last link.
- **Fix every other open issue** in both repos. All nine (#15 included) were
  filed by Nick; none need triage.

## Goals

1. Panes does everything Monitor Lizard does today, with no regression:
   - per-display brightness/contrast (DDC; DisplayServices where macOS drives
     the display), HiDPI resolution row, the TV-role fix (OverrideWriter);
   - the built-in panel's one Brightness slider: Dim → macOS → XDR boost;
   - the plain brightness keys (external DDC main display steps 1/16 and is
     swallowed; built-in passes through, with Dim/XDR steps);
   - Night Shift on/off, Warmth, Schedule… window and its status line;
   - Armonitor's icon lap and full-screen lap (`MonitorLizardLap`,
     `LapTrigger`); the tongue flick on a write.
2. Nick's existing Monitor Lizard settings carry over on first launch.
3. Monitor Lizard disappears everywhere: both Macs, parity, MinuteCue, the
   two websites, sibling READMEs, the CLAUDE.md notes.
4. Each other open issue is closed with a fix or a recorded outcome.

## Non-goals

- No new display or window features beyond the issues listed.
- No new mascot or character; no redraw of existing glyphs.
- KeyLight's ⌃+brightness keys are not touched.
- No App Store / distribution work.

## Anti-goals (a failure even if it "works")

- Two icons in the bar at any point after the cut-over, or both apps
  fighting over the brightness keys.
- Losing Nick's Night Shift schedule/place/warmth, or the XDR-off-on-battery
  choice.
- A transfer table, EDR overlay or dim overlay outliving the app (quit,
  crash) — the existing "must never outlive the app" rule stands.
- Re-granting Accessibility over and over (the stable signing identity must
  keep working for the merged binary).
- Hand-made tags or releases; `gh pr merge --admin`.

## Constraints

- Releases: every push to `main` of a Menumon repo is a release via
  `CHANGELOG.md` + `release.yml`; merge with plain `gh pr merge --merge`;
  never tag by hand; titles `vX.Y.Z`. README/agent-doc-only pushes in sibling
  repos use `[no release]` in the tip commit.
- Push over SSH remotes (the `gh` token lacks the `workflow` scope).
- parity owns `~/Applications/<App>.app`; don't hand-edit those links.
- Minimum macOS becomes **14** (Monitor Lizard's floor; Panes was 13).
  The `Package.swift` platform and `LSMinimumSystemVersion` both move.
- Nick visual-QAs animation/icon changes; one change at a time.
- Never wave off warnings: fix or file.

## The merged app

### Code layout (my call)

- Copy Monitor Lizard's `Sources/MonitorLizardCore` into Panes as a library
  target **`DisplayCore`** (renamed: it is no longer "the lizard's"), and its
  tests as `DisplayCoreTests`. Git history stays in the archived private repo;
  the Panes commit message names the source commit (`4b96a7a`).
- Monitor Lizard's app-layer files (`DisplayModel`, `XDRController`,
  `DimOverlayController`, `BrightnessKeyController`, `NightShiftScheduler`,
  `NightShiftScheduleWindow`, `SliderRow`, `ResolutionRow`,
  `MenuBuilder+Displays`, `OverrideWriter`) move into the `Panes` executable
  target, under `Sources/Panes/Displays/`.
- `main.swift` stays thin: the `App` delegate owns a `WindowsFeature`
  (today's Panes body) and a `DisplaysFeature` (today's Monitor Lizard body),
  each building its own menu section. Builder may name/split differently.
- Logging subsystem becomes `com.nicholaspsmith.Panes` with the old category
  names kept (`xdr`, `ddc`, …), so existing `log show` recipes only change the
  subsystem.

### Icon

Settings-adjacent **Icon ▸** submenu (it already sits right below Settings,
StatusItemKit 0.35.0 `belowSettings:`), in this order:

1. **Screen Grid** — default when nothing is saved. Unchanged drawing.
2. **Major Pane** — unchanged.
3. **Armonitor** — `CharacterIcon.monitorLizard(brightness:nightShift:…)`,
   showing the main display's brightness and Night Shift, as in Monitor
   Lizard.
4. **Monitor Lizard's brightness meters** — `MeterStyle.proportional`
   (my call: these are "icons from that app" too; they show the main
   display's brightness fraction). Listed under a separator, titled as
   StatusItemKit's `AppearanceMenu` titles them, **with its colour presets and
   Custom Colour…** (my call: keep them; `MeterColorHex` migrates too).

Storage: Panes's `IconStyle` key gains `armonitor` and `meter:<style>`
values. Today's default `major-pane` changes to `grid`; an explicitly saved
value is respected (Nick's M5 already has `IconStyle = grid`).

### Minute cue and laps (my call)

- Panes keeps its one slot in `MinuteCue.order`; the slot plays whatever
  icon is showing: grid → tiles slide, Major Pane → salute, Armonitor → icon
  lap, meters → nothing.
- StatusItemKit: remove `com.nicholaspsmith.MonitorLizard` from
  `MinuteCue.order` (a StatusItemKit release; Panes then bumps to it).
- The **full-screen lap** keeps its yes/no triggers (launch, a never-seen
  display, Night Shift on/off) but plays **only while Armonitor is the
  icon**, because he runs out of the icon's slot and back. Same as Monitor
  Lizard today, where it plays only with the character style. **Add** a Reduce
  Motion check so it is skipped then (it isn't today; my call, matching the
  minute cue).
- The tongue flick on a DDC/brightness write shows only with Armonitor.

### Menu layout (my call; Nick didn't object)

Top to bottom:

1. **Displays**: one block per display (brightness/contrast/resolution;
   the built-in's one Brightness slider), as Monitor Lizard draws them.
2. **Night Shift** toggle, **Warmth**, **Schedule…** and its status line.
3. Separator, then the **window grid** and the **window actions**, as Panes
   draws them, with "No window to arrange" when there is none.
4. Warnings: **⚠ Grant Accessibility…** (once, for both features),
   **⚠ macOS Edge Tiling Is On…**.
5. `SettingsMenu` footer. Settings ▸ Start at Login, **Edge Snapping**,
   **Grid on Hold ⌥⌘**, **Brightness Keys**, **Preferences…**, then the
   version. The **XDR Brightness** toggle stays in the built-in display's
   block, where Monitor Lizard has it (`addXDRRows`); "off on battery" stays a
   stored value with no row, as today (my call: no change). **Icon ▸** below Settings. Then
   **Quit Panes**.

If the menu proves too tall on the built-in display, that's a follow-up issue,
not a blocker.

### Keys and Accessibility

- One app means one Accessibility grant. Nick re-grants once for Panes's
  binary only if the merged build's signature changes trust (it shouldn't,
  with the stable "StatusItemKit Local Signing" identity).
- **One HotkeyTap** carries both the ⌘⌥ window bindings and the plain
  brightness-key bindings (HotkeyKit can mix `.key` and `.mediaKey`
  triggers; first match wins). `model.onChange` → `tap.setBindings` replaces
  the whole set, so it must re-append the brightness bindings. `ChordTap`
  (flagsChanged) and EdgeSnapper stay their own taps: "one HotkeyTap", not
  one tap.
- The tap re-assert keeps Panes's ~6 s cycle; Monitor Lizard's
  per-poll `reassert()` folds into it.
- Monitor Lizard's 60 s safety poll and Panes's 1.5 s icon poll stay
  separate cadences inside one app (builder's choice of mechanism).

### Cut-over from a running Monitor Lizard (my call)

parity installs and relaunches Panes 1.0.0 while Monitor Lizard is still
running, so Panes handles the overlap itself. At launch, before starting its
brightness keys, Night Shift scheduler, Dim or XDR:

1. If `com.nicholaspsmith.MonitorLizard` is running, ask it to quit
   (`terminate()`, wait up to 5 s, then `forceTerminate()`). Monitor Lizard's
   own `applicationWillTerminate` clears its XDR table and dim overlay.
2. Run its bundled binary with `--login off` (its `LoginCLI`), so it doesn't
   come back at login. Find the bundle via
   `NSWorkspace.urlForApplication(withBundleIdentifier:)`.
3. Then migrate the settings (below), so the snapshot is final.

Steps 1–2 repeat on every launch, quietly, while a Monitor Lizard bundle is
still installed. They do nothing once it is gone. Log each action under the
`migration` category.

### Settings migration

On first launch of the merged Panes, once (flag key
`migratedFromMonitorLizard`), after the cut-over above:

- Read the `com.nicholaspsmith.MonitorLizard` domain
  (`UserDefaults(suiteName:)` or `CFPreferencesCopyAppValue`) and copy every
  key Monitor Lizard's code reads into Panes's domain, **only if Panes has no
  value for it**. Known keys on the M5 now: `MeterStyle`, `nightShiftPlace`,
  `nightShiftSchedule`, `nightShiftScheduleWarmth`, `xdrOffOnBattery`;
  in code also `brightnessKeys`; StatusItemKit's `MeterColorHex`; plus any
  TV-role/DDC cache keys the builder finds by grepping `MonitorLizardCore`,
  the app layer and StatusItemKit's `MeterAppearance`.
- Map `MeterStyle = character` to nothing (Panes's `IconStyle` decides the
  icon; don't let the old meter choice override the new grid default). A
  non-character `MeterStyle` maps to `IconStyle = meter:<style>` only if
  `IconStyle` was unset. (My call.)
- Never copy `NSStatusItem …` keys. Never delete the old domain (it goes with
  the uninstall).
- Unit-test the mapping as a pure function in `DisplayCore` or `PanesCore`.

Run `defaults read com.nicholaspsmith.MonitorLizard` on the **M1** too before
shipping, and add any keys it has that the M5 lacks.

### Location (my call)

Monitor Lizard's sunset/sunrise schedule uses CoreLocation, and Panes's
Info.plist gains its `NSLocationUsageDescription` and
`NSLocationWhenInUseUsageDescription`. To avoid a surprise prompt at first
launch, which could also land during parity's 5 s launch check:

- Panes uses the migrated `nightShiftPlace` and **doesn't ask for Location
  at launch** while it has a saved place less than 30 days old.
- It asks when the place is missing or stale, or when Schedule… is opened.
- If Location is denied or restricted, **keep** the saved place. Today's code
  deletes it.

### Notifications

Monitor Lizard posts user notifications (TV-role fix). Panes requests
notification authorization lazily, the first time it needs to post, not at
launch (my call: no new permission prompt for people who never hit it).

## The other open issues

| Issue | Outcome |
|---|---|
| ML #30 XDR multiply overlay | **Build it** in `XDRController`: one borderless, click-through, all-Spaces, full-screen window per built-in panel with a `CAMetalLayer` (`wantsExtendedDynamicRangeContent`, `.rgba16Float`, `extendedLinearSRGB`, `compositingFilter = "multiply"`) drawing the factor. Drop the transfer-table write/clear and the 1-px trigger window if the full-screen layer engages EDR on its own. When potential headroom is ≤ 5 or none is granted, the menu says "Set Displays ▸ Preset to Apple XDR Display (P3-1600 nits)". `sharingType = .none`. Turn the XDR row back on (`XDRPolicy.available`). Overlay must be removed on quit/terminate and is exclusive with Dim. |
| ML #9 hardware checks | Needs a person watching. Transfer it to Panes, rewrite the XDR checks for the overlay (incl. #30's Touch ID prompt and full-screen video side effects), and hand Nick the checklist at the end. Closes when Nick ticks it. |
| Panes #20 refresh-rate stepping | **Build it**: step glides at the window's display refresh rate (`NSScreen.displayLink` on macOS 14, which is now the floor; no Timer fallback needed). |
| Panes #21 first-glide jump | **Build it**: start the animation clock once the first step has landed (frame read back, or one display frame passed). Measure before/after with the #19 harness. |
| Panes #19 heavy-app glides | **Measure** with the harness (add it under `scripts/glide-harness/`): one Chromium app, one Electron app and Safari, box ↔ column (⌥⌘C) and box ↔ maximize (⌥⌘M). Tune `AnimationPacing` from the numbers; record them in the issue. Needs Screen Recording for the terminal. If that can't be granted, stop and ask Nick. |
| Panes #22 ⌥⌘C on the built-in | **Build** a width floor: `min(visible width, max(half width, 1000 pt))` (my call on the 1000). Keep `CenterToggle` recognising the column when an app's minimum width wins. Nick's eye decides if 1000 is right; it goes on the final checklist. |
| Panes #6 Safari tile snap-back | Watch-only. Search `log show` for WindowManager "Update Tiled Window" lines against Panes's "move from" lines over the last week. If no snap-back since 0.8.4/0.8.5, close it as fixed by those (they handle macOS tile records). Otherwise comment with what was found. |
| Panes #15 | Closed by the merge PR. |

Transfer ML #30 and #9 to panes-menubar (`gh issue transfer`) **before** the
repo goes private.

## Releases and order of operations

1. **Panes 1.0.0** (my call: the merge is a major change): the merge,
   #30, #20, #21, #22, README rewrite (the merged feature set, a "Brightness
   and Night Shift" section from Monitor Lizard's README, the icon list),
   CHANGELOG, `**Version 1.0.0**` line. Issues #19 and #21 may land as 1.0.x
   follow-ups if measuring takes longer.
2. **Monitor Lizard final release** (1.17.0): README banner "Retired: merged
   into Panes 1.0.0" with a link, CHANGELOG entry. No code changes.
3. **Take Monitor Lizard off both Macs.** Panes 1.0.0 has already quit it
   and turned its login item off. Add `monitor-lizard-menubar` to parity's
   `excluded`. Run `parity-ctl remove` on one Mac. parity refuses to remove
   the last copy, and finds apps through the `~/Applications` links, not
   `~/Code`. The last copy comes off through parity's new **retire** feature
   (below), not by hand.
4. **Retire the repo**: `gh repo edit --visibility private
   --accept-visibility-change-consequences`, `gh repo archive`, then
   `mv ~/Code/monitor-lizard-menubar ~/Code-archive/` on the M5 **and** the
   M1. Check code-sync doesn't re-clone an archived repo into `~/Code` on
   either Mac or dino. code-sync already skips archived repos for GitHub
   clones; confirm the peer path does too, and fix code-sync if it doesn't.
5. **StatusItemKit release**, *after* Monitor Lizard is excluded from parity,
   so parity's release PRs don't land on it and take 1.17.0:
   - drop it from `MinuteCue.order`;
   - fix `MinuteAnimationTests`, which uses its bundle id;
   - drop it from `scripts/release/adopt.sh`'s `APPS`;
   - update the README table.

   Panes depends on StatusItemKit by path, so it needs no bump.
6. **Sites and docs** (below).

## parity: retire an app (Nick's decision; design mine)

A parity release (CHANGELOG + its own flow) adding
`parity-ctl retire '{"key": "<repo>:<App>.app"}'`:

- quits the app on every Mac where it runs, then removes its
  `~/Applications` link and its `~/.parity/builds/…` builds on every Mac,
  including the last copy;
- records it in a new `retired` setting (list of keys), so parity never
  builds, installs or re-discovers it again, even if a link reappears;
- the panel's All apps list stops showing it; `parity-ctl state` lists it
  under `retired`;
- `parity-ctl unretire` takes the same JSON and undoes the record (it
  doesn't reinstall).

Leave unchanged the existing rule that `remove` never takes the last copy;
retiring is the deliberate path for that. Tests alongside parity's existing
`cycle` tests. Then step 3 above is `parity-ctl retire
'{"key": "monitor-lizard-menubar:Monitor Lizard.app"}'` (check the exact key
in `parity-ctl state`) instead of `excluded` + `remove`.

## Websites and docs

- **Menumon site** (`~/Code/widgets.nicksmith.software`): remove Monitor
  Lizard's card, its mascot animation and its hero-bar slot. Rewrite Panes's
  card to cover the merged feature set and its icon options. Drop Monitor
  Lizard from the glyph renderer's app list (keep `CharacterIcon.monitorLizard`
  rendering only where Panes's Armonitor option is shown, if the site shows
  icon options). **Redirect `/daemons/monitor-lizard/` to `/daemons/panes/`**
  (my call; drop it from `scripts/build-pages.py`'s list and `sitemap.xml`).
  Run `art/glyphs/render-glyphs.sh`, check the strips, and
  `npm run deploy`. Captures must stay IP-scrubbed.
- **nicksmith.software** (`~/Code/nicksmith.software`, `src/data/projects.ts`):
  replace the `monitor-lizard` entry with a `panes` entry in the same position
  in `PROJECTS` and `UTILITY_PROJECT_IDS`, with the merged description,
  technologies (Swift, AppKit, StatusItemKit, HotkeyKit, Accessibility API,
  DDC/CI, IOKit), link `https://github.com/nicholaspsmith/panes-menubar`, logo
  `/icons/panes-logo.png` made from Panes's new Armonitor app-icon tile. Delete
  `/icons/monitor-lizard-logo.png`, update `projects.test.ts`, regenerate
  `src/generated/lqip.json` the way the repo does, and change HotkeyKit's
  "Powers …" line to name Panes instead of Monitor Lizard. Fix the Menumon
  entry's daemon count ("Eleven small daemons", which drops by one). Follow that repo's
  own PR/deploy flow.
- **Sibling READMEs**: every Menumon README's app table (apollo, battery-time,
  claude-usage, home-assistant, keylight, HotkeyKit, MacRecorder,
  mac-daddy, soundchain, vpn-dns, StatusItemKit, menu-crane if it has one,
  MacOS-Dev-Environment-Setup) drops Monitor Lizard and widens Panes's
  description. `[no release]` pushes. menubar-barn is killed; leave it.
- **MacOS-Dev-Environment-Setup**: `setup_macos_dev.py` clones and
  installs Monitor Lizard (around lines 39, 759, 919 and 954), and
  `docs/system-inventory.md` mentions it. Remove both.
- **parity README** mentions the hello lap during the launch check; update it.
- **CLAUDE.md** (`~/.claude/CLAUDE.md`): twelve apps → eleven; move the
  Monitor Lizard notes (brightness keys, Dim + XDR, presets) under Panes, mark
  Monitor Lizard as retired 2026-11 with where it lives. Update the
  monitor-lizard project memory index to point at Panes.

## Mascot and app icon

- Panes's `AppIcon.icns`, `docs/mascot.png` and its Menumon card and tile
  become **Armonitor**: his menu-bar character drawn large on a dark tile,
  via the site's `art/glyphs/app-icons.sh` pipeline. Change Panes's entry from
  Major Pane to the Monitor Lizard character; `scripts/make-icon.sh` follows.
- The README introduces Armonitor as Panes's mascot. Major Pane and the Screen
  Grid are described as icon options.
- The Menumon **hero bar** shows Panes's default menu-bar icon, the Screen
  Grid (my call: the bar shows what really sits in the bar). The card's
  animation is Armonitor's.

## Testing

- Both suites run in Panes: `PanesCoreTests`, `PanesGlyphTests`,
  `DisplayCoreTests`. All pass, no new warnings.
- New pure tests: settings-migration mapping, icon-style parsing (old and new
  values), the #22 width floor, the #21 clock start, the #20 interval choice.
- Build and launch the app on the M5. Check:
  - the grid icon is shown;
  - each icon option draws;
  - the menu shows display blocks and the window grid;
  - brightness keys step the Dell in clamshell;
  - ⌘⌥ shortcuts still tile;
  - Night Shift toggles;
  - only one Panes icon and no Monitor Lizard icon remain.
- CI keeps `release / check`. Add a smoke launch if the release workflow
  already supports one for other apps; don't invent a new CI system.

## Left to the builder

- Exact type/file names and the feature split inside `main.swift`.
- How the two poll cadences are scheduled.
- Whether the full-screen lap needs any change to run from a non-lizard slot.
  It shouldn't, since it only plays with Armonitor.
- Harness placement and output format for #19.
- The PR breakdown. One PR for the merge plus small follow-up PRs for the
  glide issues is fine, as long as each push to `main` is a valid release.

## Hand back to Nick at the end

- The hardware checklist (#9, rewritten for the overlay), including:
  - XDR on the M5 with the XDR preset, on battery and on AC;
  - Dim/XDR across sleep, wake and lid close;
  - the Touch ID prompt with the overlay up;
  - full-screen video.
- An eyeball of the ⌥⌘C 1000 pt floor on the built-in display.
- A visual QA of each icon option and the minute cue.

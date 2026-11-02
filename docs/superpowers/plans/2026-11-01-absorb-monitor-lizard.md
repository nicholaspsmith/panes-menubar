# Panes absorbs Monitor Lizard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Panes 1.0.0 does everything Monitor Lizard does, plus the other open issues are resolved. Monitor Lizard is retired from both Macs, parity, StatusItemKit, both websites and the docs.

**Architecture:** Monitor Lizard's core library is copied into Panes as `DisplayCore`, and its app layer as `Sources/Panes/Displays/`, owned by a `DisplaysFeature` object that `App` composes next to today's window code. The pure logic added here goes in `PanesCore`/`DisplayCore` with unit tests: icon choice, settings migration, location policy, width floor, glide clock and pacing. parity gains a `retire` command, so the last copy of Monitor Lizard comes off through parity rather than by hand.

**Tech Stack:**
- Swift 5.9 / SwiftPM, AppKit, Metal (EDR overlay), CoreLocation.
- StatusItemKit and HotkeyKit, both by local path.
- parity: Python 3.9 stdlib, tested with pytest.
- Sites: widgets.nicksmith.software (static site plus a Cloudflare Worker) and nicksmith.software (TS).

**Spec:** `docs/superpowers/specs/2026-11-01-absorb-monitor-lizard-design.md` (this repo). Read it before any task.

## Global Constraints

- Every push to `main` of a Menumon repo is a release. Add `## [X.Y.Z] - YYYY-MM-DD` with `- ` entries to `CHANGELOG.md` and bump the README `**Version X.Y.Z**` line. Merge with plain `gh pr merge --merge` once `release / check` passes.
- Never tag by hand, never make a release by hand, never use `--admin`, never use `--auto`.
- README- or agent-doc-only pushes in sibling repos carry `[no release]` in the tip commit.
- Push over SSH remotes.
- End commits with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. End PR bodies with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Panes's minimum macOS becomes **14.0**, in both `Package.swift` (`.macOS(.v14)`) and `LSMinimumSystemVersion`.
- The bundle id stays `com.nicholaspsmith.Panes`. The log subsystem is `com.nicholaspsmith.Panes`, keeping the old category names.
- Release versions:

  | Repo | Version |
  |---|---|
  | Panes | 1.0.0 |
  | Monitor Lizard (final) | 1.17.0 |
  | parity | 2.2.0 |
  | StatusItemKit | next minor |

- Nothing here may leave an EDR overlay, transfer table or dim overlay alive after the app quits.
- No new warnings. Fix them or file them; never wave one off as pre-existing.
- Don't hand-edit `~/Applications/<App>.app` links (parity owns them).
- Don't launch Apollo Monitor. Relaunch SoundChain only with a graceful quit.
- Nick visual-QAs icon and animation changes. Stop for his look where a task says so.

## Review Focus

1. **Monitor Lizard still running when Panes 1.0.0 lands.** Expect: one icon, ML quit and its login item off, and settings copied after it quit. Covered in Task A5 (`MonitorLizardCutoverTests` plus a manual check).
2. **Panes already has a key that ML also has** (e.g. `brightnessKeys` set by the new build before migration). Expect: Panes's value wins and nothing is overwritten. Covered in Task A5 (`testExistingPanesValueWins`).
3. **Location denied or restricted after migration.** Expect: the saved place is kept and the schedule still runs. Covered in Task A6 (`testDeniedKeepsPlace`).
4. **App minimum width larger than the ⌥⌘C column.** Expect: the next press still sees "column" and gives the box. Covered in Task A8 (`testColumnRecognisedWhenAppMinimumWins`).
5. **A stored `IconStyle` that's unknown or old** (`"major-pane"`, empty, `"meter:"`, garbage). Expect: it maps to a valid choice, and garbage falls back to the grid. Covered in Task A4 (`testUnknownFallsBackToGrid`).

---

## Part A — Panes 1.0.0 (repo `~/Code/panes-menubar`, branch `absorb-monitor-lizard`)

### Task A0: Move Monitor Lizard's issues over

- [ ] **Step 1:** `gh issue transfer 30 nicholaspsmith/panes-menubar -R nicholaspsmith/monitor-lizard-menubar` and the same for `9`. Note the new issue numbers; later tasks call them **XDR#** and **HW#**.
- [ ] **Step 2:** Check #6. Run `/usr/bin/log show --last 7d --predicate 'process == "WindowManager" AND eventMessage CONTAINS "Update Tiled Window"'` and `/usr/bin/log show --last 7d --predicate 'subsystem == "com.nicholaspsmith.Panes" AND eventMessage CONTAINS "move from"'`.
  - If no Safari window was re-tiled after a Panes move: close #6 with a comment that 0.8.4/0.8.5 cover it, quoting the counts.
  - Otherwise: comment with the matching lines and leave it open.

### Task A1: `DisplayCore` library and tests

**Files:**
- Create `Sources/DisplayCore/*.swift`: copied from `~/Code/monitor-lizard-menubar/Sources/MonitorLizardCore/` at `4b96a7a`.
- Create `Tests/DisplayCoreTests/*.swift`: copied from `.../Tests/MonitorLizardCoreTests/`.
- Modify `Package.swift`: platform `.v14`; add the `DisplayCore` library target and its test target.
- Modify `Resources/Info.plist`: `LSMinimumSystemVersion` 14.0.

**Interfaces:**
- Produces module `DisplayCore`, with the same public API `MonitorLizardCore` has today. Later tasks use `XDRBrightness`, `XDRPolicy`, `BuiltInSlider`, `PanelDim`, `BrightnessKeys`, `LapTrigger`, `NightShiftSchedule`, `Coordinate`, `SunTimes`, `DDCService`, `DisplayModes`, `Log`.

- [ ] **Step 1:** Copy the files. Replace `import MonitorLizardCore` with `@testable import DisplayCore` / `import DisplayCore` in the tests. In `Log.swift`, change the subsystem to `com.nicholaspsmith.Panes`.
- [ ] **Step 2:** Run `swift test --filter DisplayCoreTests`. Expected: all tests pass. If a test asserts the old subsystem string, update it.
- [ ] **Step 3:** Run `swift build 2>&1 | grep -i warning`. Expected: no output.
- [ ] **Step 4:** Commit: `DisplayCore: Monitor Lizard's core at 4b96a7a`.

### Task A2: Displays app layer as `DisplaysFeature`

**Files:**
- Create `Sources/Panes/Displays/`, with these files moved from `monitor-lizard-menubar/Sources/MonitorLizard/`:
  - `DisplayModel.swift`, `XDRController.swift`, `DimOverlayController.swift`
  - `BrightnessKeyController.swift`, `NightShiftScheduler.swift`, `NightShiftScheduleWindow.swift`
  - `SliderRow.swift`, `ResolutionRow.swift`, `OverrideWriter.swift`
  - `MenuBuilder+Displays.swift`, as an extension on `DisplaysFeature`
- Create `Sources/Panes/Displays/DisplaysFeature.swift`. It holds the body of ML's `App` from `main.swift`, minus `NSApplicationDelegate`, the status item, the yield client and the minute cue.
- Modify `Package.swift`: the `Panes` target depends on `DisplayCore`.

**Interfaces:**
- Produces:
  ```swift
  final class DisplaysFeature {
      init(status: StatusItemController)
      var onIconInputsChanged: (() -> Void)?   // brightness/Night Shift moved
      func start()                              // model, scheduler, xdr, dimmer, keys (keys via Task A3)
      func stop()                               // xdr.stop(); dimmer.stop()
      func addMenuSection(to menu: NSMenu)      // display blocks + Night Shift block
      func settingsItems() -> [NSMenuItem]      // the Brightness Keys toggle
      var mainBrightnessFraction: Double { get }
      var nightShiftOn: Bool { get }
      var isWaitingForTrust: Bool { get }
      func flickTongueIfShown()                 // see Task A4
      func screenLapIfArmonitor()               // see Task A4
      func safetyPoll()                         // ML's 60 s onPoll body
  }
  ```
- `Notifier` asks for permission lazily, the first time `post` is called, not at launch.

- [ ] **Step 1:** Move the files. Make `DisplaysFeature` compile, without wiring it into `App` yet. Drop ML's `AppearanceMenu`; Task A4 owns icons.
- [ ] **Step 2:** Run `swift build 2>&1 | grep -iE "error|warning"`. Expected: no output.
- [ ] **Step 3:** Commit: `Displays: Monitor Lizard's app layer as DisplaysFeature`.

### Task A3: Wire it in — menu, keys, polls, Info.plist

**Files:**
- Modify `Sources/Panes/main.swift`.
- Modify `Sources/Panes/Displays/BrightnessKeyController.swift`. It stops owning a `HotkeyTap`. Instead it exposes `var bindings: [Binding]` and `func handle(token: String) -> Bool`.
- Modify `Resources/Info.plist`: add `NSLocationUsageDescription` and `NSLocationWhenInUseUsageDescription`, both set to `Panes uses your location to work out sunset and sunrise for the Night Shift schedule.`

**Interfaces:**
- Consumes: `DisplaysFeature` (Task A2).
- `App` builds the one `HotkeyTap` from `model.tapBindings + displays.brightnessBindings`. Everywhere it calls `tap.setBindings(...)`, it re-appends the brightness bindings. Tokens are routed to the brightness controller first when they are brightness tokens.

- [ ] **Step 1:** Build the menu in this order:
  1. `displays.addMenuSection`
  2. separator
  3. the grid and the window actions
  4. one `⚠ Grant Accessibility…` when the tap isn't trusted
  5. the edge-tiling warning
  6. the `SettingsMenu` footer, with Edge Snapping, Grid on Hold ⌥⌘, Brightness Keys and Preferences…
  7. Icon ▸ below Settings

  Leave out ML's own Grant row.
- [ ] **Step 2:** Run `displays.safetyPoll()` every 40th tick of the 1.5 s poll (60 s). Fold `brightnessKeys.reassert()` into the existing ~6 s tap re-create.
- [ ] **Step 3:** In `applicationWillTerminate`, call `displays.stop()`.
- [ ] **Step 4:** Run `swift build && swift test`. Expected: all suites pass, with no warnings.
- [ ] **Step 5:** Run `scripts/build-app.sh`, quit Monitor Lizard by hand, then launch the build. Check:
  - the menu shows display blocks above the grid;
  - F1/F2 step the Dell when it's the main display;
  - ⌥⌘← tiles;
  - Night Shift toggles.
- [ ] **Step 6:** Commit: `Panes: displays, Night Shift and brightness keys in the menu`.

### Task A4: Icon choices, minute cue, laps

**Files:**
- Create `Sources/PanesCore/IconChoice.swift`.
- Test `Tests/PanesCoreTests/IconChoiceTests.swift`.
- Modify `Sources/Panes/main.swift`: icon menu, `refreshIcon`, `minuteCueFired`.
- Modify `Sources/Panes/Displays/DisplaysFeature.swift`: lap and tongue gating.

**Interfaces:**
- Produces:
  ```swift
  public enum IconChoice: Equatable {
      case grid, majorPane, armonitor, meter(String)   // meter's String = StatusItemKit MeterStyle raw value
      public static let key = "IconStyle"
      public init(stored: String?, knownMeters: Set<String>)
      public var stored: String   // "grid" | "major-pane" | "armonitor" | "meter:<raw>"
  }
  ```

- [ ] **Step 1: Failing tests** in `IconChoiceTests`:
  ```swift
  func testNilIsGrid() { XCTAssertEqual(IconChoice(stored: nil, knownMeters: ["arc"]), .grid) }
  func testRoundTrip() { for c in [IconChoice.grid, .majorPane, .armonitor, .meter("arc")] {
      XCTAssertEqual(IconChoice(stored: c.stored, knownMeters: ["arc"]), c) } }
  func testOldMajorPaneKept() { XCTAssertEqual(IconChoice(stored: "major-pane", knownMeters: []), .majorPane) }
  func testUnknownFallsBackToGrid() {
      for s in ["", "meter:", "meter:nope", "lizard", "GRID"] { XCTAssertEqual(IconChoice(stored: s, knownMeters: ["arc"]), .grid) } }
  ```
- [ ] **Step 2:** Run `swift test --filter IconChoiceTests`. Expected: FAIL (type not defined).
- [ ] **Step 3:** Implement it.
- [ ] **Step 4:** Run `swift test --filter IconChoiceTests`. Expected: PASS.
- [ ] **Step 5: Icon ▸ menu.** Items in this order: Screen Grid, Major Pane, Armonitor. Then a separator, then one item per `MeterStyle.proportional`, titled as StatusItemKit titles them, then StatusItemKit's colour presets and `Custom Colour…`.
  - Reuse `AppearanceMenu`/`MeterAppearance` for the meter half if they can be embedded. If not, build the items and write `MeterColorHex` through `MeterAppearance`.
- [ ] **Step 6: `refreshIcon` draws the chosen icon.**
  - **Armonitor:** `CharacterIcon.monitorLizard(brightness: displays.mainBrightnessFraction, nightShift: displays.nightShiftOn, tongue:, lizard:, lap:)`.
  - **Meters:** `MeterAppearance.image(fraction:)`.
  - Brightness or Night Shift changes redraw the icon only for those two choices.
- [ ] **Step 7: Minute cue.** grid → `slideTiles()`; Major Pane → `salute()`; Armonitor → the icon lap (`CharacterIcon.monitorLizardLapDuration`); meter → nothing.
  - The full-screen lap and the tongue flick happen only when the choice is `.armonitor`.
  - The full-screen lap also checks `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` and skips when it's on.
- [ ] **Step 8:** Rebuild and launch. Cycle every icon option, and wait for :00/:30 on each. **Stop for Nick's visual QA.**
- [ ] **Step 9:** Commit: `Icon: Screen Grid default; Major Pane, Armonitor and meters as options`.

### Task A5: Cut-over and settings migration

**Files:**
- Create `Sources/DisplayCore/MonitorLizardMigration.swift`.
- Test `Tests/DisplayCoreTests/MonitorLizardMigrationTests.swift`.
- Create `Sources/Panes/Displays/MonitorLizardCutover.swift`.
- Modify `Sources/Panes/main.swift`: run the cut-over before `displays.start()`.

**Interfaces:**
- Produces:
  ```swift
  public enum MonitorLizardMigration {
      public static let doneKey = "migratedFromMonitorLizard"
      public static let oldDomain = "com.nicholaspsmith.MonitorLizard"
      /// Keys to write into Panes's domain. `old` is ML's domain; `existing` the keys Panes already has.
      public static func values(old: [String: Any], existing: Set<String>, now: Date) -> [String: Any]
  }
  final class MonitorLizardCutover { func run(completion: @escaping () -> Void) }  // quit ML, `--login off`, then completion
  ```
- Copied keys:
  - `brightnessKeys`, `xdrOffOnBattery`, `nightShiftSchedule`, `nightShiftScheduleWarmth`, `nightShiftPlace`, `MeterColorHex`;
  - every TV-role/DDC key found by grepping `DisplayCore` and `Sources/Panes/Displays` for `forKey:` and key constants. List them in the source.
- Never copied: `NSStatusItem*` and `MeterStyle`. `MeterStyle` other than `character` becomes `IconStyle = meter:<raw>`, only when `IconStyle` isn't already set.
- When `nightShiftPlace` is copied, also write `nightShiftPlaceDate = now` (used by Task A6).

- [ ] **Step 1: Failing tests:**
  - `testCopiesKnownKeys`
  - `testExistingPanesValueWins`: `existing: ["brightnessKeys"]` → no `brightnessKeys` in the result
  - `testSkipsStatusItemKeys`
  - `testCharacterMeterStyleDropped`
  - `testOtherMeterStyleBecomesIconStyle`: `["MeterStyle": "arc"]` → `IconStyle == "meter:arc"`
  - `testMeterStyleDoesNotOverrideIconStyle`: `existing: ["IconStyle"]`
  - `testPlaceGetsDate`
- [ ] **Step 2:** Run `swift test --filter MonitorLizardMigrationTests`. Expected: FAIL.
- [ ] **Step 3:** Implement `values`.
- [ ] **Step 4:** Run `swift test --filter MonitorLizardMigrationTests`. Expected: PASS.
- [ ] **Step 5: Implement `MonitorLizardCutover.run`.**
  - If `com.nicholaspsmith.MonitorLizard` is running, `terminate()` it. Poll `isTerminated` for 5 s, then `forceTerminate()`.
  - Find the bundle with `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`, and run `Contents/MacOS/MonitorLizard --login off` (or whatever executable its Info.plist names).
  - Log each step under `Log` category `migration`.
  - Then, if `doneKey` isn't set, apply `values(...)` and set `doneKey`.
  - Run it on every launch. It does nothing when no bundle is found.
- [ ] **Step 6: Manual check.** Start Monitor Lizard, then launch the Panes build. Expected:
  - ML's icon goes;
  - `defaults read com.nicholaspsmith.Panes` shows the copied keys;
  - System Settings ▸ Login Items no longer lists Monitor Lizard.

  Before shipping, run `ssh macbook-pro-m1.local defaults read com.nicholaspsmith.MonitorLizard` and add any keys missing from the copy list.
- [ ] **Step 7:** Commit: `Migration: quit Monitor Lizard and bring its settings over`.

### Task A6: Location only when needed

**Files:**
- Create `Sources/DisplayCore/LocationPolicy.swift`.
- Test `Tests/DisplayCoreTests/LocationPolicyTests.swift`.
- Modify `Sources/Panes/Displays/NightShiftScheduler.swift`: `locate()` callers, and the denied path at line ~193.

**Interfaces:**
- Produces:
  ```swift
  public enum LocationPolicy {
      public static let maxAge: TimeInterval = 30 * 24 * 3600
      public static let dateKey = "nightShiftPlaceDate"
      public static func shouldLocate(hasPlace: Bool, placeDate: Date?, now: Date, scheduleOpened: Bool) -> Bool
  }
  ```
- `shouldLocate` is true when `scheduleOpened`, when there's no place, when there's no date, or when the place is older than `maxAge`.

- [ ] **Step 1: Failing tests:**
  - `testFreshPlaceNoPrompt`: place dated 1 day ago → false
  - `testStalePlaceLocates`: 31 days → true
  - `testNoPlaceLocates`
  - `testScheduleOpenedLocates`
  - `testDeniedKeepsPlace`: drive the scheduler's denied handler through a seam (`func authorizationChanged(_ status: CLAuthorizationStatus)`) and assert `nightShiftPlace` is still in a scratch `UserDefaults(suiteName:)`. Inject the defaults into the scheduler for this.
- [ ] **Step 2:** Run `swift test --filter LocationPolicyTests`. Expected: FAIL.
- [ ] **Step 3: Implement the policy and use it.**
  - Every `if usesSun { locate() }` becomes `if usesSun, LocationPolicy.shouldLocate(...)`.
  - The 6 h re-locate also goes through the policy.
  - Schedule… passes `scheduleOpened: true`.
  - A successful fix writes `dateKey`.
  - Denied or restricted no longer removes `placeKey`.
- [ ] **Step 4:** Run `swift test`. Expected: PASS.
- [ ] **Step 5:** Commit: `Night Shift: ask for Location only when the saved place is missing or stale`.

### Task A7: XDR via the multiply-composited EDR overlay (XDR#)

**Files:**
- Modify `Sources/Panes/Displays/XDRController.swift`: replace the transfer-table path.
- Create `Sources/Panes/Displays/EDRMultiplyOverlay.swift`.
- Modify `Sources/DisplayCore/XDRBrightness.swift`:
  - `XDRPolicy.available = true`;
  - add `presetHint`;
  - remove the table helpers once nothing uses them, along with their tests.
- Test `Tests/DisplayCoreTests/XDRBrightnessTests.swift`.
- Modify `Sources/Panes/Displays/MenuBuilder+Displays.swift`: the hint row.

**Interfaces:**
- Produces:
  ```swift
  extension XDRPolicy {
      /// Disabled-row text when the panel can't give headroom, else nil.
      public static func presetHint(potentialHeadroom: Float, grantedHeadroom: Float?) -> String?
      // "Set Displays ▸ Preset to Apple XDR Display (P3-1600 nits)" when potential <= 5, or granted is non-nil and <= hdrReadyThreshold
  }
  final class EDRMultiplyOverlay {      // one per built-in panel
      init(screen: NSScreen)
      var factor: Float { get set }     // draws a uniform value = factor; <= 1 hides the window
      func close()
  }
  ```
- The window:
  - borderless, `ignoresMouseEvents`, `sharingType = .none`;
  - `collectionBehavior` `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`;
  - level `.screenSaver`;
  - frame = the screen frame, refit on `didChangeScreenParametersNotification`.
- The layer: a `CAMetalLayer` with `wantsExtendedDynamicRangeContent = true`, `pixelFormat = .rgba16Float`, `colorspace = extendedLinearSRGB` and `compositingFilter = "multiply"`. It redraws only when the factor changes.
- The factor stays `XDRBrightness.factor(boost:headroom:)`, following the 4 Hz headroom timer.

- [ ] **Step 1: Failing tests.**
  - `testPresetHintOnSDRPreset`: `(5, nil)` → the string.
  - `testNoHintOnXDRPreset`: `(16, 2.67)` → nil.
  - `testHintWhenNothingGranted`: `(16, 1.0)` → the string.
- [ ] **Step 2:** Run `swift test --filter XDRBrightnessTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Keep every lifecycle rule in the file's header comment, with "table cleared" now meaning "overlay closed": sleep, display sleep, reconfiguration with settle, battery, quit.
  - Drop the 1-px trigger window if the full-screen layer engages EDR by itself. Check with `NSScreen.maximumExtendedDynamicRangeColorComponentValue > 1.05` within 2 s.
  - Dim and XDR stay exclusive.
  - Update the header comment to say the overlay replaces the table, and why (FB22273730).
- [ ] **Step 4:** Run `swift test`. Expected: PASS.
- [ ] **Step 5: Hardware check** on the M5, with the lid open and the XDR preset (already set): XDR on, slider at the top. Expected: visibly brighter whites. The log under category `xdr` shows the headroom granted. If it doesn't engage, record the log in XDR# and stop for Nick.
- [ ] **Step 6:** Commit with `Closes #XDR#` in the body: `XDR: multiply-composited EDR overlay replaces the transfer table`.

### Task A8: ⌥⌘C width floor (#22)

**Files:**
- Modify `Sources/PanesCore/CenterToggle.swift`.
- Test `Tests/PanesCoreTests/CenterToggleTests.swift`.

**Interfaces:**
- Produces:
  - `public static let minimumWidth: CGFloat = 1000`
  - `public static func width(in v: CGRect) -> CGFloat` = `min(v.width, max((v.width * widthShare).rounded(), minimumWidth))`
  - `column` and `box` use `width(in:)`.

- [ ] **Step 1: Failing tests.**
  - `testFloorOnBuiltIn`: visible width 1512 → 1000.
  - `testHalfOnWideDisplay`: 2560 → 1280.
  - `testCappedAtVisibleWidth`: 900 → 900.
  - `testColumnRecognisedWhenAppMinimumWins`: a window 1100 wide, centred, full height, on a 1512 display → `next` returns the box.

  For the last one, if the 24 pt tolerance makes it fail: recognise the column by full height plus a centred midX (±tolerance), at any width ≥ the column's.
- [ ] **Step 2:** Run `swift test --filter CenterToggleTests`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `swift test --filter CenterToggleTests`. Expected: PASS.
- [ ] **Step 5:** Commit with `Closes #22`: `⌥⌘C: at least 1000 pt wide on small displays`.

### Task A9: Step at the display's refresh rate (#20)

**Files:**
- Modify `Sources/PanesCore/FrameAnimation.swift` (`AnimationPacing`).
- Modify `Sources/Panes/WindowMover.swift` (`startGlide`).
- Test `Tests/PanesCoreTests/FrameAnimationTests.swift`.

**Interfaces:**
- Produces: `AnimationPacing.stepInterval(duration:setCost:reduceMotion:refreshRate:)`.
  - `refreshRate` is in Hz, with a default of 120.
  - The base interval is `1 / refreshRate`.
  - `frameInterval` is removed.

- [ ] **Step 1: Failing tests.**
  - `testSixtyHertzInterval`: setCost nil, refreshRate 60 → 1/60.
  - `testSlowAppCoarsens`: setCost 0.03, refreshRate 120 → 0.03.
  - `testTooSlowJumps`: setCost 0.07 → nil.
  - Keep the existing Reduce Motion test.
- [ ] **Step 2:** Run `swift test --filter FrameAnimationTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `startGlide` passes the `maximumFramesPerSecond` of the screen holding the target frame.
  - When the step equals the display's frame interval, step from that screen's `displayLink(target:selector:)`, added to `.main` in `.common` mode.
  - When the step is coarser, keep the Timer.
- [ ] **Step 4:** Run `swift test`. Expected: PASS.
- [ ] **Step 5:** Commit with `Closes #20`: `Glides step at the display's refresh rate`.

### Task A10: Start the glide clock once the first step lands (#21)

**Files:**
- Create `Sources/PanesCore/GlideClock.swift`.
- Test `Tests/PanesCoreTests/GlideClockTests.swift`.
- Modify `Sources/Panes/WindowMover.swift`.

**Interfaces:**
- Produces:
  ```swift
  public struct GlideClock {
      public init(created: TimeInterval, frameInterval: TimeInterval)
      /// Call each tick with whether the window's frame now reads back the first step.
      public mutating func tick(now: TimeInterval, firstStepLanded: Bool)
      public var elapsed: TimeInterval? { get }   // nil until started
  }
  ```
- The clock starts at the first tick where `firstStepLanded` is true, or one `frameInterval` after `created`, whichever comes first. After that, `elapsed = now - start`.

- [ ] **Step 1: Failing tests.**
  - `testWaitsForFirstStep`: created 0, interval 1/60; `tick(0.005, false)` → `elapsed` nil.
  - `testStartsWhenLanded`: `tick(0.010, true)`, then `tick(0.020, false)` → `elapsed == 0.010`.
  - `testStartsAfterOneFrameRegardless`: `tick(0.017, false)` → `elapsed == 0` at 0.017.
- [ ] **Step 2:** Run `swift test --filter GlideClockTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** In `startGlide`, set the first step, then drive `frame(at:)` from `clock.elapsed` (nil → hold).
- [ ] **Step 4:** Run `swift test`. Expected: PASS.
- [ ] **Step 5:** Commit: `Glides: start the clock when the first step reaches the window`. Task A11 measures it before #21 closes.

### Task A11: Measure glides in heavy apps (#19, #21)

**Files:**
- Create `scripts/glide-harness/TileTest.swift`, `scripts/glide-harness/edges.swift` and `scripts/glide-harness/README.md`, with the code from #19 verbatim. The README covers how to build, the Screen Recording need and the arguments.

- [ ] **Step 1:** Check that the terminal has Screen Recording. Run the `edges` build against `TileTest.app`. If capture fails for lack of permission, **stop and ask Nick** to grant it.
- [ ] **Step 2:** Measure the first press after 10 s idle, plus presses 2–4, with the 0.14.0 build (`git stash` / an old build) and with this branch, using `edges key:8` (⌥⌘C). Post both tables in #21. Close #21 if the first-press biggest jump is ≤ 1.2× the later presses' jump. Otherwise leave it open with the numbers.
- [ ] **Step 3:** Record setCost, frames shown, biggest jump and backward moves for Safari, one Chromium browser (Helium if installed) and one Electron app (Slack or VS Code), box↔column and box↔maximize. The harness reads only magenta edges; for real apps, use `key:` mode and the app's own frame from AX logging. Record whatever can be measured, and say what can't.
- [ ] **Step 4:** Tune `AnimationPacing.minimumSteps` or the coarsening only if the numbers show a gain. Any change gets a test in `FrameAnimationTests`. Post the table in #19 and close it.
- [ ] **Step 5:** Commit: `scripts/glide-harness: the edge recorder from #19`.

### Task A12: Armonitor as mascot, README, CHANGELOG

**Files:**
- Modify `~/Code/widgets.nicksmith.software/art/glyphs/app-icons.sh` (and `app-icons.swift` if the character is chosen there): Panes's tile draws `CharacterIcon.monitorLizard`.
- Modify `scripts/make-icon.sh` if it names the character.
- Regenerate `Resources/bundle/AppIcon.icns`, `docs/mascot.png` and `docs/menubar-icon.png` (the grid, as the default).
- Modify `README.md` and `CHANGELOG.md`.

- [ ] **Step 1:** Regenerate through the site's pipeline (`render-glyphs.sh`, which runs `app-icons.sh`), then copy the results as `make-icon.sh` does. Never screen-capture the bar.
- [ ] **Step 2: README.**
  - Top line: `**Version 1.0.0** · [Changelog](https://github.com/nicholaspsmith/panes-menubar/releases)`.
  - Armonitor is introduced as the mascot.
  - New sections: "Displays and brightness" and "Night Shift", taken from ML's README, with the paths and names updated.
  - An icon list: Screen Grid (default), Major Pane, Armonitor and the meters.
  - Update the Accessibility/Location permissions, the macOS 14 floor and the app table (Monitor Lizard row removed).
  - Add a note that Panes replaces Monitor Lizard.
- [ ] **Step 3: CHANGELOG.** Add `## [1.0.0] - <today>` with user-facing `- ` lines:
  - Panes now does Monitor Lizard's job (displays, brightness keys, Dim/XDR, Night Shift) and quits it on first launch, keeping its settings.
  - Screen Grid is the default icon; Armonitor and the meters are options.
  - XDR works on M5 Macs.
  - ⌥⌘C is at least 1000 pt wide.
  - Glides step at the display's refresh rate, and the first one no longer jumps.
  - Needs macOS 14.
- [ ] **Step 4:** Commit: `1.0.0: Panes absorbs Monitor Lizard`.

### Task A13: Verify, PR, merge

- [ ] **Step 1:** Run `swift build 2>&1 | grep -ci warning` → `0`, then `swift test` → all pass. Paste the summary line into the PR.
- [ ] **Step 2:** Use superpowers:requesting-code-review on the branch, and fix what it finds.
- [ ] **Step 3:** `git push -u origin absorb-monitor-lizard`, then `gh pr create`. The body says what changed, lists `Closes #15 #20 #22 #XDR#`, and links the spec.
- [ ] **Step 4:** Wait for `release / check`, then `gh pr merge --merge`, then `git pull` (tag `v1.0.0`).
- [ ] **Step 5:** Within a parity cycle or two, check both Macs:
  - `ssh macbook-pro-m1.local pgrep -lf MonitorLizard` → nothing; the same locally;
  - Panes's Version row reads `1.0.0`;
  - one Panes icon.

---

## Part B — Monitor Lizard 1.17.0, final (repo `~/Code/monitor-lizard-menubar`)

### Task B1: Final release

- [ ] **Step 1:** Put a banner under the README title: `> **Retired.** Monitor Lizard is now part of [Panes](https://github.com/nicholaspsmith/panes-menubar) 1.0.0. Install Panes; it quits Monitor Lizard and keeps its settings.` Bump the Version line to 1.17.0.
- [ ] **Step 2:** Add CHANGELOG `## [1.17.0] - <today>`: `- Retired: Monitor Lizard's features moved into Panes 1.0.0. This is the last release.`
- [ ] **Step 3:** Create branch `retire`, commit, push, open a PR, wait for the check, then `gh pr merge --merge` and `git pull`.

---

## Part C — parity 2.2.0: `retire` (repo `~/Code/parity`)

### Task C1: Retire an app everywhere

**Files:**
- Modify `parity/config.py`:
  - add the default `"retired": []`;
  - validation: a list of `"repo:App.app"` strings.
- Modify `parity/daemon.py`: `retire_app(key)`, `unretire_app(key)`.
- Modify `parity/ctl.py`: add `"retire": "POST"` and `"unretire": "POST"`.
- Modify `parity/cycle.py`:
  - retired keys are skipped by build, install, placement and `install_both`;
  - a `_remove_retired` pass, modelled on `_remove_kept_off` but without the last-copy refusal.
- Modify the agent remote-call handling, if `remove` is whitelisted there.
- Modify `README.md` and `CHANGELOG.md`.
- Test `tests/test_cycle.py`, `tests/test_daemon.py`, `tests/test_config.py`, `tests/test_ctl.py`.

**Interfaces:**
- Produces:
  - `Daemon.retire_app(key: str) -> None`: adds the key to `cfg["retired"]`, clears any placement requests, logs `asked to retire <label>`, and calls `self.sync(repo)`.
  - `Daemon.unretire_app(key) -> None`: removes the key only, with no reinstall.
- `_remove_retired(ctx, repo, entries) -> dict`, for each probed Mac:
  - a parity-sourced copy is removed with `install.remove` (or `m.call("remove", …)`);
  - a hand-installed copy gets a `_once` info line and is left alone;
  - the app is dropped from `st.app(key)["machines"]`;
  - in `dry_run`, it only logs.

- [ ] **Step 1: Failing tests:**
  - `test_retire_records_key`
  - `test_unretire_removes_key_only`
  - `test_retired_last_copy_is_removed`: one machine holds the only copy → removed
  - `test_retired_never_installed`: `install_both` true, the app on M5 only, retired → no install on M1
  - `test_retired_hand_copy_left`
  - `test_retired_dry_run_only_logs`
  - `test_config_rejects_bad_retired`
  - `test_ctl_retire_posts`
- [ ] **Step 2:** Run `python3 -m pytest -q tests`. Expected: the new tests fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `python3 -m pytest -q`. Expected: all pass.
- [ ] **Step 5:** README: document `retire`/`unretire` under the `parity-ctl` commands and `retired` under the settings. Also change the launch-check bullet "and Monitor Lizard's hello lap across the screen" to drop Monitor Lizard. Add CHANGELOG `## [2.2.0] - <today>`.
- [ ] **Step 6:** Use parity's own PR/merge flow (check its README "Releases"), then reinstall it as it says (`install.sh` or self-install).
- [ ] **Step 7:** Run `parity-ctl state | grep -i lizard` to get the exact key, then `parity-ctl retire '{"key": "<that key>"}'`. After a cycle, `ls ~/Applications | grep -i lizard` and the same over ssh on the M1 → nothing.

---

## Part D — Retire the repo

### Task D1: Private, archived, moved

- [ ] **Step 1:** Run `gh repo edit nicholaspsmith/monitor-lizard-menubar --visibility private --accept-visibility-change-consequences`, then `gh repo archive nicholaspsmith/monitor-lizard-menubar --yes`.
- [ ] **Step 2:** `mv ~/Code/monitor-lizard-menubar ~/Code-archive/`. Then `ssh macbook-pro-m1.local 'mkdir -p ~/Code-archive && mv ~/Code/monitor-lizard-menubar ~/Code-archive/'` if it's there, and the same check on `ssh dino`. dino needs Mullvad disconnected; if it's unreachable, note it.
- [ ] **Step 3:** Run `projects sync --dry-run` on the M5. Expected: no clone of monitor-lizard-menubar is planned. Read code-sync's peer-clone path. If a peer inventory could still offer it, fix code-sync to skip archived repos (with a test, following its release flow), not by hand.
- [ ] **Step 4:** Move the Claude project memory: copy `~/.claude/projects/-Users-nicholassmith-Code-monitor-lizard-menubar/memory/*` notes that still apply (release naming, visual QA, no-ignoring-warnings, the XDR gating note, now obsolete: delete it) into the panes-menubar project memory, and update both `MEMORY.md` indexes.

---

## Part E — StatusItemKit release (after Part C step 7)

### Task E1: Drop Monitor Lizard

**Files:**
- Modify `Sources/StatusItemKit/MinuteCue.swift`: remove the `com.nicholaspsmith.MonitorLizard` line. Update Panes's comment to cover all its icon choices.
- Modify `Tests/.../MinuteAnimationTests.swift`: swap the ML bundle id for another app in `order`.
- Modify `scripts/release/adopt.sh`: remove ML from `APPS`.
- Modify `README.md`: the app table.
- Modify `CHANGELOG.md`: a minor version.

- [ ] **Step 1:** Make the edits.
- [ ] **Step 2:** Run `swift test`. Expected: all pass.
- [ ] **Step 3:** Branch, PR, check, `gh pr merge --merge`, `git pull`. parity's release PRs will follow on the apps. Let them run their normal course.

---

## Part F — Menumon site (`~/Code/widgets.nicksmith.software`)

### Task F1: Remove Monitor Lizard, rewrite Panes

- [ ] **Step 1:** Run `git grep -n -i "monitor.lizard\|monitorlizard\|armonitor"`. Every hit is one of:
  - removed: card, hero slot, glyph app list, page list in `scripts/build-pages.py`, `sitemap.xml`;
  - repointed to Panes: Armonitor rendering for Panes's tile and card animation;
  - kept: copies of StatusItemKit sources under `art/glyphs/build/`, which `render-glyphs.sh` regenerates.
- [ ] **Step 2:** Rewrite Panes's card. Cover window shortcuts, the grid and snapping; display brightness (DDC), Dim and XDR; Night Shift; and the three icons plus the meters. The mascot is Armonitor.
- [ ] **Step 3:** Redirect `/daemons/monitor-lizard/` to `/daemons/panes/`, the way the site/Worker already redirects (look for existing redirects or `_redirects`). If none exists, add a 301 in the Worker for that path only.
- [ ] **Step 4:** Run `art/glyphs/render-glyphs.sh`. Check the strips, the hero bar and the anim frames: no lizard slot; Panes shows the grid in the bar and Armonitor on its tile. Run the site's IP-scrub check if captures changed.
- [ ] **Step 5:** Commit and push following the repo's flow, then `npm run deploy`. Fetch `https://menumon.nicksmith.software/daemons/monitor-lizard/`. Expected: a 301 to `/daemons/panes/`.

---

## Part G — nicksmith.software (`~/Code/nicksmith.software`)

### Task G1: Panes replaces Monitor Lizard

**Files:**
- Modify `src/data/projects.ts`.
- Modify `src/data/projects.test.ts`.
- Create `public/icons/panes-logo.png`, from Panes's new `AppIcon` tile, the same size and format as the other logos.
- Delete `public/icons/monitor-lizard-logo.png` (check the real path).
- Modify `src/generated/lqip.json`, regenerated by the repo's script.

- [ ] **Step 1:** Replace the entry in place, keeping its position. In `UTILITY_PROJECT_IDS`, replace `'monitor-lizard'` with `'panes'`.
  ```ts
  { id: 'panes', name: 'Panes',
    description: 'Windows and screens from one menu-bar icon: ⌥⌘ shortcuts, a layout grid and edge snapping for windows; DDC brightness and contrast for external monitors, the built-in panel from dimmer than macOS allows to an XDR boost, the brightness keys, and Night Shift on a sunset schedule. Armonitor the monitor lizard laps the screen when something changes.',
    technologies: ['Swift', 'AppKit', 'StatusItemKit', 'HotkeyKit', 'Accessibility API', 'DDC/CI', 'IOKit'],
    link: 'https://github.com/nicholaspsmith/panes-menubar', logo: '/icons/panes-logo.png' },
  ```
- [ ] **Step 2:** HotkeyKit's line: replace `Monitor Lizard` with `Panes`. The Menumon entry: fix the daemon count to the real number of Menumon apps after retirement (count them on the Menumon site).
- [ ] **Step 3:** Update `projects.test.ts` (`'monitor-lizard'` → `'panes'`), regenerate the LQIP, then run the repo's tests and build (`npm test`, `npm run build`, or what `package.json` names). Expected: pass.
- [ ] **Step 4:** Follow the repo's PR/deploy flow. Images must pass `scripts/qa/ip-scan.py`.

---

## Part H — Docs elsewhere

### Task H1: Sibling READMEs and setup suite

- [ ] **Step 1:** In each repo whose README lists Monitor Lizard, remove the row and widen Panes's description: apollo-monitor-menubar, battery-time-menubar, claude-usage-menubar, home-assistant-menubar, keylight-menubar, HotkeyKit, MacRecorder, mac-daddy-menubar, soundchain-menubar, vpn-dns-menubar, menu-crane (if listed). Commit each with `[no release]` in the message, then push and merge per repo.
  - Leave menubar-barn alone.
  - StatusItemKit is done in Part E.
- [ ] **Step 2:** In MacOS-Dev-Environment-Setup, remove Monitor Lizard from `setup_macos_dev.py` (the clone/install lists near lines 39, 759, 919 and 954), `docs/system-inventory.md` and the README. Run that repo's tests or lint if any. Commit it as that repo releases.
- [ ] **Step 3:** In `~/.claude/CLAUDE.md`:
  - "Twelve run as standalone" → "Eleven".
  - Remove the `Monitor Lizard.app` entry from the list.
  - Move the Monitor Lizard paragraphs (brightness keys, Dim + XDR, presets) under Panes, worded as Panes ≥ 1.0.0.
  - Add `Monitor Lizard: retired 2026-11 into Panes 1.0.0; private, archived, ~/Code-archive/monitor-lizard-menubar`.
  - In the minute-cue paragraph, Armonitor's lap is now Panes's (with the Armonitor icon).

### Task H2: Hand back to Nick

- [ ] **Step 1:** Rewrite HW# for the overlay:
  - XDR range of the slider and the keys;
  - across lid close, display sleep and plug/unplug;
  - off on battery;
  - the Touch ID prompt with the overlay up;
  - full-screen video;
  - Dim checks unchanged.
- [ ] **Step 2:** In the closing message, give Nick the HW# link, the ⌥⌘C 1000 pt eyeball on the built-in display, a visual QA of each icon option and the minute cue, and any issue left open with its numbers (#21 or #6).

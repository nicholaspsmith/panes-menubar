// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import HotkeyKit
import PanesCore
import PanesGlyph
import StatusItemKit

/// Panes — a keyboard and edge-snap window manager in the menu bar. Global
/// shortcuts (taken by a HotkeyKit tap before the front app sees them), a
/// 4×4 layout grid in the menu, and snapping a dragged window to the display
/// edges. Moves go through the Accessibility API and glide into place.
/// Above the grid, the displays (Monitor Lizard's, `DisplaysFeature`):
/// brightness, contrast, resolution, Night Shift, and the brightness keys,
/// which ride on the same tap as the window shortcuts.
final class App: NSObject, NSApplicationDelegate {
    private var status: StatusItemController!
    /// Steps this icon aside while a menu-bar manager reveals hidden items.
    private var yieldClient: YieldClient!
    private let model = BindingsModel()
    private let mover = WindowMover()
    private lazy var snapper = EdgeSnapper(mover: mover)
    private var tap: HotkeyTap!
    /// The displays, Night Shift and the brightness keys.
    private var displayFeature: DisplaysFeature!
    /// The open menu's grid and window actions, updated in place as items
    /// move the window (the menu stays open).
    private weak var menuGrid: GridMenuView?
    private var shortcutItems: [NSMenuItem] = []
    /// The Monitor Lizard cut-over, while it runs (launch only).
    private var cutover: MonitorLizardCutover?
    private let modifierTap = ModifierTap()
    /// The grid that covers the screen while ⌥⌘ is held.
    private let overlay = GridOverlay()
    private var holdGrid = HoldGrid()
    private var holdTimer: Timer?
    private var menuOpen = false

    private static let holdGridKey = "holdGrid"
    private var holdGridEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.holdGridKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.holdGridKey) }
    }
    private var prefs: PreferencesWindowController?
    private var trustTimer: Timer?
    private var pollCount = 0
    private var iconSignature: Int?
    /// Panes's turn in the minute cue: the windows slide into their tiles.
    private var minuteCue: MinuteCue!
    private var slide: IconAnimation?
    /// Major Pane, when he is the icon (Icon ▸ Major Pane).
    private var mascot: MascotController?
    /// The meter icons' shape and colour (StatusItemKit's `MeterStyle` and
    /// `MeterColorHex` keys). `iconChoice` says whether a meter shows at all.
    private let meterAppearance = MeterAppearance()
    /// StatusItemKit's colour presets and Custom Colour…, which Icon ▸ borrows.
    /// Kept: it is those items' target.
    private var colourMenu: AppearanceMenu!
    private static let knownMeters = Set(MeterStyle.proportional.map(\.rawValue))
    /// Icon ▸: Screen Grid (also when nothing or something unknown is saved),
    /// Major Pane, Armonitor or a meter. Read once at launch; each pick saves it.
    private var iconChoice = IconChoice(stored: UserDefaults.standard.string(forKey: IconChoice.key),
                                        knownMeters: App.knownMeters) {
        didSet { UserDefaults.standard.set(iconChoice.stored, forKey: IconChoice.key) }
    }
    private var mascotChosen: Bool { iconChoice == .majorPane }
    /// Armonitor and the meters show the main display's brightness, not windows.
    private var showsDisplayIcon: Bool {
        switch iconChoice {
        case .armonitor, .meter: return true
        case .grid, .majorPane: return false
        }
    }
    /// The window the open menu acts on, captured as it opens: the menu does
    /// not activate Panes, so the frontmost app is still the user's.
    private var menuTarget: AXWindow?

    private static let edgeSnappingKey = "edgeSnapping"
    private var edgeSnapping: Bool {
        get { UserDefaults.standard.object(forKey: Self.edgeSnappingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.edgeSnappingKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = StatusItemController(
            pollInterval: 1.5,
            onPoll: { [weak self] in self?.poll() },
            onBuildMenu: { [weak self] menu in self?.buildMenu(menu) }
        )
        status.start()
        yieldClient = YieldClient(item: status)
        yieldClient.start()
        // Before anything can refresh the icon (the Menu Crane 1.3.0 lesson).
        syncMeterStyle()
        colourMenu = AppearanceMenu(appearance: meterAppearance, styles: []) { [weak self] in self?.drawDisplayIcon() }
        let mascot = MascotController(status: status)
        mascot.enabled = mascotChosen
        mascot.start()
        self.mascot = mascot

        let displayFeature = DisplaysFeature(status: status)
        // The tongue, the laps and the brightness/Night Shift redraws act only
        // for the icons that show them.
        displayFeature.isArmonitorShown = { [weak self] in self?.iconChoice == .armonitor }
        displayFeature.onIconInputsChanged = { [weak self] in self?.drawDisplayIcon() }
        displayFeature.onBrightnessBindingsChanged = { [weak self] in self?.updateTapBindings() }
        self.displayFeature = displayFeature

        tap = HotkeyTap(bindings: tapBindings) { [weak self] token in self?.handle(token: token) ?? false }
        model.onChange = { [weak self] _ in self?.updateTapBindings() }
        mover.onMoved = { [weak self] in
            self?.refreshIcon(force: true)
            if self?.mascotChosen == true { self?.mascot?.bark() }
        }
        modifierTap.onModifiers = { [weak self] held in self?.holdModifiers(held) }
        modifierTap.onAnyKeyDown = { [weak self] in self?.holdKeyDown() }
        overlay.onPick = { [weak self] window, frame, visible in
            guard let self else { return }
            self.apply(self.holdGrid.dismissed())
            self.mover.move(window, to: frame, visible: visible)
        }
        status.onMenuWillOpen = { [weak self] in
            self?.menuOpen = true
            self?.holdKeyDown()
        }
        status.onMenuDidClose = { [weak self] in
            self?.menuOpen = false
            self?.displayFeature.refreshIcon()
        }

        if !tap.isTrusted { tap.requestTrust() }
        startIfTrusted()
        // Monitor Lizard may still be running (parity installs Panes over it):
        // quit it and bring its settings over before the displays feature, and
        // with it the brightness keys, starts.
        let cutover = MonitorLizardCutover()
        self.cutover = cutover
        cutover.run { [weak self] in
            self?.cutover = nil
            self?.startDisplays()
        }

        // Redraw the icon when windows are likely to have moved, besides the poll.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshIcon() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.refreshIcon(force: true) }
        refreshIcon(force: true)
        minuteCue = MinuteCue { [weak self] in self?.minuteCueFired() }
        minuteCue.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // No XDR table or dim overlay may outlive the app.
        displayFeature?.stop()
    }

    /// Starts the displays feature: DDC, Night Shift and its schedule, XDR and
    /// Dim. The one place it starts, run when the Monitor Lizard cut-over is done.
    private func startDisplays() {
        reloadIconChoice()
        displayFeature.start()
        // The brightness keys join the tap only now (none before `start()`).
        updateTapBindings()
        // start() doesn't report its first reading; draw from it now.
        displayFeature.refreshIcon()
    }

    /// The migration may have brought Monitor Lizard's meter over as `IconStyle`.
    private func reloadIconChoice() {
        guard let stored = UserDefaults.standard.string(forKey: IconChoice.key),
              stored != iconChoice.stored else { return }
        iconChoice = IconChoice(stored: stored, knownMeters: Self.knownMeters)
        syncMeterStyle()
        slide?.cancel(); slide = nil
        mascot?.enabled = mascotChosen
        refreshIcon(force: true)
    }

    // MARK: - Tap lifecycle

    /// The one tap's bindings: the window shortcuts first (first match wins),
    /// then the brightness keys (none while they are off).
    private var tapBindings: [Binding] { model.tapBindings + displayFeature.brightnessBindings }

    /// Every change to either set goes through here, so neither drops the other.
    private func updateTapBindings() {
        tap?.setBindings(tapBindings)
    }

    private func startIfTrusted() {
        // Gate on trust, not on start()'s return: an untrusted process can get
        // an inert tap that granting permission later won't wake.
        guard tap.isTrusted else {
            scheduleTrustRecheck()
            return
        }
        if !tap.isRunning { tap.start() }
        if !modifierTap.isRunning { modifierTap.start() }
        if edgeSnapping { snapper.start() }
        trustTimer?.invalidate()
        trustTimer = nil
        refreshIcon(force: true)
    }

    private func scheduleTrustRecheck() {
        guard trustTimer == nil else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.tap.isTrusted else { return }
            self.startIfTrusted()
        }
    }

    private func poll() {
        refreshIcon()
        pollCount += 1
        // Every 60 s: the displays' safety net for a missed change notification.
        if pollCount % 40 == 0 { displayFeature.safetyPoll() }
        // Every ~6 s, re-create the tap so it stays at the head of the session
        // taps (another app's tap inserted later would see our keys first).
        // The brightness keys ride on it, so this keeps them frontmost too.
        if pollCount % 4 == 0, let tap, tap.isTrusted, tap.isRunning {
            tap.stop()
            tap.start()
            modifierTap.stop()
            modifierTap.start()
        }
    }

    // MARK: - Grid on hold ⌥⌘

    private func holdModifiers(_ held: Modifiers) {
        guard holdGridEnabled, !model.isRecording else { return }
        holdGrid.delay = model.holdDelay
        apply(holdGrid.modifiers(held, at: CACurrentMediaTime(), mouseDown: NSEvent.pressedMouseButtons != 0))
    }

    private func holdKeyDown() {
        apply(holdGrid.keyDown())
    }

    private func apply(_ effect: HoldGrid.Effect) {
        switch effect {
        case .none:
            break
        case .arm(let at):
            holdTimer?.invalidate()
            let t = Timer(timeInterval: max(0, at - CACurrentMediaTime()), repeats: false) { [weak self] _ in
                guard let self else { return }
                let canShow = self.trusted && !self.menuOpen && AXWindow.focused() != nil
                self.apply(self.holdGrid.tick(at: CACurrentMediaTime(),
                                              mouseDown: NSEvent.pressedMouseButtons != 0, canShow: canShow))
            }
            RunLoop.main.add(t, forMode: .common)
            holdTimer = t
        case .show:
            if !overlay.show(fine: holdGrid.phase.isFine) { _ = holdGrid.dismissed() }
        case .hide:
            holdTimer?.invalidate()
            overlay.hide()
        case .setFine(let fine):
            overlay.setFine(fine)
        }
    }

    // MARK: - Shortcuts

    /// Brightness keys go to the displays; window shortcuts to `handleWindow`.
    private func handle(token: String) -> Bool {
        if displayFeature.isBrightnessToken(token) { return displayFeature.handleBrightness(token: token) }
        return handleWindow(token: token)
    }

    /// Swallow the key only when there is a window to act on and the action
    /// applies to it; otherwise the front app gets the key as usual.
    private func handleWindow(token: String) -> Bool {
        // The shortcut tap may see a key before the chord tap does.
        holdKeyDown()
        guard !model.isRecording, let action = WindowAction(rawValue: token),
              let window = AXWindow.focused(), mover.canPerform(action, on: window) else { return false }
        // Return to the tap at once; move on the next run-loop turn.
        DispatchQueue.main.async { [mover] in mover.perform(action, on: window) }
        return true
    }

    // MARK: - Icon

    private var trusted: Bool { tap?.isTrusted ?? false }

    /// The display the icon draws: the one this status item sits on.
    private func iconModel() -> ScreenGridIcon.Model {
        let screen = status?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let displays = Screens.displays
        let frame = screen.map { Coordinates.flip($0.frame, primaryHeight: Screens.primaryHeight) }
            ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
        let index = displays.firstIndex { $0.frame == frame } ?? 0
        let windows = WindowMap.windows(WindowList.appWindows().map(\.bounds), on: index, of: displays)
        return ScreenGridIcon.Model(display: frame, windows: windows, active: trusted)
    }

    /// The pane's lit cells: those the frontmost app's front window covers, and
    /// only when that window is on the icon's display; a front window on another
    /// display lights nothing rather than the wrong cells.
    private func frontCells(on display: CGRect) -> Set<GridCell> {
        let displays = Screens.displays
        guard let index = displays.firstIndex(where: { $0.frame == display }),
              let front = PaneCells.frontWindow(of: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                                in: WindowList.appWindows()),
              displays.index(for: front) == index else { return [] }
        return PaneCells.lit(front: front, visible: displays[index].visibleFrame)
    }

    /// The once-a-minute animation: the display's windows, as they are now,
    /// bunch up and slide out into their tiles. Nothing to slide on an empty
    /// display, and the poll leaves the icon alone until the slide is done.
    private func slideTiles() {
        guard let status, slide?.isRunning != true else { return }
        let m = iconModel()
        guard !m.windows.isEmpty else { return }
        let anim = IconAnimation(duration: ScreenGridIcon.tileDuration, frame: { t in
            status.setIcon(ScreenGridIcon.image(m, tiling: t))
        }, completion: { [weak self] in self?.refreshIcon(force: true) })
        slide = anim
        anim.start()
    }

    /// Panes's slot in the Menumon minute cue: whichever icon shows does its
    /// thing. The grid's tiles slide, Major Pane salutes, Armonitor laps his
    /// monitor; a meter has nothing to do.
    private func minuteCueFired() {
        switch iconChoice {
        case .grid: slideTiles()
        case .majorPane: mascot?.salute()
        case .armonitor: displayFeature.runIconLap()
        case .meter: break
        }
    }

    /// Armonitor and the meters redraw from the displays (`drawDisplayIcon`),
    /// not from the window poll: only a forced refresh draws them here.
    private func refreshIcon(force: Bool = false) {
        guard let status, slide?.isRunning != true else { return }
        if showsDisplayIcon {
            if force { drawDisplayIcon() }
            return
        }
        let m = iconModel()
        var sig = Hasher()
        sig.combine(WindowMap.signature(m.windows + [m.display]))
        sig.combine(m.active)
        sig.combine(iconChoice.stored)
        let s = sig.finalize()
        guard force || s != iconSignature else { return }
        iconSignature = s
        if mascotChosen {
            mascot?.show(active: m.active, lit: frontCells(on: m.display))
        } else {
            status.setIcon(ScreenGridIcon.image(m))
        }
    }

    /// Armonitor or the chosen meter, from the brightness and Night Shift the
    /// displays last read. No window map and no display query, so it suits
    /// the lap and tongue frames (about 60 a second). Nothing for the grid or
    /// Major Pane: brightness and Night Shift don't change them.
    private func drawDisplayIcon() {
        guard let status, let d = displayFeature else { return }
        let fraction = CGFloat(d.mainBrightnessFraction)
        switch iconChoice {
        case .armonitor:
            status.setIcon(CharacterIcon.monitorLizard(brightness: fraction, nightShift: d.nightShiftOn,
                                                       tongue: d.tongueActive, lizard: !d.isScreenLapRunning,
                                                       lap: d.iconLapProgress))
        case .meter:
            status.setIcon(meterAppearance.image(fraction: fraction))
        case .grid, .majorPane:
            break
        }
    }

    /// `MeterAppearance` draws the shape under its own `MeterStyle` key;
    /// `IconStyle` is the one that says which meter shows. Keep the two in step.
    private func syncMeterStyle() {
        guard case .meter(let raw) = iconChoice, let style = MeterStyle(rawValue: raw),
              meterAppearance.style != style else { return }
        meterAppearance.style = style
    }

    // MARK: - Menu

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        // Items are enabled by whether the action applies, not by AppKit's
        // validation (which would enable every item with a target).
        menu.autoenablesItems = false
        menuTarget = trusted ? AXWindow.focused() : nil

        displayFeature.addMenuSection(to: menu)
        menu.addItem(.separator())

        let gridItem = NSMenuItem()
        let grid = makeGrid()
        menuGrid = grid
        gridItem.view = grid
        menu.addItem(gridItem)
        menu.addItem(.separator())

        // The actions fold under one Shortcuts row, folded each time the
        // menu opens.
        shortcutItems = makeShortcutItems()
        MenuSection.add(title: "Shortcuts", items: shortcutItems, to: menu)

        if !trusted {
            menu.addItem(.separator())
            menu.addItem(actionItem("⚠ Grant Accessibility…", #selector(grantTrust)))
        } else if menuTarget == nil {
            menu.addItem(.separator())
            let none = NSMenuItem(title: "No window to arrange", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        if edgeSnapping, SystemTiling.isEdgeTilingOn(edge: Self.windowManagerDefault(SystemTiling.edgeKey),
                                                     top: Self.windowManagerDefault(SystemTiling.topKey)) {
            let warn = actionItem("⚠ macOS Edge Tiling Is On…", #selector(openDesktopSettings))
            warn.toolTip = "macOS also tiles windows dragged to the edges, and the two fight. "
                + "Turn off \"Drag windows to screen edges to tile\" and \"Drag windows to menu bar to fill screen\" "
                + "in Desktop & Dock, or turn off Edge Snapping here."
            menu.addItem(warn)
        }

        SettingsMenu.addFooter(to: menu, appName: "Panes", items: { sub in
            // Checkboxes keep the menu open (StatusItemKit's ToggleMenuItem).
            sub.addItem(ToggleMenuItem.make(
                title: "Edge Snapping", isOn: self.edgeSnapping,
                toolTip: "Drag a window to a display edge or corner to snap it there"
            ) { [weak self] on in self?.setEdgeSnapping(on) })
            sub.addItem(ToggleMenuItem.make(
                title: "Grid on Hold ⌥⌘", isOn: self.holdGridEnabled,
                toolTip: "Hold ⌥⌘ on its own and a grid covers the screen; click or drag across cells"
            ) { [weak self] on in self?.setHoldGrid(on) })
            for item in self.displayFeature.settingsItems() { sub.addItem(item) }
            sub.addItem(self.actionItem("Preferences…", #selector(self.openPrefs), key: ","))
        }, belowSettings: { menu in
            // Icon sits in the main menu, right below Settings.
            let icon = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
            icon.submenu = self.makeIconMenu()
            menu.addItem(icon)
        })
        // Every item but Quit and the "…" ones keeps the menu open.
        KeepOpen.apply(to: menu.items)
    }

    /// After a kept-open item or a grid cell moved the window: shade where it
    /// is going and re-check which actions apply (Restore now does).
    private func refreshOpenMenu() {
        guard let target = menuTarget else { return }
        menuGrid?.setActiveFrame(mover.currentFrame(target))
        for item in shortcutItems {
            guard let raw = item.representedObject as? String, let action = WindowAction(rawValue: raw) else { continue }
            item.isEnabled = mover.canPerform(action, on: target)
            (item.view as? MenuRowView)?.updateColors()
            item.view?.needsDisplay = true
        }
    }

    /// The window actions in their four groups (halves, quarters, maximize /
    /// center / restore, next display), each group opened by a separator, so
    /// the first also sits apart from the Shortcuts row above it.
    private func makeShortcutItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        var group: Int?
        for action in WindowAction.allCases {
            if action.group != group { items.append(.separator()); group = action.group }
            let item = NSMenuItem(title: action.label, action: #selector(performAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            if let trigger = model.trigger(for: action), let key = MenuKeyEquivalent.string(for: trigger) {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = Self.flags(trigger.modifiers)
            }
            item.isEnabled = menuTarget.map { mover.canPerform(action, on: $0) } ?? false
            items.append(item)
        }
        return items
    }

    /// Screen Grid, Major Pane, Armonitor; Monitor Lizard's meter shapes;
    /// then StatusItemKit's colour presets and Custom Colour… for the meters.
    private func makeIconMenu() -> NSMenu {
        let pick = NSMenu()
        let choices: [(String, IconChoice)] = [("Screen Grid", .grid), ("Major Pane", .majorPane), ("Armonitor", .armonitor)]
        let meters = MeterStyle.proportional.map { ($0.title, IconChoice.meter($0.rawValue)) }
        for (i, (title, choice)) in (choices + meters).enumerated() {
            if i == choices.count { pick.addItem(.separator()) }
            let item = actionItem(title, #selector(chooseIcon(_:)))
            item.representedObject = choice.stored
            item.state = iconChoice == choice ? .on : .off
            pick.addItem(item)
        }
        // AppearanceMenu with no shapes builds just a separator, the presets
        // and Custom Colour…; move them over (an item lives in one menu only).
        if let colours = colourMenu.menuItem().submenu {
            for item in colours.items {
                colours.removeItem(item)
                pick.addItem(item)
            }
        }
        return pick
    }

    private func makeGrid() -> GridMenuView {
        let displays = Screens.displays
        let targetFrame = menuTarget?.frame
        let frontFrame = targetFrame ?? WindowList.appWindows().first?.bounds
        let di = frontFrame.flatMap { displays.index(for: $0) }
            ?? displays.index(containing: Screens.cursor) ?? 0
        let visible = displays.isEmpty ? CGRect(x: 0, y: 0, width: 1512, height: 945) : displays[di].visibleFrame

        let windows = displays.isEmpty ? [] : WindowMap.windows(WindowList.appWindows().map(\.bounds), on: di, of: displays)
        let clippedTarget = targetFrame.flatMap { displays.isEmpty ? nil : $0.intersection(displays[di].frame) }
        let model = GridMenuView.Model(visible: visible, activeFrame: targetFrame,
                                       otherFrames: windows.filter { $0 != clippedTarget },
                                       enabled: menuTarget != nil)
        return GridMenuView(model: model) { [weak self] grid, selection in
            guard let self, let target = self.menuTarget else { return }
            self.mover.move(target, to: grid.frame(for: selection, in: visible), visible: visible)
            self.refreshOpenMenu()
        }
    }

    private static func windowManagerDefault(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, SystemTiling.domain as CFString)
    }

    private static func flags(_ m: Modifiers) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if m.contains(.command) { f.insert(.command) }
        if m.contains(.option) { f.insert(.option) }
        if m.contains(.control) { f.insert(.control) }
        if m.contains(.shift) { f.insert(.shift) }
        return f
    }

    private func actionItem(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Menu selectors

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = WindowAction(rawValue: raw),
              let target = menuTarget else { return }
        mover.perform(action, on: target)
        refreshOpenMenu()
    }

    @objc private func grantTrust() {
        tap.requestTrust()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        startIfTrusted()
    }

    @objc private func openDesktopSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
    }

    private func setEdgeSnapping(_ on: Bool) {
        edgeSnapping = on
        if edgeSnapping, trusted { snapper.start() } else { snapper.stop() }
    }

    private func setHoldGrid(_ on: Bool) {
        holdGridEnabled = on
        if !holdGridEnabled { apply(holdGrid.dismissed()) }
    }

    @objc private func chooseIcon(_ sender: NSMenuItem) {
        iconChoice = IconChoice(stored: sender.representedObject as? String, knownMeters: Self.knownMeters)
        syncMeterStyle()
        slide?.cancel(); slide = nil
        if iconChoice != .armonitor { displayFeature.cancelIconLap() }
        mascot?.enabled = mascotChosen
        refreshIcon(force: true)        // draws the chosen icon from how things are now
    }

    @objc private func openPrefs() {
        if prefs == nil { prefs = PreferencesWindowController(model: model) }
        prefs?.show()
    }
}

// MARK: - Entry point

// `--login on|off|status` acts and exits before any UI exists (SMAppService can
// only register the calling process's own bundle).
LoginCLI.runIfRequested()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()

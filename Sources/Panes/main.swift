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
final class App: NSObject, NSApplicationDelegate {
    private var status: StatusItemController!
    /// Steps this icon aside while a menu-bar manager reveals hidden items.
    private var yieldClient: YieldClient!
    private let model = BindingsModel()
    private let mover = WindowMover()
    private lazy var snapper = EdgeSnapper(mover: mover)
    private var tap: HotkeyTap!
    private let chordTap = ChordTap()
    private var prefs: PreferencesWindowController?
    private var trustTimer: Timer?
    private var pollCount = 0
    private var iconSignature: Int?
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

        tap = HotkeyTap(bindings: model.tapBindings) { [weak self] token in self?.handle(token: token) ?? false }
        model.onChange = { [weak self] bindings in self?.tap.setBindings(bindings) }
        mover.onMoved = { [weak self] in self?.refreshIcon(force: true) }
        chordTap.chord = model.chordModifier
        model.onChordChange = { [weak self] chord in self?.chordTap.chord = chord }
        chordTap.reservedKeys = { [weak self] chord in
            ChordLogic.reservedKeys(self?.model.bindings ?? [], chord: chord)
        }
        chordTap.isSuspended = { [weak self] in self?.model.isRecording ?? false }
        chordTap.onFinish = { [mover] window, selection, display in
            mover.move(window, to: LayoutGrid().frame(for: selection, in: display.visibleFrame),
                       visible: display.visibleFrame)
        }

        if !tap.isTrusted { tap.requestTrust() }
        startIfTrusted()

        // Redraw the icon when windows are likely to have moved, besides the poll.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshIcon() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.refreshIcon(force: true) }
        refreshIcon(force: true)
    }

    // MARK: - Tap lifecycle

    private func startIfTrusted() {
        // Gate on trust, not on start()'s return: an untrusted process can get
        // an inert tap that granting permission later won't wake.
        guard tap.isTrusted else {
            scheduleTrustRecheck()
            return
        }
        if !tap.isRunning { tap.start() }
        if !chordTap.isRunning { chordTap.start() }
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
        // Every ~6 s, re-create the tap so it stays at the head of the session
        // taps (another app's tap inserted later would see our keys first).
        pollCount += 1
        if pollCount % 4 == 0, let tap, tap.isTrusted, tap.isRunning {
            tap.stop()
            tap.start()
            if !chordTap.isBusy {
                chordTap.stop()
                chordTap.start()
            }
        }
    }

    // MARK: - Shortcuts

    /// Swallow the key only when there is a window to act on and the action
    /// applies to it; otherwise the front app gets the key as usual.
    private func handle(token: String) -> Bool {
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

    private func refreshIcon(force: Bool = false) {
        guard let status else { return }
        let m = iconModel()
        var sig = Hasher()
        sig.combine(WindowMap.signature(m.windows + [m.display]))
        sig.combine(m.active)
        let s = sig.finalize()
        guard force || s != iconSignature else { return }
        iconSignature = s
        status.setIcon(ScreenGridIcon.image(m))
    }

    // MARK: - Menu

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        // Items are enabled by whether the action applies, not by AppKit's
        // validation (which would enable every item with a target).
        menu.autoenablesItems = false
        menuTarget = trusted ? AXWindow.focused() : nil

        let gridItem = NSMenuItem()
        gridItem.view = makeGrid()
        menu.addItem(gridItem)
        menu.addItem(.separator())

        var group = WindowAction.allCases.first!.group
        for action in WindowAction.allCases {
            if action.group != group { menu.addItem(.separator()); group = action.group }
            let item = NSMenuItem(title: action.label, action: #selector(performAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            if let trigger = model.trigger(for: action), let key = MenuKeyEquivalent.string(for: trigger) {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = Self.flags(trigger.modifiers)
            }
            item.isEnabled = menuTarget.map { mover.canPerform(action, on: $0) } ?? false
            menu.addItem(item)
        }

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
            let snap = self.actionItem("Edge Snapping", #selector(self.toggleEdgeSnapping))
            snap.state = self.edgeSnapping ? .on : .off
            snap.toolTip = "Drag a window to a display edge or corner to snap it there"
            sub.addItem(snap)
            sub.addItem(self.actionItem("Preferences…", #selector(self.openPrefs), key: ","))
        })
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
    }

    @objc private func grantTrust() {
        tap.requestTrust()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        startIfTrusted()
    }

    @objc private func openDesktopSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
    }

    @objc private func toggleEdgeSnapping() {
        edgeSnapping.toggle()
        if edgeSnapping, trusted { snapper.start() } else { snapper.stop() }
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

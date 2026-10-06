// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore

/// The grid shown while ⌥⌘ is held: a dark, nearly opaque panel covering
/// exactly the target display's visible frame (the menu bar and Dock stay
/// uncovered), so each cell sits over the very area a window filling it
/// would take. Click or drag across cells as in the menu.
///
/// A non-activating panel above everything: the user's app keeps focus (and
/// so stays the window Panes acts on) while the panel takes the clicks.
final class GridOverlay {
    private var panel: NSPanel?
    private var view: GridView?
    /// Called with the target window and the frame picked.
    var onPick: (AXWindow, CGRect, CGRect) -> Void = { _, _, _ in }
    private var target: AXWindow?
    private var visible: CGRect = .zero

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Fade in over the display of `window`. Returns false when there is no
    /// window to arrange (nothing is shown).
    @discardableResult
    func show(fine: Bool) -> Bool {
        guard let window = AXWindow.focused(), let frame = window.frame else { return false }
        let displays = Screens.displays
        guard let di = displays.index(for: frame) else { return false }
        let d = displays[di]
        target = window
        visible = d.visibleFrame

        let windows = WindowMap.windows(WindowList.appWindows().map(\.bounds), on: di, of: displays)
        let clipped = frame.intersection(d.frame)
        let model = GridView.Model(visible: d.visibleFrame, activeFrame: frame,
                                   otherFrames: windows.filter { $0 != clipped }, enabled: true)
        let cocoa = Screens.cocoa(d.visibleFrame)
        let p = panel ?? makePanel()
        p.setFrame(cocoa, display: false)
        let v = GridView(frame: NSRect(origin: .zero, size: cocoa.size), model: model, style: .overlay) { [weak self] grid, sel in
            guard let self, let target = self.target else { return }
            self.onPick(target, grid.frame(for: sel, in: self.visible), self.visible)
        }
        v.setFine(fine)
        let effect = p.contentView!
        effect.subviews.forEach { $0.removeFromSuperview() }
        let dim = NSView(frame: effect.bounds)
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor(white: 0, alpha: 0.07).cgColor
        dim.autoresizingMask = [.width, .height]
        effect.addSubview(dim)
        v.frame = effect.bounds.insetBy(dx: 0, dy: 0)
        v.autoresizingMask = [.width, .height]
        effect.addSubview(v)
        view = v

        p.alphaValue = 0
        p.orderFrontRegardless()
        fade(p, to: 1, duration: 0.12)
        return true
    }

    func setFine(_ fine: Bool) { view?.setFine(fine) }

    func hide(duration: TimeInterval = 0.1) {
        guard let p = panel, p.isVisible else { return }
        view?.cancelSelection()
        target = nil
        fade(p, to: 0, duration: duration) { [weak p] in
            if p?.alphaValue == 0 { p?.orderOut(nil) }
        }
    }

    var windowNumber: Int? { panel?.windowNumber }

    private func fade(_ p: NSPanel, to alpha: CGFloat, duration: TimeInterval, done: (() -> Void)? = nil) {
        let d = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = d
            p.animator().alphaValue = alpha
        }, completionHandler: done)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.ignoresMouseEvents = false
        p.acceptsMouseMovedEvents = true
        // Clear, not frosted: the screen shows through, with only a faint
        // tint and the grid on top.
        let backdrop = NSView()
        backdrop.wantsLayer = true
        p.contentView = backdrop
        panel = p
        return p
    }
}

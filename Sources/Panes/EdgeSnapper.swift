// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore

/// Drag a window by its title bar to a display edge or corner: a translucent
/// preview shows where it will go, and letting go there snaps it. Moving away
/// from the edge before letting go cancels.
///
/// Watches the mouse with global monitors (which need no permission for
/// mouse events), and the dragged window through Accessibility. A drag counts
/// as a window move once the window under the press has moved without
/// changing size, which tells a title-bar drag from a resize, a text
/// selection or a drag inside the window's content.
final class EdgeSnapper {
    private let mover: WindowMover
    private var monitors: [Any] = []
    private let overlay = SnapOverlay()

    private enum State {
        case idle
        /// Pressed on a window; not yet known to be moving it.
        case pressed(AXWindow, CGRect, lastCheck: CFTimeInterval)
        case moving(AXWindow)
    }
    private var state = State.idle
    private var hit: SnapZone.Hit?

    init(mover: WindowMover) { self.mover = mover }

    var isEnabled: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let events: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = [
            (.leftMouseDown, { [weak self] _ in self?.mouseDown() }),
            (.leftMouseDragged, { [weak self] _ in self?.mouseDragged() }),
            (.leftMouseUp, { [weak self] _ in self?.mouseUp() }),
        ]
        for (mask, handler) in events {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { monitors.append(m) }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
    }

    private func reset() {
        state = .idle
        hit = nil
        overlay.hide()
    }

    private func mouseDown() {
        reset()
        guard AXIsProcessTrusted(), let window = AXWindow.at(Screens.cursor), let frame = window.frame else { return }
        state = .pressed(window, frame, lastCheck: 0)
    }

    private func mouseDragged() {
        switch state {
        case .idle:
            return
        case let .pressed(window, start, lastCheck):
            // One AX read per 40 ms at most while deciding.
            let now = CACurrentMediaTime()
            guard now - lastCheck > 0.04 else { return }
            guard let frame = window.frame else { reset(); return }
            if frame.size != start.size {
                state = .idle          // a resize, not a move
            } else if frame.origin != start.origin {
                state = .moving(window)
                track()
            } else {
                state = .pressed(window, start, lastCheck: now)
            }
        case .moving:
            track()
        }
    }

    private func track() {
        let displays = Screens.displays
        let newHit = SnapZone.detect(cursor: Screens.cursor, displays: displays)
        guard newHit != hit else { return }
        hit = newHit
        if let newHit, let frame = target(for: newHit, displays: displays) {
            overlay.show(axFrame: frame)
        } else {
            overlay.hide()
        }
    }

    private func target(for hit: SnapZone.Hit, displays: [Display]) -> CGRect? {
        guard displays.indices.contains(hit.displayIndex) else { return nil }
        return FrameCalculator.frame(for: hit.action, window: .zero, visible: displays[hit.displayIndex].visibleFrame)
    }

    private func mouseUp() {
        defer { reset() }
        guard case let .moving(window) = state, let hit else { return }
        let displays = Screens.displays
        guard let frame = target(for: hit, displays: displays) else { return }
        // Let the app finish its own drag before we set the frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [mover] in
            mover.move(window, to: frame, visible: displays[hit.displayIndex].visibleFrame)
        }
    }
}

/// The translucent preview of where a dragged window will snap: a rounded,
/// accent-tinted panel that ignores the mouse, above normal windows.
final class SnapOverlay {
    private var window: NSWindow?

    func show(axFrame: CGRect) {
        let frame = Screens.cocoa(axFrame).insetBy(dx: 6, dy: 6)
        let w = window ?? make()
        w.setFrame(frame, display: true)
        if !w.isVisible {
            w.alphaValue = 0
            w.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            w.animator().alphaValue = 1
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func make() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        w.isReleasedWhenClosed = false
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 2
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        tint.autoresizingMask = [.width, .height]
        view.addSubview(tint)
        w.contentView = view
        window = w
        return w
    }
}

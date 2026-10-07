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
/// changing size and has followed the pointer, which tells a title-bar drag
/// from a resize, a text selection, a drag inside the window's content, or
/// windows being put back by Mission Control / App Exposé (they slide
/// without following the pointer). The Dock keeps a window over the whole
/// screen, so "pressed on a Dock window" can't be used to spot Exposé.
final class EdgeSnapper {
    private let mover: WindowMover
    private var monitors: [Any] = []
    private let overlay = SnapOverlay()

    private enum State {
        case idle
        /// Pressed on a window; not yet known to be moving it.
        case pressed(AXWindow, CGRect, cursor: CGPoint, lastCheck: CFTimeInterval)
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
        let cursor = Screens.cursor
        guard AXIsProcessTrusted(), let window = AXWindow.at(cursor), let frame = window.frame else { return }
        state = .pressed(window, frame, cursor: cursor, lastCheck: 0)
    }

    private func mouseDragged() {
        switch state {
        case .idle:
            return
        case let .pressed(window, start, startCursor, lastCheck):
            // One AX read per 40 ms at most while deciding.
            let now = CACurrentMediaTime()
            guard now - lastCheck > 0.04 else { return }
            guard let frame = window.frame else { reset(); return }
            if frame.size != start.size {
                state = .idle          // a resize, not a move
            } else if frame.origin != start.origin {
                // A real title-bar drag moves the window with the pointer;
                // anything else moving it (Mission Control putting windows
                // back, an app repositioning itself) is not ours to snap.
                let cursor = Screens.cursor
                let moved = CGPoint(x: frame.minX - start.minX, y: frame.minY - start.minY)
                let dragged = CGPoint(x: cursor.x - startCursor.x, y: cursor.y - startCursor.y)
                if abs(moved.x - dragged.x) <= 40 && abs(moved.y - dragged.y) <= 40 {
                    log.notice("edge snap: drag started (window moved \(moved.x, privacy: .public),\(moved.y, privacy: .public); pointer \(dragged.x, privacy: .public),\(dragged.y, privacy: .public))")
                    state = .moving(window)
                    track()
                } else {
                    // Not yet: early in a real drag the window lags the
                    // pointer, so look again on the next event. Windows put
                    // back by Mission Control never line up with the pointer
                    // and so never get here.
                    state = .pressed(window, start, cursor: startCursor, lastCheck: now)
                }
            } else {
                state = .pressed(window, start, cursor: startCursor, lastCheck: now)
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

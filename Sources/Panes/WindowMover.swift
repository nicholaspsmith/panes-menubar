// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore
import os

let log = Logger(subsystem: "com.nicholaspsmith.Panes", category: "windows")

/// Performs actions on windows: works out the target frame, remembers the
/// old one for Restore, and glides the window there.
final class WindowMover {
    private var history = RestoreHistory<WindowKey>()
    /// The frame Panes last gave each window, so Center can tell a second
    /// press (grow) from a first one (just centre).
    private var lastPlaced: [WindowKey: CGRect] = [:]
    /// Where the last Center press left each window, so a repeated press
    /// steps its size up or down.
    private var lastCentered: [WindowKey: CenterGrow.State] = [:]
    private var running: [WindowKey: Glide] = [:]
    /// Seconds one position+size set took, per app, smoothed. Drives
    /// `AnimationPacing` so a slow app gets fewer steps instead of a stutter.
    private var setCost: [pid_t: TimeInterval] = [:]

    /// Called after every finished move (the icon redraws).
    var onMoved: (() -> Void)?

    // MARK: Questions

    /// Whether `action` would do anything for `window` — the key tap swallows
    /// a shortcut only when this is true.
    func canPerform(_ action: WindowAction, on window: AXWindow) -> Bool {
        switch action {
        case .restore: return history.canRestore(window.key)
        case .nextDisplay: return Screens.displays.count > 1
        default: return true
        }
    }

    // MARK: Actions

    @discardableResult
    func perform(_ action: WindowAction, on window: AXWindow) -> Bool {
        log.notice("perform \(action.rawValue, privacy: .public)")
        guard let current = currentFrame(window) else { return false }
        let displays = Screens.displays
        guard let di = displays.index(for: current) else { return false }

        switch action {
        case .restore:
            guard let previous = history.pop(for: window.key) else { return false }
            let vi = displays.index(for: previous) ?? di
            lastPlaced[window.key] = previous
            glide(window, from: current, to: previous, visible: displays[vi].visibleFrame)
            return true
        case .center:
            let v = displays[di].visibleFrame
            let state = CenterGrow.next(window: current, visible: v, last: lastCentered[window.key])
            if lastCentered.count > 200 { lastCentered.removeAll() }
            lastCentered[window.key] = state
            return move(window, from: current, to: state.frame, visible: v)
        case .nextDisplay:
            guard let ni = displays.next(after: di) else { return false }
            let target = FrameCalculator.moved(current, from: displays[di].visibleFrame, to: displays[ni].visibleFrame)
            return move(window, from: current, to: target, visible: displays[ni].visibleFrame)
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf:
            // Arrows combine like Windows 11's: ← then ↑ is the top-left quarter.
            let v = displays[di].visibleFrame
            guard let target = ArrowTiling.frame(for: action, window: current, visible: v) else { return false }
            return move(window, from: current, to: target, visible: v)
        default:
            guard let target = FrameCalculator.frame(for: action, window: current, visible: displays[di].visibleFrame)
            else { return false }
            return move(window, from: current, to: target, visible: displays[di].visibleFrame)
        }
    }

    /// Move to an explicit frame (the grid, an edge snap), remembering the old
    /// one for Restore.
    @discardableResult
    func move(_ window: AXWindow, from current: CGRect? = nil, to target: CGRect, visible: CGRect,
              caller: String = #fileID, line: Int = #line) -> Bool {
        guard let current = current ?? currentFrame(window) else { return false }
        // Every move is logged with where it came from, so an unexpected one
        // can be traced: log show --predicate 'subsystem == "com.nicholaspsmith.Panes"'
        log.notice("move from \(caller, privacy: .public):\(line, privacy: .public) \(String(describing: current), privacy: .public) -> \(String(describing: target), privacy: .public)")
        var target = target
        // A window that cannot be resized keeps its size, placed against the
        // same edges the target hugs.
        if !window.isResizable {
            let placed = CGRect(origin: target.origin, size: current.size)
            let origin = FrameFitter.nudgedOrigin(target: target, actual: placed, visible: visible) ?? target.origin
            target = CGRect(origin: origin, size: current.size)
        }
        if lastPlaced.count > 200 { lastPlaced.removeAll() }
        lastPlaced[window.key] = target
        guard target != current else { return true }
        history.record(current, for: window.key)
        glide(window, from: current, to: target, visible: visible)
        return true
    }

    /// Where the window is — or, mid-glide, where it is going, so a second
    /// press during a glide computes from (and Restore returns to) the
    /// settled frame rather than a frame halfway there.
    private func currentFrame(_ window: AXWindow) -> CGRect? {
        if let glide = running[window.key] { return glide.animation.to }
        return window.frame
    }

    // MARK: Animation

    private final class Glide {
        let window: AXWindow
        let animation: FrameAnimation
        let visible: CGRect
        let start = CACurrentMediaTime()
        var timer: Timer?
        var restoreEnhancedUI: () -> Void = {}
        init(window: AXWindow, animation: FrameAnimation, visible: CGRect) {
            self.window = window
            self.animation = animation
            self.visible = visible
        }
    }

    private func glide(_ window: AXWindow, from: CGRect, to: CGRect, visible: CGRect) {
        let key = window.key
        running[key]?.timer?.invalidate()
        running[key]?.restoreEnhancedUI()
        running[key] = nil

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let step = AnimationPacing.stepInterval(setCost: setCost[window.pid], reduceMotion: reduceMotion)
        let g = Glide(window: window, animation: FrameAnimation(from: from, to: to), visible: visible)
        g.restoreEnhancedUI = window.withEnhancedUIOff {}

        guard let step else {
            finish(g)
            return
        }
        running[key] = g
        let timer = Timer(timeInterval: step, repeats: true) { [weak self, weak g] _ in
            guard let self, let g else { return }
            let elapsed = CACurrentMediaTime() - g.start
            if g.animation.isFinished(at: elapsed) {
                g.timer?.invalidate()
                self.running[key] = nil
                self.finish(g)
                return
            }
            let f = g.animation.frame(at: elapsed)
            let t0 = CACurrentMediaTime()
            g.window.setPosition(f.origin)
            g.window.setSize(f.size)
            self.measure(g.window.pid, CACurrentMediaTime() - t0)
        }
        g.timer = timer
        // Common modes: keep gliding while a menu is tracking.
        RunLoop.main.add(timer, forMode: .common)
    }

    private func measure(_ pid: pid_t, _ cost: TimeInterval) {
        let old = setCost[pid] ?? cost
        setCost[pid] = old * 0.6 + cost * 0.4
    }

    /// The exact final set: size, position, size again (the first size may
    /// be clamped by the display the window is leaving), then re-read and
    /// nudge a window that refused the size back against the right edges.
    private func finish(_ g: Glide) {
        let w = g.window, target = g.animation.to
        let t0 = CACurrentMediaTime()
        w.setSize(target.size)
        w.setPosition(target.origin)
        w.setSize(target.size)
        measure(w.pid, (CACurrentMediaTime() - t0) / 2)
        if let actual = w.frame,
           let origin = FrameFitter.nudgedOrigin(target: target, actual: actual, visible: g.visible) {
            w.setPosition(origin)
            log.debug("nudged to \(origin.x, privacy: .public),\(origin.y, privacy: .public): wanted \(target.width, privacy: .public)x\(target.height, privacy: .public), got \(actual.width, privacy: .public)x\(actual.height, privacy: .public)")
        }
        g.restoreEnhancedUI()
        onMoved?()
    }

    /// Whether Restore has anything for this window (for the menu).
    func canRestore(_ window: AXWindow) -> Bool { history.canRestore(window.key) }
}

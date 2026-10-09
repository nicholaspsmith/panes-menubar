// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore
import PanesGlyph
import StatusItemKit

/// Draws Major Pane in the status item: the steady pose, the salute and the bark,
/// at the playing clip's own fps on one re-aimed one-shot timer, parked while
/// the displays sleep, under Reduce Motion, or while the grid icon is chosen.
final class MascotController {
    private let status: StatusItemController
    private let art = MajorPaneArt.shipped
    private var driver: MascotDriver
    private var lit = Set<GridCell>()
    private var active = true
    private var asleep = false
    private var drawn: MajorPanePose?
    private var frameTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    /// False while the grid icon is chosen: nothing is drawn or scheduled.
    var enabled = false {
        didSet { guard enabled != oldValue else { return }; drawn = nil; redraw() }
    }

    init(status: StatusItemController) {
        self.status = status
        driver = MascotDriver(now: Date())
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.redraw() })
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.setAsleep(true) })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.setAsleep(false) })
        }
        redraw()
    }

    /// The trust state and the front window's cells, from every icon refresh.
    func show(active: Bool, lit: Set<GridCell>) {
        self.active = active
        self.lit = lit
        driver.update(active: active, now: Date())
        redraw()
    }

    func salute() { driver.salute(now: Date()); redraw() }
    func bark() { driver.bark(now: Date()); redraw() }

    private func setAsleep(_ value: Bool) {
        guard asleep != value else { return }
        asleep = value
        redraw()
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func timing(_ s: MascotState) -> ClipTiming {
        let c = art.clip(s.rawValue)
        return ClipTiming(fps: c.fps, loop: c.loop, count: c.frames.count)
    }

    /// Draw the pose for now and aim the timer at the next frame boundary.
    private func redraw() {
        frameTimer?.invalidate(); frameTimer = nil
        guard enabled else { return }
        let now = Date(), reduce = reduceMotion || asleep
        let p = driver.pose(now: now, timing: { self.timing($0) }, reduceMotion: reduce)
        let pose = MajorPanePose(state: p.state.rawValue, frame: p.frame, lit: lit, active: active)
        if pose != drawn {
            drawn = pose
            status.setIcon(MajorPaneRenderer.image(art: art, pose: pose))
        }
        guard let delay = driver.nextFrameDelay(now: now, timing: { self.timing($0) }, reduceMotion: reduce) else { return }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.redraw() }
        RunLoop.main.add(t, forMode: .common)       // keeps playing while a menu is open
        frameTimer = t
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// ⌥⌘C: centre the window at the screen's own proportions, and step its
/// size up and down on repeated presses. Sizes are shares of the visible
/// frame's width and height (so the window always has the screen's ratio):
/// 50%, 66%, 80%, 100%. The first press picks the step closest to the
/// window's current size and centres it there; each further press, while the
/// window is still where the last ⌥⌘C put it, moves one step: up until full,
/// then back down to 50%, then up again, for as long as it's pressed.
public enum CenterGrow {
    public static let steps: [CGFloat] = [0.5, 2.0 / 3.0, 0.8, 1.0]
    /// How far (in points, any edge) the window may have drifted and still
    /// count as "where Panes left it" — apps round sizes to their own units.
    public static let tolerance: CGFloat = 4

    /// Where the last ⌥⌘C left a window: its frame, the step it was at and
    /// which way the next press goes.
    public struct State: Equatable {
        public var frame: CGRect
        public var step: Int
        public var growing: Bool
        public init(frame: CGRect, step: Int, growing: Bool) { self.frame = frame; self.step = step; self.growing = growing }
    }

    /// The frame for this press, and the state to remember for the next.
    public static func next(window: CGRect, visible: CGRect, last: State?) -> State {
        let v = visible.integral
        var step: Int
        var growing: Bool
        if let last, isSame(window, last.frame) {
            growing = last.growing
            if growing && last.step == steps.count - 1 { growing = false }
            if !growing && last.step == 0 { growing = true }
            step = last.step + (growing ? 1 : -1)
        } else {
            // First press: the step nearest the window's size (by area share).
            let share = sqrt(max(0, (window.width * window.height) / max(1, v.width * v.height)))
            step = steps.indices.min { abs(steps[$0] - share) < abs(steps[$1] - share) } ?? 0
            growing = step < steps.count - 1
        }
        return State(frame: frame(for: step, in: v), step: step, growing: growing)
    }

    public static func frame(for step: Int, in v: CGRect) -> CGRect {
        let f = steps[step]
        if f == 1 { return v }
        let size = CGSize(width: (v.width * f).rounded(), height: (v.height * f).rounded())
        return FrameCalculator.centered(size, in: v)
    }

    public static func isSame(_ a: CGRect, _ b: CGRect, tolerance t: CGFloat = tolerance) -> Bool {
        abs(a.minX - b.minX) <= t && abs(a.minY - b.minY) <= t
            && abs(a.maxX - b.maxX) <= t && abs(a.maxY - b.maxY) <= t
    }
}

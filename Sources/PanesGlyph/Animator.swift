// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// A clip's timing, from the art (fps, loop, frame count).
public struct ClipTiming: Equatable {
    public var fps: Double
    public var loop: Bool
    public var count: Int
    public init(fps: Double, loop: Bool, count: Int) { self.fps = fps; self.loop = loop; self.count = count }
}

/// Which frame a clip shows at a time, and when it next changes. Pure.
public enum Animator {
    /// The frame `elapsed` seconds into a clip. A clip that doesn't loop holds
    /// its last frame, and `done` says it has finished.
    public static func frame(elapsed: TimeInterval, timing: ClipTiming) -> (index: Int, done: Bool) {
        guard timing.count > 1, timing.fps > 0 else { return (0, !timing.loop) }
        let ticks = (max(0, elapsed) * timing.fps).rounded(.down)
        // Int(_:) traps on NaN, infinity and huge values. A clip that far in has long finished.
        guard ticks.isFinite, ticks < 1e15 else { return timing.loop ? (0, false) : (timing.count - 1, true) }
        let n = Int(ticks)
        if timing.loop { return (n % timing.count, false) }
        return (min(n, timing.count - 1), n >= timing.count)
    }

    /// Added past a frame boundary, so a timer that fires a hair early still lands on the new frame.
    public static let boundarySlack: TimeInterval = 0.002
    /// The menu bar is never redrawn faster than this, whatever the art says.
    public static let minimumDelay: TimeInterval = 1.0 / 60

    /// Seconds from `elapsed` until the clip's frame next changes; nil when it never will
    /// (one frame, no usable fps, a one-shot that has finished). A one-shot's last boundary
    /// is the one where it finishes, so whoever draws it can settle it then.
    public static func nextChange(elapsed: TimeInterval, timing: ClipTiming) -> TimeInterval? {
        guard timing.count > 1, timing.fps > 0, timing.fps.isFinite else { return nil }
        let e = max(0, elapsed)
        let ticks = (e * timing.fps).rounded(.down)
        guard ticks.isFinite, ticks < 1e15 else { return nil }
        if !timing.loop && ticks >= Double(timing.count) { return nil }
        let boundary = (ticks + 1) / timing.fps
        return max(boundary - e + boundarySlack, minimumDelay)
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics
import Foundation

/// A window's glide from one frame to another, eased in and out over 0.26 s,
/// about as long as macOS's own tiling.
///
/// Eased in as well as out because the start of a glide never shows: on a
/// 60 Hz display the first step reaches the screen 40-100 ms in (the app
/// redraws at the new size first). A quick ease-out spent most of its distance
/// in that time, so the window jumped and then crept: measured frame by frame,
/// a centred box growing to full height jumped up to 133 px between frames
/// with 0.18 s of ease-out, and at most 36 px with this.
///
/// Time-driven, not frame-counted: each tick asks for the frame at the time
/// that has actually passed. An app that applies Accessibility sets slowly
/// therefore gets fewer, larger steps that still land on time, instead of
/// every step played late.
public struct FrameAnimation: Equatable, Sendable {
    public static let defaultDuration: TimeInterval = 0.26

    public let from: CGRect
    public let to: CGRect
    public let duration: TimeInterval

    public init(from: CGRect, to: CGRect, duration: TimeInterval = defaultDuration) {
        self.from = from
        self.to = to
        self.duration = duration
    }

    /// Cubic ease-in-out: leaves gently, fastest half-way, settles gently.
    public static func easeInOut(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        if t < 0.5 { return 4 * t * t * t }
        let u = 2 - 2 * t
        return 1 - u * u * u / 2
    }

    public func isFinished(at elapsed: TimeInterval) -> Bool {
        duration <= 0 || elapsed >= duration
    }

    /// The frame `elapsed` seconds in, on whole points; exactly `to` once
    /// finished.
    public func frame(at elapsed: TimeInterval) -> CGRect {
        if isFinished(at: elapsed) { return to }
        let p = CGFloat(Self.easeInOut(elapsed / duration))
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { (a + (b - a) * p).rounded() }
        return CGRect(x: lerp(from.minX, to.minX), y: lerp(from.minY, to.minY),
                      width: lerp(from.width, to.width), height: lerp(from.height, to.height))
    }
}

/// Whether to animate at all, and how often to step. Decided per move from
/// how long the app took to apply its last Accessibility set: an app that
/// takes longer than a frame per set gets a coarser step; one that takes so
/// long that only a step or two would fit jumps straight to the end, as it
/// does under Reduce Motion.
public enum AnimationPacing {
    /// 120 Hz, the ProMotion refresh rate.
    public static let frameInterval: TimeInterval = 1.0 / 120
    /// Fewer than this many steps reads as a stutter, not a glide.
    public static let minimumSteps = 4

    /// The interval between steps, or nil to jump straight to the target.
    /// - Parameter setCost: seconds one position+size set took in this app
    ///   the last time Panes measured it (nil if never).
    public static func stepInterval(duration: TimeInterval = FrameAnimation.defaultDuration,
                                    setCost: TimeInterval?, reduceMotion: Bool) -> TimeInterval? {
        if reduceMotion || duration <= 0 { return nil }
        let interval = max(frameInterval, setCost ?? 0)
        return duration / interval >= Double(minimumSteps) ? interval : nil
    }
}

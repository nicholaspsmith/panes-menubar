// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

public enum MascotState: String, CaseIterable {
    case idle, salute, bark
    case atEase = "at_ease"
}

/// Which clip plays and when (spec "What he does"). The steady pose is idle
/// or at ease. Two things play once over idle: the salute (minute cue) and the
/// bark (a window moved). A one-shot never interrupts another: a cue during a
/// one-shot is skipped; a bark during a one-shot waits (one at most) and plays
/// after. Under Reduce Motion every pose is its frame 0. Pure: the app owns
/// the clock and the timer.
public struct MascotDriver {
    public private(set) var steady: MascotState = .idle
    public private(set) var steadySince: Date
    public private(set) var playing: MascotState?
    public private(set) var playingSince: Date?
    public private(set) var pendingBark = false

    public init(now: Date) { steadySince = now }

    private static func once(_ t: ClipTiming) -> ClipTiming { ClipTiming(fps: t.fps, loop: false, count: t.count) }

    public mutating func update(active: Bool, now: Date) {
        let new: MascotState = active ? .idle : .atEase
        guard new != steady else { return }
        steady = new
        steadySince = now
        playing = nil; playingSince = nil; pendingBark = false
    }

    /// The minute cue: only an idle Major Pane with nothing playing salutes.
    public mutating func salute(now: Date) {
        guard steady == .idle, playing == nil else { return }
        playing = .salute; playingSince = now
    }

    /// A window moved: bark now, or after whatever plays.
    public mutating func bark(now: Date) {
        guard steady == .idle else { return }
        if playing == nil { playing = .bark; playingSince = now } else { pendingBark = true }
    }

    public mutating func pose(now: Date, timing: (MascotState) -> ClipTiming, reduceMotion: Bool) -> (state: MascotState, frame: Int) {
        if reduceMotion {
            playing = nil; playingSince = nil; pendingBark = false
            return (steady, 0)
        }
        // The wall clock can step back (NTP, a manual change, wake): a one-shot dated
        // in the future is over, and the steady clip starts again from now.
        if let start = playingSince, start > now { playing = nil; playingSince = nil }
        if steadySince > now { steadySince = now }
        if let state = playing, let start = playingSince {
            let t = MascotDriver.once(timing(state))
            let f = Animator.frame(elapsed: now.timeIntervalSince(start), timing: t)
            if !f.done { return (state, f.index) }
            playing = nil; playingSince = nil
            // The one-shot ended on the steady clip's frame 0; count the idle from its end, not this draw.
            let length = t.count > 1 && t.fps > 0 && t.fps.isFinite ? Double(t.count) / t.fps : 0
            steadySince = min(start.addingTimeInterval(length), now)
            if pendingBark {
                pendingBark = false
                playing = .bark; playingSince = now
                return pose(now: now, timing: timing, reduceMotion: false)
            }
        }
        return (steady, Animator.frame(elapsed: now.timeIntervalSince(steadySince), timing: timing(steady)).index)
    }

    /// How long until the frame on show changes without new input; nil when nothing moves.
    /// A finished one-shot that no `pose` has settled yet is due at once.
    public func nextFrameDelay(now: Date, timing: (MascotState) -> ClipTiming, reduceMotion: Bool) -> TimeInterval? {
        if reduceMotion { return nil }
        if let state = playing, let start = playingSince, start <= now {
            return Animator.nextChange(elapsed: now.timeIntervalSince(start), timing: MascotDriver.once(timing(state))) ?? Animator.minimumDelay
        }
        if playing != nil { return Animator.minimumDelay }
        return Animator.nextChange(elapsed: now.timeIntervalSince(min(steadySince, now)), timing: timing(steady))
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation
import HotkeyKit

/// When the on-screen grid appears and goes. Hold ⌥⌘ on its own (no other
/// key, no mouse button) for `delay` and the 4×4 grid fades in; hold ⌥⌘⇧
/// and it is the 8×8 half-cell grid. Adding or dropping ⇧ switches between
/// them, before or after it appears. Letting go of ⌥ or ⌘, pressing any
/// key, or adding another modifier takes it away. After a key or a stray modifier it stays
/// away until ⌥⌘ is let go, so a ⌥⌘ shortcut or a cell-key chord held a
/// little long never flashes it.
///
/// Pure: the app feeds it modifier changes, key presses and timer ticks with
/// their times, and carries out the effect each returns.
public struct HoldGrid: Equatable, Sendable {
    public static let defaultDelay: TimeInterval = 0.35
    public static let delayRange: ClosedRange<TimeInterval> = 0.2...1.0
    public static let base: Modifiers = [.command, .option]

    public enum Phase: Equatable, Sendable {
        case idle
        /// ⌥⌘ (⇧ for `fine`) is down alone; show at `deadline` if nothing
        /// else happens.
        case arming(deadline: TimeInterval, fine: Bool)
        case shown(fine: Bool)
        /// Something else happened during this hold; wait for ⌥⌘ to go.
        case blocked
    }

    public enum Effect: Equatable, Sendable {
        case none
        /// Schedule a `tick` at this time.
        case arm(at: TimeInterval)
        /// Fade in, at the resolution `phase` says.
        case show
        case hide
        case setFine(Bool)
    }

    public private(set) var phase: Phase = .idle
    public var delay: TimeInterval

    public init(delay: TimeInterval = defaultDelay) {
        self.delay = min(max(delay, Self.delayRange.lowerBound), Self.delayRange.upperBound)
    }

    /// The held modifiers changed (a flagsChanged event).
    public mutating func modifiers(_ held: Modifiers, at now: TimeInterval, mouseDown: Bool = false) -> Effect {
        let mods = held.subtracting(.fn)
        guard mods.isSuperset(of: Self.base) else {
            let wasShown = phase.isShown
            phase = .idle
            return wasShown ? .hide : .none
        }
        // ⌥⌘ alone is the 4×4 grid, ⌥⌘⇧ the 8×8; anything else is not ours.
        let fine: Bool
        if mods == Self.base { fine = false } else if mods == Self.base.union(.shift) { fine = true } else {
            let wasShown = phase.isShown
            phase = .blocked
            return wasShown ? .hide : .none
        }
        switch phase {
        case .idle:
            if mouseDown {
                phase = .blocked
                return .none
            }
            phase = .arming(deadline: now + delay, fine: fine)
            return .arm(at: now + delay)
        case let .arming(deadline, _):
            phase = .arming(deadline: deadline, fine: fine)
            return .none
        case .shown(let was):
            guard fine != was else { return .none }
            phase = .shown(fine: fine)
            return .setFine(fine)
        case .blocked:
            return .none
        }
    }

    /// Any key went down (a shortcut, a cell key…). The key is never taken
    /// for this — it is handled as usual (⌥⌘Esc stays Force Quit); the grid
    /// just gets out of its way for the rest of this hold.
    public mutating func keyDown() -> Effect {
        switch phase {
        case .idle, .blocked:
            return .none
        case .arming:
            phase = .blocked
            return .none
        case .shown:
            phase = .blocked
            return .hide
        }
    }

    /// The timer set by `.arm` fired (or a mouse button went down: pass it).
    /// - Parameter canShow: false when there is no window to arrange.
    public mutating func tick(at now: TimeInterval, mouseDown: Bool = false, canShow: Bool = true) -> Effect {
        guard case let .arming(deadline, fine) = phase else { return .none }
        if mouseDown || !canShow {
            phase = .blocked
            return .none
        }
        guard now >= deadline - 0.001 else { return .arm(at: deadline) }
        phase = .shown(fine: fine)
        return .show
    }

    /// The grid was used (a cell picked) or closed from outside.
    public mutating func dismissed() -> Effect {
        guard phase.isShown else { return .none }
        phase = .blocked
        return .hide
    }
}

public extension HoldGrid.Phase {
    var isShown: Bool {
        if case .shown = self { return true }
        return false
    }

    /// Whether the grid is (or will be, once shown) the 8×8 half-cell grid.
    var isFine: Bool {
        switch self {
        case .shown(let fine), .arming(_, let fine): return fine
        default: return false
        }
    }
}

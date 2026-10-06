// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// The frames windows had before Panes moved them, newest last, per window.
/// Restore pops one: it undoes the last move Panes made to that window, and
/// pressing it again undoes the one before.
///
/// Bounded both ways: `depth` frames per window, and at most `capacity`
/// windows, the least recently touched forgotten first (closed windows are
/// never reported, so this is what stops it growing for ever).
public struct RestoreHistory<Key: Hashable> {
    public let depth: Int
    public let capacity: Int
    private var stacks: [Key: [CGRect]] = [:]
    private var lastTouched: [Key: Int] = [:]
    private var clock = 0

    public init(depth: Int = 10, capacity: Int = 100) {
        self.depth = max(1, depth)
        self.capacity = max(1, capacity)
    }

    /// Remember `frame` as the window's frame before a move. A frame equal to
    /// the newest one is not stored twice.
    public mutating func record(_ frame: CGRect, for key: Key) {
        var stack = stacks[key] ?? []
        if stack.last != frame { stack.append(frame) }
        if stack.count > depth { stack.removeFirst(stack.count - depth) }
        stacks[key] = stack
        touch(key)
        evict()
    }

    /// The frame to restore, removed from the history.
    public mutating func pop(for key: Key) -> CGRect? {
        guard var stack = stacks[key], let frame = stack.popLast() else { return nil }
        if stack.isEmpty {
            stacks[key] = nil
            lastTouched[key] = nil
        } else {
            stacks[key] = stack
            touch(key)
        }
        return frame
    }

    public func canRestore(_ key: Key) -> Bool { !(stacks[key]?.isEmpty ?? true) }

    public var windowCount: Int { stacks.count }

    private mutating func touch(_ key: Key) {
        clock += 1
        lastTouched[key] = clock
    }

    private mutating func evict() {
        while stacks.count > capacity,
              let oldest = lastTouched.min(by: { $0.value < $1.value })?.key {
            stacks[oldest] = nil
            lastTouched[oldest] = nil
        }
    }
}

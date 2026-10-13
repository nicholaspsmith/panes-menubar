// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics
import Foundation

/// Waiting out a window animation Panes does not drive: macOS returning a
/// window it had tiled to its previous size (about 0.4 s). Frames set while
/// that runs are overwritten by it, so the glide starts once the window has
/// held still for one sample, but never before `minimum` (the animation starts
/// a few ms after the untile, so an early still frame proves nothing) and
/// never after `timeout`.
public struct FrameSettle {
    public static let interval: TimeInterval = 0.03
    public static let minimum: TimeInterval = 0.15
    public static let timeout: TimeInterval = 1.0
    private var last: CGRect?

    public init() {}

    /// One sample of the window's frame, `elapsed` seconds after the untile;
    /// true once it is time to glide. A window that stops answering ends the wait.
    public mutating func isSettled(frame: CGRect?, elapsed: TimeInterval) -> Bool {
        defer { last = frame }
        if elapsed >= Self.timeout { return true }
        guard let frame else { return true }
        return elapsed >= Self.minimum && frame == last
    }
}

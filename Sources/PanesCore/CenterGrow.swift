// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// Center, then grow. The first press centres the window at its own size;
/// pressing again while the window is still where Panes last put it
/// re-centres it one step bigger, as a fraction of the visible frame's width
/// and height: 50%, 66%, 80%, then the whole visible frame, where it stays.
/// A step not larger than the window in both dimensions is skipped.
public enum CenterGrow {
    public static let steps: [CGFloat] = [0.5, 2.0 / 3.0, 0.8, 1.0]
    /// How far (in points, any edge) the window may have drifted and still
    /// count as "where Panes left it" — apps round sizes to their own units.
    public static let tolerance: CGFloat = 4

    /// - Parameter lastPlaced: the frame Panes last gave this window, if any.
    public static func target(window: CGRect, visible: CGRect, lastPlaced: CGRect?) -> CGRect {
        guard let lastPlaced, isSame(window, lastPlaced) else {
            return FrameCalculator.centered(window.size, in: visible)
        }
        let v = visible.integral
        for f in steps {
            let size = f == 1 ? v.size : CGSize(width: (v.width * f).rounded(), height: (v.height * f).rounded())
            if size.width > window.width + tolerance, size.height > window.height + tolerance {
                return FrameCalculator.centered(size, in: v)
            }
        }
        // Nothing bigger to grow to: full, and it stays there.
        return v
    }

    public static func isSame(_ a: CGRect, _ b: CGRect, tolerance t: CGFloat = tolerance) -> Bool {
        abs(a.minX - b.minX) <= t && abs(a.minY - b.minY) <= t
            && abs(a.maxX - b.maxX) <= t && abs(a.maxY - b.maxY) <= t
    }
}

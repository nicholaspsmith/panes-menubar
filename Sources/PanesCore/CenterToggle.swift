// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// ⌥⌘C: centre the window at half the screen's width, alternating between
/// two heights. The first press makes it a full-height column; the next
/// centres it vertically too, at two thirds of the height; the next is the
/// column again, and so on. Which comes next is read from the window itself:
/// one already in the column gets the box, any other gets the column.
public enum CenterToggle {
    public static let widthShare: CGFloat = 0.5
    public static let boxHeightShare: CGFloat = 2.0 / 3.0
    /// How far (in points, any edge) the window may be off the column and
    /// still count as in it: apps round sizes to their own units (a terminal
    /// to whole lines).
    public static let tolerance: CGFloat = 24
    /// The column is never narrower than this (small displays), unless the
    /// display itself is.
    public static let minimumWidth: CGFloat = 1000

    /// Half the visible width, at least `minimumWidth`, at most the whole width.
    public static func width(in v: CGRect) -> CGFloat {
        min(v.width, max((v.width * widthShare).rounded(), minimumWidth))
    }

    /// The frame for this press.
    public static func next(window: CGRect, visible: CGRect) -> CGRect {
        let v = visible.integral
        let column = column(in: v)
        return isSame(window, column) || isWiderColumn(window, column: column, visible: v) ? box(in: v) : column
    }

    /// Half the width, centred, full height.
    public static func column(in v: CGRect) -> CGRect {
        let w = width(in: v)
        return CGRect(x: (v.midX - w / 2).rounded(.down), y: v.minY, width: w, height: v.height)
    }

    /// Half the width and two thirds of the height, centred both ways.
    public static func box(in v: CGRect) -> CGRect {
        let size = CGSize(width: width(in: v), height: (v.height * boxHeightShare).rounded())
        return FrameCalculator.centered(size, in: v)
    }

    /// A column an app made wider than asked (its own minimum width): full
    /// height, centred, at least the column's width but not the whole screen
    /// (that is a maximized window, which gets the column).
    static func isWiderColumn(_ w: CGRect, column c: CGRect, visible v: CGRect) -> Bool {
        abs(w.minY - c.minY) <= tolerance && abs(w.maxY - c.maxY) <= tolerance
            && abs(w.midX - c.midX) <= tolerance
            && w.width >= c.width - tolerance && w.width < v.width - tolerance
    }

    public static func isSame(_ a: CGRect, _ b: CGRect, tolerance t: CGFloat = tolerance) -> Bool {
        abs(a.minX - b.minX) <= t && abs(a.minY - b.minY) <= t
            && abs(a.maxX - b.maxX) <= t && abs(a.maxY - b.maxY) <= t
    }
}

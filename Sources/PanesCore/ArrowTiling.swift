// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// ⌥⌘ + arrows combine the way Windows 11's Win + arrows do. The window's
/// tile is read from where it is now, as a column (left, full or right) and
/// a row (top, full or bottom), and each arrow sets one of them:
/// ← left, → right, ↑ top, ↓ bottom. So ⌥⌘← then ⌥⌘↑ is the top-left
/// quarter, ⌥⌘→ from there is top-right, and ⌥⌘↓ is bottom-right. A window
/// that isn't tiled counts as full in both, so ⌥⌘← alone is the left half
/// and ⌥⌘↑ alone the top half. Pressing toward the side the window is
/// already on widens it back to that half: ⌥⌘→ on the top-right quarter
/// is the right half, ⌥⌘↑ on it the top half.
public enum ArrowTiling {
    public enum Span: Equatable { case first, full, second }

    /// How close (points) an edge must be to count as on a tile line.
    public static let tolerance: CGFloat = 12

    /// The column and row a frame occupies in `visible`.
    public static func tile(of window: CGRect, in v: CGRect) -> (column: Span, row: Span) {
        (span(window.minX, window.maxX, v.minX, v.maxX), span(window.minY, window.maxY, v.minY, v.maxY))
    }

    /// A window pinned to one end of the visible frame but not the other is
    /// in that half, even if it overshoots the middle: an app with a minimum
    /// size bigger than a quarter keeps its outer edge and sticks out past
    /// the middle, and still counts as the quarter Panes put it in.
    private static func span(_ lo: CGFloat, _ hi: CGFloat, _ vLo: CGFloat, _ vHi: CGFloat) -> Span {
        let mid = (vLo + vHi) / 2
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= tolerance }
        let atLo = near(lo, vLo), atHi = near(hi, vHi)
        if atLo && !atHi && hi < vHi - tolerance { return .first }
        if atHi && !atLo && lo > vLo + tolerance { return .second }
        if near(lo, mid) && atHi { return .second }
        if atLo && near(hi, mid) { return .first }
        return .full
    }

    /// The frame for a half action (left/right/top/bottom) given where the
    /// window is now; nil for other actions. AX coordinates: y grows down, so
    /// `.first` rows are the top.
    public static func frame(for action: WindowAction, window: CGRect, visible v: CGRect) -> CGRect? {
        var (column, row) = tile(of: window, in: v)
        switch action {
        case .leftHalf: if column == .first { row = .full } else { column = .first }
        case .rightHalf: if column == .second { row = .full } else { column = .second }
        case .topHalf: if row == .first { column = .full } else { row = .first }
        case .bottomHalf: if row == .second { column = .full } else { row = .second }
        default: return nil
        }
        return rect(column: column, row: row, in: v)
    }

    public static func rect(column: Span, row: Span, in v: CGRect) -> CGRect {
        let halfW = (v.width / 2).rounded(), halfH = (v.height / 2).rounded()
        let x: CGFloat, w: CGFloat, y: CGFloat, h: CGFloat
        switch column {
        case .first: (x, w) = (v.minX, halfW)
        case .full: (x, w) = (v.minX, v.width)
        case .second: (x, w) = (v.minX + halfW, v.width - halfW)
        }
        switch row {
        case .first: (y, h) = (v.minY, halfH)
        case .full: (y, h) = (v.minY, v.height)
        case .second: (y, h) = (v.minY + halfH, v.height - halfH)
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

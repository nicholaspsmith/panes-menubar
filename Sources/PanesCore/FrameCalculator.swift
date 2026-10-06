// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// Target frames for each action. All rects are AX coordinates (y down), so
/// the top half has the smaller y. Splits use whole points: the left/top part
/// gets the floor, the right/bottom part the remainder, so the two halves
/// always tile the visible frame exactly.
public enum FrameCalculator {
    /// The frame a layout action gives `window` inside `visible`, or nil for
    /// Restore and Next Display (which are not about one display's layout).
    public static func frame(for action: WindowAction, window: CGRect, visible v: CGRect) -> CGRect? {
        let v = v.integral
        let leftW = (v.width / 2).rounded(.down), rightW = v.width - leftW
        let topH = (v.height / 2).rounded(.down), bottomH = v.height - topH
        let left = CGRect(x: v.minX, y: v.minY, width: leftW, height: v.height)
        let right = CGRect(x: v.minX + leftW, y: v.minY, width: rightW, height: v.height)
        let top = CGRect(x: v.minX, y: v.minY, width: v.width, height: topH)
        let bottom = CGRect(x: v.minX, y: v.minY + topH, width: v.width, height: bottomH)

        switch action {
        case .leftHalf: return left
        case .rightHalf: return right
        case .topHalf: return top
        case .bottomHalf: return bottom
        case .topLeft: return left.intersection(top)
        case .topRight: return right.intersection(top)
        case .bottomLeft: return left.intersection(bottom)
        case .bottomRight: return right.intersection(bottom)
        case .maximize: return v
        case .center: return centered(window.size, in: v)
        case .restore, .nextDisplay: return nil
        }
    }

    /// Keep the size (shrunk to fit if the window is bigger than the visible
    /// frame), centre it.
    public static func centered(_ size: CGSize, in v: CGRect) -> CGRect {
        let w = Swift.min(size.width, v.width), h = Swift.min(size.height, v.height)
        return CGRect(x: (v.midX - w / 2).rounded(.down), y: (v.midY - h / 2).rounded(.down), width: w, height: h)
    }

    /// Move a window to another display keeping its frame *relative* to the
    /// visible area: a window filling the left half of one display fills the
    /// left half of the other, whatever their sizes.
    public static func moved(_ window: CGRect, from src: CGRect, to dst: CGRect) -> CGRect {
        guard src.width > 0, src.height > 0 else { return centered(window.size, in: dst) }
        let sx = dst.width / src.width, sy = dst.height / src.height
        var r = CGRect(
            x: dst.minX + (window.minX - src.minX) * sx,
            y: dst.minY + (window.minY - src.minY) * sy,
            width: window.width * sx,
            height: window.height * sy
        )
        r = CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width.rounded(), height: r.height.rounded())
        return clamp(r, into: dst)
    }

    /// Shrink a rect to fit `bounds`, then slide it inside.
    public static func clamp(_ r: CGRect, into bounds: CGRect) -> CGRect {
        let w = Swift.min(r.width, bounds.width), h = Swift.min(r.height, bounds.height)
        let x = Swift.min(Swift.max(r.minX, bounds.minX), bounds.maxX - w)
        let y = Swift.min(Swift.max(r.minY, bounds.minY), bounds.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// Some windows refuse a size (a minimum width, a fixed-size panel, a
/// terminal snapping to whole character cells). After setting a frame the
/// window is re-read; if it came out a different size, this works out where
/// it should sit so it still hugs the same edges the target did — a too-wide
/// window sent to the right half stays flush with the right edge rather than
/// hanging off the display.
public enum FrameFitter {
    /// The origin to move to, or nil when the window already sits right.
    public static func nudgedOrigin(target t: CGRect, actual a: CGRect, visible v: CGRect) -> CGPoint? {
        guard a.size != t.size else { return nil }
        let x = axis(targetMin: t.minX, targetMax: t.maxX, size: a.width, visMin: v.minX, visMax: v.maxX)
        let y = axis(targetMin: t.minY, targetMax: t.maxY, size: a.height, visMin: v.minY, visMax: v.maxY)
        let origin = CGPoint(x: x, y: y)
        return origin == a.origin ? nil : origin
    }

    private static func axis(targetMin: CGFloat, targetMax: CGFloat, size: CGFloat,
                             visMin: CGFloat, visMax: CGFloat) -> CGFloat {
        let tol: CGFloat = 1
        let touchesMin = abs(targetMin - visMin) <= tol
        let touchesMax = abs(targetMax - visMax) <= tol
        var p: CGFloat
        if touchesMax && !touchesMin {
            p = targetMax - size                       // hug the far edge
        } else if touchesMin {
            p = targetMin                              // hug the near edge
        } else {
            p = ((targetMin + targetMax) / 2 - size / 2).rounded(.down)   // keep the centre
        }
        // Stay on the display if it fits at all; a window larger than the
        // visible frame starts at its near edge.
        if size >= visMax - visMin { return visMin }
        return Swift.min(Swift.max(p, visMin), visMax - size)
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// One on-screen window as `CGWindowListCopyWindowInfo` reports it. `bounds`
/// is in AX coordinates (top-left of the primary display, y down) — the
/// window server's own space, so no conversion is needed.
public struct WindowInfo: Equatable, Sendable {
    public var bounds: CGRect
    public var ownerPID: Int32
    public var layer: Int
    public var alpha: Double

    public init(bounds: CGRect, ownerPID: Int32, layer: Int = 0, alpha: Double = 1) {
        self.bounds = bounds
        self.ownerPID = ownerPID
        self.layer = layer
        self.alpha = alpha
    }
}

/// The scaling behind the menu-bar icon and the grid's shading: which windows
/// count, and where each one lands in a small drawing of its display.
public enum WindowMap {
    /// Smaller than this on either side is a palette, a tooltip or a status
    /// item's window, not something you arrange.
    public static let minimumSide: CGFloat = 40

    /// Ordinary app windows (layer 0, not invisible, not tiny, not ours), in
    /// the window server's front-to-back order.
    public static func appWindows(_ infos: [WindowInfo], excludingPID own: Int32) -> [WindowInfo] {
        infos.filter {
            $0.layer == 0 && $0.alpha > 0.01 && $0.ownerPID != own
                && $0.bounds.width >= minimumSide && $0.bounds.height >= minimumSide
        }
    }

    /// The windows that belong to `displays[index]` — the display they overlap
    /// most — clipped to it, back to front (so the last is the frontmost and
    /// is drawn on top).
    public static func windows(_ frontToBack: [CGRect], on index: Int, of displays: [Display]) -> [CGRect] {
        guard displays.indices.contains(index) else { return [] }
        let f = displays[index].frame
        return frontToBack.reversed().compactMap { w in
            guard displays.index(for: w) == index else { return nil }
            let clipped = w.intersection(f)
            return clipped.isNull || clipped.isEmpty ? nil : clipped
        }
    }

    /// Map rects on a display into `target` — a rect in an AppKit drawing
    /// (y up) standing for that display — rounded to whole device pixels at
    /// `scale` so 1-pt outlines stay crisp at 1× and 2×. A rect that would
    /// round away to nothing keeps one pixel.
    public static func scaled(_ rects: [CGRect], display: CGRect, into target: CGRect, scale: CGFloat) -> [CGRect] {
        guard display.width > 0, display.height > 0 else { return [] }
        let sx = target.width / display.width, sy = target.height / display.height
        return rects.map { r in
            // y flips: the display's top (small AX y) is the drawing's top (large y).
            let raw = CGRect(x: target.minX + (r.minX - display.minX) * sx,
                             y: target.maxY - (r.maxY - display.minY) * sy,
                             width: r.width * sx, height: r.height * sy)
            return pixelAligned(raw, scale: scale)
        }
    }

    public static func pixelAligned(_ r: CGRect, scale: CGFloat) -> CGRect {
        let s = max(scale, 1)
        let x0 = (r.minX * s).rounded() / s, y0 = (r.minY * s).rounded() / s
        var x1 = (r.maxX * s).rounded() / s, y1 = (r.maxY * s).rounded() / s
        if x1 - x0 < 1 / s { x1 = x0 + 1 / s }
        if y1 - y0 < 1 / s { y1 = y0 + 1 / s }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// The icon's drawing area for a display: as large as fits `box` at the
    /// display's aspect ratio, centred, on whole pixels.
    public static func screenRect(aspect display: CGSize, in box: CGRect, scale: CGFloat) -> CGRect {
        guard display.width > 0, display.height > 0 else { return box }
        let a = display.width / display.height
        var w = box.width, h = w / a
        if h > box.height { h = box.height; w = h * a }
        return pixelAligned(CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h), scale: scale)
    }

    /// Cheap change detection for the icon: equal lists give equal values.
    public static func signature(_ rects: [CGRect]) -> Int {
        var h = Hasher()
        h.combine(rects.count)
        for r in rects {
            h.combine(r.minX); h.combine(r.minY); h.combine(r.width); h.combine(r.height)
        }
        return h.finalize()
    }
}

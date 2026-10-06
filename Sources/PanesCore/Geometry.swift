// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// One display, in **AX coordinates**: the global space the Accessibility API
/// and Quartz use, origin at the top-left of the primary display, y growing
/// downward. A display left of the primary has negative x; one above it has
/// negative y.
public struct Display: Equatable, Sendable {
    /// The whole display.
    public var frame: CGRect
    /// The part windows may use: the frame minus the menu bar and the Dock.
    public var visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// Conversions between AppKit's global coordinates (origin at the bottom-left
/// of the primary display, y up) and AX coordinates (top-left, y down). The
/// primary display is `NSScreen.screens[0]`; only its height matters.
public enum Coordinates {
    /// Cocoa rect → AX rect. The same formula converts back, so it is its own
    /// inverse.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Cocoa point (e.g. `NSEvent.mouseLocation`) → AX point, and back.
    public static func flip(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}

public extension Array where Element == Display {
    /// The display a window belongs to: the one it overlaps most, or the one
    /// whose centre is nearest when it overlaps none (a window dragged fully
    /// off-screen). Nil only for an empty list.
    func index(for window: CGRect) -> Int? {
        guard !isEmpty else { return nil }
        var best: (index: Int, area: CGFloat)?
        for (i, d) in enumerated() {
            let overlap = d.frame.intersection(window)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > 0, area > (best?.area ?? 0) { best = (i, area) }
        }
        if let best { return best.index }
        return nearest(to: CGPoint(x: window.midX, y: window.midY))
    }

    /// The display containing a point, else the nearest one.
    func index(containing point: CGPoint) -> Int? {
        if let i = firstIndex(where: { $0.frame.contains(point) }) { return i }
        return nearest(to: point)
    }

    /// The display after `index` in left-to-right (then top-to-bottom) order,
    /// wrapping round. Nil when there is only one display.
    func next(after index: Int) -> Int? {
        guard count > 1, indices.contains(index) else { return nil }
        let order = indices.sorted {
            let a = self[$0].frame, b = self[$1].frame
            return a.minX != b.minX ? a.minX < b.minX : a.minY < b.minY
        }
        guard let pos = order.firstIndex(of: index) else { return nil }
        return order[(pos + 1) % order.count]
    }

    private func nearest(to point: CGPoint) -> Int? {
        indices.min { squaredDistance(point, self[$0].frame) < squaredDistance(point, self[$1].frame) }
    }
}

/// Squared distance from a point to the nearest point of a rect (0 inside).
func squaredDistance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
    let dx = Swift.max(r.minX - p.x, 0, p.x - r.maxX)
    let dy = Swift.max(r.minY - p.y, 0, p.y - r.maxY)
    return dx * dx + dy * dy
}

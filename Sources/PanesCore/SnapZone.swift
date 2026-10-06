// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// Where a window being dragged would snap, given the cursor.
///
/// The cursor has to reach a display's outer edge: within `edgeMargin` points
/// of it. Left and right edges snap to halves, the top edge maximizes, and the
/// first `cornerSize` points of an edge from a corner snap to that quarter
/// (the bottom edge snaps only at its corners). An edge another display sits
/// against is not an edge at all — the cursor passes straight through it — so
/// it never snaps.
public enum SnapZone {
    public static let edgeMargin: CGFloat = 5
    public static let cornerSize: CGFloat = 40

    public struct Hit: Equatable, Sendable {
        public let action: WindowAction
        public let displayIndex: Int
    }

    public static func detect(cursor: CGPoint, displays: [Display],
                              edgeMargin m: CGFloat = edgeMargin,
                              cornerSize c: CGFloat = cornerSize) -> Hit? {
        guard let i = displays.index(containing: cursor) else { return nil }
        let f = displays[i].frame
        // A cursor reported a point outside every display (Cocoa's top row can
        // read as y = height) is pulled onto the nearest one.
        let p = CGPoint(x: Swift.min(Swift.max(cursor.x, f.minX), f.maxX - 1),
                        y: Swift.min(Swift.max(cursor.y, f.minY), f.maxY - 1))

        func outer(_ probe: CGPoint) -> Bool {
            !displays.enumerated().contains { $0.offset != i && $0.element.frame.contains(probe) }
        }
        let left = p.x <= f.minX + m && outer(CGPoint(x: f.minX - 1, y: p.y))
        let right = p.x >= f.maxX - 1 - m && outer(CGPoint(x: f.maxX, y: p.y))
        let top = p.y <= f.minY + m && outer(CGPoint(x: p.x, y: f.minY - 1))
        let bottom = p.y >= f.maxY - 1 - m && outer(CGPoint(x: p.x, y: f.maxY))

        let nearTop = p.y < f.minY + c, nearBottom = p.y >= f.maxY - c
        let nearLeft = p.x < f.minX + c, nearRight = p.x >= f.maxX - c

        let action: WindowAction?
        if (left && nearTop) || (top && nearLeft) {
            action = .topLeft
        } else if (right && nearTop) || (top && nearRight) {
            action = .topRight
        } else if (left && nearBottom) || (bottom && nearLeft) {
            action = .bottomLeft
        } else if (right && nearBottom) || (bottom && nearRight) {
            action = .bottomRight
        } else if left {
            action = .leftHalf
        } else if right {
            action = .rightHalf
        } else if top {
            action = .maximize
        } else {
            action = nil
        }
        return action.map { Hit(action: $0, displayIndex: i) }
    }
}

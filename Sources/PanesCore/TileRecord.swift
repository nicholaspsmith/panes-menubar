// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// When a move can leave macOS's record of one of its own tiles behind (see
/// `NativeTile` in the app). WindowManager checks each frame a tiled window is
/// given against the tile and forgets the tile once the frame leaves it ("frame
/// not legal for tiling"). A frame inside it can keep the record, and macOS
/// later puts the window back: measured on macOS 27, Fill kept it for a half and
/// for a small floating frame, a half kept it for its own quarter. So only a
/// move into the window's current frame (the tile itself, while the record
/// stands) needs the untile, and its animation, first.
public enum TileRecord {
    /// Allowance at each edge for a window that sits a little off its tile
    /// (one that sizes in steps, or has a minimum size). Erring large only
    /// costs an untile that wasn't needed.
    public static let slack: CGFloat = 32

    /// Whether a window at `current` that macOS has tiled could still be in
    /// that tile after moving to `target`.
    public static func canOutlive(moveFrom current: CGRect, to target: CGRect) -> Bool {
        current.insetBy(dx: -slack, dy: -slack).contains(target)
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

/// macOS's own edge tiling (System Settings ▸ Desktop & Dock ▸ "Drag windows
/// to screen edges to tile" and "…to menu bar to fill screen"). With it on,
/// a window dragged to an edge is tiled by macOS *and* snapped by Panes, and
/// the two fight over the frame.
public enum SystemTiling {
    public static let domain = "com.apple.WindowManager"
    public static let edgeKey = "EnableTilingByEdgeDrag"
    public static let topKey = "EnableTopTilingByEdgeDrag"

    /// Whether either setting is on. A key that was never written means the
    /// macOS default, which is on.
    public static func isEdgeTilingOn(edge: Any?, top: Any?) -> Bool {
        isOn(edge) || isOn(top)
    }

    private static func isOn(_ value: Any?) -> Bool {
        switch value {
        case nil: return true
        case let b as Bool: return b
        case let n as Int: return n != 0
        default: return true
        }
    }
}

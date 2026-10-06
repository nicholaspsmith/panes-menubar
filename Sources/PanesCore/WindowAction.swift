// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

/// Everything Panes can do to a window, identified by its binding token.
/// Declaration order is menu and Preferences order.
public enum WindowAction: String, CaseIterable, Sendable {
    case leftHalf = "window.leftHalf"
    case rightHalf = "window.rightHalf"
    case topHalf = "window.topHalf"
    case bottomHalf = "window.bottomHalf"
    case topLeft = "window.topLeft"
    case topRight = "window.topRight"
    case bottomLeft = "window.bottomLeft"
    case bottomRight = "window.bottomRight"
    case maximize = "window.maximize"
    case center = "window.center"
    case restore = "window.restore"
    case nextDisplay = "window.nextDisplay"

    public var label: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .maximize: return "Maximize"
        case .center: return "Center"
        case .restore: return "Restore"
        case .nextDisplay: return "Next Display"
        }
    }

    /// Menu grouping: a separator goes between groups.
    public var group: Int {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return 0
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return 1
        case .maximize, .center, .restore: return 2
        case .nextDisplay: return 3
        }
    }

    /// Whether the action computes a frame inside one display's visible area
    /// (everything except Restore and Next Display).
    public var isLayout: Bool {
        self != .restore && self != .nextDisplay
    }
}

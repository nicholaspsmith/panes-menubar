// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore

/// The live display layout, converted once into AX coordinates.
enum Screens {
    /// The primary display (the one at the origin): its height anchors the
    /// Cocoa ↔ AX flip.
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static var displays: [Display] {
        let h = primaryHeight
        return NSScreen.screens.map {
            Display(frame: Coordinates.flip($0.frame, primaryHeight: h),
                    visibleFrame: Coordinates.flip($0.visibleFrame, primaryHeight: h))
        }
    }

    /// AX rect → Cocoa rect (for placing our own overlay window).
    static func cocoa(_ ax: CGRect) -> CGRect { Coordinates.flip(ax, primaryHeight: primaryHeight) }

    /// The cursor, in AX coordinates.
    static var cursor: CGPoint { Coordinates.flip(NSEvent.mouseLocation, primaryHeight: primaryHeight) }
}

/// On-screen windows from the window server, front to back. Bounds only:
/// that needs no Accessibility and no Screen Recording (titles would).
enum WindowList {
    static func appWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let infos = list.compactMap { d -> WindowInfo? in
            guard let b = d[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b) else { return nil }
            return WindowInfo(bounds: rect,
                              ownerPID: (d[kCGWindowOwnerPID as String] as? Int32) ?? 0,
                              layer: (d[kCGWindowLayer as String] as? Int) ?? 0,
                              alpha: (d[kCGWindowAlpha as String] as? Double) ?? 1)
        }
        return WindowMap.appWindows(infos, excludingPID: getpid())
    }
}

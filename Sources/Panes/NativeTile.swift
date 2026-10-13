// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import ApplicationServices

/// macOS's own window tiles: the green button's menu, Window ▸ Fill and
/// Window ▸ Move & Resize. macOS remembers a window it tiled and puts it back
/// in that tile whenever its layout changes (Mission Control closing, a
/// display waking), however the window was moved since; moving it through
/// Accessibility does not clear that. So before Panes moves a window macOS has
/// tiled, it runs the app's own Window ▸ Move & Resize ▸ Return to Previous Size.
enum NativeTile {
    /// That menu item's identifier (its action), the same in every language.
    static let untileIdentifier = "_zoomUntile:"
    private static var items: [pid_t: AXUIElement] = [:]
    private static var missing: [pid_t: CFTimeInterval] = [:]

    /// Untile `window` if macOS has it tiled; true when it did. macOS enables
    /// the item only while the app's main window is one it tiled, and the item
    /// acts on that window, so a window that isn't main is left alone.
    static func untile(_ window: AXWindow) -> Bool {
        guard window.isMain, let item = item(for: window.pid),
              let enabled = value(item, kAXEnabledAttribute) as? Bool, enabled else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// The app's Return to Previous Size item, found once (about 25 ms: the
    /// Window menu is near the end of the menu bar, so the search starts
    /// there) and kept until the app rebuilds its menus. An app without one is
    /// asked again after a minute.
    private static func item(for pid: pid_t) -> AXUIElement? {
        if let cached = items[pid] {
            if value(cached, kAXIdentifierAttribute) as? String == untileIdentifier { return cached }
            items[pid] = nil
        }
        let now = CACurrentMediaTime()
        if let since = missing[pid], now - since < 60 { return nil }
        if items.count > 64 { items.removeAll() }
        if missing.count > 64 { missing.removeAll() }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXWindow.messagingTimeout)
        if let bar = value(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() {
            for top in children(bar as! AXUIElement).reversed() {
                if let found = search(top, depth: 1) {
                    items[pid] = found
                    missing[pid] = nil
                    return found
                }
            }
        }
        missing[pid] = now
        return nil
    }

    /// Menu bar item ▸ menu ▸ item ▸ submenu ▸ item: Move & Resize is one level down.
    private static func search(_ element: AXUIElement, depth: Int) -> AXUIElement? {
        if value(element, kAXIdentifierAttribute) as? String == untileIdentifier { return element }
        guard depth < 5 else { return nil }
        for child in children(element) {
            if let found = search(child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        let list = value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        list.forEach { AXUIElementSetMessagingTimeout($0, AXWindow.messagingTimeout) }
        return list
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}

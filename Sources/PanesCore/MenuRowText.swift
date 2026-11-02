// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

/// Which menu items keep Panes's menu open when clicked. Every one does, but
/// for two kinds whose job is to leave the menu: Quit, and an item whose
/// title ends in an ellipsis, which (by macOS convention) opens a window or
/// another app. That window could not be used until the menu closed.
public enum KeepOpenPolicy {
    public static func keepsMenuOpen(title: String, isQuit: Bool) -> Bool {
        !isQuit && !title.hasSuffix("…") && !title.hasSuffix("...")
    }
}

/// A menu item's key equivalent as the menu shows it: the modifiers in
/// macOS's order (⌃⌥⇧⌘), then the key, with arrows, function and editing
/// keys as their glyphs and letters in capitals.
public enum KeyEquivalentText {
    public static func text(key: String, control: Bool = false, option: Bool = false,
                            shift: Bool = false, command: Bool = false) -> String? {
        guard let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1 else { return nil }
        let name = glyphs[scalar.value] ?? key.uppercased()
        return (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + name
    }

    private static let glyphs: [UInt32: String] = {
        var g: [UInt32: String] = [
            0xF700: "↑", 0xF701: "↓", 0xF702: "←", 0xF703: "→",
            0xF728: "⌦", 0xF729: "↖", 0xF72B: "↘", 0xF72C: "⇞", 0xF72D: "⇟",
            0x08: "⌫", 0x7F: "⌫", 0x0D: "↩", 0x03: "⌤", 0x09: "⇥", 0x1B: "⎋", 0x20: "Space",
        ]
        for n in 1...12 { g[0xF703 + UInt32(n)] = "F\(n)" }
        return g
    }()
}

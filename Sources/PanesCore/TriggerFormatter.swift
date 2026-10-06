// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics
import HotkeyKit

/// Renders a `Trigger` as glyphs for the Preferences window, e.g. "⌥⌘←".
/// Modifiers in Apple's order: ⌃ ⌥ ⇧ ⌘.
public enum TriggerFormatter {
    public static func string(_ trigger: Trigger) -> String {
        switch trigger {
        case let .key(code, mods):
            let shown = KeyCode.impliedFn.contains(code) ? mods.subtracting(.fn) : mods
            return modifierString(shown) + keyName(code)
        case let .mediaKey(code, mods):
            return modifierString(mods) + "Media(\(code))"
        }
    }

    public static func modifierString(_ m: Modifiers) -> String {
        var s = ""
        if m.contains(.fn)      { s += "fn " }
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option)  { s += "⌥" }
        if m.contains(.shift)   { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        return s
    }

    public static func keyName(_ code: CGKeyCode) -> String {
        keyNames[code] ?? "Key \(code)"
    }

    private static let keyNames: [CGKeyCode: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥",
        49: "Space", 50: "`", 51: "⌫", 53: "⎋", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

/// The `NSMenuItem.keyEquivalent` string that shows a trigger's key in a
/// menu, or nil for keys a menu cannot display (media keys, unmapped codes).
/// Kept free of AppKit: the arrow and function-key values are the
/// `NS…FunctionKey` Unicode scalars.
public enum MenuKeyEquivalent {
    public static func string(for trigger: Trigger) -> String? {
        guard case let .key(code, _) = trigger else { return nil }
        if let special = specials[code] { return String(UnicodeScalar(special)!) }
        guard let name = TriggerFormatter.keyNamesForMenu[code] else { return nil }
        return name.lowercased()
    }

    private static let specials: [CGKeyCode: UInt32] = [
        123: 0xF702, 124: 0xF703, 125: 0xF701, 126: 0xF700,   // ← → ↓ ↑
        115: 0xF729, 119: 0xF72B, 116: 0xF72C, 121: 0xF72D,   // home end pgup pgdn
        117: 0xF728,                                           // forward delete
        51: 0x08, 36: 0x0D, 48: 0x09, 53: 0x1B, 49: 0x20,      // ⌫ ↩ ⇥ ⎋ space
        122: 0xF704, 120: 0xF705, 99: 0xF706, 118: 0xF707, 96: 0xF708, 97: 0xF709,
        98: 0xF70A, 100: 0xF70B, 101: 0xF70C, 109: 0xF70D, 103: 0xF70E, 111: 0xF70F,
    ]
}

extension TriggerFormatter {
    /// Single printable characters only (letters, digits, punctuation).
    static var keyNamesForMenu: [CGKeyCode: String] {
        keyNames.filter { $0.value.count == 1 && $0.value.unicodeScalars.first!.isASCII }
    }
}

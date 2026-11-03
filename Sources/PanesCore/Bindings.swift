// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics
import HotkeyKit

/// ANSI virtual keycodes Panes binds by default.
public enum KeyCode {
    public static let leftArrow: CGKeyCode = 123
    public static let rightArrow: CGKeyCode = 124
    public static let downArrow: CGKeyCode = 125
    public static let upArrow: CGKeyCode = 126
    public static let leftBracket: CGKeyCode = 33
    public static let rightBracket: CGKeyCode = 30
    public static let semicolon: CGKeyCode = 41
    public static let quote: CGKeyCode = 39
    public static let m: CGKeyCode = 46
    public static let c: CGKeyCode = 8
    public static let n: CGKeyCode = 45
    public static let delete: CGKeyCode = 51
}

public enum BindingStore {
    private static let cmdOpt: Modifiers = [.command, .option]

    /// Nick's defaults: ⌘⌥ + arrows for halves, [ ] ; ' for the quarters (the
    /// keys sit in the same 2×2 arrangement as the corners), M maximize,
    /// C center, ⌫ restore, N next display — every one on ⌘⌥.
    public static let defaults: [Binding] = [
        Binding(token: WindowAction.leftHalf.rawValue, trigger: .key(KeyCode.leftArrow, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.rightHalf.rawValue, trigger: .key(KeyCode.rightArrow, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.topHalf.rawValue, trigger: .key(KeyCode.upArrow, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.bottomHalf.rawValue, trigger: .key(KeyCode.downArrow, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.topLeft.rawValue, trigger: .key(KeyCode.leftBracket, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.topRight.rawValue, trigger: .key(KeyCode.rightBracket, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.bottomLeft.rawValue, trigger: .key(KeyCode.semicolon, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.bottomRight.rawValue, trigger: .key(KeyCode.quote, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.maximize.rawValue, trigger: .key(KeyCode.m, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.center.rawValue, trigger: .key(KeyCode.c, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.restore.rawValue, trigger: .key(KeyCode.delete, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.nextDisplay.rawValue, trigger: .key(KeyCode.n, cmdOpt), repeatsOnHold: false),
    ]

    /// Merge user overrides (token → trigger) over the defaults, in action
    /// order. Overrides for unknown tokens are ignored.
    public static func resolve(overrides: [String: Trigger]) -> [Binding] {
        defaults.map { binding in
            guard let trigger = overrides[binding.token] else { return binding }
            var updated = binding
            updated.trigger = trigger
            return updated
        }
    }

    /// The other actions sharing a binding's trigger. The tap fires the first
    /// in action order, so the rest never would.
    public static func conflicts(for token: String, in bindings: [Binding]) -> [WindowAction] {
        guard let mine = bindings.first(where: { $0.token == token })?.trigger else { return [] }
        return bindings
            .filter { $0.token != token && $0.trigger == mine }
            .compactMap { WindowAction(rawValue: $0.token) }
    }
}

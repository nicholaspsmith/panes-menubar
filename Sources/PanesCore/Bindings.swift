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
    public static let u: CGKeyCode = 32
    public static let i: CGKeyCode = 34
    public static let j: CGKeyCode = 38
    public static let k: CGKeyCode = 40
    public static let m: CGKeyCode = 46
    public static let c: CGKeyCode = 8
    public static let n: CGKeyCode = 45
    public static let delete: CGKeyCode = 51

    /// Keys macOS flags as "function keys" on every keyboard: the arrows,
    /// Home/End, Page Up/Down, Forward Delete and Help. Their events always
    /// carry the secondary-fn flag, so to HotkeyKit (which matches modifiers
    /// exactly and only drops that flag on F1–F20) ⌘⌥← arrives as ⌘⌥fn←.
    public static let impliedFn: Set<CGKeyCode> = [123, 124, 125, 126, 115, 119, 116, 121, 117, 114]
}

public enum BindingStore {
    private static let cmdOpt: Modifiers = [.command, .option]

    /// Nick's defaults: ⌘⌥ + arrows for halves, U I J K for the quarters (the
    /// keys sit in the same 2×2 arrangement as the corners), M maximize,
    /// C center, ⌫ restore, N next display — every one on ⌘⌥.
    public static let defaults: [Binding] = [
        Binding(token: WindowAction.leftHalf.rawValue, trigger: .key(KeyCode.leftArrow, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.rightHalf.rawValue, trigger: .key(KeyCode.rightArrow, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.topHalf.rawValue, trigger: .key(KeyCode.upArrow, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.bottomHalf.rawValue, trigger: .key(KeyCode.downArrow, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.topLeft.rawValue, trigger: .key(KeyCode.u, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.topRight.rawValue, trigger: .key(KeyCode.i, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.bottomLeft.rawValue, trigger: .key(KeyCode.j, cmdOpt), repeatsOnHold: false),
        Binding(token: WindowAction.bottomRight.rawValue, trigger: .key(KeyCode.k, cmdOpt), repeatsOnHold: false),
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
            updated.trigger = normalized(trigger)
            return updated
        }
    }

    /// What the tap listens for: each binding, plus an fn-flagged twin for a
    /// key whose events always carry fn (see `KeyCode.impliedFn`). Both, not
    /// just the twin, so a keyboard or remapper that leaves the flag off still
    /// matches.
    public static func tapBindings(_ bindings: [Binding]) -> [Binding] {
        bindings.flatMap { b -> [Binding] in
            guard case let .key(code, mods) = b.trigger, KeyCode.impliedFn.contains(code) else { return [b] }
            var twin = b
            twin.trigger = .key(code, mods.union(.fn))
            return [b, twin]
        }
    }

    /// A recorded trigger as Panes stores it: the implied fn flag dropped, so
    /// "⌘⌥←" recorded on any keyboard equals the default.
    public static func normalized(_ trigger: Trigger) -> Trigger {
        if case let .key(code, mods) = trigger, KeyCode.impliedFn.contains(code) {
            return .key(code, mods.subtracting(.fn))
        }
        return trigger
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

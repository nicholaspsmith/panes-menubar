// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import HotkeyKit
import DisplayCore

/// Makes the keyboard's brightness keys drive the main external monitor —
/// over DDC, or through DisplayServices where DDC has refused and macOS can
/// dim the display itself. It matches the plain brightness media keys —
/// the ones an Apple keyboard sends, and the ones KeyLight posts for F1/F2 on
/// other boards — and swallows a press only when the main display is a
/// monitor we control; otherwise the key passes through and macOS dims the
/// built-in panel as usual — until macOS's brightness reaches 0, where the
/// keys go on to dim the panel further (`BrightnessKeys.route`).
/// Ctrl+brightness is not bound, so KeyLight still gets it.
///
/// It owns no event tap: Panes's one `HotkeyTap` carries `bindings` beside
/// the window shortcuts and sends their tokens to `handle(token:)`. With the
/// Brightness Keys off, `bindings` is empty, so the tap never sees a match
/// and every press goes to macOS.
final class BrightnessKeyController {
    static let enabledKey = "brightnessKeys"

    /// NX_KEYTYPE_BRIGHTNESS_UP / _DOWN, no modifiers.
    private static let allBindings: [Binding] = [
        Binding(token: "brightness.up", trigger: .mediaKey(2, [])),
        Binding(token: "brightness.down", trigger: .mediaKey(3, [])),
    ]
    private static let tokens = Set(allBindings.map(\.token))

    /// Where a press in this direction goes.
    private let route: (BrightnessKeys.Direction) -> BrightnessKeys.Route
    private let stepExternal: (CGDirectDisplayID, BrightnessKeys.Direction) -> Void
    private let stepDim: (BrightnessKeys.Direction) -> Void
    private let stepBoost: (BrightnessKeys.Direction) -> Void

    /// Called when `bindings` changes (the Brightness Keys turned on or off),
    /// so the tap's owner can hand the tap its new binding set.
    var onBindingsChanged: (() -> Void)?

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled != oldValue { onBindingsChanged?() }
        }
    }

    /// The bindings to add to the shared tap: both brightness keys while
    /// enabled, none while off.
    var bindings: [Binding] { isEnabled ? Self.allBindings : [] }

    init(route: @escaping (BrightnessKeys.Direction) -> BrightnessKeys.Route,
         stepExternal: @escaping (CGDirectDisplayID, BrightnessKeys.Direction) -> Void,
         stepDim: @escaping (BrightnessKeys.Direction) -> Void,
         stepBoost: @escaping (BrightnessKeys.Direction) -> Void) {
        self.route = route
        self.stepExternal = stepExternal
        self.stepDim = stepDim
        self.stepBoost = stepBoost
        // On by default: an absent key reads as enabled.
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// A press the shared tap matched. Returns true to swallow it, false for
    /// a token that isn't a brightness key, or a press that goes to macOS.
    func handle(token: String) -> Bool {
        guard isEnabled, Self.tokens.contains(token) else { return false }
        let direction: BrightnessKeys.Direction = token == "brightness.up" ? .up : .down
        switch route(direction) {
        case .external(let id): stepExternal(id, direction)
        case .dim: stepDim(direction)
        case .boost: stepBoost(direction)
        case .passThrough: return false
        }
        return true
    }

    /// Whether this token is one of the brightness keys'.
    static func isBrightnessToken(_ token: String) -> Bool { tokens.contains(token) }
}

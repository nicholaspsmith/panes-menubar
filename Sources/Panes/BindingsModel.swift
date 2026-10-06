// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Combine
import Foundation
import HotkeyKit
import PanesCore

/// The shortcuts: built-in defaults with the user's overrides (UserDefaults
/// `bindingOverrides`, token → trigger JSON) merged over them. Publishes to
/// the Preferences window; pushes the tap's set through `onChange`.
final class BindingsModel: ObservableObject {
    @Published private(set) var bindings: [Binding]
    /// True while Preferences is recording a shortcut, so the tap lets the
    /// keys through to the recorder instead of acting on them.
    @Published var isRecording = false

    var onChange: (([Binding]) -> Void)?

    var tapBindings: [Binding] { BindingStore.tapBindings(bindings) }

    private var overrides: [String: Trigger]
    private static let defaultsKey = "bindingOverrides"

    init() {
        overrides = Self.load()
        bindings = BindingStore.resolve(overrides: overrides)
    }

    func trigger(for action: WindowAction) -> Trigger? {
        bindings.first { $0.token == action.rawValue }?.trigger
    }

    func setOverride(_ action: WindowAction, trigger: Trigger) {
        overrides[action.rawValue] = BindingStore.normalized(trigger)
        changed()
    }

    func reset(_ action: WindowAction) {
        overrides[action.rawValue] = nil
        changed()
    }

    func resetAll() {
        overrides.removeAll()
        changed()
    }

    func isOverridden(_ action: WindowAction) -> Bool { overrides[action.rawValue] != nil }

    func conflicts(_ action: WindowAction) -> [WindowAction] {
        BindingStore.conflicts(for: action.rawValue, in: bindings)
    }

    private func changed() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        bindings = BindingStore.resolve(overrides: overrides)
        onChange?(tapBindings)
    }

    private static func load() -> [String: Trigger] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let dict = try? JSONDecoder().decode([String: Trigger].self, from: data) else { return [:] }
        return dict
    }
}

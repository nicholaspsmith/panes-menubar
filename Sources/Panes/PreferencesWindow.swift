// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import HotkeyKit
import PanesCore
import StatusItemKit
import SwiftUI

/// Drives a `TriggerRecorder` and tells the model while it records, so the
/// key tap stands aside for the keys being recorded.
final class RecorderModel: ObservableObject {
    @Published var recording: WindowAction?
    private let recorder = TriggerRecorder()
    private let bindings: BindingsModel

    init(bindings: BindingsModel) { self.bindings = bindings }

    func record(_ action: WindowAction) {
        recording = action
        bindings.isRecording = true
        recorder.start { [weak self] trigger in
            guard let self else { return }
            // Escape alone cancels rather than binding Escape.
            if trigger != .key(53, []) { self.bindings.setOverride(action, trigger: trigger) }
            self.finish()
        }
    }

    func cancel() {
        recorder.stop()
        finish()
    }

    private func finish() {
        recording = nil
        bindings.isRecording = false
    }
}

/// Every Panes setting, behind the menu's Preferences… (⌘,), as in Mac Daddy:
/// what the old Settings and Icon submenus held, and the window shortcuts.
/// The values live with the app (`App`); `hooks` read and change them.
/// Start at Login is StatusItemKit's `StartAtLoginToggle`, which reads and
/// sets the login item itself.
final class PreferencesModel: ObservableObject {
    struct Snapshot {
        var edgeSnapping = true
        var holdGrid = true
        var brightnessKeys = true
        var icon = IconChoice.grid
        var colorHex = ""
        /// Each icon as it would look in the menu bar now.
        var previews: [IconChoice: NSImage] = [:]
    }

    struct Hooks {
        var read: () -> Snapshot
        var setEdgeSnapping: (Bool) -> Void
        var setHoldGrid: (Bool) -> Void
        var setBrightnessKeys: (Bool) -> Void
        var setIcon: (IconChoice) -> Void
        var setColor: (NSColor) -> Void
        var preview: (IconChoice) -> NSImage
    }

    @Published private(set) var current = Snapshot()
    let bindings: BindingsModel
    let recorder: RecorderModel
    private let hooks: Hooks

    init(bindings: BindingsModel, hooks: Hooks) {
        self.bindings = bindings
        self.recorder = RecorderModel(bindings: bindings)
        self.hooks = hooks
        refresh()
    }

    /// Re-read everything: the window is shown again, or a value changed.
    func refresh() {
        var snapshot = hooks.read()
        for icon in Self.icons { snapshot.previews[icon.choice] = hooks.preview(icon.choice) }
        current = snapshot
    }

    func setEdgeSnapping(_ on: Bool) { hooks.setEdgeSnapping(on); refresh() }
    func setHoldGrid(_ on: Bool) { hooks.setHoldGrid(on); refresh() }
    func setBrightnessKeys(_ on: Bool) { hooks.setBrightnessKeys(on); refresh() }
    func setIcon(_ choice: IconChoice) { hooks.setIcon(choice); refresh() }
    func setColor(_ color: NSColor) { hooks.setColor(color); refresh() }

    /// The icons in the order the old Icon submenu listed them.
    static let icons: [(title: String, choice: IconChoice)] =
        [("Screen Grid", .grid), ("Major Pane", .majorPane), ("Armonitor", .armonitor)]
        + IconChoice.meters.compactMap(MeterStyle.init(rawValue:)).map { ($0.title, IconChoice.meter($0.rawValue)) }

    var isMeter: Bool { if case .meter = current.icon { return true } else { return false } }
}

/// The window's content: General and Shortcuts tabs. StatusItemKit's
/// `PreferencesPane` holds it ("Panes Preferences", Esc and ⌘W close it).
struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        TabView {
            GeneralPreferencesView(model: model)
                .tabItem { Text("General") }
            ShortcutsPreferencesView(model: model.bindings, recorder: model.recorder)
                .tabItem { Text("Shortcuts") }
        }
        .padding(12)
        .frame(width: 540)
    }
}

struct GeneralPreferencesView: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject private var bindings: BindingsModel

    init(model: PreferencesModel) {
        self.model = model
        bindings = model.bindings
    }

    var body: some View {
        Form {
            Section("General") {
                StartAtLoginToggle()
                Toggle(isOn: Binding(get: { model.current.edgeSnapping }, set: { model.setEdgeSnapping($0) })) {
                    Text("Edge Snapping")
                    Text("Drag a window to a display edge or corner to snap it there.")
                }
                Toggle(isOn: Binding(get: { model.current.brightnessKeys }, set: { model.setBrightnessKeys($0) })) {
                    Text("Brightness Keys")
                    Text("The keyboard's brightness keys change the main monitor's brightness.")
                }
            }
            Section("Menu Bar Icon") {
                IconTiles(model: model)
                if model.isMeter {
                    colourPicker
                }
            }
            Section {
                Toggle("Show the grid while ⌥⌘ is held",
                       isOn: Binding(get: { model.current.holdGrid }, set: { model.setHoldGrid($0) }))
                LabeledContent("Appears after") {
                    HStack(spacing: 10) {
                        Slider(value: $bindings.holdDelay, in: HoldGrid.delayRange, step: 0.05)
                            .frame(width: 180)
                        Text(String(format: "%.2f s", bindings.holdDelay))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(!model.current.holdGrid)
            } header: {
                Text("Grid on Hold ⌥⌘")
            } footer: {
                PreferencesNote("Hold ⌥⌘ on its own and a grid covers the screen: click a cell or drag across cells. Add ⇧ for half-cells.")
            }
            // A tabbed window puts the version at the foot of its General tab.
            PreferencesVersionSection()
        }
        .formStyle(.grouped)
    }

    /// The meter's colour: StatusItemKit's presets, or any colour.
    @ViewBuilder
    private var colourPicker: some View {
        let hex = model.current.colorHex.uppercased()
        let isPreset = MeterColor.presets.contains { $0.hex.uppercased() == hex }
        Picker("Colour", selection: Binding(get: { isPreset ? hex : "custom" }, set: { picked in
            if let preset = MeterColor.presets.first(where: { $0.hex.uppercased() == picked }) { model.setColor(preset.color) }
        })) {
            ForEach(MeterColor.presets, id: \.hex) { preset in
                Label { Text(preset.name) } icon: { Image(nsImage: MeterColor.swatch(preset.color)) }
                    .tag(preset.hex.uppercased())
            }
            if !isPreset { Text("Custom").tag("custom") }
        }
        ColorPicker("Custom Colour", selection: Binding(
            get: { Color(nsColor: MeterColor.color(fromHex: model.current.colorHex) ?? .systemGreen) },
            set: { model.setColor(NSColor($0)) }), supportsOpacity: false)
    }
}

/// The icons side by side, each drawn as it would be in the menu bar now,
/// its name under it; the chosen one is outlined in the accent colour.
/// Not StatusItemKit's `IconTilePicker`: that one draws each image at its own
/// size on a dark tile, where these scale the bar drawing up to fill the tile
/// (Major Pane's pixel art stays crisp, `.interpolation(.none)`) and share the
/// row's width on a light or dark fill that follows the window.
struct IconTiles: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PreferencesModel.icons, id: \.choice) { icon in
                let chosen = model.current.icon == icon.choice
                Button { model.setIcon(icon.choice) } label: {
                    VStack(spacing: 6) {
                        Group {
                            if let image = model.current.previews[icon.choice] {
                                Image(nsImage: image)
                                    .resizable()
                                    .interpolation(.none)
                                    .aspectRatio(contentMode: .fit)
                            }
                        }
                        .frame(width: 44, height: 30)
                        Text(icon.title)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(chosen ? .primary : .secondary)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(chosen ? 0.10 : 0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(chosen ? Color.accentColor : Color.clear, lineWidth: 2))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(icon.title)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
    }
}

struct ShortcutsPreferencesView: View {
    @ObservedObject var model: BindingsModel
    @ObservedObject var recorder: RecorderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 6) {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    if action.group > 0, WindowAction.allCases.first(where: { $0.group == action.group }) == action {
                        Divider().padding(.vertical, 2)
                    }
                    row(action)
                }
            }
            Divider()
            HStack(alignment: .top) {
                Text("Panes takes these keys before any app sees them, but only when there is a window to act on; "
                     + "otherwise they pass through. Press Esc while recording to cancel.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Reset All") { model.resetAll() }
            }
        }
        .padding(20)
        .onDisappear { recorder.cancel() }
    }

    @ViewBuilder
    private func row(_ action: WindowAction) -> some View {
        let conflicts = model.conflicts(action)
        HStack(spacing: 10) {
            Text(action.label).frame(width: 110, alignment: .leading)
            if !conflicts.isEmpty {
                Text("also \(conflicts.map(\.label).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Spacer()
            Text(model.trigger(for: action).map(TriggerFormatter.string) ?? "—")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(minWidth: 80, alignment: .trailing)
            Button(recorder.recording == action ? "Press keys…" : "Record") {
                if recorder.recording == action { recorder.cancel() } else { recorder.record(action) }
            }
            .frame(width: 96)
            Button("Reset") { model.reset(action) }
                .disabled(!model.isOverridden(action))
        }
    }
}

extension PreferencesModel {
    /// The window, from StatusItemKit's `PreferencesPane`: re-read the values
    /// each time it is shown, stop recording a shortcut when it closes.
    func makePane() -> PreferencesPane {
        let pane = PreferencesPane(appName: "Panes") { [self] in PreferencesView(model: self) }
        pane.onShow = { [weak self] in self?.refresh() }
        pane.onClose = { [weak self] in self?.recorder.cancel() }
        return pane
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import HotkeyKit
import PanesCore
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

struct PreferencesView: View {
    @ObservedObject var model: BindingsModel
    @ObservedObject var recorder: RecorderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Window Shortcuts").font(.headline)
            VStack(spacing: 6) {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    if action.group > 0, WindowAction.allCases.first(where: { $0.group == action.group }) == action {
                        Divider().padding(.vertical, 2)
                    }
                    row(action)
                }
            }
            Divider()
            Text("Cell Keys").font(.headline)
            HStack(spacing: 10) {
                Picker("Hold", selection: $model.chordModifier) {
                    ForEach(ChordModifier.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .frame(width: 150)
                Text("+ 1–8, 9, A, B, D–H, then let go")
                    .foregroundColor(.secondary)
            }
            if let warning = model.chordModifier.warning {
                Text(warning).font(.caption).foregroundColor(.secondary)
            }
            Text("One key fills that cell of the grid; two keys fill the rectangle between them "
                 + "(1 then 8 is the top half). Cells are 1 2 3 4 / 5 6 7 8 / 9 A B D / E F G H; C stays Center. "
                 + "Hold ⌥⌘ in the open menu to split its grid into half-cells.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        .frame(width: 500)
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

final class PreferencesWindowController {
    private var window: NSWindow?
    private let model: BindingsModel
    private lazy var recorder = RecorderModel(bindings: model)

    init(model: BindingsModel) { self.model = model }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: PreferencesView(model: model, recorder: recorder))
            let win = NSWindow(contentViewController: host)
            win.title = "Panes Preferences"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            window = win
            win.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    var windowNumber: Int? { window?.windowNumber }
}

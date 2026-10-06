// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import HotkeyKit
import PanesCore

/// Cell-key chords: hold the chord modifiers (⌥⌘ by default), press one or
/// two cell keys (1–8, 9, A, B, D–H), let go, and the front window fills that cell
/// or the rectangle spanning both. A HUD previews the target while held.
///
/// Its own `CGEventTap` rather than HotkeyKit's: a chord ends on a modifier
/// *release*, and `HotkeyTap` listens to keyDown, keyUp and media keys only,
/// never `flagsChanged`. The decisions are `ChordLogic`'s (PanesCore).
final class ChordTap {
    var chord: ChordModifier = .default
    /// When true (Preferences is recording a shortcut), every key passes.
    var isSuspended: () -> Bool = { false }
    /// Keys bound to a window shortcut with the chord's own modifiers; they
    /// fire as shortcuts and never start a chord.
    var reservedKeys: (ChordModifier) -> Set<CGKeyCode> = { _ in [] }
    /// Fills the selection on `window`.
    var onFinish: (AXWindow, GridSelection, Display) -> Void = { _, _, _ in }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var cells = CellChord()
    private var target: (window: AXWindow, display: Display)?
    private var swallowedKeys: Set<CGKeyCode> = []
    private let hud = SnapOverlay()

    var isRunning: Bool { tap != nil }
    /// A chord is being typed (re-creating the tap now would drop it).
    var isBusy: Bool { !cells.isEmpty }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<ChordTap>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
        }, userInfo: refcon) else { return false }
        tap = port
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        cancel()
    }

    private func cancel() {
        cells = CellChord()
        target = nil
        hud.hide()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let held = Modifiers(cgFlags: event.flags)

        switch type {
        case .keyUp:
            return swallowedKeys.remove(code) != nil ? nil : pass
        case .flagsChanged:
            if ChordLogic.flagsChanged(held: held, chord: chord, active: !cells.isEmpty) == .finish { finish() }
            return pass
        case .keyDown:
            guard !isSuspended() else { return pass }
            switch ChordLogic.keyDown(code, held: held, chord: chord, active: !cells.isEmpty,
                                     reserved: reservedKeys(chord)) {
            case .pass(let cancelling):
                if cancelling { cancel() }
                return pass
            case .add(let cell):
                // The window is fixed at the first key; with none to arrange,
                // the key is not ours (the app keeps its own ⌥⌘D, ⌥⌘H).
                if target == nil {
                    guard let window = AXWindow.focused(), let frame = window.frame,
                          let i = Screens.displays.index(for: frame) else { return pass }
                    target = (window, Screens.displays[i])
                }
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { cells.press(cell) }
                swallowedKeys.insert(code)
                preview()
                return nil
            case .finish:
                return pass
            }
        default:
            return pass
        }
    }

    private func preview() {
        guard let target, let s = cells.selection else { return }
        hud.show(axFrame: LayoutGrid().frame(for: s, in: target.display.visibleFrame))
    }

    private func finish() {
        defer { cancel() }
        guard let target, let s = cells.selection else { return }
        let t = target
        DispatchQueue.main.async { [onFinish] in onFinish(t.window, s, t.display) }
    }
}

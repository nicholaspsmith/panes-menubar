// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
import CoreGraphics
import HotkeyKit
@testable import PanesCore

final class BindingsTests: XCTestCase {
    private let cmdOpt: Modifiers = [.command, .option]

    func testEveryActionHasOneDefault() {
        XCTAssertEqual(BindingStore.defaults.map(\.token), WindowAction.allCases.map(\.rawValue))
    }

    func testDefaultShortcuts() {
        let byToken = Dictionary(uniqueKeysWithValues: BindingStore.defaults.map { ($0.token, $0.trigger) })
        func t(_ a: WindowAction) -> Trigger? { byToken[a.rawValue] }
        XCTAssertEqual(t(.leftHalf), .key(123, cmdOpt))
        XCTAssertEqual(t(.rightHalf), .key(124, cmdOpt))
        XCTAssertEqual(t(.topHalf), .key(126, cmdOpt))
        XCTAssertEqual(t(.bottomHalf), .key(125, cmdOpt))
        XCTAssertEqual(t(.topLeft), .key(33, cmdOpt))      // [
        XCTAssertEqual(t(.topRight), .key(30, cmdOpt))     // ]
        XCTAssertEqual(t(.bottomLeft), .key(41, cmdOpt))   // ;
        XCTAssertEqual(t(.bottomRight), .key(39, cmdOpt))  // '
        XCTAssertEqual(t(.maximize), .key(46, cmdOpt))     // M
        XCTAssertEqual(t(.center), .key(8, cmdOpt))        // C
        XCTAssertEqual(t(.restore), .key(51, cmdOpt))      // ⌫
        XCTAssertEqual(t(.nextDisplay), .key(45, [.command, .option]))
    }

    func testDefaultsDoNotConflict() {
        for b in BindingStore.defaults {
            XCTAssertEqual(BindingStore.conflicts(for: b.token, in: BindingStore.defaults), [], b.token)
        }
    }

    func testOverrideReplacesOnlyItsAction() {
        let r = BindingStore.resolve(overrides: [WindowAction.center.rawValue: .key(8, [.control, .option])])
        XCTAssertEqual(r.first { $0.token == WindowAction.center.rawValue }?.trigger, .key(8, [.control, .option]))
        XCTAssertEqual(r.first { $0.token == WindowAction.maximize.rawValue }?.trigger, .key(46, cmdOpt))
    }

    func testUnknownOverrideIgnored() {
        XCTAssertEqual(BindingStore.resolve(overrides: ["nope": .key(0, [])]), BindingStore.defaults)
    }

    /// What the tap sees for a key press with these flags (HotkeyKit drops
    /// the fn flag macOS sets on every arrow event).
    private func event(_ code: CGKeyCode, _ flags: CGEventFlags) -> EventSignature {
        EventSignature(kind: .key(code), modifiers: Modifiers(cgFlags: flags, keyCode: code))
    }

    func testArrowShortcutsMatchWithOrWithoutTheImpliedFn() {
        let defaults = BindingStore.defaults
        for flags: CGEventFlags in [[.maskCommand, .maskAlternate], [.maskCommand, .maskAlternate, .maskSecondaryFn]] {
            XCTAssertEqual(defaults.first { $0.matches(event(123, flags)) }?.token, WindowAction.leftHalf.rawValue)
            XCTAssertEqual(defaults.first { $0.matches(event(124, flags)) }?.token, WindowAction.rightHalf.rawValue)
            XCTAssertEqual(defaults.first { $0.matches(event(126, flags)) }?.token, WindowAction.topHalf.rawValue)
            XCTAssertEqual(defaults.first { $0.matches(event(125, flags)) }?.token, WindowAction.bottomHalf.rawValue)
        }
        let fnM = event(46, [.maskCommand, .maskAlternate, .maskSecondaryFn])
        XCTAssertNil(defaults.first { $0.matches(fnM) }, "fn+⌘⌥M is a different chord")
    }

    func testRecordedArrowOverrideMatchesWithTheImpliedFn() {
        // TriggerRecorder goes through the same Modifiers(cgFlags:keyCode:), so a
        // recorded ⌃⌥← carries no fn and the tap's ⌃⌥fn← event matches it.
        let recorded = Trigger.key(123, Modifiers(cgFlags: [.maskControl, .maskAlternate, .maskSecondaryFn], keyCode: 123))
        XCTAssertEqual(recorded, .key(123, [.control, .option]))
        let r = BindingStore.resolve(overrides: [WindowAction.leftHalf.rawValue: recorded])
        XCTAssertEqual(r.first { $0.matches(event(123, [.maskControl, .maskAlternate, .maskSecondaryFn])) }?.token,
                       WindowAction.leftHalf.rawValue)
    }

    func testNextDisplayDoesNotFireLeftOrRightHalf() {
        let sig = EventSignature(kind: .key(45), modifiers: [.command, .option])
        XCTAssertEqual(BindingStore.defaults.first { $0.matches(sig) }?.token, WindowAction.nextDisplay.rawValue)
    }

    func testConflictsReported() {
        let r = BindingStore.resolve(overrides: [WindowAction.center.rawValue: .key(46, cmdOpt)])
        XCTAssertEqual(BindingStore.conflicts(for: WindowAction.center.rawValue, in: r), [.maximize])
        XCTAssertEqual(BindingStore.conflicts(for: WindowAction.maximize.rawValue, in: r), [.center])
    }

    func testBindingsDoNotRepeat() {
        XCTAssertTrue(BindingStore.defaults.allSatisfy { !$0.repeatsOnHold })
    }
}

final class TriggerFormatterTests: XCTestCase {
    func testDefaultsRender() {
        XCTAssertEqual(TriggerFormatter.string(.key(123, [.command, .option])), "⌥⌘←")
        XCTAssertEqual(TriggerFormatter.string(.key(124, [.command, .option, .control])), "⌃⌥⌘→")
        XCTAssertEqual(TriggerFormatter.string(.key(32, [.command, .option])), "⌥⌘U")
        XCTAssertEqual(TriggerFormatter.string(.key(51, [.command, .option])), "⌥⌘⌫")
    }

    func testRecordedArrowShowsNoFn() {
        let recorded = Trigger.key(126, Modifiers(cgFlags: [.maskCommand, .maskAlternate, .maskSecondaryFn], keyCode: 126))
        XCTAssertEqual(TriggerFormatter.string(recorded), "⌥⌘↑")
        XCTAssertEqual(TriggerFormatter.string(.key(46, [.fn, .command])), "fn ⌘M")
    }

    func testUnknownKey() {
        XCTAssertEqual(TriggerFormatter.string(.key(200, [])), "Key 200")
    }

    func testMenuKeyEquivalents() {
        XCTAssertEqual(MenuKeyEquivalent.string(for: .key(123, [])), "\u{F702}")
        XCTAssertEqual(MenuKeyEquivalent.string(for: .key(124, [])), "\u{F703}")
        XCTAssertEqual(MenuKeyEquivalent.string(for: .key(125, [])), "\u{F701}")
        XCTAssertEqual(MenuKeyEquivalent.string(for: .key(126, [])), "\u{F700}")
        XCTAssertEqual(MenuKeyEquivalent.string(for: .key(32, [])), "u")
        XCTAssertEqual(MenuKeyEquivalent.string(for: .key(51, [])), "\u{8}")
        XCTAssertNil(MenuKeyEquivalent.string(for: .mediaKey(2, [])))
        XCTAssertNil(MenuKeyEquivalent.string(for: .key(200, [])))
    }
}

final class SystemTilingTests: XCTestCase {
    func testOffOnlyWhenBothKeysAreOff() {
        XCTAssertFalse(SystemTiling.isEdgeTilingOn(edge: 0, top: 0))
        XCTAssertFalse(SystemTiling.isEdgeTilingOn(edge: false, top: false))
        XCTAssertTrue(SystemTiling.isEdgeTilingOn(edge: 1, top: 0))
        XCTAssertTrue(SystemTiling.isEdgeTilingOn(edge: 0, top: true))
    }

    func testUnsetMeansTheMacOSDefaultOn() {
        XCTAssertTrue(SystemTiling.isEdgeTilingOn(edge: nil, top: 0))
        XCTAssertTrue(SystemTiling.isEdgeTilingOn(edge: 0, top: nil))
    }
}

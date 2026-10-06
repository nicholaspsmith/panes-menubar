// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
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
        XCTAssertEqual(t(.topLeft), .key(32, cmdOpt))      // U
        XCTAssertEqual(t(.topRight), .key(34, cmdOpt))     // I
        XCTAssertEqual(t(.bottomLeft), .key(38, cmdOpt))   // J
        XCTAssertEqual(t(.bottomRight), .key(40, cmdOpt))  // K
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

    func testOverrideIsNormalized() {
        let r = BindingStore.resolve(overrides: [WindowAction.leftHalf.rawValue: .key(123, [.control, .option, .fn])])
        XCTAssertEqual(r[0].trigger, .key(123, [.control, .option]))
    }

    func testArrowBindingsGetAnFnTwinForTheTap() {
        let tap = BindingStore.tapBindings(BindingStore.defaults)
        // The 4 arrow bindings (halves) gain a twin; the 8 letter/⌫ ones do not.
        XCTAssertEqual(tap.count, 12 + 4)
        let fnSig = EventSignature(kind: .key(123), modifiers: [.command, .option, .fn])
        let plainSig = EventSignature(kind: .key(123), modifiers: cmdOpt)
        XCTAssertEqual(tap.first { $0.matches(fnSig) }?.token, WindowAction.leftHalf.rawValue)
        XCTAssertEqual(tap.first { $0.matches(plainSig) }?.token, WindowAction.leftHalf.rawValue)
        let mSig = EventSignature(kind: .key(46), modifiers: [.command, .option, .fn])
        XCTAssertNil(tap.first { $0.matches(mSig) }, "fn+⌘⌥M is a different chord")
    }

    func testNextDisplayDoesNotFireLeftOrRightHalf() {
        let tap = BindingStore.tapBindings(BindingStore.defaults)
        let sig = EventSignature(kind: .key(45), modifiers: [.command, .option])
        XCTAssertEqual(tap.first { $0.matches(sig) }?.token, WindowAction.nextDisplay.rawValue)
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

    func testImpliedFnIsHidden() {
        XCTAssertEqual(TriggerFormatter.string(.key(126, [.command, .option, .fn])), "⌥⌘↑")
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

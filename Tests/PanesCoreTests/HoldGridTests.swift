// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
import HotkeyKit
@testable import PanesCore

final class HoldGridTests: XCTestCase {
    let cmdOpt: Modifiers = [.command, .option]

    private func shown() -> HoldGrid {
        var h = HoldGrid()
        _ = h.modifiers(cmdOpt, at: 10)
        _ = h.tick(at: 10.35)
        return h
    }

    func testHoldingAloneShowsAfterTheDelay() {
        var h = HoldGrid()
        XCTAssertEqual(h.modifiers([.command], at: 10), .none)
        XCTAssertEqual(h.modifiers(cmdOpt, at: 10.05), .arm(at: 10.4))
        XCTAssertEqual(h.tick(at: 10.4), .show)
        XCTAssertEqual(h.phase, .shown(fine: false))
    }

    func testEarlyTickReschedules() {
        var h = HoldGrid()
        _ = h.modifiers(cmdOpt, at: 10)
        XCTAssertEqual(h.tick(at: 10.1), .arm(at: 10.35))
    }

    func testQuickShortcutNeverShows() {
        var h = HoldGrid()
        _ = h.modifiers(cmdOpt, at: 10)
        XCTAssertEqual(h.keyDown(), .none)        // ⌥⌘← at 10.1
        XCTAssertEqual(h.tick(at: 10.35), .none)
        XCTAssertEqual(h.phase, .blocked)
        // Still holding ⌥⌘ after the shortcut: stays away until released.
        XCTAssertEqual(h.modifiers(cmdOpt, at: 11), .none)
        XCTAssertEqual(h.modifiers([], at: 11.1), .none)
        XCTAssertEqual(h.phase, .idle)
        XCTAssertEqual(h.modifiers(cmdOpt, at: 12), .arm(at: 12.35), "the next hold arms again")
    }

    func testReleasingBeforeTheDelayCancels() {
        var h = HoldGrid()
        _ = h.modifiers(cmdOpt, at: 10)
        XCTAssertEqual(h.modifiers([.command], at: 10.2), .none)
        XCTAssertEqual(h.tick(at: 10.35), .none)
        XCTAssertEqual(h.phase, .idle)
    }

    func testReleasingHides() {
        var h = shown()
        XCTAssertEqual(h.modifiers([.option], at: 11), .hide)
        XCTAssertEqual(h.phase, .idle)
    }

    func testAnyKeyHidesAndBlocks() {
        var h = shown()
        XCTAssertEqual(h.keyDown(), .hide)       // a cell key or a shortcut
        XCTAssertEqual(h.phase, .blocked)
        XCTAssertEqual(h.tick(at: 20), .none)
    }

    func testShiftSwitchesToHalfCellsAndBack() {
        var h = shown()
        XCTAssertEqual(h.modifiers([.command, .option, .shift], at: 11), .setFine(true))
        XCTAssertEqual(h.modifiers([.command, .option, .shift], at: 11.1), .none)
        XCTAssertEqual(h.modifiers(cmdOpt, at: 11.2), .setFine(false))
    }

    func testOtherModifierHidesWhileShown() {
        var h = shown()
        XCTAssertEqual(h.modifiers([.command, .option, .control], at: 11), .hide)
        XCTAssertEqual(h.phase, .blocked)
    }

    func testExtraModifierWhileArmingBlocks() {
        var h = HoldGrid()
        _ = h.modifiers(cmdOpt, at: 10)
        _ = h.modifiers([.command, .option, .control], at: 10.1)
        XCTAssertEqual(h.tick(at: 10.35), .none)
        XCTAssertEqual(h.phase, .blocked)
    }

    func testHoldingCommandOptionShiftFromTheStartShowsHalfCells() {
        var h = HoldGrid()
        _ = h.modifiers([.command], at: 10)
        _ = h.modifiers([.command, .shift], at: 10.02)
        XCTAssertEqual(h.modifiers([.command, .option, .shift], at: 10.05), .arm(at: 10.4))
        XCTAssertEqual(h.tick(at: 10.4), .show)
        XCTAssertEqual(h.phase, .shown(fine: true))
        XCTAssertEqual(h.modifiers(cmdOpt, at: 11), .setFine(false), "letting go of ⇧ is 4×4")
        XCTAssertEqual(h.modifiers([.option, .shift], at: 11.2), .hide, "letting go of ⌘ hides")
    }

    func testShiftDuringTheDelayDecidesTheResolution() {
        var h = HoldGrid()
        _ = h.modifiers(cmdOpt, at: 10)
        XCTAssertEqual(h.modifiers([.command, .option, .shift], at: 10.1), .none, "keeps the same deadline")
        XCTAssertTrue(h.phase.isFine)
        XCTAssertEqual(h.tick(at: 10.35), .show)
        XCTAssertEqual(h.phase, .shown(fine: true))
    }

    func testCommandShiftAloneIsNotOurs() {
        var h = HoldGrid()
        XCTAssertEqual(h.modifiers([.command, .shift], at: 10), .none)
        XCTAssertEqual(h.phase, .idle)
    }

    func testStartingWithAnotherModifierDoesNotArm() {
        var h = HoldGrid()
        XCTAssertEqual(h.modifiers([.command, .option, .control], at: 10), .none)
        XCTAssertEqual(h.modifiers(cmdOpt, at: 10.1), .none, "dropping ⌃ leaves ⌥⌘, but this hold is spent")
    }

    func testMouseButtonDownBlocks() {
        var h = HoldGrid()
        XCTAssertEqual(h.modifiers(cmdOpt, at: 10, mouseDown: true), .none)
        XCTAssertEqual(h.phase, .blocked)
        var h2 = HoldGrid()
        _ = h2.modifiers(cmdOpt, at: 10)
        XCTAssertEqual(h2.tick(at: 10.35, mouseDown: true), .none)
        XCTAssertEqual(h2.phase, .blocked)
    }

    func testNoWindowNoGrid() {
        var h = HoldGrid()
        _ = h.modifiers(cmdOpt, at: 10)
        XCTAssertEqual(h.tick(at: 10.35, canShow: false), .none)
        XCTAssertEqual(h.phase, .blocked)
    }

    func testFnIsIgnored() {
        var h = HoldGrid()
        XCTAssertEqual(h.modifiers([.command, .option, .fn], at: 10), .arm(at: 10.35))
    }

    func testPickingACellDismisses() {
        var h = shown()
        XCTAssertEqual(h.dismissed(), .hide)
        XCTAssertEqual(h.phase, .blocked)
        XCTAssertEqual(h.dismissed(), .none)
    }

    func testDelayIsClamped() {
        XCTAssertEqual(HoldGrid(delay: 0).delay, 0.2)
        XCTAssertEqual(HoldGrid(delay: 5).delay, 1.0)
        XCTAssertEqual(HoldGrid().delay, 0.35)
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
import HotkeyKit
@testable import PanesCore

final class CellKeysTests: XCTestCase {
    func testLabelsRowMajor() {
        XCTAssertEqual(CellKeys.label(for: GridCell(column: 0, row: 0)), "1")
        XCTAssertEqual(CellKeys.label(for: GridCell(column: 3, row: 1)), "8")
        XCTAssertEqual(CellKeys.label(for: GridCell(column: 0, row: 2)), "9")
        XCTAssertEqual(CellKeys.label(for: GridCell(column: 1, row: 2)), "A")
        XCTAssertEqual(CellKeys.label(for: GridCell(column: 3, row: 2)), "D", "C is skipped")
        XCTAssertEqual(CellKeys.label(for: GridCell(column: 0, row: 3)), "E")
        XCTAssertEqual(CellKeys.label(for: GridCell(column: 3, row: 3)), "H")
        XCTAssertEqual(CellKeys.labels.joined(), "12345678" + "9ABDEFGH")
    }

    func testFineGridHasNoLabels() {
        XCTAssertNil(CellKeys.label(for: GridCell(column: 0, row: 0), in: .fine))
    }

    func testNoDefaultShortcutKeyIsACellKey() {
        // C (center), U I J K (quarters), M (maximize), ⌫ and the arrows fire at once.
        for b in BindingStore.defaults {
            guard case let .key(code, _) = b.trigger else { continue }
            XCTAssertNil(CellKeys.cell(forKeyCode: code), b.token)
        }
    }

    func testKeyCodesMapToTheirLabelledCell() {
        for (i, code) in CellKeys.keyCodes.enumerated() {
            let cell = CellKeys.cell(forKeyCode: code)!
            XCTAssertEqual(CellKeys.label(for: cell), CellKeys.labels[i])
            // The keycode's own name is the label.
            XCTAssertEqual(TriggerFormatter.keyName(code), CellKeys.labels[i])
        }
        XCTAssertNil(CellKeys.cell(forKeyCode: 46))   // M is not a cell
        XCTAssertNil(CellKeys.cell(forKeyCode: 8))    // nor C
    }
}

final class CellChordTests: XCTestCase {
    private func cell(_ label: String) -> GridCell {
        CellKeys.cell(forKeyCode: CellKeys.keyCodes[CellKeys.labels.firstIndex(of: label)!])!
    }

    func testEmptyChordSelectsNothing() {
        XCTAssertNil(CellChord().selection)
    }

    func testOneKeyFillsThatCell() {
        var c = CellChord(); c.press(cell("6"))
        XCTAssertEqual(c.selection, GridSelection(GridCell(column: 1, row: 1), GridCell(column: 1, row: 1)))
    }

    func testOneThenEightIsTopHalf() {
        var c = CellChord(); c.press(cell("1")); c.press(cell("8"))
        let v = CGRect(x: 0, y: 25, width: 1440, height: 815)
        XCTAssertEqual(LayoutGrid().frame(for: c.selection!, in: v),
                       FrameCalculator.frame(for: .topHalf, window: .zero, visible: v))
    }

    func testOrderDoesNotMatter() {
        var a = CellChord(); a.press(cell("H")); a.press(cell("6"))
        var b = CellChord(); b.press(cell("6")); b.press(cell("H"))
        XCTAssertEqual(a.selection, b.selection)
    }

    func testMoreThanTwoUsesFirstAndLast() {
        var c = CellChord(); c.press(cell("1")); c.press(cell("H")); c.press(cell("E"))
        XCTAssertEqual(c.selection, GridSelection(cell("1"), cell("E")), "left column")
    }
}

final class ChordLogicTests: XCTestCase {
    let cmdShift: Modifiers = [.command, .option]

    func testCellKeyWithChordHeldIsAdded() {
        XCTAssertEqual(ChordLogic.keyDown(18, held: cmdShift, chord: .commandOption, active: false),
                       .add(GridCell(column: 0, row: 0)))
    }

    func testWrongModifiersPass() {
        XCTAssertEqual(ChordLogic.keyDown(18, held: [.command], chord: .commandOption, active: false), .pass(cancel: false))
        XCTAssertEqual(ChordLogic.keyDown(18, held: [.command, .shift, .option], chord: .commandOption, active: false),
                       .pass(cancel: false))
    }

    func testNonCellKeyCancelsAChordInProgress() {
        XCTAssertEqual(ChordLogic.keyDown(46, held: cmdShift, chord: .commandOption, active: true), .pass(cancel: true))
        XCTAssertEqual(ChordLogic.keyDown(46, held: cmdShift, chord: .commandOption, active: false), .pass(cancel: false))
    }

    func testReleasingEitherModifierFinishes() {
        XCTAssertEqual(ChordLogic.flagsChanged(held: [.command], chord: .commandOption, active: true), .finish)
        XCTAssertEqual(ChordLogic.flagsChanged(held: [], chord: .commandOption, active: true), .finish)
        XCTAssertEqual(ChordLogic.flagsChanged(held: cmdShift, chord: .commandOption, active: true), .pass(cancel: false))
        XCTAssertEqual(ChordLogic.flagsChanged(held: [], chord: .commandOption, active: false), .pass(cancel: false))
    }

    func testAlternativeModifiers() {
        XCTAssertEqual(ChordModifier.controlOption.modifiers, [.control, .option])
        XCTAssertEqual(ChordLogic.keyDown(4, held: [.control, .option], chord: .controlOption, active: false),
                       .add(GridCell(column: 3, row: 3)))
        XCTAssertEqual(ChordLogic.keyDown(4, held: cmdShift, chord: .controlOption, active: false), .pass(cancel: false))
        XCTAssertEqual(ChordModifier.commandShift.label, "⇧⌘")
    }

    func testDefaultIsCommandOption() {
        XCTAssertEqual(ChordModifier.default, .commandOption)
        XCTAssertEqual(ChordModifier.default.modifiers, [.command, .option])
        XCTAssertTrue(ChordModifier.commandShift.warning!.contains("screenshot"))
        XCTAssertNil(ChordModifier.controlOption.warning)
    }

    func testArrowWithImpliedFnCancelsChordAndPasses() {
        XCTAssertEqual(ChordLogic.keyDown(123, held: [.command, .option, .fn], chord: .commandOption, active: true),
                       .pass(cancel: true))
    }

    func testReservedKeyNeverStartsAChord() {
        // Maximize rebound to ⌥⌘1: it fires as a shortcut, not cell 1.
        let bindings = BindingStore.resolve(overrides: [WindowAction.maximize.rawValue: .key(18, [.command, .option])])
        let reserved = ChordLogic.reservedKeys(bindings, chord: .commandOption)
        XCTAssertTrue(reserved.contains(18))
        XCTAssertTrue(reserved.contains(123), "arrows are bound with ⌥⌘ (fn ignored)")
        XCTAssertFalse(reserved.contains(124 + 100))
        XCTAssertEqual(ChordLogic.keyDown(18, held: [.command, .option], chord: .commandOption, active: true, reserved: reserved),
                       .pass(cancel: true))
        XCTAssertEqual(ChordLogic.keyDown(19, held: [.command, .option], chord: .commandOption, active: false, reserved: reserved),
                       .add(GridCell(column: 1, row: 0)))
        // Every default is on ⌥⌘, so a ⌃⌥⌘ chord reserves nothing.
        XCTAssertEqual(ChordLogic.reservedKeys(BindingStore.defaults, chord: .controlOptionCommand), [])
    }

    func testChordModifiersDoNotShadowDefaultBindings() {
        // ⌃⌥⌘ + cell key never collides with ⌃⌥⌘→ (arrows are not cell keys).
        for b in BindingStore.defaults {
            guard case let .key(code, mods) = b.trigger else { continue }
            for chord in ChordModifier.allCases where chord.modifiers == mods {
                XCTAssertNil(CellKeys.cell(forKeyCode: code), "\(b.token) vs \(chord)")
            }
        }
    }
}

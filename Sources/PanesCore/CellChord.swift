// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics
import HotkeyKit

/// The keys that name the 16 cells of the 4×4 grid, row-major from the
/// top-left:
///
///     1 2 3 4
///     5 6 7 8
///     9 A B D
///     E F G H
///
/// C is skipped: ⌥⌘C is Center. None of the quarter keys ([ ] ; ') or M is a
/// cell key either, so every default ⌥⌘ shortcut still fires at once.
public enum CellKeys {
    public static let labels: [String] = ["1", "2", "3", "4", "5", "6", "7", "8",
                                          "9", "A", "B", "D", "E", "F", "G", "H"]
    /// ANSI keycodes, in the same order as `labels`.
    public static let keyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28,
                                               25, 0, 11, 2, 14, 3, 5, 4]

    /// Cell keys name the cells of the standard 4×4 grid only.
    public static let grid = LayoutGrid()

    public static func cell(forKeyCode code: CGKeyCode) -> GridCell? {
        guard let i = keyCodes.firstIndex(of: code) else { return nil }
        return GridCell(column: i % grid.columns, row: i / grid.columns)
    }

    /// The key for a cell of `inGrid`, or nil when that grid has no keys
    /// (the menu's fine 8×8 grid).
    public static func label(for cell: GridCell, in inGrid: LayoutGrid = LayoutGrid()) -> String? {
        guard inGrid == grid else { return nil }
        let i = cell.row * grid.columns + cell.column
        return labels.indices.contains(i) ? labels[i] : nil
    }
}

/// The modifiers held to type cell keys: ⌥⌘ by default, the same as the
/// other window shortcuts. A chord only starts on a cell key, so ⌥⌘ plus an
/// arrow, [ ] ; ', M, C or ⌫ still acts at once.
public enum ChordModifier: String, CaseIterable, Sendable {
    case commandOption
    case controlOption
    case controlOptionCommand
    case commandShift

    public static let `default` = ChordModifier.commandOption

    public var modifiers: Modifiers {
        switch self {
        case .commandOption: return [.command, .option]
        case .commandShift: return [.command, .shift]
        case .controlOption: return [.control, .option]
        case .controlOptionCommand: return [.control, .option, .command]
        }
    }

    public var label: String { TriggerFormatter.modifierString(modifiers) }

    /// A one-line note on the well-known shortcuts a choice takes over.
    public var warning: String? {
        switch self {
        case .commandOption: return "Takes over ⌥⌘D (Dock hiding) and ⌥⌘H (Hide Others)."
        case .commandShift: return "Takes over the screenshot shortcuts ⇧⌘3, ⇧⌘4 and ⇧⌘5."
        default: return nil
        }
    }
}

/// The cell keys pressed while the chord modifier is held. One key fills
/// that cell; two or more span the first and the last, in any order.
public struct CellChord: Equatable, Sendable {
    public private(set) var cells: [GridCell] = []

    public init() {}

    public mutating func press(_ cell: GridCell) { cells.append(cell) }

    public var isEmpty: Bool { cells.isEmpty }

    /// The rectangle to fill, or nil when no key was pressed.
    public var selection: GridSelection? {
        guard let first = cells.first, let last = cells.last else { return nil }
        return GridSelection(first, last)
    }
}

/// What the chord tap should do with one event, decided from the held
/// modifiers alone. Pure, so the state machine is tested without real keys.
public enum ChordStep: Equatable, Sendable {
    /// Not ours: let it through (and drop any chord in progress if `cancel`).
    case pass(cancel: Bool)
    /// A cell key with the chord held: swallow it and add the cell.
    case add(GridCell)
    /// The chord modifiers were let go: fill the chord's rectangle.
    case finish
}

public enum ChordLogic {
    /// A key press with `held` modifiers. `reserved` are keys bound to a
    /// window shortcut with exactly the chord modifiers (a rebinding onto a
    /// cell key, say): those fire as shortcuts, never start a chord, and
    /// cancel one in progress — like every other key.
    public static func keyDown(_ code: CGKeyCode, held: Modifiers, chord: ChordModifier, active: Bool,
                               reserved: Set<CGKeyCode> = []) -> ChordStep {
        guard held.subtracting(.fn) == chord.modifiers, !reserved.contains(code),
              let cell = CellKeys.cell(forKeyCode: code) else {
            return .pass(cancel: active)
        }
        return .add(cell)
    }

    /// The keys bound (in `bindings`) with exactly the chord's modifiers.
    public static func reservedKeys(_ bindings: [Binding], chord: ChordModifier) -> Set<CGKeyCode> {
        Set(bindings.compactMap {
            guard case let .key(code, mods) = $0.trigger, mods.subtracting(.fn) == chord.modifiers else { return nil }
            return code
        })
    }

    /// A modifier change. The chord ends as soon as any of its modifiers is up.
    public static func flagsChanged(held: Modifiers, chord: ChordModifier, active: Bool) -> ChordStep {
        guard active else { return .pass(cancel: false) }
        return held.isSuperset(of: chord.modifiers) ? .pass(cancel: false) : .finish
    }
}

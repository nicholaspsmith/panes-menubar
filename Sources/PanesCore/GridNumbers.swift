// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

/// The numbers shown on the grid on hold ⌥⌘: every cell numbered from 1 in
/// upper-case hex, row-major from the top-left (1–10 on the 4×4 grid, 1–40
/// on the 8×8 one). Only a guide to the grid; no key types them.
public enum GridNumbers {
    public static func label(for cell: GridCell, in grid: LayoutGrid) -> String? {
        guard (0..<grid.columns).contains(cell.column), (0..<grid.rows).contains(cell.row) else { return nil }
        return String(cell.row * grid.columns + cell.column + 1, radix: 16, uppercase: true)
    }
}

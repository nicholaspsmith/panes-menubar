// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// One cell of the menu's layout grid. Column 0 is the left, row 0 the top.
public struct GridCell: Hashable, Sendable {
    public let column: Int
    public let row: Int
    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

/// A rectangular run of cells, from any two corners (the cell a drag started
/// in and the one it is over now, in either order).
public struct GridSelection: Equatable, Sendable {
    public let columns: ClosedRange<Int>
    public let rows: ClosedRange<Int>

    public init(_ a: GridCell, _ b: GridCell) {
        columns = min(a.column, b.column)...max(a.column, b.column)
        rows = min(a.row, b.row)...max(a.row, b.row)
    }

    public func contains(_ cell: GridCell) -> Bool {
        columns.contains(cell.column) && rows.contains(cell.row)
    }
}

/// The layout grid: a display's visible frame cut into `columns` × `rows`
/// cells. Cell edges sit on whole points and the last column/row ends exactly
/// on the visible frame's far edge, so adjacent selections tile with no gap.
/// Rects are AX coordinates (row 0 has the smallest y).
public struct LayoutGrid: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int = 4, rows: Int = 4) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }

    /// The fine grid, shown while ⌥⌘⇧ is held (in the menu and on the
    /// overlay): each 4×4 cell split
    /// into its own 2×2. Its edges fall on the 4×4 grid's edges exactly.
    public static let fine = LayoutGrid(columns: 8, rows: 8)

    public var cells: [GridCell] {
        (0..<rows).flatMap { r in (0..<columns).map { GridCell(column: $0, row: r) } }
    }

    /// The window frame for a selection inside `visible`.
    public func frame(for s: GridSelection, in visible: CGRect) -> CGRect {
        let v = visible.integral
        let x0 = edge(s.columns.lowerBound, of: columns, from: v.minX, length: v.width)
        let x1 = edge(s.columns.upperBound + 1, of: columns, from: v.minX, length: v.width)
        let y0 = edge(s.rows.lowerBound, of: rows, from: v.minY, length: v.height)
        let y1 = edge(s.rows.upperBound + 1, of: rows, from: v.minY, length: v.height)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func frame(for cell: GridCell, in visible: CGRect) -> CGRect {
        frame(for: GridSelection(cell, cell), in: visible)
    }

    /// The cells a window covers: those at least half under it. Half, so a
    /// window tiled to a grid boundary fills exactly its cells and a window a
    /// few points off still reads as filling them.
    public func cells(coveredBy window: CGRect, in visible: CGRect) -> Set<GridCell> {
        Set(cells.filter { cell in
            let c = frame(for: cell, in: visible)
            let overlap = c.intersection(window)
            guard !overlap.isNull, c.width > 0, c.height > 0 else { return false }
            return overlap.width * overlap.height >= 0.5 * c.width * c.height
        })
    }

    /// The cell under a point in a view of `size` drawn with row 0 at the
    /// **top** (pass a flipped y for an unflipped AppKit view). Points
    /// outside the view are clamped onto its edge cells, so a drag that
    /// strays past the grid keeps extending the selection.
    public func cell(at point: CGPoint, in size: CGSize) -> GridCell {
        guard size.width > 0, size.height > 0 else { return GridCell(column: 0, row: 0) }
        let c = Int((point.x / size.width * CGFloat(columns)).rounded(.down))
        let r = Int((point.y / size.height * CGFloat(rows)).rounded(.down))
        return GridCell(column: min(max(c, 0), columns - 1), row: min(max(r, 0), rows - 1))
    }

    private func edge(_ i: Int, of n: Int, from origin: CGFloat, length: CGFloat) -> CGFloat {
        i >= n ? origin + length : origin + (length * CGFloat(i) / CGFloat(n)).rounded(.down)
    }
}

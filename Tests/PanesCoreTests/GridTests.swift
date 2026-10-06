// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class GridTests: XCTestCase {
    let grid = LayoutGrid()
    let v = primaryVisible   // 1440×815 at y 25

    private func sel(_ c0: Int, _ r0: Int, _ c1: Int, _ r1: Int) -> GridSelection {
        GridSelection(GridCell(column: c0, row: r0), GridCell(column: c1, row: r1))
    }

    func testSixteenCells() {
        XCTAssertEqual(grid.cells.count, 16)
        XCTAssertEqual(grid.cells.first, GridCell(column: 0, row: 0))
        XCTAssertEqual(grid.cells.last, GridCell(column: 3, row: 3))
    }

    func testSingleCellIsAQuarterByAQuarter() {
        XCTAssertEqual(grid.frame(for: GridCell(column: 0, row: 0), in: v), CGRect(x: 0, y: 25, width: 360, height: 203))
        XCTAssertEqual(grid.frame(for: GridCell(column: 3, row: 3), in: v), CGRect(x: 1080, y: 636, width: 360, height: 204))
    }

    func testDragFromTopLeftDownTwoColumnsIsLeftHalf() {
        XCTAssertEqual(grid.frame(for: sel(0, 0, 1, 3), in: v),
                       FrameCalculator.frame(for: .leftHalf, window: .zero, visible: v))
    }

    func testSelectionInEitherDirection() {
        XCTAssertEqual(sel(3, 3, 2, 0), sel(2, 0, 3, 3))
        XCTAssertEqual(grid.frame(for: sel(3, 3, 2, 0), in: v),
                       FrameCalculator.frame(for: .rightHalf, window: .zero, visible: v))
    }

    func testWholeGridIsMaximize() {
        XCTAssertEqual(grid.frame(for: sel(0, 0, 3, 3), in: v), v)
    }

    func testCellsTileWithNoGapsOnOddSizes() {
        let odd = CGRect(x: -1513, y: -37, width: 1513, height: 947)
        for r in 0..<4 {
            for c in 0..<3 {
                let a = grid.frame(for: GridCell(column: c, row: r), in: odd)
                let b = grid.frame(for: GridCell(column: c + 1, row: r), in: odd)
                XCTAssertEqual(a.maxX, b.minX)
            }
        }
        XCTAssertEqual(grid.frame(for: GridCell(column: 3, row: 3), in: odd).maxX, odd.maxX)
        XCTAssertEqual(grid.frame(for: GridCell(column: 3, row: 3), in: odd).maxY, odd.maxY)
    }

    func testCoveredCellsOfATiledWindow() {
        let left = grid.frame(for: sel(0, 0, 1, 3), in: v)
        let covered = grid.cells(coveredBy: left, in: v)
        XCTAssertEqual(covered.count, 8)
        XCTAssertTrue(covered.allSatisfy { $0.column <= 1 })
    }

    func testCoveredCellsNeedHalfACell() {
        // Covers all of column 0 and 40% of column 1.
        let w = CGRect(x: 0, y: 25, width: 360 + 144, height: 203)
        XCTAssertEqual(grid.cells(coveredBy: w, in: v), [GridCell(column: 0, row: 0)])
        // 60% of column 1 counts.
        let w2 = CGRect(x: 0, y: 25, width: 360 + 216, height: 203)
        XCTAssertEqual(grid.cells(coveredBy: w2, in: v), [GridCell(column: 0, row: 0), GridCell(column: 1, row: 0)])
    }

    func testWindowOffTheDisplayCoversNothing() {
        XCTAssertTrue(grid.cells(coveredBy: CGRect(x: 2000, y: 0, width: 500, height: 500), in: v).isEmpty)
    }

    func testCellAtPoint() {
        let size = CGSize(width: 200, height: 120)
        XCTAssertEqual(grid.cell(at: CGPoint(x: 1, y: 1), in: size), GridCell(column: 0, row: 0))
        XCTAssertEqual(grid.cell(at: CGPoint(x: 199, y: 119), in: size), GridCell(column: 3, row: 3))
        XCTAssertEqual(grid.cell(at: CGPoint(x: 100, y: 59), in: size), GridCell(column: 2, row: 1))
        // Outside the view: clamped onto the edge cells.
        XCTAssertEqual(grid.cell(at: CGPoint(x: -40, y: 500), in: size), GridCell(column: 0, row: 3))
    }
}

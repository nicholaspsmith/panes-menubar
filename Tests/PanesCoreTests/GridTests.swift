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

    // MARK: The fine 8×8 grid

    func testFineGridHasSixtyFourCells() {
        XCTAssertEqual(LayoutGrid.fine.cells.count, 64)
    }

    func testFineTwoByTwoIsExactlyOneCoarseCell() {
        let odd = CGRect(x: -1513, y: -37, width: 1513, height: 947)
        for coarse in grid.cells {
            let fineSel = GridSelection(GridCell(column: coarse.column * 2, row: coarse.row * 2),
                                        GridCell(column: coarse.column * 2 + 1, row: coarse.row * 2 + 1))
            XCTAssertEqual(LayoutGrid.fine.frame(for: fineSel, in: odd), grid.frame(for: coarse, in: odd), "\(coarse)")
        }
    }

    func testFineHalfCell() {
        XCTAssertEqual(LayoutGrid.fine.frame(for: GridCell(column: 0, row: 0), in: v), CGRect(x: 0, y: 25, width: 180, height: 101))
        XCTAssertEqual(LayoutGrid.fine.frame(for: GridCell(column: 7, row: 7), in: v).maxX, v.maxX)
    }

    func testFineDragAcrossHalfCells() {
        // Three half-cells wide, one tall, from the top-left.
        let s = GridSelection(GridCell(column: 0, row: 0), GridCell(column: 2, row: 0))
        XCTAssertEqual(LayoutGrid.fine.frame(for: s, in: v), CGRect(x: 0, y: 25, width: 540, height: 101))
    }

    func testFineCellAtPoint() {
        let size = CGSize(width: 200, height: 120)
        XCTAssertEqual(LayoutGrid.fine.cell(at: CGPoint(x: 26, y: 16), in: size), GridCell(column: 1, row: 1))
        XCTAssertEqual(LayoutGrid.fine.cell(at: CGPoint(x: 199, y: 119), in: size), GridCell(column: 7, row: 7))
    }

    func testFineShadingOfALeftHalfWindow() {
        let left = FrameCalculator.frame(for: .leftHalf, window: .zero, visible: v)!
        let covered = LayoutGrid.fine.cells(coveredBy: left, in: v)
        XCTAssertEqual(covered.count, 32)
        XCTAssertTrue(covered.allSatisfy { $0.column <= 3 })
    }

    func testFineShadingOfAWindowThatFitsHalfCells() {
        // A window 3/8 wide, 1/8 tall in the top-left: shaded at 8×8, not at 4×4 (it covers only 3/4 of cell 1's width, half its height).
        let w = CGRect(x: 0, y: 25, width: 540, height: 101)
        XCTAssertEqual(LayoutGrid.fine.cells(coveredBy: w, in: v).count, 3)
        XCTAssertEqual(grid.cells(coveredBy: w, in: v), [], "under half of any 4×4 cell")
    }
}

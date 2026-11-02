// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class GridNumbersTests: XCTestCase {
    private func labels(_ grid: LayoutGrid) -> [String] {
        grid.cells.compactMap { GridNumbers.label(for: $0, in: grid) }
    }

    func testFourByFourCountsStraightThroughInHex() {
        XCTAssertEqual(labels(LayoutGrid()).joined(separator: " "),
                       "1 2 3 4 5 6 7 8 9 A B C D E F 10", "no letter skipped")
        XCTAssertEqual(GridNumbers.label(for: GridCell(column: 3, row: 2), in: LayoutGrid()), "C")
    }

    func testHalfCellsNumberedInHexRowMajor() {
        let fine = LayoutGrid.fine
        XCTAssertEqual(GridNumbers.label(for: GridCell(column: 0, row: 0), in: fine), "1")
        XCTAssertEqual(GridNumbers.label(for: GridCell(column: 7, row: 0), in: fine), "8")
        XCTAssertEqual(GridNumbers.label(for: GridCell(column: 0, row: 1), in: fine), "9")
        XCTAssertEqual(GridNumbers.label(for: GridCell(column: 1, row: 1), in: fine), "A")
        XCTAssertEqual(GridNumbers.label(for: GridCell(column: 7, row: 1), in: fine), "10")
        XCTAssertEqual(GridNumbers.label(for: GridCell(column: 2, row: 3), in: fine), "1B", "upper case")
        XCTAssertEqual(GridNumbers.label(for: GridCell(column: 7, row: 7), in: fine), "40")
        XCTAssertEqual(Set(labels(fine)).count, 64, "every half-cell has its own number")
    }

    func testCellsOutsideTheGridHaveNoNumber() {
        XCTAssertNil(GridNumbers.label(for: GridCell(column: 4, row: 0), in: LayoutGrid()))
        XCTAssertNil(GridNumbers.label(for: GridCell(column: 0, row: 8), in: .fine))
    }
}

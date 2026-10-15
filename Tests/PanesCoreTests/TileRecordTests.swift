// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class TileRecordTests: XCTestCase {
    // The display the rule was measured on, in AX coordinates.
    let fill = CGRect(x: 0, y: 30, width: 2560, height: 983)
    let left = CGRect(x: 0, y: 30, width: 1280, height: 983)
    let right = CGRect(x: 1280, y: 30, width: 1280, height: 983)

    func testAMoveInsideTheTileCanKeepIt() {
        // Both kept macOS's record, which then put the window back.
        XCTAssertTrue(TileRecord.canOutlive(moveFrom: fill, to: left))
        XCTAssertTrue(TileRecord.canOutlive(moveFrom: left, to: CGRect(x: 0, y: 30, width: 1280, height: 491)))
        XCTAssertTrue(TileRecord.canOutlive(moveFrom: fill, to: CGRect(x: 300, y: 150, width: 700, height: 450)))
    }

    func testAMoveOutOfTheTileCannot() {
        XCTAssertFalse(TileRecord.canOutlive(moveFrom: left, to: right))
        // Another display.
        XCTAssertFalse(TileRecord.canOutlive(moveFrom: fill, to: CGRect(x: 2560, y: 0, width: 1920, height: 1050)))
        // Centre growing past the window.
        XCTAssertFalse(TileRecord.canOutlive(moveFrom: CGRect(x: 640, y: 276, width: 1280, height: 491), to: CGRect(x: 427, y: 194, width: 1707, height: 655)))
    }

    func testAWindowALittleOffItsTileStillCounts() {
        // Read back a point short, or sized in steps a few points inside the tile.
        XCTAssertTrue(TileRecord.canOutlive(moveFrom: CGRect(x: 0, y: 30, width: 1280, height: 982), to: left))
        XCTAssertTrue(TileRecord.canOutlive(moveFrom: CGRect(x: 0, y: 30, width: 1274, height: 970), to: CGRect(x: 0, y: 30, width: 1280, height: 491)))
        XCTAssertFalse(TileRecord.canOutlive(moveFrom: left, to: left.insetBy(dx: -40, dy: 0)))
    }
}

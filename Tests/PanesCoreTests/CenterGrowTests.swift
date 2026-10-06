// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class CenterGrowTests: XCTestCase {
    let v = CGRect(x: 0, y: 0, width: 1200, height: 900)

    func testFirstPressCentersAtCurrentSize() {
        let w = CGRect(x: 10, y: 10, width: 300, height: 200)
        XCTAssertEqual(CenterGrow.target(window: w, visible: v, lastPlaced: nil),
                       CGRect(x: 450, y: 350, width: 300, height: 200))
    }

    func testMovedSinceLastPlacedCentersAgainInsteadOfGrowing() {
        let w = CGRect(x: 10, y: 10, width: 300, height: 200)
        let elsewhere = CGRect(x: 450, y: 350, width: 300, height: 200)
        XCTAssertEqual(CenterGrow.target(window: w, visible: v, lastPlaced: elsewhere).size, w.size)
    }

    func testGrowsThroughEveryStep() {
        var w = CGRect(x: 450, y: 350, width: 300, height: 200)
        var sizes: [CGSize] = []
        for _ in 0..<5 {
            let t = CenterGrow.target(window: w, visible: v, lastPlaced: w)
            sizes.append(t.size)
            XCTAssertEqual(t.midX, v.midX, accuracy: 1)
            XCTAssertEqual(t.midY, v.midY, accuracy: 1)
            w = t
        }
        XCTAssertEqual(sizes, [CGSize(width: 600, height: 450), CGSize(width: 800, height: 600),
                               CGSize(width: 960, height: 720), CGSize(width: 1200, height: 900),
                               CGSize(width: 1200, height: 900)], "at full it stays")
    }

    func testSkipsStepsNotLargerInBothDimensions() {
        // 700 wide is already wider than 50% (600): skip to 66%.
        let w = CGRect(x: 250, y: 300, width: 700, height: 300)
        XCTAssertEqual(CenterGrow.target(window: w, visible: v, lastPlaced: w).size, CGSize(width: 800, height: 600))
        // Taller than 80%: straight to full.
        let tall = CGRect(x: 500, y: 50, width: 200, height: 800)
        XCTAssertEqual(CenterGrow.target(window: tall, visible: v, lastPlaced: tall), v)
    }

    func testSmallDriftStillCountsAsWherePanesLeftIt() {
        let placed = CGRect(x: 450, y: 350, width: 300, height: 200)
        let drifted = CGRect(x: 452, y: 351, width: 297, height: 199)  // a terminal rounding to cells
        XCTAssertEqual(CenterGrow.target(window: drifted, visible: v, lastPlaced: placed).size, CGSize(width: 600, height: 450))
        let moved = CGRect(x: 470, y: 350, width: 300, height: 200)
        XCTAssertEqual(CenterGrow.target(window: moved, visible: v, lastPlaced: placed).size, moved.size)
    }

    func testOnDisplayLeftOfPrimary() {
        let lv = CGRect(x: -1920, y: 25, width: 1920, height: 1055)
        let w = FrameCalculator.centered(CGSize(width: 400, height: 300), in: lv)
        let t = CenterGrow.target(window: w, visible: lv, lastPlaced: w)
        XCTAssertEqual(t.size, CGSize(width: 960, height: 528))
        XCTAssertEqual(t.midX, lv.midX, accuracy: 1)
    }
}

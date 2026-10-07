// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class ArrowTilingTests: XCTestCase {
    let v = CGRect(x: 0, y: 30, width: 2560, height: 960)

    private func press(_ a: WindowAction, _ w: CGRect) -> CGRect { ArrowTiling.frame(for: a, window: w, visible: v)! }

    func testUntiledWindowGetsHalves() {
        let w = CGRect(x: 300, y: 200, width: 900, height: 500)
        XCTAssertEqual(press(.leftHalf, w), CGRect(x: 0, y: 30, width: 1280, height: 960))
        XCTAssertEqual(press(.topHalf, w), CGRect(x: 0, y: 30, width: 2560, height: 480))
    }

    func testLeftThenUpIsTopLeftQuarter() {
        let left = press(.leftHalf, CGRect(x: 300, y: 200, width: 900, height: 500))
        XCTAssertEqual(press(.topHalf, left), CGRect(x: 0, y: 30, width: 1280, height: 480))
        XCTAssertEqual(press(.bottomHalf, left), CGRect(x: 0, y: 510, width: 1280, height: 480))
    }

    func testWalkingAroundTheQuarters() {
        let tl = CGRect(x: 0, y: 30, width: 1280, height: 480)
        let tr = press(.rightHalf, tl)
        XCTAssertEqual(tr, CGRect(x: 1280, y: 30, width: 1280, height: 480))
        let br = press(.bottomHalf, tr)
        XCTAssertEqual(br, CGRect(x: 1280, y: 510, width: 1280, height: 480))
        XCTAssertEqual(press(.leftHalf, br), CGRect(x: 0, y: 510, width: 1280, height: 480))
    }

    func testTopHalfThenSideIsQuarter() {
        let top = CGRect(x: 0, y: 30, width: 2560, height: 480)
        XCTAssertEqual(press(.rightHalf, top), CGRect(x: 1280, y: 30, width: 1280, height: 480))
    }

    func testSmallRoundingStillCountsAsATile() {
        // A terminal rounding its left half to whole cells.
        let left = CGRect(x: 0, y: 32, width: 1274, height: 955)
        XCTAssertEqual(press(.topHalf, left), CGRect(x: 0, y: 30, width: 1280, height: 480))
    }

    func testPressingTowardTheSideItIsOnWidensToThatHalf() {
        let tr = CGRect(x: 1280, y: 30, width: 1280, height: 480)
        XCTAssertEqual(press(.rightHalf, tr), CGRect(x: 1280, y: 30, width: 1280, height: 960))
        XCTAssertEqual(press(.topHalf, tr), CGRect(x: 0, y: 30, width: 2560, height: 480))
        let bl = CGRect(x: 0, y: 510, width: 1280, height: 480)
        XCTAssertEqual(press(.leftHalf, bl), CGRect(x: 0, y: 30, width: 1280, height: 960))
        XCTAssertEqual(press(.bottomHalf, bl), CGRect(x: 0, y: 510, width: 2560, height: 480))
        // Already the right half: stays the right half.
        let right = CGRect(x: 1280, y: 30, width: 1280, height: 960)
        XCTAssertEqual(press(.rightHalf, right), right)
    }

    func testMinimumSizeWindowStillCountsAsItsQuarter() {
        // Nick's case: a window that won't go below 548 tall, put in the
        // bottom-left quarter of a 978-tall area, sits 548 tall against the bottom.
        let vis = CGRect(x: 0, y: 30, width: 2560, height: 978)
        let bl = CGRect(x: 0, y: 460, width: 1280, height: 548)
        XCTAssertEqual(ArrowTiling.frame(for: .bottomHalf, window: bl, visible: vis),
                       CGRect(x: 0, y: 519, width: 2560, height: 489))
        XCTAssertEqual(ArrowTiling.frame(for: .leftHalf, window: bl, visible: vis),
                       CGRect(x: 0, y: 30, width: 1280, height: 978))
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class CenterToggleTests: XCTestCase {
    let v = CGRect(x: 0, y: 30, width: 2560, height: 959)
    let column = CGRect(x: 640, y: 30, width: 1280, height: 959)
    let box = CGRect(x: 640, y: 190, width: 1280, height: 639)

    private func press(_ window: CGRect) -> CGRect { CenterToggle.next(window: window, visible: v) }

    func testFirstPressIsAFullHeightColumnAtHalfTheWidth() {
        XCTAssertEqual(press(CGRect(x: 0, y: 30, width: 1280, height: 959)), column)   // left half
        XCTAssertEqual(press(CGRect(x: 100, y: 100, width: 700, height: 400)), column)
        XCTAssertEqual(press(v), column)                                                  // maximized
    }

    func testSecondPressCentresItVerticallyAtTwoThirdsHeight() {
        XCTAssertEqual(press(column), box)
        XCTAssertEqual(box.midX, v.midX, accuracy: 1)
        XCTAssertEqual(box.midY, v.midY, accuracy: 1)
    }

    func testPressesAlternate() {
        var w = CGRect(x: 100, y: 100, width: 700, height: 400)
        var seen: [CGRect] = []
        for _ in 0..<4 { w = press(w); seen.append(w) }
        XCTAssertEqual(seen, [column, box, column, box])
    }

    func testAColumnTheAppRoundedStillCountsAsTheColumn() {
        // A terminal sizes to whole lines and columns.
        XCTAssertEqual(press(CGRect(x: 640, y: 30, width: 1274, height: 945)), box)
        // Moved off it by more than that: the column again.
        XCTAssertEqual(press(column.offsetBy(dx: 40, dy: 0)), column)
    }
}

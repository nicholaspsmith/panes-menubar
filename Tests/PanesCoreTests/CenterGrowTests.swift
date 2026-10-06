// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class CenterGrowTests: XCTestCase {
    let v = CGRect(x: 0, y: 30, width: 2560, height: 959)

    private func press(_ window: CGRect, _ last: CenterGrow.State?) -> CenterGrow.State {
        CenterGrow.next(window: window, visible: v, last: last)
    }

    func testFirstPressCentresAtScreenRatioNearestStep() {
        // A left half (50% wide, full height) has the area of a ~71% box: nearest is 66%.
        let s = press(CGRect(x: 0, y: 30, width: 1280, height: 959), nil)
        XCTAssertEqual(s.step, 1)
        XCTAssertEqual(s.frame.size, CGSize(width: 1707, height: 639))
        XCTAssertEqual(s.frame.midX, v.midX, accuracy: 1)
        XCTAssertEqual(s.frame.midY, v.midY, accuracy: 1)
        XCTAssertEqual(s.frame.width / s.frame.height, v.width / v.height, accuracy: 0.01)
    }

    func testPressesBounceUpAndDownForever() {
        var s = press(CGRect(x: 100, y: 100, width: 1280, height: 480), nil)   // 50%
        XCTAssertEqual(s.step, 0)
        var seen = [s.step]
        for _ in 0..<9 { s = press(s.frame, s); seen.append(s.step) }
        XCTAssertEqual(seen, [0, 1, 2, 3, 2, 1, 0, 1, 2, 3])
        XCTAssertEqual(CenterGrow.frame(for: 3, in: v), v)
    }

    func testFullScreenWindowStartsGoingDown() {
        let s = press(v, nil)
        XCTAssertEqual(s.step, 3)
        XCTAssertFalse(s.growing)
        XCTAssertEqual(press(s.frame, s).step, 2)
    }

    func testMovedInBetweenStartsOver() {
        let s = press(CGRect(x: 100, y: 100, width: 1280, height: 480), nil)
        let moved = s.frame.offsetBy(dx: 40, dy: 0)
        XCTAssertEqual(press(moved, s).step, 0)   // nearest again, not the next step
    }

    func testSmallDriftStillCountsAsTheSamePlace() {
        let s = press(CGRect(x: 100, y: 100, width: 1280, height: 480), nil)
        let drifted = s.frame.insetBy(dx: 1.5, dy: 1)
        XCTAssertEqual(press(drifted, s).step, 1)
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class FrameSettleTests: XCTestCase {
    let a = CGRect(x: 0, y: 30, width: 2560, height: 983)
    func moved(_ i: Int) -> CGRect { a.insetBy(dx: CGFloat(i), dy: CGFloat(i)) }

    func testAStillFrameIsNotSettledBeforeTheMinimum() {
        // macOS starts its untile animation a few ms after the press: a frame that
        // has not moved yet has not necessarily finished.
        var s = FrameSettle()
        XCTAssertFalse(s.isSettled(frame: a, elapsed: 0))
        XCTAssertFalse(s.isSettled(frame: a, elapsed: 0.03))
        XCTAssertFalse(s.isSettled(frame: a, elapsed: 0.12))
        XCTAssertTrue(s.isSettled(frame: a, elapsed: FrameSettle.minimum))
    }

    func testAMovingFrameIsWaitedOut() {
        var s = FrameSettle()
        for i in 0..<14 { XCTAssertFalse(s.isSettled(frame: moved(i), elapsed: Double(i) * 0.03), "sample \(i)") }
        XCTAssertTrue(s.isSettled(frame: moved(13), elapsed: 14 * 0.03))
    }

    func testOneUnchangedPairAfterTheMinimumIsEnough() {
        var s = FrameSettle()
        XCTAssertFalse(s.isSettled(frame: moved(1), elapsed: 0.18))
        XCTAssertFalse(s.isSettled(frame: moved(2), elapsed: 0.21))
        XCTAssertTrue(s.isSettled(frame: moved(2), elapsed: 0.24))
    }

    func testTheTimeoutEndsTheWait() {
        var s = FrameSettle()
        XCTAssertFalse(s.isSettled(frame: moved(1), elapsed: FrameSettle.timeout - 0.01))
        XCTAssertTrue(s.isSettled(frame: moved(2), elapsed: FrameSettle.timeout))
    }

    func testAWindowThatStopsAnsweringEndsTheWait() {
        var s = FrameSettle()
        XCTAssertFalse(s.isSettled(frame: a, elapsed: 0))
        XCTAssertTrue(s.isSettled(frame: nil, elapsed: 0.03))
    }
}

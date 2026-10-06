// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class RestoreHistoryTests: XCTestCase {
    let a = CGRect(x: 10, y: 10, width: 100, height: 100)
    let b = CGRect(x: 20, y: 20, width: 200, height: 200)
    let c = CGRect(x: 30, y: 30, width: 300, height: 300)

    func testEmptyHistoryCannotRestore() {
        var h = RestoreHistory<Int>()
        XCTAssertFalse(h.canRestore(1))
        XCTAssertNil(h.pop(for: 1))
    }

    func testRestoreUndoesLastMoveThenTheOneBefore() {
        var h = RestoreHistory<Int>()
        h.record(a, for: 1)   // a → left half
        h.record(b, for: 1)   // left half (b) → maximize
        XCTAssertTrue(h.canRestore(1))
        XCTAssertEqual(h.pop(for: 1), b)
        XCTAssertEqual(h.pop(for: 1), a)
        XCTAssertNil(h.pop(for: 1))
        XCTAssertFalse(h.canRestore(1))
    }

    func testWindowsAreIndependent() {
        var h = RestoreHistory<Int>()
        h.record(a, for: 1)
        h.record(b, for: 2)
        XCTAssertEqual(h.pop(for: 1), a)
        XCTAssertEqual(h.pop(for: 2), b)
    }

    func testDuplicateFrameNotStoredTwice() {
        var h = RestoreHistory<Int>()
        h.record(a, for: 1)
        h.record(a, for: 1)
        XCTAssertEqual(h.pop(for: 1), a)
        XCTAssertNil(h.pop(for: 1))
    }

    func testDepthKeepsNewest() {
        var h = RestoreHistory<Int>(depth: 2)
        h.record(a, for: 1); h.record(b, for: 1); h.record(c, for: 1)
        XCTAssertEqual(h.pop(for: 1), c)
        XCTAssertEqual(h.pop(for: 1), b)
        XCTAssertNil(h.pop(for: 1))
    }

    func testCapacityEvictsLeastRecentlyTouchedWindow() {
        var h = RestoreHistory<Int>(capacity: 2)
        h.record(a, for: 1)
        h.record(a, for: 2)
        h.record(b, for: 1)   // 1 touched again; 2 is now the oldest
        h.record(a, for: 3)
        XCTAssertEqual(h.windowCount, 2)
        XCTAssertTrue(h.canRestore(1))
        XCTAssertFalse(h.canRestore(2))
        XCTAssertTrue(h.canRestore(3))
    }
}

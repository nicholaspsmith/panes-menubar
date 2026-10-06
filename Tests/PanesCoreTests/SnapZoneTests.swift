// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class SnapZoneTests: XCTestCase {
    private func hit(_ x: CGFloat, _ y: CGFloat, _ ds: [Display] = [Layouts.primary]) -> SnapZone.Hit? {
        SnapZone.detect(cursor: CGPoint(x: x, y: y), displays: ds)
    }

    func testMiddleOfScreenIsNoZone() {
        XCTAssertNil(hit(700, 400))
    }

    func testEdges() {
        XCTAssertEqual(hit(0, 400)?.action, .leftHalf)
        XCTAssertEqual(hit(1439, 400)?.action, .rightHalf)
        XCTAssertEqual(hit(700, 0)?.action, .maximize)
        XCTAssertNil(hit(700, 899), "the bottom edge snaps only at its corners")
    }

    func testMarginIsGenerousButNarrow() {
        XCTAssertEqual(hit(5, 400)?.action, .leftHalf)
        XCTAssertNil(hit(6, 400))
        XCTAssertEqual(hit(1434, 400)?.action, .rightHalf)
        XCTAssertNil(hit(1433, 400))
    }

    func testCorners() {
        XCTAssertEqual(hit(0, 10)?.action, .topLeft)
        XCTAssertEqual(hit(10, 0)?.action, .topLeft)
        XCTAssertEqual(hit(1439, 10)?.action, .topRight)
        XCTAssertEqual(hit(1430, 0)?.action, .topRight)
        XCTAssertEqual(hit(0, 890)?.action, .bottomLeft)
        XCTAssertEqual(hit(20, 899)?.action, .bottomLeft)
        XCTAssertEqual(hit(1439, 870)?.action, .bottomRight)
        XCTAssertEqual(hit(1420, 899)?.action, .bottomRight)
    }

    func testCursorJustOutsideDisplayIsPulledOntoIt() {
        // Cocoa's top row can come back as y = height, i.e. AX y = -1 … 0.
        XCTAssertEqual(hit(700, -1)?.action, .maximize)
        XCTAssertEqual(hit(1440, 400)?.action, .rightHalf)
    }

    func testSharedEdgeWithDisplayToTheLeftDoesNotSnap() {
        let ds = [Layouts.primary, Layouts.left]
        XCTAssertNil(hit(0, 400, ds), "the cursor passes into the left display here")
        XCTAssertNil(hit(-1, 400, ds).map { $0.action == .rightHalf ? $0 : nil } ?? nil)
        // The left display's own outer left edge still snaps, on that display.
        XCTAssertEqual(hit(-1920, 400, ds), SnapZone.Hit(action: .leftHalf, displayIndex: 1))
        // Primary's right edge is outer.
        XCTAssertEqual(hit(1439, 400, ds), SnapZone.Hit(action: .rightHalf, displayIndex: 0))
    }

    func testSharedEdgeOnlyWhereDisplaysActuallyTouch() {
        // The left display is 1080 tall, the primary 900, top-aligned: below
        // y=900 the left display's right edge has nothing beside it.
        let ds = [Layouts.primary, Layouts.left]
        XCTAssertNil(hit(-1, 400, ds))
        XCTAssertEqual(hit(-1, 1000, ds), SnapZone.Hit(action: .rightHalf, displayIndex: 1))
    }

    func testDisplayAboveMakesPrimaryTopEdgeInner() {
        let ds = [Layouts.primary, Layouts.above]
        XCTAssertNil(hit(700, 0, ds), "the cursor passes up into the display above")
        // The display above: its own top edge maximizes there.
        XCTAssertEqual(hit(700, -1080, ds), SnapZone.Hit(action: .maximize, displayIndex: 1))
        // Its bottom edge is shared with the primary where they overlap (x < 1440)…
        XCTAssertNil(hit(20, -1, ds))
        // …but beyond the primary's right edge it is outer: bottom-right corner.
        XCTAssertEqual(hit(1900, -1, ds), SnapZone.Hit(action: .bottomRight, displayIndex: 1))
        // Primary's left edge stays a half even though its top is shared.
        XCTAssertEqual(hit(0, 400, ds)?.action, .leftHalf)
        XCTAssertEqual(hit(0, 10, ds)?.action, .topLeft, "left edge near the top is still the corner")
    }
}

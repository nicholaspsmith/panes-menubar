// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

/// Primary 1440×900 at the origin; a 1920×1080 display to its left and
/// another above it, as AX rects (y down).
enum Layouts {
    static let primary = Display(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                 visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 815))
    static let left = Display(frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                              visibleFrame: CGRect(x: -1920, y: 25, width: 1920, height: 1055))
    static let above = Display(frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080),
                               visibleFrame: CGRect(x: 0, y: -1055, width: 1920, height: 1055))
    static let right = Display(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                               visibleFrame: CGRect(x: 1440, y: 25, width: 1920, height: 1055))
}

final class CoordinatesTests: XCTestCase {
    func testPrimaryFlipsOntoItself() {
        let cocoa = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(Coordinates.flip(cocoa, primaryHeight: 900), cocoa)
    }

    func testVisibleFrameLosesMenuBarAtTop() {
        // Cocoa visibleFrame: Dock 60 at the bottom, menu bar 25 at the top.
        let cocoa = CGRect(x: 0, y: 60, width: 1440, height: 815)
        XCTAssertEqual(Coordinates.flip(cocoa, primaryHeight: 900), CGRect(x: 0, y: 25, width: 1440, height: 815))
    }

    func testDisplayAbovePrimaryHasNegativeY() {
        let cocoa = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        XCTAssertEqual(Coordinates.flip(cocoa, primaryHeight: 900), Layouts.above.frame)
    }

    func testDisplayLeftOfPrimaryKeepsNegativeX() {
        // Bottom-aligned with the primary in Cocoa: y = 0 there, 900 - 1080 = -180 here.
        let cocoa = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(Coordinates.flip(cocoa, primaryHeight: 900), CGRect(x: -1920, y: -180, width: 1920, height: 1080))
    }

    func testDisplayBelowPrimary() {
        let cocoa = CGRect(x: 200, y: -1080, width: 1920, height: 1080)
        XCTAssertEqual(Coordinates.flip(cocoa, primaryHeight: 900), CGRect(x: 200, y: 900, width: 1920, height: 1080))
    }

    func testFlipIsItsOwnInverse() {
        let r = CGRect(x: -300, y: 1234, width: 640, height: 480)
        XCTAssertEqual(Coordinates.flip(Coordinates.flip(r, primaryHeight: 982), primaryHeight: 982), r)
        let p = CGPoint(x: -5, y: 77)
        XCTAssertEqual(Coordinates.flip(Coordinates.flip(p, primaryHeight: 982), primaryHeight: 982), p)
    }

    func testCursorAtTopOfPrimary() {
        XCTAssertEqual(Coordinates.flip(CGPoint(x: 10, y: 900), primaryHeight: 900), CGPoint(x: 10, y: 0))
    }
}

final class DisplayLookupTests: XCTestCase {
    let displays = [Layouts.primary, Layouts.left, Layouts.above]

    func testWindowBelongsToDisplayWithMostOverlap() {
        let straddling = CGRect(x: -100, y: 100, width: 400, height: 300)   // mostly on primary
        XCTAssertEqual(displays.index(for: straddling), 0)
        let mostlyLeft = CGRect(x: -350, y: 100, width: 400, height: 300)
        XCTAssertEqual(displays.index(for: mostlyLeft), 1)
        let onAbove = CGRect(x: 100, y: -500, width: 400, height: 300)
        XCTAssertEqual(displays.index(for: onAbove), 2)
    }

    func testOffscreenWindowGoesToNearestDisplay() {
        let farBelow = CGRect(x: 500, y: 1350, width: 400, height: 300)
        XCTAssertEqual(displays.index(for: farBelow), 0)
        XCTAssertNil([Display]().index(for: farBelow))
    }

    func testNextDisplayCyclesLeftToRight() {
        let ds = [Layouts.primary, Layouts.left, Layouts.right]
        XCTAssertEqual(ds.next(after: 1), 0)   // left → primary
        XCTAssertEqual(ds.next(after: 0), 2)   // primary → right
        XCTAssertEqual(ds.next(after: 2), 1)   // right wraps to left
    }

    func testNextDisplayWithSameXOrdersTopToBottom() {
        let ds = [Layouts.primary, Layouts.above]
        XCTAssertEqual(ds.next(after: 1), 0)
        XCTAssertEqual(ds.next(after: 0), 1)
    }

    func testNoNextDisplayWithOne() {
        XCTAssertNil([Layouts.primary].next(after: 0))
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class WindowMapTests: XCTestCase {
    func testAppWindowsFilter() {
        let infos = [
            WindowInfo(bounds: CGRect(x: 0, y: 0, width: 800, height: 600), ownerPID: 10),
            WindowInfo(bounds: CGRect(x: 0, y: 0, width: 800, height: 600), ownerPID: 99),            // ours
            WindowInfo(bounds: CGRect(x: 0, y: 0, width: 800, height: 24), ownerPID: 11, layer: 25),  // status/menu layer
            WindowInfo(bounds: CGRect(x: 0, y: 0, width: 30, height: 30), ownerPID: 12),              // tiny
            WindowInfo(bounds: CGRect(x: 0, y: 0, width: 800, height: 600), ownerPID: 13, alpha: 0), // invisible
            WindowInfo(bounds: CGRect(x: 5, y: 5, width: 500, height: 400), ownerPID: 14),
        ]
        XCTAssertEqual(WindowMap.appWindows(infos, excludingPID: 99).map(\.ownerPID), [10, 14])
    }

    func testWindowsOnOtherDisplaysExcludedAndOrderReversed() {
        let displays = [Layouts.primary, Layouts.left]
        let front = CGRect(x: 100, y: 100, width: 400, height: 300)
        let back = CGRect(x: 300, y: 200, width: 400, height: 300)
        let onLeft = CGRect(x: -1500, y: 100, width: 400, height: 300)
        let r = WindowMap.windows([front, onLeft, back], on: 0, of: displays)
        XCTAssertEqual(r, [back, front], "back to front, the left display's window gone")
        XCTAssertEqual(WindowMap.windows([front, onLeft, back], on: 1, of: displays), [onLeft])
    }

    func testPartlyOffscreenWindowIsClipped() {
        let displays = [Layouts.primary]
        let hanging = CGRect(x: 1200, y: 700, width: 600, height: 400)
        XCTAssertEqual(WindowMap.windows([hanging], on: 0, of: displays), [CGRect(x: 1200, y: 700, width: 240, height: 200)])
    }

    func testStraddlingWindowBelongsToOneDisplayOnly() {
        let displays = [Layouts.primary, Layouts.left]
        let mostlyPrimary = CGRect(x: -100, y: 100, width: 500, height: 300)
        XCTAssertEqual(WindowMap.windows([mostlyPrimary], on: 0, of: displays), [CGRect(x: 0, y: 100, width: 400, height: 300)])
        XCTAssertEqual(WindowMap.windows([mostlyPrimary], on: 1, of: displays), [])
    }

    func testScaledFlipsYAndScales() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let target = CGRect(x: 2, y: 4, width: 16, height: 10)   // 1/90 scale
        let leftHalf = CGRect(x: 0, y: 0, width: 720, height: 900)
        let topHalf = CGRect(x: 0, y: 0, width: 1440, height: 450)
        let r = WindowMap.scaled([leftHalf, topHalf], display: display, into: target, scale: 2)
        XCTAssertEqual(r[0], CGRect(x: 2, y: 4, width: 8, height: 10))
        XCTAssertEqual(r[1], CGRect(x: 2, y: 9, width: 16, height: 5), "AX top half is the drawing's upper half")
    }

    func testScaledOnDisplayLeftOfPrimary() {
        let display = Layouts.left.frame   // x from -1920
        let target = CGRect(x: 0, y: 0, width: 19.2, height: 10.8)
        let w = CGRect(x: -1920, y: 0, width: 960, height: 1080)
        XCTAssertEqual(WindowMap.scaled([w], display: display, into: target, scale: 2), [CGRect(x: 0, y: 0, width: 9.5, height: 11)])
    }

    func testPixelAlignmentAt1xAnd2x() {
        let r = CGRect(x: 1.3, y: 2.74, width: 3.3, height: 0.1)
        let one = WindowMap.pixelAligned(r, scale: 1)
        XCTAssertEqual(one, CGRect(x: 1, y: 3, width: 4, height: 1), "a sliver keeps one pixel")
        let two = WindowMap.pixelAligned(r, scale: 2)
        XCTAssertEqual(two, CGRect(x: 1.5, y: 2.5, width: 3, height: 0.5))
        for v in [two.minX, two.minY, two.maxX, two.maxY] { XCTAssertEqual(v * 2, (v * 2).rounded()) }
    }

    func testOverlappingWindowsKeepTheirOwnRects() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let a = CGRect(x: 0, y: 0, width: 600, height: 600), b = CGRect(x: 400, y: 400, width: 600, height: 600)
        let r = WindowMap.scaled([a, b], display: display, into: CGRect(x: 0, y: 0, width: 20, height: 20), scale: 2)
        XCTAssertEqual(r[0], CGRect(x: 0, y: 8, width: 12, height: 12))
        XCTAssertEqual(r[1], CGRect(x: 8, y: 0, width: 12, height: 12))
        XCTAssertTrue(r[0].intersects(r[1]))
    }

    func testScreenRectKeepsAspect() {
        let r = WindowMap.screenRect(aspect: CGSize(width: 1600, height: 1000), in: CGRect(x: 0, y: 0, width: 30, height: 12), scale: 2)
        XCTAssertEqual(r.height, 12)
        XCTAssertEqual(r.width, 19, accuracy: 0.5)
        XCTAssertEqual(r.midX, 15, accuracy: 0.5)
    }

    func testSignatureChangesWithAnyMove() {
        let a = [CGRect(x: 0, y: 0, width: 10, height: 10)]
        XCTAssertEqual(WindowMap.signature(a), WindowMap.signature(a))
        XCTAssertNotEqual(WindowMap.signature(a), WindowMap.signature([CGRect(x: 1, y: 0, width: 10, height: 10)]))
        XCTAssertNotEqual(WindowMap.signature(a), WindowMap.signature(a + a))
    }
}

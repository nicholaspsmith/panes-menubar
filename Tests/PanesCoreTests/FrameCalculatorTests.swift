// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

/// A 1440×900 primary with a 25pt menu bar and a 60pt Dock.
let primaryVisible = CGRect(x: 0, y: 25, width: 1440, height: 815)

final class FrameCalculatorTests: XCTestCase {
    private let win = CGRect(x: 100, y: 100, width: 600, height: 400)

    private func f(_ a: WindowAction, _ v: CGRect = primaryVisible, window: CGRect? = nil) -> CGRect? {
        FrameCalculator.frame(for: a, window: window ?? win, visible: v)
    }

    func testHalves() {
        XCTAssertEqual(f(.leftHalf), CGRect(x: 0, y: 25, width: 720, height: 815))
        XCTAssertEqual(f(.rightHalf), CGRect(x: 720, y: 25, width: 720, height: 815))
        XCTAssertEqual(f(.topHalf), CGRect(x: 0, y: 25, width: 1440, height: 407))
        XCTAssertEqual(f(.bottomHalf), CGRect(x: 0, y: 432, width: 1440, height: 408))
    }

    func testQuarters() {
        XCTAssertEqual(f(.topLeft), CGRect(x: 0, y: 25, width: 720, height: 407))
        XCTAssertEqual(f(.topRight), CGRect(x: 720, y: 25, width: 720, height: 407))
        XCTAssertEqual(f(.bottomLeft), CGRect(x: 0, y: 432, width: 720, height: 408))
        XCTAssertEqual(f(.bottomRight), CGRect(x: 720, y: 432, width: 720, height: 408))
    }

    func testOddWidthHalvesTileExactly() {
        let v = CGRect(x: 0, y: 0, width: 1511, height: 945)
        let l = f(.leftHalf, v)!, r = f(.rightHalf, v)!
        XCTAssertEqual(l.maxX, r.minX)
        XCTAssertEqual(l.width + r.width, 1511)
        XCTAssertEqual(r.maxX, 1511)
    }

    func testMaximizeIsVisibleFrame() {
        XCTAssertEqual(f(.maximize), primaryVisible)
    }

    func testCenterKeepsSize() {
        XCTAssertEqual(f(.center), CGRect(x: 420, y: 232, width: 600, height: 400))
    }

    func testCenterShrinksOversizedWindow() {
        let big = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        XCTAssertEqual(f(.center, window: big), primaryVisible)
    }

    func testRestoreAndNextDisplayAreNotLayouts() {
        XCTAssertNil(f(.restore))
        XCTAssertNil(f(.nextDisplay))
        XCTAssertFalse(WindowAction.restore.isLayout)
        XCTAssertTrue(WindowAction.leftHalf.isLayout)
    }

    /// A display left of the primary has negative x in AX space.
    func testDisplayLeftOfPrimary() {
        let v = CGRect(x: -1920, y: 25, width: 1920, height: 1055)
        XCTAssertEqual(f(.leftHalf, v), CGRect(x: -1920, y: 25, width: 960, height: 1055))
        XCTAssertEqual(f(.rightHalf, v), CGRect(x: -960, y: 25, width: 960, height: 1055))
        XCTAssertEqual(f(.bottomRight, v), CGRect(x: -960, y: 552, width: 960, height: 528))
        XCTAssertEqual(f(.center, v), CGRect(x: -1260, y: 352, width: 600, height: 400))
    }

    /// A display above the primary has negative y in AX space; "top" is the
    /// more negative y.
    func testDisplayAbovePrimary() {
        let v = CGRect(x: 0, y: -1055, width: 1920, height: 1055)
        XCTAssertEqual(f(.topHalf, v), CGRect(x: 0, y: -1055, width: 1920, height: 527))
        XCTAssertEqual(f(.bottomHalf, v), CGRect(x: 0, y: -528, width: 1920, height: 528))
        XCTAssertEqual(f(.topRight, v), CGRect(x: 960, y: -1055, width: 960, height: 527))
        XCTAssertEqual(f(.maximize, v), v)
    }

    func testFractionalVisibleFrameIsMadeIntegral() {
        let v = CGRect(x: 0, y: 24.5, width: 1440, height: 815.5)
        let top = f(.topHalf, v)!
        XCTAssertEqual(top.minY, top.minY.rounded())
        XCTAssertEqual(top.height, top.height.rounded())
    }
}

final class NextDisplayTests: XCTestCase {
    func testLeftHalfStaysLeftHalfOnABiggerDisplay() {
        let src = primaryVisible
        let dst = CGRect(x: 1440, y: 25, width: 1920, height: 1055)
        let leftHalf = FrameCalculator.frame(for: .leftHalf, window: .zero, visible: src)!
        XCTAssertEqual(FrameCalculator.moved(leftHalf, from: src, to: dst),
                       CGRect(x: 1440, y: 25, width: 960, height: 1055))
    }

    func testRelativePositionOntoDisplayLeftOfPrimary() {
        let src = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let dst = CGRect(x: -2000, y: 0, width: 2000, height: 1000)
        let w = CGRect(x: 250, y: 100, width: 500, height: 400)
        XCTAssertEqual(FrameCalculator.moved(w, from: src, to: dst),
                       CGRect(x: -1500, y: 100, width: 1000, height: 400))
    }

    func testRelativePositionOntoDisplayAbovePrimary() {
        let src = CGRect(x: 0, y: 25, width: 1440, height: 815)
        let dst = CGRect(x: 0, y: -1055, width: 1920, height: 1055)
        let maxed = FrameCalculator.moved(src, from: src, to: dst)
        XCTAssertEqual(maxed, dst)
    }

    func testResultIsClampedInsideTarget() {
        let src = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let dst = CGRect(x: 1000, y: 0, width: 800, height: 600)
        // Hanging off the bottom-right of the source.
        let w = CGRect(x: 900, y: 900, width: 300, height: 300)
        let r = FrameCalculator.moved(w, from: src, to: dst)
        XCTAssertTrue(dst.contains(r), "\(r)")
    }

    func testClamp() {
        let b = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(FrameCalculator.clamp(CGRect(x: 90, y: -10, width: 20, height: 20), into: b),
                       CGRect(x: 80, y: 0, width: 20, height: 20))
        XCTAssertEqual(FrameCalculator.clamp(CGRect(x: 0, y: 0, width: 300, height: 50), into: b),
                       CGRect(x: 0, y: 0, width: 100, height: 50))
    }
}

final class FrameFitterTests: XCTestCase {
    let v = primaryVisible

    func testExactFitNeedsNoNudge() {
        let t = CGRect(x: 720, y: 25, width: 720, height: 815)
        XCTAssertNil(FrameFitter.nudgedOrigin(target: t, actual: t, visible: v))
    }

    func testTooWideRightHalfStaysFlushRight() {
        let t = CGRect(x: 720, y: 25, width: 720, height: 815)
        let a = CGRect(x: 720, y: 25, width: 800, height: 815)   // min width 800
        XCTAssertEqual(FrameFitter.nudgedOrigin(target: t, actual: a, visible: v), CGPoint(x: 640, y: 25))
    }

    func testTooTallBottomHalfStaysFlushBottom() {
        let t = CGRect(x: 0, y: 432, width: 1440, height: 408)
        let a = CGRect(x: 0, y: 432, width: 1440, height: 500)
        XCTAssertEqual(FrameFitter.nudgedOrigin(target: t, actual: a, visible: v), CGPoint(x: 0, y: 340))
    }

    func testSmallerThanTargetLeftHalfStaysAtLeftEdge() {
        // A terminal snapping to whole cells comes out a little short: already right.
        let t = CGRect(x: 0, y: 25, width: 720, height: 815)
        let a = CGRect(x: 0, y: 25, width: 714, height: 810)
        XCTAssertNil(FrameFitter.nudgedOrigin(target: t, actual: a, visible: v))
    }

    func testCenteredTargetKeepsCentre() {
        let t = CGRect(x: 420, y: 232, width: 600, height: 400)
        let a = CGRect(x: 420, y: 232, width: 700, height: 400)
        XCTAssertEqual(FrameFitter.nudgedOrigin(target: t, actual: a, visible: v), CGPoint(x: 370, y: 232))
    }

    func testWindowBiggerThanDisplayStartsAtNearEdge() {
        let t = CGRect(x: 720, y: 25, width: 720, height: 815)
        let a = CGRect(x: 720, y: 25, width: 1600, height: 815)
        XCTAssertEqual(FrameFitter.nudgedOrigin(target: t, actual: a, visible: v), CGPoint(x: 0, y: 25))
    }

    func testNudgeOnDisplayLeftOfPrimary() {
        let dv = CGRect(x: -1920, y: 25, width: 1920, height: 1055)
        let t = CGRect(x: -960, y: 25, width: 960, height: 1055)
        let a = CGRect(x: -960, y: 25, width: 1000, height: 1055)
        XCTAssertEqual(FrameFitter.nudgedOrigin(target: t, actual: a, visible: dv), CGPoint(x: -1000, y: 25))
    }
}

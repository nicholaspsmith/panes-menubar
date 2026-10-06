// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class FrameAnimationTests: XCTestCase {
    let a = CGRect(x: 0, y: 25, width: 600, height: 400)
    let b = CGRect(x: 720, y: 25, width: 720, height: 815)

    func testEaseOutEndpointsAndShape() {
        XCTAssertEqual(FrameAnimation.easeOut(0), 0)
        XCTAssertEqual(FrameAnimation.easeOut(1), 1)
        XCTAssertEqual(FrameAnimation.easeOut(-1), 0)
        XCTAssertEqual(FrameAnimation.easeOut(2), 1)
        // Ease-out: more than half-way at the half-way time, and monotonic.
        XCTAssertGreaterThan(FrameAnimation.easeOut(0.5), 0.8)
        var last = 0.0
        for i in 1...100 {
            let v = FrameAnimation.easeOut(Double(i) / 100)
            XCTAssertGreaterThanOrEqual(v, last)
            last = v
        }
    }

    func testStartsAtFromEndsExactlyAtTo() {
        let anim = FrameAnimation(from: a, to: b)
        XCTAssertEqual(anim.duration, 0.18)
        XCTAssertEqual(anim.frame(at: 0), a)
        XCTAssertEqual(anim.frame(at: 0.18), b)
        XCTAssertEqual(anim.frame(at: 5), b)
        XCTAssertTrue(anim.isFinished(at: 0.18))
        XCTAssertFalse(anim.isFinished(at: 0.1))
    }

    func testMidwayIsBetweenAndWholePoints() {
        let anim = FrameAnimation(from: a, to: b)
        let mid = anim.frame(at: 0.09)
        XCTAssertGreaterThan(mid.minX, a.minX)
        XCTAssertLessThan(mid.minX, b.minX)
        XCTAssertGreaterThan(mid.width, a.width)
        XCTAssertLessThan(mid.width, b.width)
        for v in [mid.minX, mid.minY, mid.width, mid.height] { XCTAssertEqual(v, v.rounded()) }
    }

    func testAcrossDisplaysWithNegativeCoordinates() {
        let left = CGRect(x: -1920, y: 25, width: 960, height: 1055)
        let anim = FrameAnimation(from: a, to: left)
        let mid = anim.frame(at: 0.05)
        XCTAssertLessThan(mid.minX, 0)
        XCTAssertGreaterThan(mid.minX, -1920)
    }

    func testZeroDurationJumps() {
        let anim = FrameAnimation(from: a, to: b, duration: 0)
        XCTAssertEqual(anim.frame(at: 0), b)
    }
}

final class AnimationPacingTests: XCTestCase {
    func testFastAppGetsDisplayRate() {
        XCTAssertEqual(AnimationPacing.stepInterval(setCost: 0.002, reduceMotion: false), 1.0 / 120)
        XCTAssertEqual(AnimationPacing.stepInterval(setCost: nil, reduceMotion: false), 1.0 / 120)
    }

    func testSlowAppGetsFewerSteps() {
        XCTAssertEqual(AnimationPacing.stepInterval(setCost: 0.03, reduceMotion: false), 0.03)
    }

    func testVerySlowAppJumps() {
        // 0.18 / 0.05 = 3.6 steps: under the four-step minimum.
        XCTAssertNil(AnimationPacing.stepInterval(setCost: 0.05, reduceMotion: false))
    }

    func testReduceMotionJumps() {
        XCTAssertNil(AnimationPacing.stepInterval(setCost: 0.001, reduceMotion: true))
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesGlyph

final class AnimatorTests: XCTestCase {
    func testLoopsOrHolds() {
        let loop = ClipTiming(fps: 4, loop: true, count: 4)
        XCTAssertEqual(Animator.frame(elapsed: 0, timing: loop).index, 0)
        XCTAssertEqual(Animator.frame(elapsed: 0.26, timing: loop).index, 1)
        XCTAssertEqual(Animator.frame(elapsed: 1.0, timing: loop).index, 0)
        XCTAssertFalse(Animator.frame(elapsed: 9, timing: loop).done)
        let once = ClipTiming(fps: 6, loop: false, count: 3)
        XCTAssertEqual(Animator.frame(elapsed: 0.2, timing: once).index, 1)
        XCTAssertFalse(Animator.frame(elapsed: 0.34, timing: once).done)
        XCTAssertEqual(Animator.frame(elapsed: 0.5, timing: once).index, 2)
        XCTAssertTrue(Animator.frame(elapsed: 0.5, timing: once).done)
    }

    func testOneFrameClipsAreDoneAtOnce() {
        XCTAssertTrue(Animator.frame(elapsed: 0, timing: ClipTiming(fps: 4, loop: false, count: 1)).done)
        XCTAssertFalse(Animator.frame(elapsed: 0, timing: ClipTiming(fps: 4, loop: true, count: 1)).done)
        XCTAssertNil(Animator.nextChange(elapsed: 0, timing: ClipTiming(fps: 4, loop: true, count: 1)))
    }

    func testNeverTrapsOnBadNumbers() {
        let once = ClipTiming(fps: 6, loop: false, count: 3)
        XCTAssertEqual(Animator.frame(elapsed: .infinity, timing: once).index, 2)
        XCTAssertTrue(Animator.frame(elapsed: 1e300, timing: once).done)
        XCTAssertEqual(Animator.frame(elapsed: .nan, timing: ClipTiming(fps: 6, loop: true, count: 3)).index, 0)
        XCTAssertEqual(Animator.frame(elapsed: -5, timing: once).index, 0)
        XCTAssertEqual(Animator.frame(elapsed: 1, timing: ClipTiming(fps: .infinity, loop: false, count: 3)).index, 2)
        XCTAssertNil(Animator.nextChange(elapsed: 1, timing: ClipTiming(fps: .infinity, loop: true, count: 3)))
    }

    func testNextChangeIsTheNextBoundaryAtTheClipsFps() {
        let loop = ClipTiming(fps: 4, loop: true, count: 2)
        XCTAssertEqual(Animator.nextChange(elapsed: 0, timing: loop)!, 0.25 + Animator.boundarySlack, accuracy: 1e-9)
        XCTAssertEqual(Animator.nextChange(elapsed: 0.1, timing: loop)!, 0.15 + Animator.boundarySlack, accuracy: 1e-9)
        XCTAssertEqual(Animator.nextChange(elapsed: 0.2499, timing: loop)!, Animator.minimumDelay, accuracy: 1e-9)
        let once = ClipTiming(fps: 4, loop: false, count: 2)
        XCTAssertEqual(Animator.nextChange(elapsed: 0.3, timing: once)!, 0.2 + Animator.boundarySlack, accuracy: 1e-9)
        XCTAssertNil(Animator.nextChange(elapsed: 0.6, timing: once))
    }
}

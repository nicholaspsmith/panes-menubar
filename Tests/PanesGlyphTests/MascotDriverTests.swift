// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesGlyph

final class MascotDriverTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    /// idle loops 2 frames at 4 fps (0.5 s); salute 4 frames at 8 fps (0.5 s); bark 2 frames at 8 fps (0.25 s); at_ease 2 at 2 fps.
    func timing(_ s: MascotState) -> ClipTiming {
        switch s {
        case .idle: return ClipTiming(fps: 4, loop: true, count: 2)
        case .salute: return ClipTiming(fps: 8, loop: false, count: 4)
        case .bark: return ClipTiming(fps: 8, loop: false, count: 2)
        case .atEase: return ClipTiming(fps: 2, loop: true, count: 2)
        }
    }
    func pose(_ d: inout MascotDriver, _ s: Double, reduce: Bool = false) -> (state: MascotState, frame: Int) {
        d.pose(now: at(s), timing: timing, reduceMotion: reduce)
    }

    func testIdleLoopsFromWhenItStarted() {
        var d = MascotDriver(now: t0)
        XCTAssertEqual(pose(&d, 0).state, .idle); XCTAssertEqual(pose(&d, 0).frame, 0)
        XCTAssertEqual(pose(&d, 0.3).frame, 1)
        XCTAssertEqual(pose(&d, 0.5).frame, 0)
    }

    func testSalutePlaysOnceThenIdleResumes() {
        var d = MascotDriver(now: t0)
        d.salute(now: at(1))
        XCTAssertEqual(pose(&d, 1).state, .salute); XCTAssertEqual(pose(&d, 1.3).frame, 2)
        XCTAssertEqual(pose(&d, 1.6).state, .idle)
        XCTAssertNil(d.playing)
    }

    func testACueDuringAnyOneShotIsSkipped() {
        var d = MascotDriver(now: t0)
        d.bark(now: at(1))
        d.salute(now: at(1.1))
        XCTAssertEqual(pose(&d, 1.1).state, .bark)
        XCTAssertEqual(pose(&d, 1.3).state, .idle)       // bark is 0.25 s; no salute follows
    }

    func testABarkDuringASaluteWaitsAndThenPlays() {
        var d = MascotDriver(now: t0)
        d.salute(now: at(1))
        d.bark(now: at(1.2))
        XCTAssertEqual(pose(&d, 1.2).state, .salute)
        XCTAssertTrue(d.pendingBark)
        XCTAssertEqual(pose(&d, 1.55).state, .bark)      // salute ended at 1.5
        XCTAssertFalse(d.pendingBark)
        XCTAssertEqual(pose(&d, 1.9).state, .idle)
    }

    func testOnlyOneBarkIsEverQueued() {
        var d = MascotDriver(now: t0)
        d.bark(now: at(1)); d.bark(now: at(1.05)); d.bark(now: at(1.1))
        XCTAssertEqual(pose(&d, 1.3).state, .bark)        // the queued one
        XCTAssertEqual(pose(&d, 1.6).state, .idle)        // and no third
    }

    func testAtEaseIsTheSteadyPoseAndNothingPlaysThere() {
        var d = MascotDriver(now: t0)
        d.salute(now: at(1))
        d.update(active: false, now: at(1.1))
        XCTAssertEqual(pose(&d, 1.1).state, .atEase); XCTAssertNil(d.playing); XCTAssertFalse(d.pendingBark)
        d.salute(now: at(2)); d.bark(now: at(2))
        XCTAssertEqual(pose(&d, 2).state, .atEase)
        XCTAssertEqual(pose(&d, 2.6).frame, 1)            // the at_ease loop runs from 1.1
        d.update(active: true, now: at(3))
        XCTAssertEqual(pose(&d, 3).state, .idle); XCTAssertEqual(pose(&d, 3).frame, 0)
    }

    func testOneFrameOneShotFinishesAtOnce() {
        var d = MascotDriver(now: t0)
        d.salute(now: at(1))
        let one: (MascotState) -> ClipTiming = { $0 == .salute ? ClipTiming(fps: 8, loop: false, count: 1) : self.timing($0) }
        XCTAssertEqual(d.pose(now: at(1), timing: one, reduceMotion: false).state, .idle)
        XCTAssertNil(d.playing)
    }

    func testClockSteppingBackEndsAOneShot() {
        var d = MascotDriver(now: t0)
        d.salute(now: at(100))
        XCTAssertEqual(pose(&d, 50).state, .idle)
        XCTAssertNil(d.playing)
        XCTAssertEqual(pose(&d, 50).frame, 0)             // idle restarts from now, never from the future
    }

    func testReduceMotionClearsEverythingPlaying() {
        var d = MascotDriver(now: t0)
        d.salute(now: at(1)); d.bark(now: at(1.1))
        XCTAssertEqual(pose(&d, 1.2, reduce: true).state, .idle)
        XCTAssertEqual(pose(&d, 1.2, reduce: true).frame, 0)
        XCTAssertNil(d.playing); XCTAssertFalse(d.pendingBark)
        XCTAssertNil(d.nextFrameDelay(now: at(1.2), timing: timing, reduceMotion: true))
    }

    func testNextFrameDelayFollowsWhatPlays() {
        var d = MascotDriver(now: t0)
        XCTAssertEqual(d.nextFrameDelay(now: at(0.1), timing: timing, reduceMotion: false)!, 0.15 + Animator.boundarySlack, accuracy: 1e-6)
        d.salute(now: at(1))
        XCTAssertEqual(d.nextFrameDelay(now: at(1), timing: timing, reduceMotion: false)!, 0.125 + Animator.boundarySlack, accuracy: 1e-6)
        let still: (MascotState) -> ClipTiming = { _ in ClipTiming(fps: 4, loop: true, count: 1) }
        var s = MascotDriver(now: t0)
        XCTAssertNil(s.nextFrameDelay(now: at(0), timing: still, reduceMotion: false))
        _ = s.pose(now: at(0), timing: still, reduceMotion: false)
    }
}

import XCTest
@testable import PanesCore

final class GlideClockTests: XCTestCase {
    func testWaitsForFirstStep() {
        var c = GlideClock(created: 0, frameInterval: 1.0 / 60)
        c.tick(now: 0.005, firstStepLanded: false)
        XCTAssertNil(c.elapsed)
    }

    func testStartsWhenLanded() {
        var c = GlideClock(created: 0, frameInterval: 1.0 / 60)
        c.tick(now: 0.010, firstStepLanded: true)
        c.tick(now: 0.020, firstStepLanded: false)
        XCTAssertEqual(c.elapsed!, 0.010, accuracy: 1e-9)
    }

    func testStartsAfterOneFrameRegardless() {
        var c = GlideClock(created: 0, frameInterval: 1.0 / 60)
        c.tick(now: 0.017, firstStepLanded: false)
        XCTAssertEqual(c.elapsed!, 0, accuracy: 1e-9)
    }
}

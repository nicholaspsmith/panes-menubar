// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class IconChoiceTests: XCTestCase {
    func testNilIsGrid() { XCTAssertEqual(IconChoice(stored: nil, knownMeters: ["arc"]), .grid) }
    func testRoundTrip() { for c in [IconChoice.grid, .majorPane, .armonitor, .meter("arc")] {
        XCTAssertEqual(IconChoice(stored: c.stored, knownMeters: ["arc"]), c) } }
    func testOldMajorPaneKept() { XCTAssertEqual(IconChoice(stored: "major-pane", knownMeters: []), .majorPane) }
    func testUnknownFallsBackToGrid() {
        for s in ["", "meter:", "meter:nope", "lizard", "GRID"] { XCTAssertEqual(IconChoice(stored: s, knownMeters: ["arc"]), .grid) } }
}

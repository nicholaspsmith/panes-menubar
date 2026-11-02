// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesCore

final class MenuRowTextTests: XCTestCase {
    func testOrdinaryItemsKeepTheMenuOpen() {
        XCTAssertTrue(KeepOpenPolicy.keepsMenuOpen(title: "Left Half", isQuit: false))
        XCTAssertTrue(KeepOpenPolicy.keepsMenuOpen(title: "Armonitor", isQuit: false))
        XCTAssertTrue(KeepOpenPolicy.keepsMenuOpen(title: "✗ TV mode · Night Shift blocked · Retry", isQuit: false))
    }

    func testQuitAndWindowOpenersCloseIt() {
        XCTAssertFalse(KeepOpenPolicy.keepsMenuOpen(title: "Quit Panes", isQuit: true))
        XCTAssertFalse(KeepOpenPolicy.keepsMenuOpen(title: "Preferences…", isQuit: false))
        XCTAssertFalse(KeepOpenPolicy.keepsMenuOpen(title: "Schedule...", isQuit: false))
    }

    func testModifiersInMacOSOrder() {
        XCTAssertEqual(KeyEquivalentText.text(key: "c", control: true, option: true, shift: true, command: true), "⌃⌥⇧⌘C")
        XCTAssertEqual(KeyEquivalentText.text(key: "n", option: true, command: true), "⌥⌘N")
    }

    func testSpecialKeysAsGlyphs() {
        XCTAssertEqual(KeyEquivalentText.text(key: "\u{F702}", option: true, command: true), "⌥⌘←")
        XCTAssertEqual(KeyEquivalentText.text(key: "\u{F700}", command: true), "⌘↑")
        XCTAssertEqual(KeyEquivalentText.text(key: "\u{F704}"), "F1")
        XCTAssertEqual(KeyEquivalentText.text(key: "\u{F70F}"), "F12")
        XCTAssertEqual(KeyEquivalentText.text(key: "\r", command: true), "⌘↩")
        XCTAssertEqual(KeyEquivalentText.text(key: "[", option: true, command: true), "⌥⌘[")
    }

    func testNoKeyNoText() {
        XCTAssertNil(KeyEquivalentText.text(key: ""))
    }
}

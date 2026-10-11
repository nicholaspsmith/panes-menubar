// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesGlyph

final class MajorPanePreviewTests: XCTestCase {
    func testPreviewShowsEveryClipTheLitRowAndTheIcon() {
        let html = MajorPanePreview.html(art: MajorPaneArt.shipped)
        XCTAssertTrue(html.contains("<title>Major Pane Preview</title>"))
        for name in MajorPaneArt.stateNames { XCTAssertTrue(html.contains("<h2>\(name)</h2>"), name) }
        XCTAssertEqual(html.components(separatedBy: "class=\"zoom\"").count - 1, 4)
        XCTAssertEqual(html.components(separatedBy: "class=\"lit pt\"").count - 1, 4)   // none, quarter, half, all
        XCTAssertTrue(html.contains("class=\"icon\""))
        XCTAssertTrue(html.contains(".pt { width: \(MajorPaneArt.shipped.width)px; height: \(MajorPaneArt.shipped.height)px; }"))
        XCTAssertFalse(html.contains("Payne"))
    }
}

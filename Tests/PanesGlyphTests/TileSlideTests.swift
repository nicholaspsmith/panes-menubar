// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import XCTest
import PanesCore
@testable import PanesGlyph

/// The glyph's once-a-minute animation: the windows start bunched near the
/// middle of the screen and slide out into their tiles, the front one
/// glowing as it lands; the last frame is the resting glyph.
final class TileSlideTests: XCTestCase {
    let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    var windows: [CGRect] {
        let visible = CGRect(x: 0, y: 37, width: 1512, height: 945)
        return [.bottomLeft, .topLeft, .topRight].map { FrameCalculator.frame(for: $0, window: .zero, visible: visible)! }
    }

    func testWindowsStartBunchedAndEndSettled() {
        XCTAssertEqual(ScreenGridIcon.tileSettle(at: 0), 0)
        XCTAssertEqual(ScreenGridIcon.tileSettle(at: ScreenGridIcon.tileDuration), 1)
        let mid = ScreenGridIcon.tileSettle(at: 0.3)
        XCTAssertGreaterThan(mid, 0); XCTAssertLessThan(mid, 1)
        XCTAssertGreaterThan(ScreenGridIcon.tileSettle(at: 0.5), mid)
    }

    func testFrontTileGlowsOnLandingThenFades() {
        XCTAssertEqual(ScreenGridIcon.frontGlow(at: 0), 0)
        XCTAssertEqual(ScreenGridIcon.frontGlow(at: ScreenGridIcon.tileDuration), 0)
        let landed = ScreenGridIcon.tileLanding
        XCTAssertEqual(ScreenGridIcon.tileSettle(at: landed), 1)
        XCTAssertGreaterThan(ScreenGridIcon.frontGlow(at: landed), 0.9)
        XCTAssertLessThan(ScreenGridIcon.frontGlow(at: (landed + ScreenGridIcon.tileDuration) / 2), 0.9)
    }

    func testEndFrameIsTheRestingGlyph() {
        func png(_ i: NSImage) -> Data? {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(i.size.width * 2), pixelsHigh: 44, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = i.size
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            i.draw(in: NSRect(origin: .zero, size: i.size)); NSGraphicsContext.restoreGraphicsState()
            return rep.representation(using: .png, properties: [:])
        }
        let m = ScreenGridIcon.Model(display: display, windows: windows)
        let rest = png(ScreenGridIcon.image(m))
        XCTAssertEqual(png(ScreenGridIcon.image(m, tiling: nil)), rest)
        XCTAssertEqual(png(ScreenGridIcon.image(m, tiling: ScreenGridIcon.tileDuration)), rest)
        XCTAssertNotEqual(png(ScreenGridIcon.image(m, tiling: 0)), rest)
        XCTAssertNotEqual(png(ScreenGridIcon.image(m, tiling: ScreenGridIcon.tileLanding)), rest, "the front tile glows as it lands")
    }
}

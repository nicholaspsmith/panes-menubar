// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import XCTest
import PanesCore
@testable import PanesGlyph

final class MajorPaneRendererTests: XCTestCase {
    /// 6x5: an outline K at (0,0), skin S at (1,0), a 4x4 pane of p at x 2…5, y 1…4.
    let art = MajorPaneArt(
        width: 6, height: 5, palette: ["K": 0x000000, "S": 0xF2B98A, "p": 0x1E2A40], pane: ["p"],
        clips: ["idle": MajorPaneClip(fps: 4, loop: true, frames: [["KS....", "..pppp", "..pppp", "..pppp", "..pppp"]]),
                "salute": MajorPaneClip(fps: 8, loop: false, frames: [["KS....", "......", "......", "......", "......"]]),
                "bark": MajorPaneClip(fps: 8, loop: false, frames: [["KS....", "..pppp", "..pppp", "..pppp", "..pppp"]]),
                "at_ease": MajorPaneClip(fps: 2, loop: true, frames: [["KS....", "..pppp", "..pppp", "..pppp", "..pppp"]])])
    func cell(_ c: Int, _ r: Int) -> GridCell { GridCell(column: c, row: r) }

    func testPaletteColoursFollowTheMap() {
        let cells = MajorPaneRenderer.cells(art: art, pose: .init(state: "idle"))
        XCTAssertEqual(cells.count, 5); XCTAssertEqual(cells[0].count, 6)
        XCTAssertEqual(cells[0][0], 0x000000); XCTAssertEqual(cells[0][1], 0xF2B98A); XCTAssertNil(cells[0][2])
    }

    func testPanePixelsAreUnlitByDefaultAndLitByTheirCell() {
        let none = MajorPaneRenderer.cells(art: art, pose: .init(state: "idle"))
        XCTAssertEqual(none[1][2], 0x1E2A40)
        let lit = MajorPaneRenderer.cells(art: art, pose: .init(state: "idle", lit: [cell(0, 0), cell(3, 3)]))
        XCTAssertEqual(lit[1][2], MajorPaneRenderer.litCell)       // column 0, row 0 → top-left pane pixel
        XCTAssertEqual(lit[4][5], MajorPaneRenderer.litCell)       // column 3, row 3 → bottom-right
        XCTAssertEqual(lit[1][3], 0x1E2A40)                        // column 1, row 0 stays dark
    }

    func testCellsScaleToThePanesBox() {
        // An 8x8 pane: each cell is a 2x2 block.
        var frame = ["KS........"] + Array(repeating: "..pppppppp", count: 8)
        frame.append("..........")
        let big = MajorPaneArt(width: 10, height: 10, palette: art.palette, pane: ["p"],
                               clips: ["idle": MajorPaneClip(fps: 4, loop: true, frames: [frame])])
        let lit = MajorPaneRenderer.cells(art: big, pose: .init(state: "idle", lit: [cell(1, 2)]))
        for (x, y) in [(4, 5), (5, 5), (4, 6), (5, 6)] { XCTAssertEqual(lit[y][x], MajorPaneRenderer.litCell, "(\(x),\(y))") }
        XCTAssertEqual(lit[5][3], 0x1E2A40); XCTAssertEqual(lit[4][4], 0x1E2A40)
    }

    func testFrameWithoutAPaneDrawsAndLightsNothing() {
        let cells = MajorPaneRenderer.cells(art: art, pose: .init(state: "salute", lit: PaneCells.all))
        XCTAssertEqual(cells[0][0], 0x000000)
        XCTAssertTrue(cells[1...4].allSatisfy { $0.allSatisfy { $0 == nil } })
    }

    func testInactiveGreysEveryPixelByLuminance() {
        let grey = MajorPaneRenderer.cells(art: art, pose: .init(state: "at_ease", lit: PaneCells.all, active: false))
        XCTAssertEqual(grey[0][1], MajorPaneRenderer.greyed(0xF2B98A))
        XCTAssertEqual(grey[1][2], MajorPaneRenderer.greyed(MajorPaneRenderer.litCell))
        XCTAssertEqual(MajorPaneRenderer.greyed(0xFFFFFF), 0xFFFFFF)
        XCTAssertEqual(MajorPaneRenderer.greyed(0xFF0000), 0x4C4C4C)   // 299/1000 of 255 = 76
    }

    func testFrameIndexIsClampedToTheClip() {
        XCTAssertEqual(MajorPaneRenderer.cells(art: art, pose: .init(state: "idle", frame: 9)),
                       MajorPaneRenderer.cells(art: art, pose: .init(state: "idle", frame: 0)))
    }

    func testBitmapIsWholePixelBlocksAtEveryScale() {
        for scale in [1, 2, 3] {
            let rep = MajorPaneRenderer.bitmap(art: art, pose: .init(state: "idle", lit: [cell(0, 0)]), scale: scale)
            XCTAssertEqual(rep.pixelsWide, 6 * scale); XCTAssertEqual(rep.pixelsHigh, 5 * scale)
            XCTAssertEqual(rep.size, NSSize(width: 6, height: 5))
            for dy in 0..<scale { for dx in 0..<scale {
                XCTAssertEqual(rep.colorAt(x: 2 * scale + dx, y: 1 * scale + dy)!.redComponent, 1, accuracy: 0.01)
                XCTAssertEqual(rep.colorAt(x: 2 * scale + dx, y: 1 * scale + dy)!.alphaComponent, 1)
                XCTAssertEqual(rep.colorAt(x: 2 * scale + dx, y: 0 * scale + dy)!.alphaComponent, 0)
            } }
        }
    }

    func testImageCarriesOneBitmapPerScale() {
        let img = MajorPaneRenderer.image(art: art, pose: .init(state: "idle"))
        XCTAssertEqual(img.size, NSSize(width: 6, height: 5))
        XCTAssertEqual(img.representations.count, 3)
        XCTAssertEqual(MajorPaneRenderer.image(art: art, pose: .init(state: "idle"), scales: [1, 2, 32]).representations.map(\.pixelsWide), [6, 12, 192])
        XCTAssertFalse(img.isTemplate)
    }

    // MARK: PaneCells

    let visible = CGRect(x: 0, y: 37, width: 1512, height: 945)
    func testLitCellsFollowTheFrontWindow() {
        let grid = LayoutGrid()
        let half = grid.frame(for: GridSelection(cell(0, 0), cell(1, 3)), in: visible)
        XCTAssertEqual(PaneCells.lit(windows: [half], visible: visible), PaneCells.half)
        let quarter = grid.frame(for: GridSelection(cell(0, 0), cell(1, 1)), in: visible)
        XCTAssertEqual(PaneCells.lit(windows: [half, quarter], visible: visible), PaneCells.quarter)  // the last is the front
        XCTAssertEqual(PaneCells.lit(windows: [visible], visible: visible), PaneCells.all)
        XCTAssertEqual(PaneCells.lit(windows: [], visible: visible), [])
    }

    func testLitCellsIgnoreWindowsOffTheDisplay() {
        XCTAssertEqual(PaneCells.lit(windows: [CGRect(x: 5000, y: 100, width: 800, height: 600)], visible: visible), [])
    }

    // MARK: Review fixes (0.8.1)

    func testFrameKeyIsEqualForIdenticalFramesAndDiffersOtherwise() {
        let twice = MajorPaneArt(width: 2, height: 1, palette: ["K": 0], pane: [],
                                 clips: ["idle": MajorPaneClip(fps: 4, loop: true, frames: [["K."], ["K."], [".K"]])])
        let a = FrameKey(art: twice, pose: .init(state: "idle", frame: 0))
        XCTAssertEqual(a, FrameKey(art: twice, pose: .init(state: "idle", frame: 1)))      // same rows: nothing to redraw
        XCTAssertNotEqual(a, FrameKey(art: twice, pose: .init(state: "idle", frame: 2)))
        XCTAssertNotEqual(a, FrameKey(art: twice, pose: .init(state: "idle", frame: 0, lit: PaneCells.all)))
        XCTAssertNotEqual(a, FrameKey(art: twice, pose: .init(state: "idle", frame: 0, active: false)))
    }

    func testFrontWindowIsTheFrontmostAppsFirstWindow() {
        let infos = [WindowInfo(bounds: CGRect(x: 0, y: 0, width: 10, height: 10), ownerPID: 7),
                     WindowInfo(bounds: CGRect(x: 5, y: 5, width: 10, height: 10), ownerPID: 9),
                     WindowInfo(bounds: CGRect(x: 1, y: 1, width: 10, height: 10), ownerPID: 9)]
        XCTAssertEqual(PaneCells.frontWindow(of: 9, in: infos), CGRect(x: 5, y: 5, width: 10, height: 10))
        XCTAssertNil(PaneCells.frontWindow(of: 3, in: infos))
        XCTAssertNil(PaneCells.frontWindow(of: nil, in: infos))
    }

    func testNoFrontWindowLightsNothing() {
        XCTAssertEqual(PaneCells.lit(front: nil, visible: visible), [])
        XCTAssertEqual(PaneCells.lit(front: visible, visible: visible), PaneCells.all)
    }
}

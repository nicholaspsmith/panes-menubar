// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore

public struct MajorPanePose: Equatable {
    public var state: String
    public var frame: Int
    /// The pane's lit cells (column 0…3, row 0…3; row 0 is the top).
    public var lit: Set<GridCell>
    /// False without Accessibility: the whole glyph goes grey.
    public var active: Bool
    public init(state: String, frame: Int = 0, lit: Set<GridCell> = [], active: Bool = true) {
        self.state = state; self.frame = frame; self.lit = lit; self.active = active
    }
}

/// Which pane cells the front window lights (spec "The pane's cells").
public enum PaneCells {
    /// `windows` back to front, as `WindowMap.windows` returns them; the last is the front.
    public static func lit(windows: [CGRect], visible: CGRect) -> Set<GridCell> {
        guard let front = windows.last else { return [] }
        return LayoutGrid().cells(coveredBy: front, in: visible)
    }
    public static let all = Set(LayoutGrid().cells)
    public static let half = Set(LayoutGrid().cells.filter { $0.column < 2 })
    public static let quarter = Set(LayoutGrid().cells.filter { $0.column < 2 && $0.row < 2 })
}

/// Major Pane's pixels → bitmaps. Every art pixel becomes a whole block of
/// device pixels, written directly, so nothing is ever interpolated.
public enum MajorPaneRenderer {
    /// A lit cell: the amber the grid glyph gives the front window.
    public static let litCell: UInt32 = 0xFFD166

    /// The bounding box of the pane's pixels in a frame, nil when it has none.
    static func paneBox(_ frame: [String], pane: Set<Character>) -> (x: Int, y: Int, w: Int, h: Int)? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for (y, row) in frame.enumerated() {
            for (x, c) in row.enumerated() where pane.contains(c) {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }

    /// The colour of every art pixel for a pose: always `art.height` rows of `art.width`.
    /// A pane pixel is lit or dark by the 4×4 cell its position in the pane's box falls in.
    public static func cells(art: MajorPaneArt, pose: MajorPanePose) -> [[UInt32?]] {
        let clip = art.clip(pose.state)
        let frame = clip.frames.isEmpty ? [] : clip.frames[min(max(pose.frame, 0), clip.frames.count - 1)]
        let box = paneBox(frame, pane: art.pane)
        let width = max(art.width, 0), height = max(art.height, 0)
        return (0..<height).map { y in
            let row = y < frame.count ? Array(frame[y]) : []
            return (0..<width).map { x -> UInt32? in
                guard x < row.count, row[x] != "." else { return nil }
                var c: UInt32?
                if art.pane.contains(row[x]), let box {
                    let cell = GridCell(column: min(3, (x - box.x) * 4 / max(box.w, 1)), row: min(3, (y - box.y) * 4 / max(box.h, 1)))
                    c = pose.lit.contains(cell) ? litCell : art.palette[row[x]]
                } else {
                    c = art.palette[row[x]]
                }
                if !pose.active, let v = c { c = greyed(v) }
                return c
            }
        }
    }

    /// Greyed by luminance (Rec. 601).
    public static func greyed(_ c: UInt32) -> UInt32 {
        let r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF
        let l = (r * 299 + g * 587 + b * 114) / 1000
        return (l << 16) | (l << 8) | l
    }

    static func blank(_ w: Int, _ h: Int) -> NSBitmapImageRep {
        let w = max(w, 1), h = max(h, 1)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
        memset(rep.bitmapData!, 0, rep.bytesPerRow * h)
        return rep
    }

    static func fill(_ rep: NSBitmapImageRep, x: Int, y: Int, size: Int, color: UInt32) {
        let x0 = max(x, 0), x1 = min(x + size, rep.pixelsWide), y0 = max(y, 0), y1 = min(y + size, rep.pixelsHigh)
        guard x0 < x1, y0 < y1, let data = rep.bitmapData else { return }
        let r = UInt8((color >> 16) & 0xFF), g = UInt8((color >> 8) & 0xFF), b = UInt8(color & 0xFF)
        for py in y0..<y1 {
            var p = data + py * rep.bytesPerRow + x0 * 4
            for _ in x0..<x1 { p[0] = r; p[1] = g; p[2] = b; p[3] = 255; p += 4 }
        }
    }

    /// One pose, `scale` device pixels per art pixel; its point size is the art's grid.
    public static func bitmap(art: MajorPaneArt, pose: MajorPanePose, scale: Int) -> NSBitmapImageRep {
        let scale = max(scale, 1)
        let rep = blank(art.width * scale, art.height * scale)
        for (y, line) in cells(art: art, pose: pose).enumerated() {
            for (x, c) in line.enumerated() { if let c { fill(rep, x: x * scale, y: y * scale, size: scale, color: c) } }
        }
        let out = rep.retagging(with: .sRGB) ?? rep
        out.size = NSSize(width: art.width, height: art.height)
        return out
    }

    /// The status-item image: one bitmap per scale, all of one point size. AppKit
    /// draws the one that matches the bar's backing scale, 1:1. The site passes
    /// a large extra scale for the app icon.
    public static func image(art: MajorPaneArt, pose: MajorPanePose, scales: [Int] = [1, 2, 3]) -> NSImage {
        let image = NSImage(size: NSSize(width: art.width, height: art.height))
        for s in scales { image.addRepresentation(bitmap(art: art, pose: pose, scale: s)) }
        image.isTemplate = false
        return image
    }
}

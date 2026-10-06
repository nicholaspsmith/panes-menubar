// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore
import PanesGlyph

// Renders, from the app's own drawing code:
//   docs/menubar-icon.png        the icon at a few window layouts, on a dark and a light bar, at 2x
//   Resources/bundle/AppIcon.icns the app icon (via build/AppIcon.iconset + iconutil)
//   docs/mascot.png              the 1024 app icon, for the README
//
// The app icon mirrors the Menumon site's art/glyphs/app-icons.swift tile:
// the glyph large on a dark macOS superellipse.
//
//     swift run panes-render-icons      (from the repo root)

let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
let visible = CGRect(x: 0, y: 37, width: 1512, height: 945)
func frame(_ a: WindowAction) -> CGRect { FrameCalculator.frame(for: a, window: .zero, visible: visible)! }

/// Back to front; the last is the frontmost.
let layouts: [[CGRect]] = [
    [],
    [frame(.leftHalf), frame(.rightHalf)],
    [frame(.topLeft), frame(.bottomLeft), frame(.rightHalf)],
    [CGRect(x: 90, y: 120, width: 820, height: 560), CGRect(x: 520, y: 260, width: 760, height: 600),
     CGRect(x: 1100, y: 80, width: 520, height: 420)],   // free-floating, one partly off-screen
    [frame(.maximize)],
]

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func draw(into rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.shouldAntialias = true
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func png(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// MARK: - Menu-bar strip

let scale: CGFloat = 2
let iconW = ScreenGridIcon.width(for: display.size)
let gap: CGFloat = 14, padX: CGFloat = 12
let stripW = padX * 2 + CGFloat(layouts.count) * iconW + CGFloat(layouts.count - 1) * gap
let barH: CGFloat = 30
let strip = bitmap(Int(stripW * scale), Int(barH * 2 * scale))
draw(into: strip) {
    let t = NSAffineTransform(); t.scale(by: scale); t.concat()
    // Top: dark bar. Bottom: light bar.
    for (row, color) in [(1, NSColor(white: 0.12, alpha: 1)), (0, NSColor(white: 0.93, alpha: 1))] {
        let y = CGFloat(row) * barH
        color.set(); NSBezierPath(roundedRect: NSRect(x: 0, y: y + 1, width: stripW, height: barH - 2), xRadius: 8, yRadius: 8).fill()
        for (i, windows) in layouts.enumerated() {
            let x = padX + CGFloat(i) * (iconW + gap)
            let r = NSRect(x: x, y: y + (barH - ScreenGridIcon.height) / 2, width: iconW, height: ScreenGridIcon.height)
            ScreenGridIcon.draw(.init(display: display, windows: windows), in: r, scale: scale)
        }
    }
}
png(strip, "docs/menubar-icon.png")
print("docs/menubar-icon.png")

// MARK: - App icon

let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
func superellipse(_ r: NSRect, exponent n: CGFloat = 5.6) -> NSBezierPath {
    let p = NSBezierPath()
    for k in 0...1440 {
        let t = CGFloat(k) / 1440 * 2 * .pi, c = cos(t), s = sin(t)
        let pt = NSPoint(x: r.midX + r.width / 2 * pow(abs(c), 2 / n) * (c < 0 ? -1 : 1),
                         y: r.midY + r.height / 2 * pow(abs(s), 2 / n) * (s < 0 ? -1 : 1))
        k == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close()
    return p
}

let iconModel = ScreenGridIcon.Model(display: display, windows: layouts[2])
func appIcon(px: Int) -> NSBitmapImageRep {
    let rep = bitmap(px, px)
    draw(into: rep) {
        let k = CGFloat(px) / 1024
        let t = NSAffineTransform(); t.scale(by: k); t.concat()
        let tile = superellipse(tileRect)
        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        NSColor(white: 1, alpha: 0.16).set(); tile.fill()
        NSGradient(starting: NSColor(srgbRed: 0x15 / 255, green: 0x17 / 255, blue: 0x1B / 255, alpha: 1),
                   ending: NSColor(srgbRed: 0x2B / 255, green: 0x2E / 255, blue: 0x35 / 255, alpha: 1))!
            .draw(in: superellipse(tileRect.offsetBy(dx: 0, dy: -1.5)), angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        // The glyph at most 72% of the tile wide, 62% tall (app-icons.swift's limits).
        let w = ScreenGridIcon.width(for: display.size), h = ScreenGridIcon.height
        let s = min(tileRect.width * 0.72 / w, tileRect.height * 0.62 / h)
        let r = NSRect(x: tileRect.midX - w * s / 2, y: tileRect.midY - h * s / 2, width: w * s, height: h * s)
        ScreenGridIcon.draw(iconModel, in: r, scale: k)
    }
    return rep
}

let set = "build/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: set)
try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for s in [1, 2] {
        png(appIcon(px: points * s), "\(set)/icon_\(points)x\(points)\(s == 2 ? "@2x" : "").png")
    }
}
png(appIcon(px: 1024), "docs/mascot.png")
try! FileManager.default.createDirectory(atPath: "Resources/bundle", withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set, "-o", "Resources/bundle/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print("Resources/bundle/AppIcon.icns, docs/mascot.png")

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore

/// The menu-bar icon: a little display in the Menumon glyph style (shaded
/// grey bezel on a stand, dark glass with a sheen, ink outlines) with a faint
/// 4×4 grid on the screen and every window on that display drawn as a tile
/// at its true scaled position and size, back to front. The frontmost
/// window is amber; the rest take soft hues so overlaps stay readable.
///
/// Full colour, not a template, like the other Menumon glyphs; the ink
/// outline carries it on light and dark bars. Window tiles are snapped to
/// device pixels at whatever scale the image is being drawn, so they stay
/// crisp at 1× and 2×.
public enum ScreenGridIcon {
    /// What to draw. `windows` are AX rects on the display whose frame is
    /// `display`, back to front (the last is the frontmost window).
    public struct Model: Equatable {
        public var display: CGRect
        public var windows: [CGRect]
        /// False while Panes cannot move windows (no Accessibility): the
        /// glass goes grey and the tiles fade, like KeyLight's greyed key.
        public var active: Bool

        public init(display: CGRect, windows: [CGRect], active: Bool = true) {
            self.display = display
            self.windows = windows
            self.active = active
        }
    }

    public static let height: CGFloat = 22
    /// The screen's height inside the bezel; its width follows the display.
    static let screenHeight: CGFloat = 13.2
    static let bezelInset: CGFloat = 1.3
    static let sidePad: CGFloat = 1.0

    // MARK: Palette (shared with Armonitor's monitor, so the two sit together)

    static let ink = NSColor(srgbRed: 0.13, green: 0.10, blue: 0.08, alpha: 1)
    static let bezel = (light: NSColor(white: 0.82, alpha: 1), dark: NSColor(white: 0.50, alpha: 1))
    static let stand = (light: NSColor(white: 0.64, alpha: 1), dark: NSColor(white: 0.38, alpha: 1))
    static let glass = (light: NSColor(srgbRed: 0.20, green: 0.27, blue: 0.40, alpha: 1),
                        dark: NSColor(srgbRed: 0.07, green: 0.09, blue: 0.15, alpha: 1))
    static let idleGlass = (light: NSColor(white: 0.34, alpha: 1), dark: NSColor(white: 0.16, alpha: 1))
    static let front = (light: NSColor(srgbRed: 1.00, green: 0.82, blue: 0.40, alpha: 1),
                        dark: NSColor(srgbRed: 0.97, green: 0.55, blue: 0.10, alpha: 1))
    /// The other windows, cycled from the front backwards.
    static let others: [(light: NSColor, dark: NSColor)] = [
        (NSColor(srgbRed: 0.72, green: 0.86, blue: 1.00, alpha: 1), NSColor(srgbRed: 0.42, green: 0.64, blue: 0.92, alpha: 1)),
        (NSColor(srgbRed: 0.74, green: 0.93, blue: 0.80, alpha: 1), NSColor(srgbRed: 0.42, green: 0.74, blue: 0.54, alpha: 1)),
        (NSColor(srgbRed: 0.86, green: 0.80, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.60, green: 0.52, blue: 0.86, alpha: 1)),
        (NSColor(srgbRed: 1.00, green: 0.82, blue: 0.84, alpha: 1), NSColor(srgbRed: 0.88, green: 0.52, blue: 0.58, alpha: 1)),
    ]

    // MARK: Geometry

    /// The canvas width for a display's aspect ratio.
    public static func width(for display: CGSize) -> CGFloat {
        (screenSize(for: display).width + 2 * bezelInset + 2 * sidePad).rounded(.up)
    }

    static func screenSize(for display: CGSize) -> CGSize {
        let aspect = display.height > 0 ? min(max(display.width / display.height, 1.0), 2.4) : 1.6
        return CGSize(width: (screenHeight * aspect).rounded(), height: screenHeight)
    }

    // MARK: Drawing

    public static func image(_ model: Model) -> NSImage {
        let w = width(for: model.display.size)
        let image = NSImage(size: NSSize(width: w, height: height), flipped: false) { rect in
            let scale = NSGraphicsContext.current?.cgContext.userSpaceToDeviceSpaceTransform.a ?? 2
            draw(model, in: rect, scale: max(1, scale))
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws into the current context at any size: the design is 22pt tall,
    /// scaled to fit `rect` (the app icon draws it large).
    public static func draw(_ model: Model, in rect: NSRect, scale: CGFloat) {
        let w = width(for: model.display.size)
        let k = min(rect.width / w, rect.height / height)
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: rect.midX - w * k / 2, yBy: rect.midY - height * k / 2)
        t.scale(by: k)
        t.concat()
        drawDesign(model, width: w, pixelScale: scale * k)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawDesign(_ m: Model, width w: CGFloat, pixelScale px: CGFloat) {
        let screenSz = screenSize(for: m.display.size)
        let screen = WindowMap.pixelAligned(
            CGRect(x: (w - screenSz.width) / 2, y: 4.4, width: screenSz.width, height: screenSz.height), scale: px)
        let bezelRect = screen.insetBy(dx: -bezelInset, dy: -bezelInset)

        // Stand: a short neck and a rounded foot.
        let neck = NSBezierPath(rect: NSRect(x: w / 2 - 1.4, y: 1.9, width: 2.8, height: bezelRect.minY - 1.9))
        shaded(neck, stand, ink: 0.5)
        let foot = NSBezierPath(roundedRect: NSRect(x: w / 2 - 4, y: 0.9, width: 8, height: 1.2), xRadius: 0.6, yRadius: 0.6)
        shaded(foot, stand, ink: 0.5)

        // Bezel with a lighter lip round the glass.
        let bz = NSBezierPath(roundedRect: bezelRect, xRadius: 1.7, yRadius: 1.7)
        shaded(bz, bezel, ink: 0.65)
        let lip = NSBezierPath(roundedRect: screen.insetBy(dx: -0.5, dy: -0.5), xRadius: 0.9, yRadius: 0.9)
        NSGradient(starting: bezel.dark, ending: NSColor(white: 0.93, alpha: 1))?.draw(in: lip, angle: -70)

        // Glass.
        let glassPath = NSBezierPath(roundedRect: screen, xRadius: 0.6, yRadius: 0.6)
        let g = m.active ? glass : idleGlass
        NSGradient(starting: g.light, ending: g.dark)?.draw(in: glassPath, angle: -70)

        NSGraphicsContext.saveGraphicsState()
        glassPath.addClip()

        // The faint 4×4 grid, on whole pixels.
        let grid = NSBezierPath()
        let hair = 1 / px
        for i in 1..<4 {
            let x = ((screen.minX + screen.width * CGFloat(i) / 4) * px).rounded() / px + hair / 2
            let y = ((screen.minY + screen.height * CGFloat(i) / 4) * px).rounded() / px + hair / 2
            grid.move(to: NSPoint(x: x, y: screen.minY)); grid.line(to: NSPoint(x: x, y: screen.maxY))
            grid.move(to: NSPoint(x: screen.minX, y: y)); grid.line(to: NSPoint(x: screen.maxX, y: y))
        }
        grid.lineWidth = hair
        NSColor(white: 1, alpha: 0.16).set(); grid.stroke()

        // Windows, back to front.
        let tiles = WindowMap.scaled(m.windows, display: m.display, into: screen, scale: px)
        for (i, tile) in tiles.enumerated() {
            let isFront = i == tiles.count - 1
            let colors = isFront ? front : others[(tiles.count - 2 - i) % others.count]
            drawTile(tile, colors, pixel: hair, faded: !m.active)
        }

        // Glare across the top-left of the glass.
        let glare = NSBezierPath()
        glare.move(to: NSPoint(x: screen.minX, y: screen.maxY - 4))
        glare.line(to: NSPoint(x: screen.minX + 4, y: screen.maxY))
        glare.line(to: NSPoint(x: screen.minX + 6, y: screen.maxY))
        glare.line(to: NSPoint(x: screen.minX, y: screen.maxY - 6))
        glare.close()
        NSColor(white: 1, alpha: 0.14).set(); glare.fill()
        NSGraphicsContext.restoreGraphicsState()

        ink.withAlphaComponent(0.8).set(); glassPath.lineWidth = 0.45; glassPath.stroke()
    }

    /// A window tile: a soft gradient body, a darker title-bar strip along
    /// its top, and an ink outline drawn inside its pixel-aligned edge.
    private static func drawTile(_ r: CGRect, _ c: (light: NSColor, dark: NSColor), pixel: CGFloat, faded: Bool) {
        let alpha: CGFloat = faded ? 0.45 : 1
        let radius = min(0.7, r.width / 4, r.height / 4)
        let body = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        NSGradient(starting: c.light.withAlphaComponent(alpha), ending: c.dark.withAlphaComponent(alpha))?.draw(in: body, angle: -70)
        if r.height >= 3 * pixel {
            NSGraphicsContext.saveGraphicsState()
            body.addClip()
            let bar = max(pixel, (0.8 / pixel).rounded() * pixel)
            c.dark.blended(withFraction: 0.35, of: .black)?.withAlphaComponent(alpha).set()
            NSBezierPath(rect: NSRect(x: r.minX, y: r.maxY - bar, width: r.width, height: bar)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let outline = NSBezierPath(roundedRect: r.insetBy(dx: pixel / 2, dy: pixel / 2), xRadius: radius, yRadius: radius)
        outline.lineWidth = pixel
        ink.withAlphaComponent(0.85 * alpha).set(); outline.stroke()
    }

    /// Fills `path` with a top-left-lit gradient, then outlines it in ink.
    private static func shaded(_ path: NSBezierPath, _ c: (light: NSColor, dark: NSColor), ink width: CGFloat) {
        NSGradient(starting: c.light, ending: c.dark)?.draw(in: path, angle: -70)
        ink.set(); path.lineWidth = width; path.lineJoinStyle = .round; path.stroke()
    }
}

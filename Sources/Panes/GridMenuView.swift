// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore

/// The 4×4 layout grid at the top of the menu, shaped like the visible frame
/// of the display the target window is on. Click a cell to fill it, or drag
/// across cells to fill the rectangle they make; the selection highlights
/// live and the menu closes once the window has been told where to go.
///
/// Cells under windows are shaded: the target window's in the accent colour,
/// other windows' in a light tint.
final class GridMenuView: NSView {
    struct Model {
        var grid = LayoutGrid()
        var visible: CGRect
        var activeCells: Set<GridCell>
        var otherCells: Set<GridCell>
        var enabled: Bool
    }

    private let model: Model
    private let onSelect: (GridSelection) -> Void
    private var anchor: GridCell?
    private var selection: GridSelection?
    private var hover: GridCell?

    static let width: CGFloat = 248
    private static let pad = NSEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
    private static let gap: CGFloat = 3

    init(model: Model, onSelect: @escaping (GridSelection) -> Void) {
        self.model = model
        self.onSelect = onSelect
        let gridW = Self.width - Self.pad.left - Self.pad.right
        let aspect = model.visible.height > 0 ? model.visible.width / model.visible.height : 1.6
        let gridH = min(max((gridW / aspect).rounded(), 80), 200)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: gridH + Self.pad.top + Self.pad.bottom))
        setAccessibilityRole(.group)
        setAccessibilityLabel("Window layout grid")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }   // row 0 at the top, like the grid

    private var gridRect: NSRect {
        NSRect(x: Self.pad.left, y: Self.pad.top,
               width: bounds.width - Self.pad.left - Self.pad.right,
               height: bounds.height - Self.pad.top - Self.pad.bottom)
    }

    private func rect(for cell: GridCell) -> NSRect {
        let g = gridRect, n = CGFloat(model.grid.columns), m = CGFloat(model.grid.rows)
        let x0 = g.minX + (g.width * CGFloat(cell.column) / n).rounded()
        let x1 = g.minX + (g.width * CGFloat(cell.column + 1) / n).rounded()
        let y0 = g.minY + (g.height * CGFloat(cell.row) / m).rounded()
        let y1 = g.minY + (g.height * CGFloat(cell.row + 1) / m).rounded()
        return NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).insetBy(dx: Self.gap / 2, dy: Self.gap / 2)
    }

    private func cell(at event: NSEvent) -> GridCell {
        let p = convert(event.locationInWindow, from: nil)
        let g = gridRect
        return model.grid.cell(at: CGPoint(x: p.x - g.minX, y: p.y - g.minY), in: g.size)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        // The screen behind the cells.
        let back = NSBezierPath(roundedRect: gridRect.insetBy(dx: -2, dy: -2), xRadius: 7, yRadius: 7)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        back.fill()

        for c in model.grid.cells {
            let path = NSBezierPath(roundedRect: rect(for: c), xRadius: 4, yRadius: 4)
            let fill: NSColor
            if let selection, selection.contains(c) {
                fill = accent
            } else if model.activeCells.contains(c) {
                fill = accent.withAlphaComponent(0.55)
            } else if model.otherCells.contains(c) {
                fill = accent.withAlphaComponent(0.2)
            } else {
                fill = NSColor.labelColor.withAlphaComponent(0.08)
            }
            (model.enabled ? fill : fill.withAlphaComponent(fill.alphaComponent * 0.5)).setFill()
            path.fill()
            if model.enabled, selection == nil, hover == c {
                accent.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let c = cell(at: event)
        if c != hover { hover = c; redraw() }
    }

    override func mouseExited(with event: NSEvent) {
        hover = nil
        redraw()
    }

    override func mouseDown(with event: NSEvent) {
        guard model.enabled else { return }
        let c = cell(at: event)
        anchor = c
        selection = GridSelection(c, c)
        redraw()
    }

    override func mouseDragged(with event: NSEvent) {
        guard model.enabled else { return }
        let c = cell(at: event)
        // A press that began on the status item and slid into the menu
        // arrives as a drag with no mouseDown: start there.
        let a = anchor ?? c
        anchor = a
        let s = GridSelection(a, c)
        if s != selection { selection = s; redraw() }
    }

    override func mouseUp(with event: NSEvent) {
        guard model.enabled, let selection else { return }
        anchor = nil
        self.selection = nil
        onSelect(selection)
        enclosingMenuItem?.menu?.cancelTracking()
    }

    /// The menu runs its own event loop; ask for the pixels now.
    private func redraw() {
        needsDisplay = true
        displayIfNeeded()
    }
}

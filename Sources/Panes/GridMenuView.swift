// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore

/// The layout grid at the top of the menu, shaped like the visible frame of
/// the display the target window is on. Click a cell to fill it, or drag
/// across cells to fill the rectangle they make; the selection highlights
/// live and the menu closes once the window has been told where to go.
///
/// 4×4 with each cell labelled with its cell key; holding ⌥⌘ splits every
/// cell into its own 2×2 (the fine 8×8 grid, unlabelled) until it is let go.
/// Cells under windows are shaded at whichever resolution is showing: the
/// target window's in the accent colour, other windows' in a light tint.
final class GridMenuView: NSView {
    struct Model {
        var visible: CGRect
        /// The target window's frame (AX), if there is one.
        var activeFrame: CGRect?
        /// The other windows on that display (AX).
        var otherFrames: [CGRect]
        var enabled: Bool
    }

    private let model: Model
    private let onSelect: (LayoutGrid, GridSelection) -> Void
    private var grid = LayoutGrid()
    private var activeCells: Set<GridCell> = []
    private var otherCells: Set<GridCell> = []
    private var anchor: GridCell?
    private var selection: GridSelection?
    private var hover: GridCell?
    private var modifierTimer: Timer?

    static let width: CGFloat = 248
    private static let pad = NSEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
    /// Holding these shows the fine grid.
    static let fineModifiers: NSEvent.ModifierFlags = [.command, .option]

    init(model: Model, onSelect: @escaping (LayoutGrid, GridSelection) -> Void) {
        self.model = model
        self.onSelect = onSelect
        let gridW = Self.width - Self.pad.left - Self.pad.right
        let aspect = model.visible.height > 0 ? model.visible.width / model.visible.height : 1.6
        let gridH = min(max((gridW / aspect).rounded(), 80), 200)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: gridH + Self.pad.top + Self.pad.bottom))
        setAccessibilityRole(.group)
        setAccessibilityLabel("Window layout grid")
        setGrid(LayoutGrid())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }   // row 0 at the top, like the grid

    private var gap: CGFloat { grid.columns > 4 ? 2 : 3 }

    private func setGrid(_ g: LayoutGrid) {
        grid = g
        let v = model.visible
        activeCells = model.activeFrame.map { g.cells(coveredBy: $0, in: v) } ?? []
        otherCells = Set(model.otherFrames.flatMap { g.cells(coveredBy: $0, in: v) }).subtracting(activeCells)
        anchor = nil
        selection = nil
        hover = nil
        redraw()
    }

    // MARK: ⌥⌘ watch

    // A menu tracks in its own run-loop mode and does not reliably deliver
    // flagsChanged to local monitors, so the modifiers are polled (in common
    // modes) for as long as the grid is on screen.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        modifierTimer?.invalidate()
        modifierTimer = nil
        guard window != nil else { return }
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.checkModifiers() }
        RunLoop.main.add(t, forMode: .common)
        modifierTimer = t
        checkModifiers()
    }

    private func checkModifiers() {
        let held = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let fine = held.isSuperset(of: Self.fineModifiers)
        if fine != (grid == LayoutGrid.fine) { setGrid(fine ? .fine : LayoutGrid()) }
    }

    // MARK: Geometry

    private var gridRect: NSRect {
        NSRect(x: Self.pad.left, y: Self.pad.top,
               width: bounds.width - Self.pad.left - Self.pad.right,
               height: bounds.height - Self.pad.top - Self.pad.bottom)
    }

    private func rect(for cell: GridCell) -> NSRect {
        let g = gridRect, n = CGFloat(grid.columns), m = CGFloat(grid.rows)
        let x0 = g.minX + (g.width * CGFloat(cell.column) / n).rounded()
        let x1 = g.minX + (g.width * CGFloat(cell.column + 1) / n).rounded()
        let y0 = g.minY + (g.height * CGFloat(cell.row) / m).rounded()
        let y1 = g.minY + (g.height * CGFloat(cell.row + 1) / m).rounded()
        return NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).insetBy(dx: gap / 2, dy: gap / 2)
    }

    private func cell(at event: NSEvent) -> GridCell {
        let p = convert(event.locationInWindow, from: nil)
        let g = gridRect
        return grid.cell(at: CGPoint(x: p.x - g.minX, y: p.y - g.minY), in: g.size)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let back = NSBezierPath(roundedRect: gridRect.insetBy(dx: -2, dy: -2), xRadius: 7, yRadius: 7)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        back.fill()

        let radius: CGFloat = grid.columns > 4 ? 2.5 : 4
        for c in grid.cells {
            let r = rect(for: c)
            let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
            let selected = selection?.contains(c) ?? false
            let fill: NSColor
            if selected {
                fill = accent
            } else if activeCells.contains(c) {
                fill = accent.withAlphaComponent(0.55)
            } else if otherCells.contains(c) {
                fill = accent.withAlphaComponent(0.2)
            } else {
                fill = NSColor.labelColor.withAlphaComponent(0.08)
            }
            (model.enabled ? fill : fill.withAlphaComponent(fill.alphaComponent * 0.5)).setFill()
            path.fill()
            drawLabel(for: c, in: r, onAccent: selected || activeCells.contains(c))
            if model.enabled, selection == nil, hover == c {
                accent.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }
    }

    /// The cell's key, small and centred (4×4 only); white on the
    /// accent-shaded cells, secondary label colour elsewhere.
    private func drawLabel(for cell: GridCell, in r: NSRect, onAccent: Bool) {
        guard let label = CellKeys.label(for: cell, in: grid) else { return }
        let color: NSColor = onAccent ? .white : .secondaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: model.enabled ? color : color.withAlphaComponent(0.5),
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        (label as NSString).draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
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
        let g = grid
        anchor = nil
        self.selection = nil
        modifierTimer?.invalidate()
        onSelect(g, selection)
        enclosingMenuItem?.menu?.cancelTracking()
    }

    /// The menu runs its own event loop; ask for the pixels now.
    private func redraw() {
        needsDisplay = true
        displayIfNeeded()
    }
}

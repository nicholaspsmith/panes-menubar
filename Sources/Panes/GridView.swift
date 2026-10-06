// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore

/// The layout grid, shared by the menu and the on-screen overlay so the two
/// draw and select identically: a display's visible frame cut into cells.
/// Click a cell to fill it, or drag across cells to fill the rectangle they
/// make; the selection highlights live and `onSelect` gets it on release.
///
/// 4×4 with each cell labelled with its cell key, or the 8×8 half-cell grid
/// (unlabelled). Cells under windows are shaded at whichever resolution is
/// showing: the target window's in the accent colour, other windows' in a
/// light tint.
class GridView: NSView {
    struct Model {
        var visible: CGRect
        /// The target window's frame (AX), if there is one.
        var activeFrame: CGRect?
        /// The other windows on that display (AX).
        var otherFrames: [CGRect]
        var enabled: Bool
    }

    /// Sizes and colours: the menu's small grid, or the overlay that covers
    /// the display's visible frame.
    struct Style {
        var insets: NSEdgeInsets
        var gap: (coarse: CGFloat, fine: CGFloat)
        var radius: (coarse: CGFloat, fine: CGFloat)
        var labelSize: CGFloat
        /// The panel behind the cells (nil: none).
        var backing: NSColor?
        var emptyCell: NSColor
        var cellBorder: NSColor?
        var label: NSColor
        /// How strongly windows' cells are shaded (the overlay is a faint
        /// veil over the screen; the menu shades at full strength). The live
        /// selection is never this faint, so a drag always shows.
        var shade: CGFloat = 1
        var selectionAlpha: CGFloat = 1

        static let menu = Style(insets: NSEdgeInsets(top: 6, left: 16, bottom: 6, right: 16),
                                gap: (3, 2), radius: (4, 2.5), labelSize: 11,
                                backing: NSColor.labelColor.withAlphaComponent(0.06),
                                emptyCell: NSColor.labelColor.withAlphaComponent(0.08),
                                cellBorder: nil, label: .secondaryLabelColor)
        static let overlay = Style(insets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                                   gap: (10, 6), radius: (12, 8), labelSize: 40,
                                   backing: nil,
                                   emptyCell: NSColor(white: 1, alpha: 0.01),
                                   cellBorder: NSColor(white: 1, alpha: 0.1),
                                   label: NSColor(white: 1, alpha: 0.15),
                                   shade: 0.12, selectionAlpha: 0.3)
    }

    let model: Model
    let style: Style
    private let onSelect: (LayoutGrid, GridSelection) -> Void
    private(set) var grid = LayoutGrid()
    private var activeCells: Set<GridCell> = []
    private var otherCells: Set<GridCell> = []
    private var anchor: GridCell?
    private var selection: GridSelection?
    private var hover: GridCell?

    init(frame: NSRect, model: Model, style: Style, onSelect: @escaping (LayoutGrid, GridSelection) -> Void) {
        self.model = model
        self.style = style
        self.onSelect = onSelect
        super.init(frame: frame)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Window layout grid")
        setGrid(LayoutGrid())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }   // row 0 at the top, like the grid
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var isFine: Bool { grid == LayoutGrid.fine }

    /// Switch between the 4×4 and the 8×8 grid (drops any selection).
    func setFine(_ fine: Bool) {
        if fine != isFine { setGrid(fine ? .fine : LayoutGrid()) }
    }

    /// Forget a drag in progress (the overlay going away mid-drag).
    func cancelSelection() {
        anchor = nil
        selection = nil
        redraw()
    }

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

    // MARK: Geometry

    private var gridRect: NSRect {
        let i = style.insets
        return NSRect(x: i.left, y: i.top, width: bounds.width - i.left - i.right, height: bounds.height - i.top - i.bottom)
    }

    private func rect(for cell: GridCell) -> NSRect {
        let g = gridRect, n = CGFloat(grid.columns), m = CGFloat(grid.rows)
        let x0 = g.minX + (g.width * CGFloat(cell.column) / n).rounded()
        let x1 = g.minX + (g.width * CGFloat(cell.column + 1) / n).rounded()
        let y0 = g.minY + (g.height * CGFloat(cell.row) / m).rounded()
        let y1 = g.minY + (g.height * CGFloat(cell.row + 1) / m).rounded()
        let gap = isFine ? style.gap.fine : style.gap.coarse
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
        if let backing = style.backing {
            backing.setFill()
            NSBezierPath(roundedRect: gridRect.insetBy(dx: -2, dy: -2), xRadius: 7, yRadius: 7).fill()
        }
        let radius = isFine ? style.radius.fine : style.radius.coarse
        for c in grid.cells {
            let r = rect(for: c)
            let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
            let selected = selection?.contains(c) ?? false
            let fill: NSColor
            if selected {
                fill = accent.withAlphaComponent(style.selectionAlpha)
            } else if activeCells.contains(c) {
                fill = accent.withAlphaComponent(0.55 * style.shade)
            } else if otherCells.contains(c) {
                fill = accent.withAlphaComponent(0.2 * style.shade)
            } else {
                fill = style.emptyCell
            }
            (model.enabled ? fill : fill.withAlphaComponent(fill.alphaComponent * 0.5)).setFill()
            path.fill()
            if let border = style.cellBorder {
                (selected ? accent : border).setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
            drawLabel(for: c, in: r, onAccent: selected || activeCells.contains(c))
            if model.enabled, selection == nil, hover == c {
                (style.cellBorder == nil ? accent : NSColor.white).setStroke()
                path.lineWidth = style.cellBorder == nil ? 1.5 : 2.5
                path.stroke()
            }
        }
    }

    /// The cell's key, centred (4×4 only); white on accent-shaded cells.
    private func drawLabel(for cell: GridCell, in r: NSRect, onAccent: Bool) {
        guard let label = CellKeys.label(for: cell, in: grid) else { return }
        let color: NSColor = onAccent ? .white : style.label
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: style.labelSize, weight: .semibold),
            .foregroundColor: model.enabled ? color : color.withAlphaComponent(0.5),
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        (label as NSString).draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
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
        willSelect()
        onSelect(g, selection)
    }

    /// Hook for subclasses, just before `onSelect`.
    func willSelect() {}

    /// A menu runs its own event loop; ask for the pixels now.
    func redraw() {
        needsDisplay = true
        displayIfNeeded()
    }
}

/// The grid at the top of the menu, shaped like the target display's visible
/// frame. Holding ⌥⌘⇧ while the menu is open splits it into half-cells, as
/// on the overlay; the menu closes once a cell is picked.
final class GridMenuView: GridView {
    static let width: CGFloat = 248
    /// Holding these shows the fine grid.
    static let fineModifiers: NSEvent.ModifierFlags = [.command, .option, .shift]
    private var modifierTimer: Timer?

    init(model: Model, onSelect: @escaping (LayoutGrid, GridSelection) -> Void) {
        let i = Style.menu.insets
        let gridW = Self.width - i.left - i.right
        let aspect = model.visible.height > 0 ? model.visible.width / model.visible.height : 1.6
        let gridH = min(max((gridW / aspect).rounded(), 80), 200)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: gridH + i.top + i.bottom),
                   model: model, style: .menu, onSelect: onSelect)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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
        setFine(held.isSuperset(of: Self.fineModifiers))
    }

    override func willSelect() {
        modifierTimer?.invalidate()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        enclosingMenuItem?.menu?.cancelTracking()
    }
}

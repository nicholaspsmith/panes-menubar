// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore
import StatusItemKit

/// A view-based menu row: clicking it does not close the menu. AppKit draws
/// nothing for a view item, so this paints the native look itself (the
/// `.selection` material StatusItemKit's `ToggleMenuItem` uses, at the native
/// inset and radius) and takes the click, Return, Enter or Space.
class MenuRowView: NSView {
    static let metrics = ToggleMenuMetrics.current
    /// Where a native key equivalent or submenu arrow ends, from the menu's
    /// right edge: measured in the 2x capture of the Panes 1.1.1 menu on
    /// macOS 27 (shortcut text lit to x = 509 px of 548).
    static let trailingInset: CGFloat = 19
    /// Where native key-equivalent text ends: half a point further out than
    /// the arrow (Quit's ⌘Q ends 18.5 pt from the edge in the same capture
    /// as these rows, macOS 27).
    static let keyTrailingInset: CGFloat = 18.5

    private let selection = NSVisualEffectView()

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.metrics.height))
        // The menu widens its item views to its own width.
        autoresizingMask = [.width]
        selection.material = .selection
        selection.state = .active
        selection.isEmphasized = true
        selection.blendingMode = .behindWindow
        selection.maskImage = Self.roundedMask(radius: Self.metrics.highlightRadius)
        selection.frame = Self.metrics.highlightRect(in: bounds)
        selection.autoresizingMask = [.width]
        selection.isHidden = true
        addSubview(selection)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// What a click (or Return) does. The row is disabled with its item.
    func press() {}

    var isRowEnabled: Bool { enclosingMenuItem?.isEnabled ?? true }
    var isRowHighlighted: Bool { isRowEnabled && enclosingMenuItem?.isHighlighted == true }
    var textColor: NSColor {
        !isRowEnabled ? .disabledControlTextColor : isRowHighlighted ? .selectedMenuItemTextColor : .labelColor
    }
    var secondaryColor: NSColor {
        !isRowEnabled ? .disabledControlTextColor : isRowHighlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
    }

    /// Recolour the row's own text for the highlight; called before each draw.
    func updateColors() {}

    // The menu marks the row for display when its highlight changes.
    override func viewWillDraw() {
        selection.isHidden = !isRowHighlighted
        updateColors()
        super.viewWillDraw()
    }

    // MARK: Mouse

    // Take the first click though the menu window is not key, and take the
    // release: a view item that handles the mouse itself keeps the menu up.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // The whole row takes the mouse, not the labels in it.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard isRowEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        press()
    }

    // MARK: Keyboard (as StatusItemKit's ToggleMenuItemView)

    // Arrow keys moving the highlight onto a view item ask whether it takes
    // first responder; say yes only then (not while the menu is opening).
    override var acceptsFirstResponder: Bool {
        NSApp.currentEvent?.type == .keyDown && window?.isVisible == true
    }

    override func keyDown(with event: NSEvent) {
        if isRowEnabled, enclosingMenuItem?.isHighlighted == true,
           ToggleMenuKeys.toggles(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            press()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func isAccessibilityEnabled() -> Bool { isRowEnabled }
    override func accessibilityPerformPress() -> Bool {
        guard isRowEnabled else { return false }
        press()
        return true
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// A section heading that folds the rows below it away: its title, an
/// optional small tag (a display's "HDMI"), and a chevron that points down
/// while folded and up while open, as Homestead's dashboard picker does.
final class DisclosureRow: MenuRowView {
    var onClick: (() -> Void)?

    var expanded: Bool {
        didSet { if expanded != oldValue { updateChevron(animated: true) } }
    }

    private let label = NSTextField(labelWithString: "")
    private let tagLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private let title: String

    /// `width` only seeds the frame: the row stretches to the menu's width.
    init(title: String, tag: String? = nil, expanded: Bool, width: CGFloat = 240) {
        self.title = title
        self.expanded = expanded
        super.init(width: width)

        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        label.stringValue = title
        tagLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        tagLabel.stringValue = tag ?? ""
        tagLabel.isHidden = tag == nil
        chevron.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        updateChevron(animated: false)

        for view in [label, tagLabel, chevron] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.metrics.titleX),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            tagLabel.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            tagLabel.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingInset),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.leadingAnchor.constraint(greaterThanOrEqualTo: tagLabel.trailingAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func press() { onClick?() }

    override func updateColors() {
        label.textColor = textColor
        tagLabel.textColor = isRowHighlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor
        chevron.contentTintColor = secondaryColor
    }

    private func updateChevron(animated: Bool) {
        guard let image = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down",
                                  accessibilityDescription: nil) else { return }
        if animated {
            chevron.setSymbolImage(image, contentTransition: .replace.downUp)
        } else {
            chevron.image = image
        }
        needsDisplay = true
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .disclosureTriangle }
    override func accessibilityLabel() -> String? { title }
    override func accessibilityValue() -> Any? { NSNumber(value: expanded ? 1 : 0) }
}

/// An ordinary action item drawn as a view so it keeps the menu open: its
/// tick, title and key equivalent where AppKit would draw them. Clicking it
/// sends the item's action to its target, with the item as sender, as AppKit
/// would; then `KeepOpen.didPerform` brings the open menu up to date.
final class KeepOpenRow: MenuRowView {
    private let content = ContentView()
    private var font: NSFont { .menuFont(ofSize: 0) }

    init(item: NSMenuItem) {
        let font = NSFont.menuFont(ofSize: 0)
        let titleWidth = (item.title as NSString).size(withAttributes: [.font: font]).width
        let keyWidth = Self.keyText(of: item).map { ($0 as NSString).size(withAttributes: [.font: font]).width + 24 } ?? 0
        super.init(width: ceil(Self.metrics.titleX + titleWidth + keyWidth + Self.trailingInset))
        content.owner = self
        content.frame = bounds
        content.autoresizingMask = [.width]
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func press() {
        guard let item = enclosingMenuItem, let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
        KeepOpen.didPerform(item)
    }

    override func updateColors() { content.needsDisplay = true }

    static func keyText(of item: NSMenuItem) -> String? {
        guard !item.keyEquivalent.isEmpty else { return nil }
        let m = item.keyEquivalentModifierMask
        return KeyEquivalentText.text(key: item.keyEquivalent, control: m.contains(.control), option: m.contains(.option),
                                      shift: m.contains(.shift), command: m.contains(.command))
    }

    fileprivate func drawContent(in bounds: NSRect) {
        guard let item = enclosingMenuItem else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let height = (item.title as NSString).size(withAttributes: attrs).height
        let y = floor((bounds.height - height) / 2)
        (item.title as NSString).draw(at: NSPoint(x: Self.metrics.titleX, y: y), withAttributes: attrs)

        if let key = Self.keyText(of: item) {
            let keyAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: secondaryColor]
            let w = (key as NSString).size(withAttributes: keyAttrs).width
            (key as NSString).draw(at: NSPoint(x: bounds.maxX - Self.keyTrailingInset - w, y: y), withAttributes: keyAttrs)
        }
        if item.state == .on, let check = Self.checkmark(font: font, color: textColor) {
            let cy = round((bounds.height - check.size.height) / 2)
            check.draw(in: NSRect(x: round(Self.metrics.checkCenterX - check.size.width / 2), y: cy,
                                  width: check.size.width, height: check.size.height))
        }
    }

    /// The checkmark macOS draws in the state column, as StatusItemKit's
    /// ToggleMenuItemView draws it: `checkmark`, bold, 10.5 pt beside 13 pt
    /// text, filled with the text colour.
    static func checkmark(font: NSFont, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: ToggleMenuMetrics.checkmarkPointSize(menuFontSize: font.pointSize),
                                                 weight: .bold)
        guard let symbol = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        return NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceIn)
            return true
        }
    }

    private final class ContentView: NSView {
        weak var owner: KeepOpenRow?
        override func draw(_ dirtyRect: NSRect) { owner?.drawContent(in: bounds) }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .menuItem }
    override func accessibilityLabel() -> String? { enclosingMenuItem?.title }
}

/// Turns a menu's action items into `KeepOpenRow`s, so clicking one leaves
/// the menu up (all but Quit and the "…" items, `KeepOpenPolicy`).
enum KeepOpen {
    /// Every eligible item in `items` and in their submenus.
    static func apply(to items: [NSMenuItem]) {
        for item in items {
            if let sub = item.submenu { apply(to: sub.items); continue }
            guard item.view == nil, !item.isSeparatorItem, let action = item.action,
                  KeepOpenPolicy.keepsMenuOpen(title: item.title,
                                               isQuit: action == #selector(NSApplication.terminate(_:)))
            else { continue }
            item.view = KeepOpenRow(item: item)
        }
    }

    /// In a submenu, ticked items with one target are a pick-one set (the
    /// icon, the colour, the resolution): move the tick to the one just
    /// picked, as reopening the menu would. Then redraw the rows.
    static func didPerform(_ item: NSMenuItem) {
        if let menu = item.menu, let target = item.target {
            let set = menu.items.filter { $0.target === target && $0.action != nil }
            if menu.supermenu != nil, set.count > 1, set.contains(where: { $0.state != .off }) {
                for other in set { other.state = other === item ? .on : .off }
            }
            for row in menu.items.compactMap({ $0.view as? KeepOpenRow }) { row.updateColors() }
        }
    }
}

/// A folding section of a menu: a `DisclosureRow` heading with its rows
/// below it while open. `key` remembers the state between openings; without
/// one the section starts folded every time.
enum MenuSection {
    @discardableResult
    static func add(title: String, tag: String? = nil, key: String? = nil, defaultExpanded: Bool = false,
                    items: [NSMenuItem], to menu: NSMenu) -> DisclosureRow {
        KeepOpen.apply(to: items)
        let defaultsKey = key.map { "menuSection.\($0).expanded" }
        let expanded = defaultsKey.map { UserDefaults.standard.object(forKey: $0) as? Bool ?? defaultExpanded }
            ?? defaultExpanded
        let header = NSMenuItem()
        let row = DisclosureRow(title: title, tag: tag, expanded: expanded)
        row.onClick = { [weak menu, weak header, weak row] in
            guard let menu, let header, let row else { return }
            row.expanded.toggle()
            if let defaultsKey { UserDefaults.standard.set(row.expanded, forKey: defaultsKey) }
            if row.expanded {
                let at = menu.index(of: header) + 1
                for (i, item) in items.enumerated() { menu.insertItem(item, at: at + i) }
            } else {
                for item in items where item.menu === menu { menu.removeItem(item) }
            }
        }
        header.view = row
        // AppKit lays the menu out around whether any item has a state: with
        // none (every section folded) it drops the checkmark column and the
        // native titles move left of this row's. The heading says `.on` to
        // keep the column, as StatusItemKit's ToggleMenuItem does; AppKit
        // draws nothing for a view item's state.
        header.state = .on
        menu.addItem(header)
        if expanded { for item in items { menu.addItem(item) } }
        return row
    }
}

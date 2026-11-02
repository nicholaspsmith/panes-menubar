// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit

/// A menu row with a title and a chevron that folds the rows below it away.
/// Clicking it does not dismiss the menu (it is view-based), so the owner can
/// insert or remove the rows in place. Same look as Homestead's disclosure rows.
///
/// A view-based item gets none of AppKit's drawing, so this paints the
/// selection bar itself: `NSMenuItem.isHighlighted` is true while the pointer
/// is over it, even for a view-based item.
final class DisclosureRow: NSView {
    var onClick: (() -> Void)?

    var expanded: Bool {
        didSet { updateChevron() }
    }

    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var tracking: NSTrackingArea?

    /// `width` only seeds the frame: the row stretches to the menu's width.
    init(title: String, expanded: Bool, width: CGFloat) {
        self.expanded = expanded
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        autoresizingMask = [.width]

        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        label.stringValue = title
        chevron.contentTintColor = .secondaryLabelColor
        chevron.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        updateChevron()

        for view in [label, chevron] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.titleInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.chevronInset),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
        ])
        setAccessibilityRole(.disclosureTriangle)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Where a native item's title starts in Panes's menu, measured on macOS 27
    /// (the Night Shift rows' checkmarks give the menu a state column), so
    /// the row's title lines up with the items around it.
    static let titleInset: CGFloat = 30
    /// The native submenu arrow's distance from the menu's right edge.
    static let chevronInset: CGFloat = 19

    private func updateChevron() {
        chevron.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                                accessibilityDescription: nil)
        setAccessibilityValue(expanded)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    private var highlighted: Bool { enclosingMenuItem?.isHighlighted == true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            // A native item's highlight stops short of the menu's rounded edge.
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 5, yRadius: 5).fill()
        }
        label.textColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        chevron.contentTintColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
    }
}

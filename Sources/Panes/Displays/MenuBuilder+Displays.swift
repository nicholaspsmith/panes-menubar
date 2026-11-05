// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import StatusItemKit
import DisplayCore

/// The per-display blocks of the menu. Kept out of `DisplaysFeature.swift` so it stays
/// the wiring and this stays the layout.
extension DisplaysFeature {
    /// One display's rows, folded under a heading with its name; whether
    /// it is open is remembered per display.
    func addDisplaySection(_ entry: DisplayModel.Entry, to menu: NSMenu) {
        let rows = NSMenu()
        addDisplayRows(entry, to: rows)
        let items = rows.items
        rows.removeAllItems()
        let info = entry.info
        FoldingSection.add(title: info.name, tag: info.isHDMI ? "HDMI" : nil,
                           key: "display.\(info.vendorID).\(info.productID).\(info.serial)",
                           items: items, to: menu)
    }

    /// The display's controls: brightness (and contrast), resolution, and
    /// whether Night Shift works on it.
    private func addDisplayRows(_ entry: DisplayModel.Entry, to menu: NSMenu) {
        switch entry.brightnessSource {
        case .system where entry.info.isBuiltIn:
            addBuiltInBrightnessRow(entry, to: menu)
        case .system:
            // The built-in panel, or an external display macOS dims itself
            // (the keyboard keys work on it even when DDC doesn't).
            let row = NSMenuItem()
            let view = SliderRow(title: "Brightness", symbol: "sun.max", value: entry.systemBrightness.map { Double($0) * 100 }, maximum: 100,
                                 format: { "\(Int($0.rounded()))" }) { [weak self] v in
                self?.model.setSystemBrightness(entry.info.id, Float(v / 100))
                self?.refreshIcon()
            }
            row.view = view
            systemBrightnessRows[entry.info.id] = view
            menu.addItem(row)
        case .ddc:
            let b = NSMenuItem()
            let brightnessView = SliderRow(title: "Brightness", symbol: "sun.max",
                               value: entry.brightness.map { Double($0.current) }, maximum: Double(entry.brightness?.maximum ?? 100),
                               format: { "\(Int($0.rounded()))" }) { [weak self] v in
                self?.model.setBrightness(entry.info.id, UInt16(v.rounded()))
            }
            b.view = brightnessView
            sliderRows[entry.info.id, default: [:]][.brightness] = brightnessView
            menu.addItem(b)
        case .none:
            break
        }
        if entry.info.isBuiltIn {
            addXDRRows(entry, to: menu)
            return
        }

        if entry.isExternalControllable {
            let c = NSMenuItem()
            let contrastView = SliderRow(title: "Contrast", symbol: "circle.lefthalf.filled",
                               value: entry.contrast.map { Double($0.current) }, maximum: Double(entry.contrast?.maximum ?? 100),
                               format: { "\(Int($0.rounded()))" }) { [weak self] v in
                self?.model.setContrast(entry.info.id, UInt16(v.rounded()))
            }
            c.view = contrastView
            sliderRows[entry.info.id, default: [:]][.contrast] = contrastView
            menu.addItem(c)
        } else if entry.brightnessSource == .none {
            let none = InfoMenuItem.make("No DDC control")
            none.indentationLevel = 1
            menu.addItem(none)
        }

        let res = NSMenuItem()
        res.view = ResolutionRow(plan: entry.plan) { [weak self] spec in
            guard let self else { return .failure }
            let rc = self.model.apply(spec, to: entry.info.id)
            if rc != .success { Log.modes.error("apply failed rc=\(rc.rawValue)") }
            return rc
        }
        res.submenu = ResolutionMenu.make(plan: entry.plan, displayID: entry.info.id, target: self, action: #selector(pickMode(_:)))
        menu.addItem(res)

        let ns: NSMenuItem
        switch entry.tvState {
        case .ok:
            ns = InfoMenuItem.make("✓ Night Shift works on this display")
        case .fixedPendingReconnect:
            ns = InfoMenuItem.make("⏳ Marked as a monitor — reconnect to enable Night Shift")
        case .blocked, .skipped:
            ns = NSMenuItem(title: "✗ TV mode · Night Shift blocked · Retry", action: #selector(retryTVFix(_:)), keyEquivalent: "")
            ns.target = self
            ns.representedObject = NSNumber(value: entry.info.id)
        }
        menu.addItem(ns)
    }

    /// The built-in panel's one Brightness slider: Dim along the bottom
    /// fifth, macOS's range in the middle, and the XDR boost along the top
    /// fifth where the panel has headroom (`BuiltInSlider`).
    private func addBuiltInBrightnessRow(_ entry: DisplayModel.Entry, to menu: NSMenu) {
        let canBoost = xdr.canBoost(entry.info.id)
        let row = NSMenuItem()
        let position = builtInLevel().map { BuiltInSlider.position($0, xdr: canBoost) * 100 }
        let view = SliderRow(title: "Brightness", symbol: "sun.max", value: entry.systemBrightness == nil ? nil : position, maximum: 100,
                             valueWidth: Self.builtInValueWidth,
                             // Reads the range live: plugging in or unplugging moves it while the menu is open.
                             format: { [weak self] in BuiltInSlider.label(BuiltInSlider.level(at: $0 / 100, xdr: self?.boostAvailable ?? canBoost)) }) { [weak self] v in
            self?.setBuiltIn(position: v / 100)
        }
        view.toolTip = Self.builtInToolTip
        row.view = view
        builtInRow = view
        menu.addItem(row)
    }

    /// Why the slider stops at full on a panel that could go past it: on
    /// battery, or on a preset that can't give headroom (or once the panel
    /// granted none).
    private func addXDRRows(_ entry: DisplayModel.Entry, to menu: NSMenu) {
        let id = entry.info.id
        guard XDRPolicy.available, xdr.isSupported(id) else { return }
        if xdr.isBlockedByBattery {
            menu.addItem(InfoMenuItem.make("XDR Brightness · off on battery"))
        }
        if let hint = xdr.presetHint(id) {
            let row = InfoMenuItem.make(hint)
            row.toolTip = "XDR Brightness needs headroom above SDR white, which only the XDR preset gives (System Settings ▸ Displays ▸ Preset)."
            menu.addItem(row)
        }
    }

    /// Room for the longest readout, "XDR +100%"; the Dim labels are shorter.
    static let builtInValueWidth: CGFloat = 62

    static let builtInToolTip = "The bottom of the slider dims past the lowest brightness. Where the panel has HDR headroom, the top brightens past full."

    @objc func pickMode(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ModeBox else { return }
        _ = model.apply(box.mode, to: CGDirectDisplayID(sender.tag))
    }

    @objc func retryTVFix(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value, let entry = model.entry(id) else { return }
        model.tvRoles.clearSkipped(entry.info)
        fixTVRole(entry.info)
    }
}

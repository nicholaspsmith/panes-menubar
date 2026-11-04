// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import IOKit.ps
import DisplayCore

/// XDR brightness for the built-in panel: a full-screen, multiply-composited
/// EDR overlay (`EDRMultiplyOverlay`) per built-in panel. The EDR layer makes
/// the window server put the panel into HDR mode, and its uniform value
/// multiplies everything beneath it into the headroom the panel grants.
///
/// The overlay replaces the transfer table this used to write (Monitor
/// Lizard's BrightIntosh-style boost): on macOS 27 an M5 Pro/Max panel ignores
/// `CGSetDisplayTransferByTable` — it reports success and reads back, but
/// nothing changes on screen (Apple FB22273730, issue #28). The full-screen
/// layer also engages HDR by itself, so the old 1-px trigger window is gone.
///
/// A colour boost is exactly what BetterDisplay's wake colour-scramble bug
/// left behind, so the lifecycle is the feature; "cleared" means the overlay
/// is closed:
/// - off at every launch; the on state is never persisted
/// - the overlay is closed before sleep, before display sleep, on quit, and
///   at the start of every display reconfiguration (lid close, the panel
///   leaving the display list); it comes back only once reconfiguration has
///   been quiet for `settleDelay`
/// - unplugging switches it off (optional, on by default)
/// - built-in displays only; external displays are never touched
/// - Dim and XDR are exclusive: the one Brightness slider (`BuiltInSlider`)
///   and the keys (`BrightnessKeys.route`) never give a dim and a boost at once
///
/// On quit, `applicationWillTerminate` → `DisplaysFeature.stop()` → `stop()`
/// closes the overlay. A crash can't leave it behind: unlike a transfer table
/// it is a window, and it dies with the process.
final class XDRController {
    static let offOnBatteryKey = "xdrOffOnBattery"
    private static let settleDelay: TimeInterval = 2

    private(set) var isEnabled = false {
        // The boost is the top of the Brightness slider, which only exists
        // while XDR is on; switching off (by hand or on battery) lowers it.
        didSet { if !isEnabled { boost = 0 } }
    }
    /// 0…1 across the panel's usable headroom: the top fifth of the built-in
    /// Brightness slider. Starts at 0, so switching XDR on changes nothing
    /// until the slider or the keys go past full. In memory only.
    var boost: Float = 0 {
        didSet { update() }
    }
    /// Read through to UserDefaults rather than once at init: the controller
    /// exists before the Monitor Lizard migration copies this key in.
    /// Safe by default: an absent key reads as "switch off on battery".
    var offOnBattery: Bool {
        get { UserDefaults.standard.object(forKey: Self.offOnBatteryKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.offOnBatteryKey)
            switchOffIfOnBattery()
            update()
        }
    }
    /// The toggle can't be turned on while unplugged with "Off on Battery" set.
    /// (No menu row since 2026-09-26: the setting keeps its stored value,
    /// on by default.)
    var isBlockedByBattery: Bool { onBattery && offOnBattery }

    private var onBattery = false
    private var systemAsleep = false
    private var screensAsleep = false
    private var settling = false
    private var settleWork: DispatchWorkItem?
    private var overlays: [CGDirectDisplayID: EDRMultiplyOverlay] = [:]
    /// When each panel's overlay first asked for headroom, until it was
    /// granted or `hdrWait` ran out.
    private var asking: [CGDirectDisplayID: Date] = [:]
    /// Panels whose boost is on screen (headroom granted), for the logs.
    private var boosted: Set<CGDirectDisplayID> = []
    /// The headroom each panel granted the last time the overlay asked: nil
    /// until it has asked; ≤ `hdrReadyThreshold` when nothing came. Feeds the
    /// menu's preset hint.
    private var granted: [CGDirectDisplayID: Float] = [:]
    /// How long the panel may take to switch into HDR mode once the overlay
    /// asks (measured: under 0.25 s on the XDR preset).
    private static let hdrWait: TimeInterval = 2
    /// While the overlay is up: follows the panel's headroom, which ramps up
    /// for ~1.5 s after HDR engages (1.0 → 6.3 measured) and moves with
    /// brightness, so the factor never sits above what is granted.
    private var headroomTimer: Timer?
    private static let headroomInterval: TimeInterval = 0.25
    private var powerSource: CFRunLoopSource?

    func start() {
        onBattery = Self.isOnBattery()
        switchOffIfOnBattery()
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard let userInfo else { return }
            let controller = Unmanaged<XDRController>.fromOpaque(userInfo).takeUnretainedValue()
            controller.reconfigured(beginning: flags.contains(.beginConfigurationFlag))
        }, Unmanaged.passUnretained(self).toOpaque())

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemAsleep = true
            self?.update()
        }
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true
            self?.update()
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemAsleep = false
            self?.settle()
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false
            self?.settle()
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<XDRController>.fromOpaque(context).takeUnretainedValue().powerChanged()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
    }

    /// On quit: the overlay goes before the app does.
    func stop() {
        isEnabled = false
        update()
    }

    func setEnabled(_ on: Bool) {
        isEnabled = on && XDRPolicy.canEnable(onBattery: onBattery, offOnBattery: offOnBattery)
        // A fresh try: the preset may have changed since the last one.
        if isEnabled { granted = [:] }
        Log.xdr.info("XDR brightness \(self.isEnabled ? "on" : "off")")
        update()
    }

    /// Whether the display is a built-in panel with EDR headroom to boost into.
    func isSupported(_ id: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsBuiltin(id) != 0, let screen = Self.screen(for: id) else { return false }
        return screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1
    }

    /// Whether the panel's preset can give headroom at all (not an SDR preset).
    func canHaveHeadroom(_ id: CGDirectDisplayID) -> Bool {
        guard let screen = Self.screen(for: id) else { return false }
        return XDRPolicy.canHaveHeadroom(potentialHeadroom: Float(screen.maximumPotentialExtendedDynamicRangeColorComponentValue))
    }

    /// The menu's "switch the preset" line, or nil while the panel can (or
    /// did) give headroom.
    func presetHint(_ id: CGDirectDisplayID) -> String? {
        guard let screen = Self.screen(for: id) else { return nil }
        return XDRPolicy.presetHint(potentialHeadroom: Float(screen.maximumPotentialExtendedDynamicRangeColorComponentValue),
                                    grantedHeadroom: granted[id])
    }

    // MARK: - Lifecycle

    private func reconfigured(beginning: Bool) {
        if beginning {
            // Close before the display list changes under the overlay.
            settleWork?.cancel()
            settling = true
            update()
        } else {
            settle()
        }
    }

    /// Hold the boost off until wake/reconfiguration has been quiet for a while.
    private func settle() {
        settleWork?.cancel()
        settling = true
        update()
        let work = DispatchWorkItem { [weak self] in
            self?.settling = false
            self?.update()
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func powerChanged() {
        let now = Self.isOnBattery()
        guard now != onBattery else { return }
        onBattery = now
        switchOffIfOnBattery()
        update()
    }

    private func switchOffIfOnBattery() {
        guard XDRPolicy.shouldSwitchOff(enabled: isEnabled, onBattery: onBattery, offOnBattery: offOnBattery) else { return }
        isEnabled = false
        Log.xdr.info("XDR brightness switched off: on battery")
    }

    private func update() {
        if XDRPolicy.shouldBoost(enabled: isEnabled, asleep: systemAsleep || screensAsleep, settling: settling,
                                 onBattery: onBattery, offOnBattery: offOnBattery) {
            apply()
        } else {
            clear()
        }
    }

    // MARK: - Overlay

    private func apply() {
        let panels = Self.builtInDisplays()
        // A panel that has left the list takes its overlay with it.
        for id in overlays.keys where !panels.contains(id) { closeOverlay(id) }
        for id in panels {
            guard let screen = Self.screen(for: id) else { continue }
            guard screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1 else { continue }
            let overlay = overlays[id] ?? EDRMultiplyOverlay(screen: screen)
            overlays[id] = overlay
            follow(id, overlay, screen: screen)
        }
        if boost > 0 { startTrackingHeadroom() } else { stopTrackingHeadroom() }
    }

    /// Sets the overlay's factor from the boost and the headroom the panel
    /// grants now. With no headroom yet it draws the request value, which
    /// asks for HDR mode without visibly changing anything.
    private func follow(_ id: CGDirectDisplayID, _ overlay: EDRMultiplyOverlay, screen: NSScreen) {
        let headroom = Float(screen.maximumExtendedDynamicRangeColorComponentValue)
        let potential = Float(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
        let factor = XDRBrightness.overlayFactor(boost: boost, headroom: headroom)
        let changed = overlay.factor != factor
        if changed { overlay.factor = factor }
        guard boost > 0 else {
            // Hidden: the next boost asks afresh.
            asking[id] = nil
            if boosted.remove(id) != nil { Log.xdr.info("display \(id): boost 0, overlay hidden") }
            return
        }
        if XDRBrightness.isHDREngaged(currentHeadroom: headroom) {
            granted[id] = headroom
            if let since = asking.removeValue(forKey: id) {
                Log.xdr.info("display \(id): HDR engaged in \(Date().timeIntervalSince(since), format: .fixed(precision: 2)) s, headroom \(headroom) of potential \(potential)")
            }
            if boosted.insert(id).inserted {
                Log.xdr.info("display \(id): boost on, factor \(factor) of headroom \(headroom)")
            } else if changed {
                Log.xdr.debug("display \(id): factor \(factor) of headroom \(headroom)")
            }
            return
        }
        boosted.remove(id)
        guard let since = asking[id] else {
            asking[id] = Date()
            return
        }
        // Once per try: a failure already recorded stays recorded.
        let alreadyFailed = granted[id].map { !XDRBrightness.isHDREngaged(currentHeadroom: $0) } ?? false
        if Date().timeIntervalSince(since) > Self.hdrWait, !alreadyFailed {
            granted[id] = headroom
            Log.xdr.error("display \(id): panel never entered HDR mode (headroom \(headroom), potential \(potential)); on an SDR preset? Not boosting")
        }
    }

    private func startTrackingHeadroom() {
        guard headroomTimer == nil else { return }
        let t = Timer(timeInterval: Self.headroomInterval, repeats: true) { [weak self] _ in self?.trackHeadroom() }
        RunLoop.main.add(t, forMode: .common) // keeps following while the menu is open
        headroomTimer = t
    }

    private func stopTrackingHeadroom() {
        headroomTimer?.invalidate()
        headroomTimer = nil
    }

    private func trackHeadroom() {
        for (id, overlay) in overlays {
            guard let screen = Self.screen(for: id) else { continue }
            follow(id, overlay, screen: screen)
            overlay.keepPresenting()
        }
    }

    private func closeOverlay(_ id: CGDirectDisplayID) {
        overlays.removeValue(forKey: id)?.close()
        asking[id] = nil
        boosted.remove(id)
    }

    private func clear() {
        stopTrackingHeadroom()
        let wasBoosted = !boosted.isEmpty
        for id in Array(overlays.keys) { closeOverlay(id) }
        if wasBoosted { Log.xdr.info("boost off: overlay closed") }
    }

    // MARK: - System queries

    private static func builtInDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) != 0 }
    }

    private static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    private static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}

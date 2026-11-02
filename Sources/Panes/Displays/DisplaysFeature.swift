// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import DisplayCore
import HotkeyKit
import StatusItemKit
import UserNotifications

/// Monitor Lizard's app layer inside Panes: external-display control (DDC
/// brightness and contrast, DisplayServices brightness where macOS drives the
/// display itself), HiDPI resolution, built-in brightness, Night Shift with an
/// automatic fix for displays macOS wrongly calls televisions, and XDR
/// brightness and dimming below macOS's minimum for the built-in panel.
///
/// Panes's `App` owns the status item, the icon, the minute cue and the
/// settings footer. This class tells it when the icon's inputs change
/// (`onIconInputsChanged`) and contributes menu sections.
final class DisplaysFeature: NSObject {
    private let status: StatusItemController
    private let notifier = Notifier()
    let model: DisplayModel
    private var tongueUntil = Date.distantPast
    /// The big lap round the whole screen, played at launch, when a new
    /// display appears and when Night Shift turns on or off.
    private let screenLapRun = MonitorLizardLap()
    private var lapTrigger = LapTrigger()
    /// Once a minute, in his turn with the other animated mascots, Armonitor
    /// runs a lap of his own monitor in the icon. Progress 0...1, 0 at rest.
    private var iconLap: CGFloat = 0
    private lazy var iconLapAnimation = IconAnimation(duration: CharacterIcon.monitorLizardLapDuration, frame: { [weak self] t in
        self?.iconLap = CGFloat(t / CharacterIcon.monitorLizardLapDuration)
        self?.drawLapFrame()
    }, completion: { [weak self] in
        self?.iconLap = 0
        self?.refreshIcon()
    })
    /// Open-menu slider rows, so a confirmed read can correct them in place.
    var sliderRows: [CGDirectDisplayID: [VCPCode: SliderRow]] = [:]
    /// Same, for DisplayServices brightness rows: the keyboard keys and
    /// Control Center move these while the menu is open.
    var systemBrightnessRows: [CGDirectDisplayID: SliderRow] = [:]
    private var fixInProgress = false
    /// The brightness keys' routing. Panes's one `HotkeyTap` carries its
    /// bindings (`brightnessBindings`) and sends it their presses
    /// (`handleBrightness`). Made on first use, so it exists before `start()`.
    private lazy var brightnessKeys: BrightnessKeyController = {
        let keys = BrightnessKeyController(
            route: { [weak self] direction in
                guard let self else { return .passThrough }
                let builtIn = self.model.entries.first { $0.info.isBuiltIn }
                return BrightnessKeys.route(
                    among: self.model.entries.map {
                        BrightnessKeys.Display(id: $0.info.id, isMain: $0.info.isMain,
                                               isBuiltIn: $0.info.isBuiltIn, source: $0.brightnessSource)
                    },
                    direction: direction,
                    builtInBrightness: builtIn.flatMap { self.model.liveSystemBrightness($0.info.id) },
                    dimLevel: self.dimmer.level,
                    dimAvailable: self.dimmer.isAvailable,
                    xdrEnabled: self.xdr.isEnabled,
                    boost: self.xdr.boost
                )
            },
            stepExternal: { [weak self] id, direction in self?.model.stepBrightness(id, direction) },
            stepDim: { [weak self] direction in self?.stepDim(direction) },
            stepBoost: { [weak self] direction in self?.stepBoost(direction) }
        )
        keys.onBindingsChanged = { [weak self] in self?.onBrightnessBindingsChanged?() }
        return keys
    }()
    /// XDR brightness for the built-in panel; off at every launch.
    let xdr = XDRController()
    /// Dimming the built-in panel below macOS's lowest lit brightness; off at
    /// every launch.
    let dimmer = DimOverlayController()
    /// The open menu's built-in Brightness row (dim, macOS, XDR boost in one),
    /// so the keys and outside changes move it.
    weak var builtInRow: SliderRow?
    /// The built-in panel's last macOS brightness, to notice it being raised.
    private var lastBuiltInBrightness: Float?
    /// Night Shift on Monitor Lizard's own schedule, and its window.
    private var scheduler: NightShiftScheduler?
    private var scheduleWindow: NightShiftScheduleWindow?

    /// Called when the brightness, Night Shift state, tongue or lap changed, so
    /// the owner redraws the lizard icon.
    var onIconInputsChanged: (() -> Void)?
    /// Whether the Armonitor icon is the one showing. The tongue and the
    /// full-screen lap act only then.
    var isArmonitorShown: () -> Bool = { false }
    /// Called when `brightnessBindings` changes (Brightness Keys turned on or
    /// off), so the owner hands its tap the new binding set.
    var onBrightnessBindingsChanged: (() -> Void)?

    /// Whether `start()` has run. Panes starts the feature only after the
    /// Monitor Lizard cut-over, so until then ML may still own the keys.
    private(set) var isStarted = false

    /// The brightness keys' bindings for the owner's `HotkeyTap`, after its
    /// own. Empty while the Brightness Keys are off, and before `start()`.
    var brightnessBindings: [Binding] { isStarted ? brightnessKeys.bindings : [] }

    /// A press the owner's tap matched. True to swallow it; false for a token
    /// that isn't a brightness key's, or a press that goes on to macOS.
    func handleBrightness(token: String) -> Bool { brightnessKeys.handle(token: token) }

    /// Whether this token is one of `brightnessBindings`'.
    func isBrightnessToken(_ token: String) -> Bool { BrightnessKeyController.isBrightnessToken(token) }

    init(status: StatusItemController) {
        self.status = status
        model = DisplayModel(brightness: DisplayServicesBrightness(), nightShift: CoreBrightnessNightShift(), tvRoles: TVRoleTracker())
        super.init()
    }

    func start() {
        isStarted = true
        model.onChange = { [weak self] in self?.modelChanged() }
        model.onWrite = { [weak self] in self?.flickTongueIfShown() }
        // Dispatched async so the admin dialog in `fixTVRole` never runs from
        // inside `DisplayModel.refresh()`'s own enumeration loop.
        model.onNeedsTVFix = { [weak self] info in DispatchQueue.main.async { self?.fixTVRole(info) } }
        model.start()
        if let ns = model.nightShift, ns.isAvailable {
            let scheduler = NightShiftScheduler(backend: ns)
            scheduler.onChange = { [weak self] in self?.refreshIcon() }
            scheduler.start()
            self.scheduler = scheduler
            scheduleWindow = NightShiftScheduleWindow(scheduler: scheduler)
        }
        // A lap to say hello. Deferred so the status item has its place in the
        // bar before he leaves it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.screenLapIfArmonitor() }

        xdr.start()
        dimmer.start()
        lastBuiltInBrightness = model.entries.first { $0.info.isBuiltIn }?.systemBrightness
        updateShown()
    }

    func stop() {
        // The boost's transfer table must never outlive the app.
        xdr.stop()
        dimmer.stop()
    }

    /// The 60 s safety net. Brightness and Night Shift both push change
    /// notifications; this is only for a missed one. DDC is never polled.
    func safetyPoll() {
        model.readSystemBrightness()
        refreshIcon()
    }

    // MARK: - Icon

    /// The brightness and Night Shift the icon last showed. Lap frames reuse
    /// them: asking the display for both 60 times a second is what made the
    /// lap expensive, not drawing it.
    private var shown: (fraction: CGFloat, nightShift: Bool) = (0, false)

    /// The main display's brightness, 0...1, as of the last icon refresh.
    var mainBrightnessFraction: Double { Double(shown.fraction) }
    /// Whether Night Shift is on, as of the last icon refresh.
    var nightShiftOn: Bool { shown.nightShift }
    /// Whether the lizard's tongue is out.
    var tongueActive: Bool { Date() < tongueUntil }
    /// Whether the full-screen lap is running (the lizard is off the icon).
    var isScreenLapRunning: Bool { screenLapRun.isRunning }
    /// Progress 0...1 of the lap round his own monitor in the icon; 0 at rest.
    var iconLapProgress: CGFloat { iconLap }

    private func updateShown() {
        shown = (CGFloat(model.mainBrightnessFraction), model.nightShift?.status().enabled ?? false)
    }

    /// A frame of the icon lap, about 60 a second. Draws from `shown`, not
    /// from the display.
    private func drawLapFrame() {
        guard isArmonitorShown() else { return }
        onIconInputsChanged?()
    }

    func refreshIcon() {
        updateShown()
        onIconInputsChanged?()
    }

    /// Run the lap round Armonitor's own monitor in the icon (the minute cue).
    /// Only while he is the icon, and not while the full-screen lap is out.
    func runIconLap() {
        guard isArmonitorShown(), !screenLapRun.isRunning else { return }
        iconLapAnimation.start()
    }

    /// Stop the icon lap where it is, for when another icon is chosen. The
    /// tongue needs no stopping: it is only a deadline the drawing reads.
    func cancelIconLap() {
        iconLapAnimation.cancel()
        iconLap = 0
    }

    /// Armonitor leaves the monitor and slithers counterclockwise round the
    /// whole screen and back: when the app starts, when a display it has not
    /// seen appears, and when Night Shift turns on or off (`LapTrigger`) —
    /// yes/no changes only, never a slider. A second trigger while he is out
    /// is ignored. Not while the slot is lent out (yielded) or off screen, and
    /// not under Reduce Motion.
    func screenLapIfArmonitor() {
        guard isArmonitorShown(), !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              !screenLapRun.isRunning, let button = status.button,
              let window = button.window, let screen = window.screen else { return }
        let slot = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard slot.width >= 8 else { return }
        iconLapAnimation.cancel()
        iconLap = 0
        screenLapRun.run(from: slot, on: screen) { [weak self] in self?.refreshIcon() }
        refreshIcon()
    }

    func flickTongueIfShown() {
        guard isArmonitorShown() else { return }
        tongueUntil = Date().addingTimeInterval(0.6)
        refreshIcon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in self?.refreshIcon() }
    }

    /// A brightness key press past macOS's minimum, or back.
    private func stepDim(_ direction: BrightnessKeys.Direction) {
        guard let builtIn = model.entries.first(where: { $0.info.isBuiltIn }) else { return }
        let brightness = model.liveSystemBrightness(builtIn.info.id) ?? 0
        let next = PanelDim.keyStep(level: dimmer.level, brightness: brightness, direction: direction)
        if next.level > 0 { dimmer.level = next.level }
        if let b = next.brightness {
            // Set before `lastBuiltInBrightness` sees it, so coming back from
            // off doesn't read as someone raising the brightness.
            lastBuiltInBrightness = b
            model.setSystemBrightness(builtIn.info.id, b)
        }
        if next.level == 0 { dimmer.level = 0 }
        refreshBuiltInRow()
    }

    /// A brightness key press past full brightness with XDR on, or back.
    private func stepBoost(_ direction: BrightnessKeys.Direction) {
        xdr.boost = BuiltInSlider.boostStep(xdr.boost, direction)
        refreshBuiltInRow()
    }

    /// Where the built-in panel is along its one Brightness slider.
    func builtInLevel() -> BuiltInLevel? {
        guard let entry = model.entries.first(where: { $0.info.isBuiltIn }) else { return nil }
        return BuiltInLevel(dim: dimmer.level, brightness: entry.systemBrightness ?? 0, boost: xdr.boost)
    }

    /// The built-in Brightness slider moved: set the dim, macOS brightness and
    /// boost it stands for.
    func setBuiltIn(position: Double) {
        guard let entry = model.entries.first(where: { $0.info.isBuiltIn }) else { return }
        let level = BuiltInSlider.level(at: position, xdr: xdr.isEnabled)
        dimmer.level = level.dim
        if xdr.isEnabled { xdr.boost = level.boost }
        if entry.systemBrightness != level.brightness {
            lastBuiltInBrightness = level.brightness
            model.setSystemBrightness(entry.info.id, level.brightness)
        }
        refreshIcon()
    }

    func refreshBuiltInRow() {
        guard let level = builtInLevel() else { return }
        builtInRow?.update(value: BuiltInSlider.position(level, xdr: xdr.isEnabled) * 100)
    }

    private func modelChanged() {
        // Raising macOS brightness while dimmed (Control Center, auto-brightness
        // in a brighter room) means someone wants light: drop the dim.
        let builtIn = model.entries.first { $0.info.isBuiltIn }?.systemBrightness
        if dimmer.level > 0, PanelDim.cancels(previous: lastBuiltInBrightness, current: builtIn) {
            Log.xdr.info("dim cancelled: brightness raised to \(builtIn ?? -1)")
            dimmer.level = 0
        }
        lastBuiltInBrightness = builtIn
        refreshIcon()
        if lapTrigger.update(displays: Set(model.entries.map { $0.info.id }),
                             nightShift: model.nightShift?.status().enabled) {
            screenLapIfArmonitor()
        }
        // Correct any open slider to the value the monitor confirmed, or that
        // DisplayServices reports after a change made elsewhere.
        for entry in model.entries {
            if let v = entry.brightness { sliderRows[entry.info.id]?[.brightness]?.update(value: Double(v.current)) }
            if let v = entry.contrast { sliderRows[entry.info.id]?[.contrast]?.update(value: Double(v.current)) }
            if let b = entry.systemBrightness { systemBrightnessRows[entry.info.id]?.update(value: Double(b) * 100) }
        }
        refreshBuiltInRow()
    }

    // MARK: - Menu

    /// The display blocks and the Night Shift block.
    func addMenuSection(to menu: NSMenu) {
        sliderRows = [:]
        systemBrightnessRows = [:]
        model.readValues()

        if model.entries.isEmpty {
            menu.addItem(disabledItem("No displays"))
        }
        for (i, entry) in model.entries.enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            addDisplaySection(entry, to: menu)
        }

        menu.addItem(.separator())
        if let ns = model.nightShift, ns.isAvailable {
            let s = ns.status()
            var items = [ToggleMenuItem.make(title: "Enabled", isOn: s.enabled) { [weak self] on in
                self?.setNightShift(on)
            }]
            let warmth = NSMenuItem()
            let shownWarmth = scheduler?.sliderWarmth ?? s.strength
            warmth.view = SliderRow(title: "Warmth", symbol: "thermometer.sun", value: Double(shownWarmth) * 100, maximum: 100,
                                    format: { "\(Int($0.rounded()))" }) { [weak self] v in
                if let scheduler = self?.scheduler { scheduler.warmthSliderMoved(to: Float(v / 100)) }
                else { _ = ns.setStrength(Float(v / 100)) }
            }
            items.append(warmth)
            if let scheduler {
                let item = actionItem("Schedule…", #selector(showSchedule))
                item.state = scheduler.schedule.isEnabled ? .on : .off
                items.append(item)
                if let line = scheduleLine(scheduler) { items.append(disabledItem(line)) }
            }
            MenuSection.add(title: "Night Shift", key: "nightShift", items: items, to: menu)
        } else {
            menu.addItem(disabledItem("Night Shift unavailable on this macOS"))
        }
    }

    /// Whether the keyboard's brightness keys step the main monitor over DDC
    /// (the Settings window's Brightness Keys).
    var brightnessKeysEnabled: Bool {
        get { brightnessKeys.isEnabled }
        set { brightnessKeys.isEnabled = newValue }
    }

    /// A line of information: greyed and not selectable, like a native
    /// section header. (The menu doesn't autoenable, so an item without an
    /// action would otherwise highlight and do nothing.)
    func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func actionItem(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - TV-role fix

    /// Posts after the permission is known. The first call asks (nothing is
    /// asked at launch) and posts from the answer; posting before it arrives
    /// would be rejected.
    private func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let post = { [notifier] in notifier.post(title: title, body: body) }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                DispatchQueue.main.async(execute: post)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { DispatchQueue.main.async(execute: post) }
                }
            default:
                break
            }
        }
    }

    func fixTVRole(_ info: DisplayInfo) {
        guard !fixInProgress, model.tvRoles.needsFix(info) else { return }
        // Held through the trailing async refresh (reset there, not via
        // `defer`), so a second blocked display's queued fix waits until this
        // one has fully settled rather than firing while the admin dialog for
        // this one is still up — it gets picked up by that refresh instead.
        fixInProgress = true
        switch OverrideWriter.write(for: info) {
        case .written:
            notify(title: "Marked \(info.name) as a monitor",
                   body: "Reconnect it (or reboot) to enable Night Shift.")
        case .cancelled:
            model.tvRoles.markSkipped(info)
        case .failed(let message):
            notify(title: "Couldn't mark \(info.name) as a monitor", body: message)
            model.tvRoles.markSkipped(info)
        }
        DispatchQueue.main.async { [weak self] in
            self?.model.refresh()
            self?.fixInProgress = false
        }
    }

    // MARK: - Selectors

    private func setNightShift(_ on: Bool) {
        guard let ns = model.nightShift else { return }
        _ = ns.setEnabled(on)
        refreshIcon()
    }

    @objc private func showSchedule() { scheduleWindow?.show() }

    /// "On until 6:48 AM" / "On at 7:12 PM", under the Schedule item.
    private func scheduleLine(_ scheduler: NightShiftScheduler) -> String? {
        guard scheduler.schedule.isEnabled else { return nil }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        if let now = scheduler.currentWindow { return "Off at \(f.string(from: now.off))" }
        if let next = scheduler.nextWindow { return "On at \(f.string(from: next.on))" }
        return nil
    }
}

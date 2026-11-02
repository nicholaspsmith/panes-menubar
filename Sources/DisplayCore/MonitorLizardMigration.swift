// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Monitor Lizard's settings, brought into Panes's domain once, after the
/// cut-over has quit it (so the snapshot is final).
///
/// Only the keys in `copiedKeys` move, and only where Panes has no value of
/// its own. ML's `MeterStyle` becomes Panes's `IconStyle` (below); its
/// `NSStatusItem …` positions never move (they describe ML's own item). The
/// old domain is never deleted: it goes with ML's uninstall.
public enum MonitorLizardMigration {
    /// Set in Panes's domain once the copy has run.
    public static let doneKey = "migratedFromMonitorLizard"
    public static let oldDomain = "com.nicholaspsmith.MonitorLizard"
    /// When the copied `nightShiftPlace` was last known good. Written with it.
    public static let placeDateKey = "nightShiftPlaceDate"

    /// Every UserDefaults key Monitor Lizard's code reads, as found by
    /// grepping DisplayCore, Sources/Panes/Displays (ML's app layer) and
    /// StatusItemKit's MeterAppearance, and checked against
    /// `defaults read com.nicholaspsmith.MonitorLizard` on the M5 and the M1
    /// (2026-11-01). There are no TV-role or DDC keys: the TV-role fix is a
    /// display override plist under /Library/Displays, its "skipped" set lives
    /// in memory, and DDC keeps no cache on disk.
    public static let copiedKeys: [String] = [
        "brightnessKeys",            // BrightnessKeyController.enabledKey (Bool)
        "xdrOffOnBattery",           // XDRController.offOnBatteryKey (Bool)
        "nightShiftSchedule",        // NightShiftScheduler.scheduleKey (JSON Data)
        "nightShiftScheduleWarmth",  // NightShiftScheduler.warmthKey (Float)
        "nightShiftPlace",           // NightShiftScheduler.placeKey (JSON Data)
        "MeterColorHex",             // StatusItemKit MeterAppearance.colorKey (String)
    ]

    /// StatusItemKit's `MeterAppearance.styleKey`: read, never copied.
    static let meterStyleKey = "MeterStyle"
    /// PanesCore's `IconChoice.key` (DisplayCore doesn't depend on PanesCore).
    static let iconStyleKey = "IconStyle"
    /// ML's character icon, which Panes's own icon choice replaces.
    static let characterStyle = "character"

    /// Keys to write into Panes's domain. `old` is ML's domain; `existing` the keys Panes already has.
    public static func values(old: [String: Any], existing: Set<String>, now: Date) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in copiedKeys where !existing.contains(key) {
            if let value = old[key] { result[key] = value }
        }
        if result["nightShiftPlace"] != nil { result[placeDateKey] = now }
        // `character` maps to nothing: the grid default wins over ML's lizard.
        if let style = old[meterStyleKey] as? String, !style.isEmpty, style != characterStyle,
           !existing.contains(iconStyleKey) {
            result[iconStyleKey] = "meter:" + style
        }
        return result
    }

    /// Runs the copy into `defaults` (whose persistent domain is `domain`)
    /// unless `doneKey` is already set there, then sets it. Returns the keys
    /// written, or nil when it had already run.
    @discardableResult
    public static func applyOnce(old: [String: Any], to defaults: UserDefaults, domain: String,
                                 now: Date = Date()) -> [String]? {
        let existing = defaults.persistentDomain(forName: domain) ?? [:]
        guard existing[doneKey] as? Bool != true else { return nil }
        let new = values(old: old, existing: Set(existing.keys), now: now)
        for (key, value) in new { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: doneKey)
        return new.keys.sorted()
    }

    /// One domain's own keys for the current user, any host. Unlike
    /// `UserDefaults(suiteName:).dictionaryRepresentation()`, nothing from the
    /// global or registration domains is mixed in.
    public static func readDomain(_ domain: String) -> [String: Any] {
        let all = CFPreferencesCopyMultiple(nil, domain as CFString,
                                            kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return all as? [String: Any] ?? [:]
    }
}

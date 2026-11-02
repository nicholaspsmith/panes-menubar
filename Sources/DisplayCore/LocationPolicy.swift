// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// When Night Shift's sun schedule may ask macOS for the Mac's location. A
/// saved place is good for a month; Location is only asked for when there is
/// none, it has gone stale, or the Schedule window has just been opened.
public enum LocationPolicy {
    public static let maxAge: TimeInterval = 30 * 24 * 3600
    /// When the saved place was last known good (shared with the migration).
    public static let dateKey = MonitorLizardMigration.placeDateKey

    public static func shouldLocate(hasPlace: Bool, placeDate: Date?, now: Date, scheduleOpened: Bool, timeZoneChanged: Bool = false) -> Bool {
        if scheduleOpened || timeZoneChanged || !hasPlace { return true }
        guard let placeDate else { return true }
        return now.timeIntervalSince(placeDate) > maxAge
    }

    /// The place to keep using when Location is denied or restricted: the
    /// saved one, untouched. Nil means none was saved (use the time zone).
    public static func placeKeptOnDenial(defaults: UserDefaults, placeKey: String) -> Coordinate? {
        guard let data = defaults.data(forKey: placeKey) else { return nil }
        return try? JSONDecoder().decode(Coordinate.self, from: data)
    }
}

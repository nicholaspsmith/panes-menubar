// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

/// Which icon Panes shows in the menu bar (Icon ▸), as stored under `key`.
///
/// Nothing stored, or anything this build doesn't know (an empty string, a
/// meter shape it doesn't draw, a typo), is the Screen Grid: an unreadable
/// choice never leaves the bar blank.
public enum IconChoice: Equatable {
    /// The display's windows drawn as tiles. The default.
    case grid
    /// Major Pane, the mascot.
    case majorPane
    /// Monitor Lizard's Armonitor: the main display's brightness and Night Shift.
    case armonitor
    /// One of Monitor Lizard's brightness meters; the String is StatusItemKit's
    /// `MeterStyle` raw value ("arc", "gauge", …).
    case meter(String)

    /// The defaults key. The same one Panes has always used for the
    /// grid/Major Pane choice, so a saved "grid" or "major-pane" is kept.
    public static let key = "IconStyle"

    private static let meterPrefix = "meter:"

    /// - Parameter knownMeters: the meter shapes this build can draw; any
    ///   other `meter:` value reads as the grid.
    public init(stored: String?, knownMeters: Set<String>) {
        switch stored {
        case "major-pane": self = .majorPane
        case "armonitor": self = .armonitor
        case let s? where s.hasPrefix(Self.meterPrefix):
            let raw = String(s.dropFirst(Self.meterPrefix.count))
            self = knownMeters.contains(raw) ? .meter(raw) : .grid
        default: self = .grid
        }
    }

    /// "grid" | "major-pane" | "armonitor" | "meter:<raw>"
    public var stored: String {
        switch self {
        case .grid: return "grid"
        case .majorPane: return "major-pane"
        case .armonitor: return "armonitor"
        case .meter(let raw): return Self.meterPrefix + raw
        }
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

/// The arithmetic of XDR brightness: how far a multiply-composited EDR
/// overlay lifts the built-in panel (`EDRMultiplyOverlay` draws the factor and
/// the window server multiplies everything beneath it), given the headroom
/// the panel reports. Pure, so it is unit-testable without a display.
public enum XDRBrightness {
    /// `NSScreen.maximumExtendedDynamicRangeColorComponentValue` sits at 1.0
    /// until HDR mode is engaged; a factor above it would only clip.
    public static let hdrReadyThreshold: Float = 1.05

    public static func isHDREngaged(currentHeadroom: Float) -> Bool {
        currentHeadroom > hdrReadyThreshold
    }

    /// Never lift SDR white higher than this, whatever headroom the panel
    /// reports: the potential headroom on an XDR panel is reference-mode HDR
    /// (16×), which would blow every highlight out. 2× is ~1000 nits from a
    /// 500-nit SDR ceiling — what the panel sustains full-screen.
    public static let maxFactor: Float = 2

    /// How far to lift SDR white: `boost` 0…1 across 1…min(headroom, maxFactor).
    /// Never above the headroom granted, so nothing clips.
    public static func factor(boost: Float, headroom: Float) -> Float {
        let top = min(max(1, headroom), maxFactor)
        return 1 + max(0, min(1, boost)) * (top - 1)
    }

    /// The least the overlay draws while any boost is wanted. The panel only
    /// grants headroom while an EDR layer is on screen, and the overlay hides
    /// at a factor of 1, so before the headroom arrives (factor 1) it draws
    /// this instead: invisible (white clips back to white), but enough to keep
    /// the layer up and ask for HDR mode.
    public static let requestFactor: Float = 1.001

    /// What the overlay draws: 1 (hidden) with no boost, else the factor, kept
    /// at least at `requestFactor` while the headroom ramps up.
    public static func overlayFactor(boost: Float, headroom: Float) -> Float {
        guard boost > 0 else { return 1 }
        return max(requestFactor, factor(boost: boost, headroom: headroom))
    }

    /// Whether the overlay needs redrawing for a new factor. The headroom
    /// ramps up for a couple of seconds after HDR engages and moves with
    /// brightness, so the factor is tracked, not computed once.
    public static func shouldRewrite(written: Float?, wanted: Float, tolerance: Float = 0.005) -> Bool {
        guard let written else { return true }
        return abs(written - wanted) > tolerance
    }
}

/// When the boost may be on the panel. Everything that can go wrong with a
/// colour boost happens across sleep and reconfiguration, so the overlay is
/// only up while the machine is awake and the display list has settled.
public enum XDRPolicy {
    /// On since the multiply-composited EDR overlay replaced the transfer
    /// table (issue #28): on macOS 27 an M5 Pro/Max panel ignores the table
    /// (Apple FB22273730). Turning this off stops the slider at full.
    public static let available = true

    /// The most potential headroom an SDR preset offers: "Apple Display
    /// (P3-600 nits)" reports 5 and grants none; "Apple XDR Display
    /// (P3-1600 nits)" reports 16.
    public static let sdrPresetPotentialHeadroom: Float = 5

    /// Whether the panel's preset can give any headroom at all.
    public static func canHaveHeadroom(potentialHeadroom: Float) -> Bool {
        potentialHeadroom > sdrPresetPotentialHeadroom
    }

    public static let presetHintText = "Set Displays ▸ Preset to Apple XDR Display (P3-1600 nits)"

    /// Disabled-row text when the panel can't give headroom, else nil: on an
    /// SDR preset, or once the overlay asked and nothing was granted.
    /// `grantedHeadroom` is nil until the overlay has asked.
    public static func presetHint(potentialHeadroom: Float, grantedHeadroom: Float?) -> String? {
        if !canHaveHeadroom(potentialHeadroom: potentialHeadroom) { return presetHintText }
        if let granted = grantedHeadroom, granted <= XDRBrightness.hdrReadyThreshold { return presetHintText }
        return nil
    }

    /// Whether switching XDR on takes: never while unavailable, and not on
    /// battery with Off on Battery set.
    public static func canEnable(available: Bool = available, onBattery: Bool, offOnBattery: Bool) -> Bool {
        available && !(onBattery && offOnBattery)
    }

    public static func shouldBoost(enabled: Bool, asleep: Bool, settling: Bool,
                                   onBattery: Bool, offOnBattery: Bool) -> Bool {
        enabled && !asleep && !settling && !(onBattery && offOnBattery)
    }

    /// Unplugging switches the feature off rather than pausing it, so going
    /// back on power never brightens the panel by surprise.
    public static func shouldSwitchOff(enabled: Bool, onBattery: Bool, offOnBattery: Bool) -> Bool {
        enabled && onBattery && offOnBattery
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import DisplayCore

final class XDRBrightnessTests: XCTestCase {
    func testFactorSpansOneToTheHeadroom() {
        XCTAssertEqual(XDRBrightness.factor(boost: 0, headroom: 1.8), 1, accuracy: 0.0001)
        XCTAssertEqual(XDRBrightness.factor(boost: 1, headroom: 1.8), 1.8, accuracy: 0.0001)
        XCTAssertEqual(XDRBrightness.factor(boost: 0.5, headroom: 1.8), 1.4, accuracy: 0.0001)
    }

    func testFactorIsCappedWhateverTheReportedHeadroom() {
        // An XDR panel reports 16× potential headroom (reference-mode HDR).
        XCTAssertEqual(XDRBrightness.factor(boost: 1, headroom: 16), XDRBrightness.maxFactor, accuracy: 0.0001)
    }

    func testNoHeadroomMeansNoBoost() {
        XCTAssertEqual(XDRBrightness.factor(boost: 1, headroom: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(XDRBrightness.factor(boost: 1, headroom: 0), 1, accuracy: 0.0001)
    }

    func testHDRIsEngagedOnlyOncePanelReportsHeadroom() {
        // Before the overlay takes effect the panel reports 1.0; a rounding wobble is not HDR.
        XCTAssertFalse(XDRBrightness.isHDREngaged(currentHeadroom: 1))
        XCTAssertFalse(XDRBrightness.isHDREngaged(currentHeadroom: 1.02))
        XCTAssertTrue(XDRBrightness.isHDREngaged(currentHeadroom: 1.6))
    }

    func testBoostOnlyWhileAwakeSettledAndAllowedOnPower() {
        XCTAssertTrue(XDRPolicy.shouldBoost(enabled: true, asleep: false, settling: false, onBattery: false, offOnBattery: true))
        XCTAssertTrue(XDRPolicy.shouldBoost(enabled: true, asleep: false, settling: false, onBattery: true, offOnBattery: false))
        XCTAssertFalse(XDRPolicy.shouldBoost(enabled: false, asleep: false, settling: false, onBattery: false, offOnBattery: true))
        XCTAssertFalse(XDRPolicy.shouldBoost(enabled: true, asleep: true, settling: false, onBattery: false, offOnBattery: true))
        XCTAssertFalse(XDRPolicy.shouldBoost(enabled: true, asleep: false, settling: true, onBattery: false, offOnBattery: true))
        XCTAssertFalse(XDRPolicy.shouldBoost(enabled: true, asleep: false, settling: false, onBattery: true, offOnBattery: true))
    }

    func testUnpluggingSwitchesItOffOnlyWhenAsked() {
        XCTAssertTrue(XDRPolicy.shouldSwitchOff(enabled: true, onBattery: true, offOnBattery: true))
        XCTAssertFalse(XDRPolicy.shouldSwitchOff(enabled: true, onBattery: true, offOnBattery: false))
        XCTAssertFalse(XDRPolicy.shouldSwitchOff(enabled: true, onBattery: false, offOnBattery: true))
        XCTAssertFalse(XDRPolicy.shouldSwitchOff(enabled: false, onBattery: true, offOnBattery: true))
    }

    // The panel's headroom ramps from 1.0 to its maximum over ~2 s after HDR
    // engages (measured 1.0 → 5.0 in 2.25 s), and moves with brightness; the
    // overlay is redrawn whenever the factor it should carry changes.
    func testRewriteWhenTheFactorMoves() {
        XCTAssertTrue(XDRBrightness.shouldRewrite(written: nil, wanted: 1.2))
        XCTAssertTrue(XDRBrightness.shouldRewrite(written: 1.26, wanted: 2))
        XCTAssertFalse(XDRBrightness.shouldRewrite(written: 2, wanted: 2.002))
    }

    func testFactorOnceTheHeadroomHasRamped() {
        XCTAssertEqual(XDRBrightness.factor(boost: 1, headroom: 1.26), 1.26, accuracy: 1e-6, "early in the ramp")
        XCTAssertEqual(XDRBrightness.factor(boost: 1, headroom: 5), 2, accuracy: 1e-6, "ramped: capped at maxFactor")
        XCTAssertEqual(XDRBrightness.factor(boost: 0.5, headroom: 5), 1.5, accuracy: 1e-6)
    }

    // MARK: What the overlay draws

    func testNoBoostHidesTheOverlay() {
        XCTAssertEqual(XDRBrightness.overlayFactor(boost: 0, headroom: 2.67), 1)
        XCTAssertEqual(XDRBrightness.overlayFactor(boost: 0, headroom: 1), 1)
    }

    func testBoostBeforeHeadroomStillAsksForIt() {
        // The panel grants headroom only while an EDR layer is up; the factor
        // is 1 until it does, so the overlay draws the invisible request value.
        XCTAssertEqual(XDRBrightness.overlayFactor(boost: 1, headroom: 1), XDRBrightness.requestFactor)
        XCTAssertGreaterThan(XDRBrightness.requestFactor, 1)
        XCTAssertLessThan(XDRBrightness.requestFactor, XDRBrightness.hdrReadyThreshold)
    }

    func testBoostOnceGrantedIsTheFactor() {
        XCTAssertEqual(XDRBrightness.overlayFactor(boost: 1, headroom: 2.67), 2, accuracy: 1e-6)
        XCTAssertEqual(XDRBrightness.overlayFactor(boost: 0.5, headroom: 1.6), 1.3, accuracy: 1e-6)
    }

    // MARK: Availability (issue #28)

    func testXDRIsAvailableWithTheMultiplyOverlay() {
        // The multiply-composited EDR overlay replaces the transfer table that
        // M5 Pro panels ignore under macOS 27 (FB22273730).
        XCTAssertTrue(XDRPolicy.available)
        XCTAssertTrue(XDRPolicy.canEnable(onBattery: false, offOnBattery: true))
        XCTAssertFalse(XDRPolicy.canEnable(available: false, onBattery: false, offOnBattery: true))
    }

    func testWhenAvailableOnlyTheBatteryRuleCanRefuse() {
        XCTAssertTrue(XDRPolicy.canEnable(available: true, onBattery: false, offOnBattery: true))
        XCTAssertTrue(XDRPolicy.canEnable(available: true, onBattery: true, offOnBattery: false))
        XCTAssertFalse(XDRPolicy.canEnable(available: true, onBattery: true, offOnBattery: true))
    }

    // MARK: Preset hint

    private let hint = "Set Displays ▸ Preset to Apple XDR Display (P3-1600 nits)"

    func testPresetHintOnSDRPreset() {
        // "Apple Display (P3-600 nits)": potential headroom 5, nothing granted yet.
        XCTAssertEqual(XDRPolicy.presetHint(potentialHeadroom: 5, grantedHeadroom: nil), hint)
    }

    func testNoHintOnXDRPreset() {
        // "Apple XDR Display (P3-1600 nits)": potential 16, live 2.67 once engaged.
        XCTAssertNil(XDRPolicy.presetHint(potentialHeadroom: 16, grantedHeadroom: 2.67))
        XCTAssertNil(XDRPolicy.presetHint(potentialHeadroom: 16, grantedHeadroom: nil), "not asked yet")
    }

    func testOnlyAnXDRPresetCanHaveHeadroom() {
        XCTAssertFalse(XDRPolicy.canHaveHeadroom(potentialHeadroom: 5))
        XCTAssertTrue(XDRPolicy.canHaveHeadroom(potentialHeadroom: 16))
    }

    func testHintWhenNothingGranted() {
        XCTAssertEqual(XDRPolicy.presetHint(potentialHeadroom: 16, grantedHeadroom: 1.0), hint)
    }
}

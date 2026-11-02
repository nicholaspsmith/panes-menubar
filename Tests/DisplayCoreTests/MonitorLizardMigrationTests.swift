// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import DisplayCore

final class MonitorLizardMigrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    private let place = Data(#"{"latitude":51.5,"longitude":-0.1}"#.utf8)
    private let schedule = Data(#"{"isEnabled":true}"#.utf8)

    private var everything: [String: Any] {
        [
            "brightnessKeys": false,
            "xdrOffOnBattery": false,
            "nightShiftSchedule": schedule,
            "nightShiftScheduleWarmth": Float(0.7),
            "nightShiftPlace": place,
            "MeterColorHex": "#FF8800",
        ]
    }

    func testCopiesKnownKeys() {
        let result = MonitorLizardMigration.values(old: everything, existing: [], now: now)
        XCTAssertEqual(result["brightnessKeys"] as? Bool, false)
        XCTAssertEqual(result["xdrOffOnBattery"] as? Bool, false)
        XCTAssertEqual(result["nightShiftSchedule"] as? Data, schedule)
        XCTAssertEqual(result["nightShiftScheduleWarmth"] as? Float, 0.7)
        XCTAssertEqual(result["nightShiftPlace"] as? Data, place)
        XCTAssertEqual(result["MeterColorHex"] as? String, "#FF8800")
        // Every listed key that ML had arrives; nothing it lacked is invented.
        for key in MonitorLizardMigration.copiedKeys { XCTAssertNotNil(result[key], key) }
        XCTAssertNil(MonitorLizardMigration.values(old: [:], existing: [], now: now)["brightnessKeys"])
    }

    func testExistingPanesValueWins() {
        let result = MonitorLizardMigration.values(old: everything, existing: ["brightnessKeys"], now: now)
        XCTAssertNil(result["brightnessKeys"])
        XCTAssertEqual(result["xdrOffOnBattery"] as? Bool, false)
    }

    func testSkipsStatusItemKeys() {
        var old = everything
        old["NSStatusItem Preferred Position Item-0"] = 412.0
        old["NSStatusItem Visible Item-0"] = true
        old["SomethingElse"] = "x"
        let result = MonitorLizardMigration.values(old: old, existing: [], now: now)
        XCTAssertFalse(result.keys.contains { $0.hasPrefix("NSStatusItem") })
        XCTAssertNil(result["SomethingElse"])
    }

    func testCharacterMeterStyleDropped() {
        let result = MonitorLizardMigration.values(old: ["MeterStyle": "character"], existing: [], now: now)
        XCTAssertNil(result["IconStyle"])
        XCTAssertNil(result["MeterStyle"])
        XCTAssertTrue(result.isEmpty)
    }

    func testOtherMeterStyleBecomesIconStyle() {
        let result = MonitorLizardMigration.values(old: ["MeterStyle": "arc"], existing: [], now: now)
        XCTAssertEqual(result["IconStyle"] as? String, "meter:arc")
        XCTAssertNil(result["MeterStyle"])
    }

    func testMeterStyleDoesNotOverrideIconStyle() {
        let result = MonitorLizardMigration.values(old: ["MeterStyle": "arc"], existing: ["IconStyle"], now: now)
        XCTAssertNil(result["IconStyle"])
    }

    func testPlaceGetsDate() {
        let result = MonitorLizardMigration.values(old: ["nightShiftPlace": place], existing: [], now: now)
        XCTAssertEqual(result[MonitorLizardMigration.placeDateKey] as? Date, now)
        // No place copied (Panes already has one): no date either.
        let kept = MonitorLizardMigration.values(old: ["nightShiftPlace": place], existing: ["nightShiftPlace"], now: now)
        XCTAssertNil(kept[MonitorLizardMigration.placeDateKey])
    }

    // MARK: - Applying it once

    private let domain = "com.nicholaspsmith.Panes.tests.migration"

    override func tearDown() {
        // Leave no empty plist behind in ~/Library/Preferences.
        UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain)
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(domain).plist")
        try? FileManager.default.removeItem(at: file)
        super.tearDown()
    }

    private func freshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        return defaults
    }

    func testApplyOnceWritesAndSetsDoneKey() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "brightnessKeys")
        let written = MonitorLizardMigration.applyOnce(old: everything, to: defaults, domain: domain, now: now)
        XCTAssertEqual(defaults.bool(forKey: MonitorLizardMigration.doneKey), true)
        XCTAssertEqual(defaults.bool(forKey: "brightnessKeys"), true, "Panes's own value wins")
        XCTAssertEqual(defaults.object(forKey: "xdrOffOnBattery") as? Bool, false)
        XCTAssertEqual(written?.contains("brightnessKeys"), false)
        XCTAssertEqual(written?.contains("nightShiftPlace"), true)

        // Second launch: the flag is set, so nothing more is copied.
        defaults.removeObject(forKey: "xdrOffOnBattery")
        XCTAssertNil(MonitorLizardMigration.applyOnce(old: everything, to: defaults, domain: domain, now: now))
        XCTAssertNil(defaults.object(forKey: "xdrOffOnBattery"))
    }

    func testReadDomainHasOnlyItsOwnKeys() {
        let defaults = freshDefaults()
        defaults.set("#123456", forKey: "MeterColorHex")
        let read = MonitorLizardMigration.readDomain(domain)
        XCTAssertEqual(read["MeterColorHex"] as? String, "#123456")
        XCTAssertEqual(Set(read.keys), ["MeterColorHex"], "no global-domain keys")
        XCTAssertTrue(MonitorLizardMigration.readDomain("com.nicholaspsmith.Panes.tests.absent").isEmpty)
    }
}

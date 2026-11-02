// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import DisplayCore

final class LocationPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let suite = "LocationPolicyTests.scratch"

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func days(_ n: Double) -> Date { now.addingTimeInterval(-n * 24 * 3600) }

    func testFreshPlaceNoPrompt() {
        XCTAssertFalse(LocationPolicy.shouldLocate(hasPlace: true, placeDate: days(1), now: now, scheduleOpened: false))
    }

    func testStalePlaceLocates() {
        XCTAssertTrue(LocationPolicy.shouldLocate(hasPlace: true, placeDate: days(31), now: now, scheduleOpened: false))
    }

    func testNoPlaceLocates() {
        XCTAssertTrue(LocationPolicy.shouldLocate(hasPlace: false, placeDate: nil, now: now, scheduleOpened: false))
    }

    func testNoDateLocates() {
        XCTAssertTrue(LocationPolicy.shouldLocate(hasPlace: true, placeDate: nil, now: now, scheduleOpened: false))
    }

    func testScheduleOpenedLocates() {
        XCTAssertTrue(LocationPolicy.shouldLocate(hasPlace: true, placeDate: days(1), now: now, scheduleOpened: true))
    }

    func testTimeZoneChangeLocates() {
        XCTAssertTrue(LocationPolicy.shouldLocate(hasPlace: true, placeDate: days(1), now: now, scheduleOpened: false, timeZoneChanged: true))
    }

    func testDateKeyMatchesMigration() {
        XCTAssertEqual(LocationPolicy.dateKey, MonitorLizardMigration.placeDateKey)
    }

    func testDeniedKeepsPlace() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let place = Coordinate(latitude: 51.5, longitude: -0.12)
        defaults.set(try JSONEncoder().encode(place), forKey: "nightShiftPlace")
        XCTAssertEqual(LocationPolicy.placeKeptOnDenial(defaults: defaults, placeKey: "nightShiftPlace"), place)
        XCTAssertNotNil(defaults.data(forKey: "nightShiftPlace"), "denial must not remove the saved place")
        XCTAssertNil(LocationPolicy.placeKeptOnDenial(defaults: defaults, placeKey: "other"))
    }
}

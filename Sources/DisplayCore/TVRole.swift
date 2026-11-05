// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Whether Night Shift can work on a display, and what the app has done about it.
public enum TVRoleState: Equatable {
    case ok                      // macOS treats it as a monitor
    case blocked                 // flagged as a TV, no override on disk
    case fixedPendingReconnect   // override on disk; takes effect on the next attach
    case skipped                 // blocked, and the admin prompt was cancelled this launch
}

/// The per-model override macOS reads at display attach. Same file, same
/// three keys, as BetterDisplay's "display role: computer monitor" writes, so
/// an existing file counts as already fixed.
public enum OverridePlist {
    public static let root = "/Library/Displays/Contents/Resources/Overrides"

    public static func path(vendorID: UInt32, productID: UInt32) -> String {
        "\(root)/DisplayVendorID-\(String(vendorID, radix: 16))/DisplayProductID-\(String(productID, radix: 16))"
    }

    public static func contents(vendorID: UInt32, productID: UInt32) -> Data {
        let dict: [String: Any] = ["DisplayIsTV": false, "DisplayVendorID": Int(vendorID), "DisplayProductID": Int(productID)]
        // A fresh plist of three scalars cannot fail to serialise.
        return try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }
}

/// A display model, as an override file is keyed.
public struct DisplayModelID: Hashable {
    public let vendorID: UInt32
    public let productID: UInt32
    public init(vendorID: UInt32, productID: UInt32) { self.vendorID = vendorID; self.productID = productID }
}

/// Which displays macOS treats as televisions. Since macOS 27 CoreDisplay's
/// info dictionary has `DisplayIsTV` only when an override file sets it, so a
/// missing key doesn't mean "not a TV"; `system_profiler` still says.
public enum TVScan {
    /// Blocks for about a quarter of a second: call it off the main thread.
    /// Empty if the tool can't be run.
    public static func run() -> Set<DisplayModelID> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPDisplaysDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.tvrole.error("couldn't run system_profiler: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return televisions(inProfilerJSON: data)
    }

    public static func televisions(inProfilerJSON data: Data) -> Set<DisplayModelID> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gpus = root["SPDisplaysDataType"] as? [[String: Any]] else { return [] }
        var found: Set<DisplayModelID> = []
        for display in gpus.flatMap({ $0["spdisplays_ndrvs"] as? [[String: Any]] ?? [] })
        where display["spdisplays_television"] as? String == "spdisplays_yes" {
            guard let vendor = (display["_spdisplays_display-vendor-id"] as? String).flatMap({ UInt32($0, radix: 16) }),
                  let product = (display["_spdisplays_display-product-id"] as? String).flatMap({ UInt32($0, radix: 16) })
            else { continue }
            found.insert(DisplayModelID(vendorID: vendor, productID: product))
        }
        return found
    }
}

public final class TVRoleTracker {
    private let fileExists: (String) -> Bool
    private var skipped: Set<String> = []
    /// The models the last `TVScan` named.
    public var reportedTVs: Set<DisplayModelID> = []

    public init(fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.fileExists = fileExists
    }

    private func key(_ d: DisplayInfo) -> String { "\(d.vendorID):\(d.productID)" }

    public func state(for display: DisplayInfo) -> TVRoleState {
        guard display.isTV || reportedTVs.contains(DisplayModelID(vendorID: display.vendorID, productID: display.productID)) else { return .ok }
        if fileExists(OverridePlist.path(vendorID: display.vendorID, productID: display.productID)) { return .fixedPendingReconnect }
        return skipped.contains(key(display)) ? .skipped : .blocked
    }

    public func markSkipped(_ display: DisplayInfo) { skipped.insert(key(display)) }
    public func clearSkipped(_ display: DisplayInfo) { skipped.remove(key(display)) }
    public func needsFix(_ display: DisplayInfo) -> Bool { state(for: display) == .blocked }
}

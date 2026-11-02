// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics
import Foundation

// usage: refresh <hz>
// Holds the main display at <hz> (same resolution) until this process ends,
// to measure glides at 60 Hz on a ProMotion panel. The change is app-only
// (kCGConfigureForAppOnly): macOS restores the old mode the moment the process
// exits, however it exits, so it never sticks in System Settings.
let hz = Double(CommandLine.arguments.dropFirst().first ?? "60") ?? 60
let id = CGMainDisplayID()
guard let cur = CGDisplayCopyDisplayMode(id) else { print("no display mode"); exit(1) }
let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
let modes = (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode]) ?? []
guard let mode = modes.first(where: {
    $0.width == cur.width && $0.height == cur.height && $0.pixelWidth == cur.pixelWidth && abs($0.refreshRate - hz) < 0.01
}) else { print("no \(hz) Hz mode at \(cur.width)x\(cur.height)"); exit(1) }
var config: CGDisplayConfigRef?
CGBeginDisplayConfiguration(&config)
CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
let err = CGCompleteDisplayConfiguration(config, .forAppOnly)
guard err == .success else { print("configure failed: \(err.rawValue)"); exit(1) }
print("main display at \(mode.refreshRate) Hz (was \(cur.refreshRate) Hz) until this process ends")
signal(SIGTERM) { _ in exit(0) }
signal(SIGINT) { _ in exit(0) }
while true { sleep(60) }

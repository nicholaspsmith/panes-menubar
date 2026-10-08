// swift-tools-version:5.9
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import PackageDescription

let package = Package(
    name: "Panes",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Panes", targets: ["Panes"]),
        .library(name: "PanesCore", targets: ["PanesCore"]),
    ],
    dependencies: [
        .package(path: "../StatusItemKit"),
        .package(path: "../HotkeyKit"),
    ],
    targets: [
        .target(
            name: "PanesCore",
            dependencies: [.product(name: "HotkeyKit", package: "HotkeyKit")]
        ),
        // The menu-bar icon's drawing (AppKit). The Menumon site's renderer
        // (widgets.nicksmith.software, art/glyphs) compiles it too, for the
        // README images and the app icon: scripts/make-icon.sh.
        .target(name: "PanesGlyph", dependencies: ["PanesCore"]),
        .executableTarget(
            name: "Panes",
            dependencies: [
                "PanesCore",
                "PanesGlyph",
                .product(name: "StatusItemKit", package: "StatusItemKit"),
                .product(name: "HotkeyKit", package: "HotkeyKit"),
            ]
        ),
        .testTarget(name: "PanesCoreTests", dependencies: ["PanesCore"]),
        .testTarget(name: "PanesGlyphTests", dependencies: ["PanesGlyph"]),
    ]
)

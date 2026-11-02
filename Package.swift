// swift-tools-version:5.9
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import PackageDescription

let package = Package(
    name: "Panes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Panes", targets: ["Panes"]),
        .library(name: "PanesCore", targets: ["PanesCore"]),
        .library(name: "DisplayCore", targets: ["DisplayCore"]),
        // The Major Pane review page: `swift run major-pane-render preview OUT.html [--frames FILE]`.
        .executable(name: "major-pane-render", targets: ["MajorPaneRender"]),
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
        .executableTarget(name: "MajorPaneRender", dependencies: ["PanesGlyph"]),
        .executableTarget(
            name: "Panes",
            dependencies: [
                "PanesCore",
                "PanesGlyph",
                "DisplayCore",
                .product(name: "StatusItemKit", package: "StatusItemKit"),
                .product(name: "HotkeyKit", package: "HotkeyKit"),
            ]
        ),
        // Monitor Lizard's pure core (DDC, XDR, dim, Night Shift); no dependencies.
        .target(name: "DisplayCore"),
        .testTarget(name: "DisplayCoreTests", dependencies: ["DisplayCore"]),
        .testTarget(name: "PanesCoreTests", dependencies: ["PanesCore"]),
        .testTarget(name: "PanesGlyphTests", dependencies: ["PanesGlyph"]),
    ]
)

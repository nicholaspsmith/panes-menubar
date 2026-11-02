#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

# Build the glide harness into build/glide-harness/: TileTest.app (the
# magenta test window), edges (the edge recorder) and appglide (the recorder for
# real apps: AX frames plus on-screen magenta content). See README.md.
set -euo pipefail
cd "$(dirname "$0")"
OUT=../../build/glide-harness
mkdir -p "$OUT"

swiftc -O -o "$OUT/edges" edges.swift
swiftc -O -o "$OUT/appglide" appglide.swift
swiftc -O -o "$OUT/refresh" refresh.swift
swiftc -O -o "$OUT/fpsprobe" fpsprobe.swift

APP="$OUT/TileTest.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/TileTest" TileTest.swift
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.nicholassmith.tiletest</string>
    <key>CFBundleName</key><string>TileTest</string>
    <key>CFBundleExecutable</key><string>TileTest</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built $OUT/{edges,appglide,refresh,fpsprobe,TileTest.app}"

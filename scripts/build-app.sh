#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

# Build Panes.app via the shared StatusItemKit bundler.
#
# make-app.sh stamps the version from the nearest vX.Y.Z tag and refuses to
# build without one. Releases are tagged by the workflow only after they reach
# main, so a checkout with no tag yet (the first release, before its merge)
# builds here instead: the same bundle and signing, stamped with the top
# CHANGELOG version marked "+untagged", as Spotmoji's build does.
set -euo pipefail
cd "$(dirname "$0")/.."

if git describe --tags --match 'v[0-9]*.[0-9]*.[0-9]*' >/dev/null 2>&1; then
    exec ../StatusItemKit/scripts/make-app.sh Panes "Panes"
fi

PRODUCT=Panes
APP=build/Panes.app

echo "==> swift build -c release"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$PRODUCT"
[ -x "$BIN" ] || { echo "Build did not produce executable at $BIN" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$PRODUCT"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -d Resources/bundle ]; then cp -R Resources/bundle/. "$APP/Contents/Resources/"; fi

BASE="$(sed -n 's/^## \[\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\].*/\1/p' CHANGELOG.md | head -1)"
[ -n "$BASE" ] || { echo "No vX.Y.Z tag and no \"## [X.Y.Z]\" section in CHANGELOG.md" >&2; exit 1; }
HASH="$(git rev-parse --short HEAD)"
DIRTY=""; git diff --quiet HEAD -- || DIRTY=".dirty"
VERSION="${BASE}+untagged.g${HASH}${DIRTY}"
PLIST="$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$BASE" "$PLIST"
plutil -replace CFBundleVersion -string "${HASH}${DIRTY}" "$PLIST"
plutil -replace StatusItemKitVersion -string "$VERSION" "$PLIST"
echo "==> Version $VERSION (no tag yet)"

# The same identity make-app.sh prefers, so the Accessibility grant survives.
SIGN_ID="${STATUSITEMKIT_SIGN_ID:-}"
[ -n "$SIGN_ID" ] || SIGN_ID="$(security find-identity -p codesigning 2>/dev/null \
    | awk '/StatusItemKit Local Signing/ {print $2; exit}')" || true
SIGN_ID="${SIGN_ID:--}"
codesign --force --sign "$SIGN_ID" "$APP" >/dev/null
echo "==> Signed with ${SIGN_ID}"
echo "==> Built $APP"

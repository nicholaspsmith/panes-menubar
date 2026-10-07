#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

# Rebuild Resources/bundle/AppIcon.icns and docs/mascot.png: Panes's menu-bar
# glyph (PanesGlyph's ScreenGridIcon, a display with its windows on it) drawn
# large on the dark macOS tile every Menumon app shares. The renderer lives in
# the Menumon site repo, which draws every app's icon the same way; this runs
# it for this app only. docs/menubar-icon.png comes from the same repo's
# art/glyphs/render-glyphs.sh, which renders every app's strip.
# Needs widgets.nicksmith.software and StatusItemKit checked out beside this repo.
set -euo pipefail
cd "$(dirname "$0")/.."
renderer=../widgets.nicksmith.software/art/glyphs/app-icons.sh
[ -x "$renderer" ] || { echo "Missing $renderer (clone widgets.nicksmith.software beside this repo)" >&2; exit 1; }
CODE="$(cd .. && pwd)" "$renderer" panes

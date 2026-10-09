// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation
import PanesGlyph

/// major-pane-render preview OUT.html [--frames FRAMES.json]
/// Renders the review page from the compiled art, or from a frames file.
let args = Array(CommandLine.arguments.dropFirst())
func usage() -> Never {
    FileHandle.standardError.write(Data("usage: major-pane-render preview OUT.html [--frames FRAMES.json]\n".utf8))
    exit(2)
}
guard args.count >= 2, args[0] == "preview" else { usage() }
var art = MajorPaneArt.shipped
if let i = args.firstIndex(of: "--frames") {
    guard i + 1 < args.count else { usage() }
    do { art = try MajorPaneArt(json: Data(contentsOf: URL(fileURLWithPath: args[i + 1]))) }
    catch { FileHandle.standardError.write(Data("major-pane-render: \(error)\n".utf8)); exit(1) }
}
let out = URL(fileURLWithPath: args[1])
do { try Data(MajorPanePreview.html(art: art).utf8).write(to: out) } catch { FileHandle.standardError.write(Data("major-pane-render: \(error)\n".utf8)); exit(1) }
print("wrote \(out.path)")

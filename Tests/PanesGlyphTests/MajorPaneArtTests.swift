// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import PanesGlyph

final class MajorPaneArtTests: XCTestCase {
    /// The smallest valid art at any size: every state is one solid frame of `fill`.
    func canvas(_ w: Int, _ h: Int, fill: Character = "K") -> [String: Any] {
        let solid = Array(repeating: String(repeating: fill, count: w), count: h)
        let clip: [String: Any] = ["fps": 4, "loop": true, "frames": [solid]]
        return ["width": w, "height": h, "palette": ["K": "#000000"], "pane": [String: String](),
                "states": Dictionary(uniqueKeysWithValues: MajorPaneArt.stateNames.map { ($0, clip) })]
    }
    func data(_ o: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: o) }
    func edited(_ base: [String: Any], _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var o = base; edit(&o); return try data(o)
    }
    func refused(_ json: Data, _ needle: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try MajorPaneArt(json: json), file: file, line: line) { e in
            XCTAssertTrue("\(e)".contains(needle), "got: \(e)", file: file, line: line)
        }
    }

    func testLoadsAtItsOwnSizeWithItsClips() throws {
        let art = try MajorPaneArt(json: data(canvas(30, 22)))
        XCTAssertEqual(art.width, 30); XCTAssertEqual(art.height, 22)
        XCTAssertEqual(art.palette["K"], 0x000000)
        XCTAssertEqual(Set(art.clips.keys), Set(MajorPaneArt.stateNames))
        XCTAssertEqual(art.clip("idle").frames[0].count, 22)
        XCTAssertEqual(art.clip("idle").fps, 4); XCTAssertTrue(art.clip("idle").loop)
    }

    func testPaneCharactersAreKept() throws {
        let json = try edited(canvas(6, 4)) { o in
            o["palette"] = ["K": "#000000", "p": "#1E2A40"]
            o["pane"] = ["p": "cell"]
        }
        XCTAssertEqual(try MajorPaneArt(json: json).pane, ["p"])
    }

    func testUnknownStateFallsBackToIdle() throws {
        let art = try MajorPaneArt(json: data(canvas(3, 2)))
        XCTAssertEqual(art.clip("dance"), art.clip("idle"))
    }

    func testArtWithNoClipsAnswersWithABlankFrameOfItsOwnSize() {
        let art = MajorPaneArt(width: 3, height: 2, palette: [:], pane: [], clips: [:])
        XCTAssertEqual(art.clip("idle").frames, [["...", "..."]])
    }

    func testRefusesWhatTheGeneratorRefuses() throws {
        let base = canvas(4, 3)
        refused(try edited(base) { $0["extra"] = 1 }, "unknown keys: extra")
        refused(try edited(base) { $0.removeValue(forKey: "pane") }, "missing pane")
        refused(try edited(base) { $0["width"] = 0 }, "width and height must be integers from 1 to 64")
        // JSONSerialization writes 4.0 as 4, so the float case is spelled out by hand.
        refused(Data(##"{"width":4.0,"height":3,"palette":{"K":"#000000"},"pane":{},"states":{}}"##.utf8), "width and height must be integers from 1 to 64")
        refused(try edited(base) { $0["palette"] = ["KK": "#000000"] }, "one printable ASCII character")
        refused(try edited(base) { $0["palette"] = ["K": "#00000"] }, "must be #RRGGBB")
        refused(try edited(base) { $0["pane"] = ["z": "cell"] }, "pane key z is not in the palette")
        refused(try edited(base) { $0["pane"] = ["K": "perch"] }, "pane role perch for K must be \"cell\"")
        refused(try edited(base) { var s = $0["states"] as! [String: Any]; s["bark"] = nil; $0["states"] = s }, "missing states: bark")
        refused(try edited(base) { var s = $0["states"] as! [String: Any]; s["bob"] = s["idle"]; $0["states"] = s }, "unknown states: bob")
        refused(try edited(base) { var s = $0["states"] as! [String: Any]; var c = s["idle"] as! [String: Any]
            c["fps"] = 31; s["idle"] = c; $0["states"] = s }, "idle: fps must be a number in (0, 30]")
        refused(try edited(base) { var s = $0["states"] as! [String: Any]; var c = s["idle"] as! [String: Any]
            c["frames"] = [["KKKK", "KKKK"]]; s["idle"] = c; $0["states"] = s }, "idle frame 0: needs 3 rows")
        refused(try edited(base) { var s = $0["states"] as! [String: Any]; var c = s["idle"] as! [String: Any]
            c["frames"] = [["KKK", "KKKK", "KKKK"]]; s["idle"] = c; $0["states"] = s }, "idle frame 0 row 0: needs 4 characters")
        refused(try edited(base) { var s = $0["states"] as! [String: Any]; var c = s["idle"] as! [String: Any]
            c["frames"] = [["KKKZ", "KKKK", "KKKK"]]; s["idle"] = c; $0["states"] = s }, "character not in the palette: Z")
        refused(try edited(base) { $0["palette"] = Dictionary(uniqueKeysWithValues: "ABCDEFGHIJKLM".map { (String($0), "#000000") }) },
                "palette has 13 colours; the most is 12")
        refused(Data("[]".utf8), "the top level must be an object")
        refused(Data("nope".utf8), "not JSON")
    }

    /// …/panes-menubar/Tests/PanesGlyphTests/X.swift → …/panes-menubar
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testCompiledFramesMatchTheirSourceJSON() throws {
        let swift = try String(contentsOf: Self.repo.appendingPathComponent("Sources/PanesGlyph/MajorPaneFrames.swift"), encoding: .utf8)
        let line = try XCTUnwrap(swift.split(separator: "\n").first { $0.hasPrefix("// source: ") })
        let file = Self.repo.appendingPathComponent(String(line.dropFirst("// source: ".count)))
        let fromSource = try MajorPaneArt(json: Data(contentsOf: file))
        XCTAssertEqual(fromSource, MajorPaneArt.shipped,
                       "MajorPaneFrames.swift is out of sync with \(file.lastPathComponent); run scripts/gen_major_pane_frames.py")
    }
}

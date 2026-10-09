// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// One state's animation: rows of palette characters per frame, "." transparent.
public struct MajorPaneClip: Equatable {
    public let fps: Double
    public let loop: Bool
    public let frames: [[String]]
    public init(fps: Double, loop: Bool, frames: [[String]]) {
        self.fps = fps; self.loop = loop; self.frames = frames
    }
}

public struct MajorPaneArtError: Error, CustomStringConvertible {
    public let description: String
}

/// Major Pane as data (spec "Art format"). The app draws `shipped`, compiled in
/// from MajorPaneFrames.swift; `init(json:)` reads the same format at run time
/// for previews and the drift test. The canvas is whatever the art says it is.
public struct MajorPaneArt: Equatable {
    /// The four clips every art must draw, and no others.
    public static let stateNames = ["idle", "salute", "bark", "at_ease"]
    /// Palette entries, "." (transparent) not counted.
    public static let maxColours = 24
    static let topLevelKeys: Set<String> = ["width", "height", "palette", "pane", "states"]

    public static let shipped = MajorPaneArt(width: MajorPaneFrames.width, height: MajorPaneFrames.height,
                                             palette: MajorPaneFrames.palette, pane: MajorPaneFrames.pane,
                                             clips: MajorPaneFrames.clips)

    public let width: Int
    public let height: Int
    public let palette: [Character: UInt32]
    /// Characters whose pixels are the pane's cells: coloured at render time.
    public let pane: Set<Character>
    public let clips: [String: MajorPaneClip]

    public init(width: Int, height: Int, palette: [Character: UInt32], pane: Set<Character>,
                clips: [String: MajorPaneClip]) {
        self.width = width; self.height = height; self.palette = palette; self.pane = pane; self.clips = clips
    }

    /// The clip for a state; an unknown name gets idle. Art with no clips at
    /// all gets a single blank frame, never a trap.
    public func clip(_ state: String) -> MajorPaneClip {
        if let c = clips[state] ?? clips["idle"] ?? clips.values.first { return c }
        let blank = Array(repeating: String(repeating: ".", count: max(width, 0)), count: max(height, 0))
        return MajorPaneClip(fps: 1, loop: false, frames: [blank])
    }

    private struct Raw: Decodable {
        struct Clip: Decodable { let fps: Double; let loop: Bool; let frames: [[String]] }
        let width: Int
        let height: Int
        let palette: [String: String]
        let pane: [String: String]
        let states: [String: Clip]
    }

    /// Reads the format scripts/gen_major_pane_frames.py validates, with the same rules.
    public init(json: Data) throws {
        func fail(_ m: String) -> MajorPaneArtError { MajorPaneArtError(description: m) }
        let top: [String: Any]
        do {
            guard let o = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
                throw fail("the top level must be an object")
            }
            top = o
        } catch let e as MajorPaneArtError { throw e } catch { throw fail("not JSON: \(error.localizedDescription)") }
        let unknown = top.keys.filter { !MajorPaneArt.topLevelKeys.contains($0) }.sorted()
        guard unknown.isEmpty else { throw fail("unknown keys: " + unknown.joined(separator: ", ")) }
        guard top["pane"] != nil else { throw fail("missing pane (use {} for none)") }
        for key in ["width", "height"] {
            if let n = top[key] as? NSNumber, CFNumberIsFloatType(n) { throw fail("width and height must be integers from 1 to 64") }
        }
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: json)
        } catch let DecodingError.keyNotFound(key, _) {
            throw fail("missing \(key.stringValue)")
        } catch let DecodingError.typeMismatch(_, ctx), let DecodingError.valueNotFound(_, ctx), let DecodingError.dataCorrupted(ctx) {
            let at = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            throw fail(at.isEmpty ? ctx.debugDescription : "\(at): \(ctx.debugDescription)")
        }
        let w = raw.width, h = raw.height
        guard (1...64).contains(w), (1...64).contains(h) else { throw fail("width and height must be integers from 1 to 64") }
        guard !raw.palette.isEmpty else { throw fail("palette must be a non-empty object") }
        var palette: [Character: UInt32] = [:]
        for (key, value) in raw.palette {
            guard let ch = MajorPaneArt.pixelCharacter(key) else {
                throw fail("palette key \(key) must be one printable ASCII character other than \".\"")
            }
            guard let rgb = MajorPaneArt.hexColor(value) else { throw fail("palette colour for \(key) must be #RRGGBB") }
            palette[ch] = rgb
        }
        guard palette.count <= MajorPaneArt.maxColours else {
            throw fail("palette has \(palette.count) colours; the most is \(MajorPaneArt.maxColours)")
        }
        var pane = Set<Character>()
        for (key, role) in raw.pane {
            guard let ch = MajorPaneArt.pixelCharacter(key), palette[ch] != nil else { throw fail("pane key \(key) is not in the palette") }
            guard role == "cell" else { throw fail("pane role \(role) for \(key) must be \"cell\"") }
            pane.insert(ch)
        }
        let missing = MajorPaneArt.stateNames.filter { raw.states[$0] == nil }
        guard missing.isEmpty else { throw fail("missing states: " + missing.joined(separator: ", ")) }
        let extra = raw.states.keys.filter { !MajorPaneArt.stateNames.contains($0) }.sorted()
        guard extra.isEmpty else { throw fail("unknown states: " + extra.joined(separator: ", ")) }
        var clips: [String: MajorPaneClip] = [:]
        for name in MajorPaneArt.stateNames {
            let c = raw.states[name]!
            guard c.fps > 0, c.fps <= 30 else { throw fail("\(name): fps must be a number in (0, 30]") }
            guard !c.frames.isEmpty else { throw fail("\(name): needs at least one frame") }
            for (i, frame) in c.frames.enumerated() {
                guard frame.count == h else { throw fail("\(name) frame \(i): needs \(h) rows") }
                for (y, row) in frame.enumerated() {
                    guard row.unicodeScalars.count == w else { throw fail("\(name) frame \(i) row \(y): needs \(w) characters") }
                    for s in row.unicodeScalars where s != "." && palette[Character(s)] == nil {
                        throw fail("\(name) frame \(i) row \(y): character not in the palette: \(s)")
                    }
                }
            }
            clips[name] = MajorPaneClip(fps: c.fps, loop: c.loop, frames: c.frames)
        }
        self.init(width: w, height: h, palette: palette, pane: pane, clips: clips)
    }

    /// One printable ASCII character, not space and not ".".
    static func pixelCharacter(_ s: String) -> Character? {
        let scalars = Array(s.unicodeScalars)
        guard scalars.count == 1, let c = scalars.first, c.value > 0x20, c.value < 0x7F, c != "." else { return nil }
        return Character(c)
    }

    /// "#RRGGBB" only.
    static func hexColor(_ s: String) -> UInt32? {
        let bytes = Array(s.utf8)
        guard bytes.count == 7, bytes[0] == UInt8(ascii: "#") else { return nil }
        var v: UInt32 = 0
        for b in bytes.dropFirst() {
            let d: UInt32
            switch b {
            case 48...57: d = UInt32(b) - 48
            case 65...70: d = UInt32(b) - 55
            case 97...102: d = UInt32(b) - 87
            default: return nil
            }
            v = v << 4 | d
        }
        return v
    }
}

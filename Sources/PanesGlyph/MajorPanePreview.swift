// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import PanesCore

/// The review-gate page (spec "Process and gates", step 5): every clip animating
/// at its fps at menu-bar size on a light and a dark bar and 8x enlarged, a row
/// of idle frame 0 with none, a quarter, a half and all cells lit, and the
/// icon pose at 32x on a dark tile.
public enum MajorPanePreview {
    static func png(_ rep: NSBitmapImageRep) -> String {
        "data:image/png;base64," + (rep.representation(using: .png, properties: [:]) ?? Data()).base64EncodedString()
    }
    static func number(_ v: Double) -> String { v.rounded() == v && abs(v) < 1e9 ? String(Int(v)) : String(v) }

    public static func html(art: MajorPaneArt) -> String {
        var cards = "", data: [String] = []
        for name in MajorPaneArt.stateNames {
            let clip = art.clip(name)
            let frames = clip.frames.indices.map {
                "\"" + png(MajorPaneRenderer.bitmap(art: art, pose: MajorPanePose(state: name, frame: $0, lit: PaneCells.quarter, active: name != "at_ease"), scale: 2)) + "\""
            }.joined(separator: ",")
            data.append("\"\(name)\":{\"fps\":\(number(clip.fps)),\"loop\":\(clip.loop),\"frames\":[\(frames)]}")
            let n = clip.frames.count
            cards += """
            <section class="card"><h2>\(name)</h2><p>\(n) frame\(n == 1 ? "" : "s") · \(number(clip.fps)) fps · \(clip.loop ? "loops" : "plays once")</p>
            <div class="bars"><div class="bar light"><img class="pt" data-state="\(name)" alt=""></div><div class="bar dark"><img class="pt" data-state="\(name)" alt=""></div></div>
            <img class="zoom" data-state="\(name)" alt="\(name), enlarged"></section>

            """
        }
        let lit = [("none", Set<GridCell>()), ("quarter", PaneCells.quarter), ("half", PaneCells.half), ("all", PaneCells.all)].map { label, cells in
            "<figure><img class=\"lit pt\" src=\"\(png(MajorPaneRenderer.bitmap(art: art, pose: MajorPanePose(state: "idle", lit: cells), scale: 2)))\" alt=\"\"><figcaption>\(label)</figcaption></figure>"
        }.joined()
        let icon = png(MajorPaneRenderer.bitmap(art: art, pose: MajorPanePose(state: "idle", lit: PaneCells.quarter), scale: 32))
        return template(cards: cards, lit: lit, data: "{" + data.joined(separator: ",") + "}", icon: icon, width: art.width, height: art.height)
    }

    static func template(cards: String, lit: String, data: String, icon: String, width: Int, height: Int) -> String {
        #"""
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Major Pane Preview</title>
        <style>
        :root { --bg: #f5f5f3; --fg: #1d1d1f; --muted: #6e6e73; --card: #ffffff; --line: #d9d9de; }
        @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #161618; --fg: #f2f2f2; --muted: #a1a1a6; --card: #232326; --line: #3a3a3d; } }
        :root[data-theme="dark"] { --bg: #161618; --fg: #f2f2f2; --muted: #a1a1a6; --card: #232326; --line: #3a3a3d; }
        body { margin: 0; padding: 24px 16px; background: var(--bg); color: var(--fg); font: 15px/1.4 -apple-system, system-ui, sans-serif; }
        h1 { font-size: 22px; margin: 0 0 4px; } .lede { color: var(--muted); margin: 0 0 20px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 16px; }
        .card { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 14px; min-width: 0; }
        .card h2 { font-size: 15px; margin: 0; font-family: ui-monospace, monospace; }
        .card p { color: var(--muted); margin: 2px 0 10px; font-size: 13px; }
        .bars { display: flex; gap: 8px; margin-bottom: 8px; align-items: center; }
        .bar { flex: 1; height: \#(max(24, height + 2))px; border-radius: 6px; display: flex; align-items: center; justify-content: center; }
        .light { background: #e8e8e8; } .dark { background: #262626; }
        img { image-rendering: pixelated; }
        .pt { width: \#(width)px; height: \#(height)px; }
        .zoom { width: \#(width * 8)px; aspect-ratio: \#(width) / \#(height); height: auto; max-width: 100%; display: block; margin: 0 auto; }
        .row { display: flex; gap: 24px; flex-wrap: wrap; margin: 8px 0 24px; } figure { margin: 0; text-align: center; color: var(--muted); font-size: 12px; }
        .row img { width: \#(width * 4)px; height: \#(height * 4)px; background: #262626; padding: 8px; border-radius: 8px; }
        .tile { width: 256px; height: 256px; border-radius: 56px; background: linear-gradient(#2B2E35, #15171B); display: flex; align-items: center; justify-content: center; }
        .icon { width: \#(width * 6)px; height: \#(height * 6)px; }
        </style></head><body>
        <h1>Major Pane Preview</h1>
        <p class="lede">Every clip as Panes draws it: menu-bar size on a light and a dark bar (a quarter lit; at_ease greyed), and enlarged 8×. Then idle with the pane none / a quarter / a half / all lit, and the icon pose.</p>
        <div class="grid">
        \#(cards)</div>
        <h2>The pane</h2><div class="row">\#(lit)</div>
        <h2>App icon pose</h2><div class="tile"><img class="icon" src="\#(icon)" alt="Major Pane, the app icon pose"></div>
        <script>
        const clips = \#(data);
        for (const [name, c] of Object.entries(clips)) {
          const imgs = document.querySelectorAll(`img[data-state="${name}"]`);
          let i = 0; const show = () => { for (const im of imgs) im.src = c.frames[i]; };
          show();
          if (c.frames.length > 1) setInterval(() => { i = c.loop ? (i + 1) % c.frames.length : Math.min(i + 1, c.frames.length - 1); if (!c.loop && i === c.frames.length - 1) setTimeout(() => { i = 0; show(); }, 1500); show(); }, 1000 / c.fps);
        }
        </script>
        </body></html>
        """#
    }
}

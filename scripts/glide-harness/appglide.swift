// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import ApplicationServices
import ScreenCaptureKit
import CoreMedia

// Records what the real Panes does to a window of ANY app (edges.swift only
// knows TileTest): presses ⌘⌥ + each key in turn and, per press, records
//   - the window's AX frame, read back as fast as possible (when the app
//     APPLIED each step; not when it reached the screen), and/or
//   - with --capture, the edges of the magenta CONTENT on screen along two
//     scan lines through the start frame's centre (what was SHOWN; needs
//     Screen Recording and a page/editor painted #ff00ff).
// It never presses a key unless the target window is the focused window of
// the frontmost app, so Panes cannot move anything else.
//
// usage: appglide <bundle-id | pid:N> <keys> [--start box|x,y,w,h] [--idle S]
//                 [--gap S] [--capture] [--no-ax] [--trace] [--costs N] [--title T] [--probe]
//   --title T: refuse to run unless the focused window's title contains T
//   --probe: after the idle, time two AX reads (is the app slow to wake?)
//   keys: comma-separated virtual keycodes pressed with ⌘⌥ (8 C, 46 M, 51 ⌫)

let args = Array(CommandLine.arguments.dropFirst())
func opt(_ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
func flag(_ name: String) -> Bool { args.contains(name) }
guard args.count >= 2 else {
    print("usage: appglide <bundle-id | pid:N> <keys> [--start box|x,y,w,h] [--idle S] [--gap S] [--capture] [--no-ax] [--trace] [--costs N] [--title T] [--probe]")
    exit(2)
}
let keys = args[1].split(separator: ",").compactMap { CGKeyCode(String($0)) }
let idle = Double(opt("--idle") ?? "10") ?? 10
let gap = Double(opt("--gap") ?? "1.0") ?? 1.0
let costRuns = Int(opt("--costs") ?? "10") ?? 10
let capture = flag("--capture"), sampleAX = !flag("--no-ax"), trace = flag("--trace")

let app: NSRunningApplication? = args[0].hasPrefix("pid:")
    ? NSRunningApplication(processIdentifier: pid_t(args[0].dropFirst(4))!)
    : NSRunningApplication.runningApplications(withBundleIdentifier: args[0]).first
guard let app else { print("not running: \(args[0])"); exit(1) }
let pid = app.processIdentifier
let appEl = AXUIElementCreateApplication(pid)
func focusedWindow() -> AXUIElement? {
    var v: AnyObject?
    guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &v) == .success else { return nil }
    return (v as! AXUIElement)
}
// Bring the app forward (AX, which works from a command-line tool), then take its focused window.
AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
Thread.sleep(forTimeInterval: 0.5)
guard let win = focusedWindow() else { print("no focused window in pid \(pid) (Accessibility granted?)"); exit(1) }
if let want = opt("--title") {
    var tv: AnyObject?
    AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &tv)
    let title = tv as? String ?? ""
    guard title.contains(want) else { print("STOP: focused window is \"\(title)\", not one titled *\(want)*"); exit(1) }
}

/// Position and size in ONE round trip, so a sample never pairs a new
/// position with an old size of the sampler's own making. (A sample can still
/// land between Panes's position set and its size set: that half-applied
/// frame is real, the app held it.)
let frameAttrs = [kAXPositionAttribute, kAXSizeAttribute] as CFArray
func frame() -> CGRect? {
    var out: CFArray?
    guard AXUIElementCopyMultipleAttributeValues(win, frameAttrs, AXCopyMultipleAttributeOptions(rawValue: 0), &out) == .success,
          let vals = out as? [AnyObject], vals.count == 2,
          CFGetTypeID(vals[0]) == AXValueGetTypeID(), CFGetTypeID(vals[1]) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(vals[0] as! AXValue, .cgPoint, &p); AXValueGetValue(vals[1] as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}
func setPos(_ p: CGPoint) { var p = p; AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!) }
func setSize(_ s: CGSize) { var s = s; AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!) }
func setFrame(_ r: CGRect) { setSize(r.size); setPos(r.origin); setSize(r.size) }

/// Safety: only press while our window is the focused window of the frontmost app.
func targetIsFront() -> Bool {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, let f = focusedWindow() else { return false }
    return CFEqual(f, win)
}

// The main display's visible frame in AX (top-left) coordinates, and Panes's ⌥⌘C box in it.
let primaryH = NSScreen.screens.first!.frame.height
let vf = NSScreen.main!.visibleFrame
let visibleAX = CGRect(x: vf.minX, y: primaryH - vf.maxY, width: vf.width, height: vf.height).integral
func box() -> CGRect {
    let w = min(visibleAX.width, max((visibleAX.width * 0.5).rounded(), 1000)), h = (visibleAX.height * 2 / 3).rounded()
    return CGRect(x: (visibleAX.midX - w / 2).rounded(), y: (visibleAX.midY - h / 2).rounded(), width: w, height: h)
}
let startArg = opt("--start") ?? "box"
let start: CGRect = {
    if startArg == "box" { return box() }
    let n = startArg.split(separator: ",").compactMap { Double(String($0)) }
    return CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
}()

// ---- on-screen edges (the capture from edges.swift, for any window) ----
struct Edge { var t: Double; var top: Int; var bottom: Int; var left: Int; var right: Int }
var shown: [Edge] = []
let lock = NSLock()
let scanX = Int(start.midX.rounded()), scanY = Int(start.midY.rounded())
final class Out: NSObject, SCStreamOutput {
    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        if let att = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
           let raw = att[.status] as? Int, raw != SCFrameStatus.complete.rawValue { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(pb), w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        func magenta(_ x: Int, _ y: Int) -> Bool {
            let p = base + y * bpr + x * 4   // BGRA
            return p[2] > 200 && p[1] < 90 && p[0] > 200
        }
        var top = -1, bottom = -1, left = -1, right = -1
        for y in 0..<h where magenta(min(scanX, w - 1), y) { if top < 0 { top = y }; bottom = y }
        for x in 0..<w where magenta(x, min(scanY, h - 1)) { if left < 0 { left = x }; right = x }
        lock.lock(); shown.append(Edge(t: t, top: top, bottom: bottom + 1, left: left, right: right + 1)); lock.unlock()
    }
}
let sem = DispatchSemaphore(value: 0)
var stream: SCStream?
let out = Out()
if capture {
    var display: SCDisplay?
    var err: Error?
    SCShareableContent.getWithCompletionHandler { c, e in display = c?.displays.first { $0.displayID == CGMainDisplayID() }; err = e; sem.signal() }
    sem.wait()
    guard let display else { print("capture error: \(err.map { "\($0)" } ?? "no display")"); exit(3) }
    let cfg = SCStreamConfiguration()
    cfg.width = display.width; cfg.height = display.height     // 1 px per point
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 120)
    cfg.pixelFormat = kCVPixelFormatType_32BGRA
    cfg.queueDepth = 8
    cfg.showsCursor = false
    let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: nil)
    try! s.addStreamOutput(out, type: .screen, sampleHandlerQueue: DispatchQueue(label: "cap"))
    var startErr: Error?
    s.startCapture { e in startErr = e; sem.signal() }
    sem.wait()
    if let startErr { print("capture error \(startErr)"); exit(3) }
    stream = s
}

// ---- stats over one press ----
struct Stats { var first = -1.0, last = -1.0, frames = 0, back = 0, maxBack = 0.0, maxJump = 0.0, firstBack = "" }
/// Frames as [top, bottom, left, right]; t in seconds since the key went down.
func stats(_ s: [(t: Double, e: [Double])]) -> Stats {
    var r = Stats()
    guard let a = s.first, let z = s.last else { return r }
    let net = zip(a.e, z.e).map { $1 - $0 }
    for (p, q) in zip(s, s.dropFirst()) {
        let d = zip(p.e, q.e).map { $1 - $0 }
        guard d.contains(where: { $0 != 0 }) else { continue }
        r.frames += 1
        if r.first < 0 { r.first = q.t * 1000 }
        r.last = q.t * 1000
        for (i, di) in d.enumerated() where di != 0 {
            r.maxJump = max(r.maxJump, abs(di))
            if net[i] == 0 || (di > 0) != (net[i] > 0) {
                r.back += 1; r.maxBack = max(r.maxBack, abs(di))
                if r.firstBack.isEmpty { r.firstBack = String(format: "%@ %+.0f at %.0f ms (change %d)", ["top", "bottom", "left", "right"][i], di, q.t * 1000, r.frames) }
            }
        }
    }
    return r
}
func line(_ label: String, _ r: Stats, _ extra: String = "") -> String {
    String(format: "  %@: first change %4.0f ms, last %4.0f ms, %2d frames, %d backward (max %3.0f px), biggest jump %4.0f px%@",
           label, r.first, r.last, r.frames, r.back, r.maxBack, r.maxJump, extra)
}

// ---- run ----
setFrame(start)
Thread.sleep(forTimeInterval: 0.3)
var costs: [Double] = []
for i in 0..<costRuns {
    let f = i % 2 == 0 ? start.insetBy(dx: 0, dy: 1) : start
    let t0 = CACurrentMediaTime(); setPos(f.origin); setSize(f.size); costs.append(CACurrentMediaTime() - t0)
    Thread.sleep(forTimeInterval: 0.05)
}
setFrame(start)
let sorted = costs.sorted()
print(String(format: "%@ pid %d, window %@, start %@", app.localizedName ?? "?", pid, "\(frame() ?? .null)", "\(start)"))
if !costs.isEmpty {
    print(String(format: "setCost (position+size, %d sets): mean %.1f ms, median %.1f ms, max %.1f ms",
                 costs.count, costs.reduce(0, +) / Double(costs.count) * 1000, sorted[sorted.count / 2] * 1000, sorted.last! * 1000))
}
print(String(format: "idle %.0f s, then ⌘⌥ keys %@; AX sampling %@, screen capture %@", idle, args[1], sampleAX ? "on" : "off", capture ? "on" : "off"))
Thread.sleep(forTimeInterval: idle)
if flag("--probe") {
    // Is the app itself slow to answer after the idle? Time two reads back to back.
    let a0 = CACurrentMediaTime(); _ = frame(); let a1 = CACurrentMediaTime(); _ = frame(); let a2 = CACurrentMediaTime()
    print(String(format: "probe after idle: first AX read %.1f ms, second %.1f ms", (a1 - a0) * 1000, (a2 - a1) * 1000))
}

for (i, code) in keys.enumerated() {
    guard targetIsFront() else { print("STOP: target window is not the focused window of the frontmost app; not pressing"); break }
    var ax: [(t: Double, e: [Double])] = []
    var reads = 0, worstRead = 0.0
    let src = CGEventSource(stateID: .hidSystemState)
    let t0 = CACurrentMediaTime()
    for down in [true, false] { let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!; e.flags = [.maskCommand, .maskAlternate]; e.post(tap: .cghidEventTap) }
    if let f = frame() { ax.append((0, [f.minY, f.maxY, f.minX, f.maxX])) }
    while CACurrentMediaTime() - t0 < gap {
        if sampleAX {
            let r0 = CACurrentMediaTime()
            guard let f = frame() else { continue }
            let r1 = CACurrentMediaTime()
            reads += 1; worstRead = max(worstRead, r1 - r0)
            ax.append((r1 - t0, [f.minY, f.maxY, f.minX, f.maxX]))
        } else {
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
    print("press \(i + 1) (key \(code))")
    if sampleAX {
        let r = stats(ax)
        print(line("AX    ", r, String(format: "; %d reads, slowest %.1f ms; ends %@", reads, worstRead * 1000, "\(frame() ?? .null)")))
        if !r.firstBack.isEmpty { print("    first backward (AX): \(r.firstBack)") }
        if trace {
            var lastE: [Double] = []
            let changes = ax.filter { defer { lastE = $0.e }; return $0.e != lastE }
            print("    AX trace (ms: top/bottom/left/right): " + changes.map { String(format: "%.0f:%.0f/%.0f/%.0f/%.0f", $0.t * 1000, $0.e[0], $0.e[1], $0.e[2], $0.e[3]) }.joined(separator: " "))
        }
    }
    if capture {
        Thread.sleep(forTimeInterval: 0.05)   // let the last frames arrive
        lock.lock(); let es = shown.filter { $0.t >= t0 - 0.02 && $0.t <= t0 + gap && $0.top >= 0 && $0.left >= 0 }; lock.unlock()
        let s = es.map { (t: $0.t - t0, e: [Double($0.top), Double($0.bottom), Double($0.left), Double($0.right)]) }
        let r = stats(s)
        let end = es.last.map { "top \($0.top) bottom \($0.bottom) left \($0.left) right \($0.right)" } ?? "-"
        print(line("screen", r, "; \(es.count) captures; ends \(end)"))
        if !r.firstBack.isEmpty { print("    first backward (screen): \(r.firstBack)") }
        if trace {
            var lastE: [Double] = []
            let changes = s.filter { defer { lastE = $0.e }; return $0.e != lastE }
            print("    screen trace (ms: top/bottom/left/right): " + changes.map { String(format: "%.0f:%.0f/%.0f/%.0f/%.0f", $0.t * 1000, $0.e[0], $0.e[1], $0.e[2], $0.e[3]) }.joined(separator: " "))
        }
    }
    lock.lock(); shown.removeAll(); lock.unlock()
}
if let stream { stream.stopCapture { _ in sem.signal() }; sem.wait() }

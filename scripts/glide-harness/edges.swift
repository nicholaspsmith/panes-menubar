import AppKit
import ApplicationServices
import ScreenCaptureKit
import CoreMedia

// Captures only the test window's edges (as numbers, never images) at up to
// 120 fps while it glides, to see what a glide actually looks like on screen.
// usage: edges <variant> x y w h  x y w h   (AX points, A then B)
let args = CommandLine.arguments
let variant = args[1]
let n = args.dropFirst(2).compactMap { Double($0) }
let A = CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
let B = CGRect(x: n[4], y: n[5], width: n[6], height: n[7])
let runs = 3

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.nicholassmith.tiletest").first else { print("not running"); exit(1) }
let appEl = AXUIElementCreateApplication(app.processIdentifier)
var wv: AnyObject?
AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &wv)
let win = wv as! AXUIElement
func setPos(_ p: CGPoint) { var p = p; AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!) }
func setSize(_ s: CGSize) { var s = s; AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!) }
func setFrame(_ r: CGRect) { setSize(r.size); setPos(r.origin); setSize(r.size) }

// Scan lines: a column through the middle of both frames, a row through the middle of both.
let scanX = Int(((A.intersection(B)).midX).rounded())
let scanY = Int(((A.intersection(B)).midY).rounded())
struct Edge { var t: Double; var top: Int; var bottom: Int; var left: Int; var right: Int }
var edges: [Edge] = []
let lock = NSLock()

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
        for y in 0..<h where magenta(scanX, y) { if top < 0 { top = y }; bottom = y }
        for x in 0..<w where magenta(x, scanY) { if left < 0 { left = x }; right = x }
        lock.lock(); edges.append(Edge(t: t, top: top, bottom: bottom + 1, left: left, right: right + 1)); lock.unlock()
    }
}

let sem = DispatchSemaphore(value: 0)
var display: SCDisplay!
SCShareableContent.getWithCompletionHandler { c, e in display = c?.displays.first { $0.displayID == CGMainDisplayID() }; sem.signal() }
sem.wait()
let cfg = SCStreamConfiguration()
cfg.width = display.width; cfg.height = display.height     // 1 px per point
cfg.minimumFrameInterval = CMTime(value: 1, timescale: 120)
cfg.pixelFormat = kCVPixelFormatType_32BGRA
cfg.queueDepth = 8
cfg.showsCursor = false
let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: nil)
let out = Out()
try! stream.addStreamOutput(out, type: .screen, sampleHandlerQueue: DispatchQueue(label: "cap"))
stream.startCapture { e in if let e { print("capture error \(e)") }; sem.signal() }
sem.wait()

// ---- glide variants ----
func easeOut(_ t: Double) -> Double { let u = 1 - min(max(t, 0), 1); return 1 - u * u * u }
func easeInOut(_ t: Double) -> Double { let t = min(max(t, 0), 1); return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func lerp(_ f: CGRect, _ g: CGRect, _ p: CGFloat) -> CGRect {
    func l(_ a: CGFloat, _ b: CGFloat) -> CGFloat { (a + (b - a) * p).rounded() }
    return CGRect(x: l(f.minX, g.minX), y: l(f.minY, g.minY), width: l(f.width, g.width), height: l(f.height, g.height))
}
var duration = 0.18
var curve: (Double) -> Double = easeOut
var order = "pos"      // pos: position then size; env: keep the in-between frame inside both
if variant.contains("long") { duration = 0.26 }
if variant.contains("inout") { curve = easeInOut }
if variant.contains("smooth") { curve = { t in let t = min(max(t, 0), 1); return t * t * (3 - 2 * t) } }
if variant.contains("mid") { duration = 0.22 }
if variant.contains("env") { order = "env" }
if variant.contains("sizefirst") { order = "size" }

func apply(_ cur: CGRect, _ f: CGRect) {
    var sizeFirst = order == "size"
    if order == "env" {
        // Shrinking: size first (the window pulls in before it moves). Growing: position first.
        sizeFirst = f.width * f.height < cur.width * cur.height
    }
    if sizeFirst { setSize(f.size); setPos(f.origin) } else { setPos(f.origin); setSize(f.size) }
}

final class Stepper: NSObject {
    var body: () -> Void = {}
    @objc func tick(_ l: CADisplayLink) { body() }
}
func glide(_ from: CGRect, _ to: CGRect) -> Double {
    let start = CACurrentMediaTime(); var done = false; var cur = from
    if variant.contains("dl") {
        let st = Stepper()
        let link = NSScreen.main!.displayLink(target: st, selector: #selector(Stepper.tick(_:)))
        st.body = {
            let el = CACurrentMediaTime() - start
            if el >= duration { link.invalidate(); done = true; return }
            let f = lerp(from, to, CGFloat(curve(el / duration)))
            apply(cur, f); cur = f
        }
        link.add(to: .main, forMode: .common)
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
        setFrame(to)
        return start
    }
    let t = Timer(timeInterval: 1.0 / 120, repeats: true) { t in
        let el = CACurrentMediaTime() - start
        if el >= duration { t.invalidate(); done = true; return }
        let f = lerp(from, to, CGFloat(curve(el / duration)))
        apply(cur, f); cur = f
    }
    RunLoop.main.add(t, forMode: .common)
    while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
    setFrame(to)
    return start
}

func report(_ label: String, _ start: Double, _ from: CGRect, _ to: CGRect) {
    lock.lock(); let es = edges.filter { $0.t >= start - 0.02 && $0.t <= start + duration + 0.25 }; lock.unlock()
    let ys = es.map { $0 }
    var back = 0, maxBack = 0, maxJump = 0, changes = 0, firstMs = -1.0
    let topDir = (to.minY - from.minY).sign == .minus ? -1 : 1
    let botDir = (to.maxY - from.maxY).sign == .minus ? -1 : 1
    for (a, b) in zip(ys, ys.dropFirst()) {
        let dt = b.top - a.top, db = b.bottom - a.bottom
        if dt != 0 || db != 0 { changes += 1; if firstMs < 0 { firstMs = (b.t - start) * 1000 } }
        for (d, dir) in [(dt, topDir), (db, botDir)] where d != 0 {
            if (d > 0 ? 1 : -1) != dir { back += 1; maxBack = max(maxBack, abs(d)) }
            maxJump = max(maxJump, abs(d))
        }
    }
    let last = ys.last.map { "top \($0.top) bottom \($0.bottom)" } ?? "-"
    print(String(format: "  %@: first change %3.0f ms, %2d frames, %d backward (max %3d px), biggest jump %3d px; ends %@", label, firstMs, changes, back, maxBack, maxJump, last))
    if variant.hasSuffix("+trace") && label.hasPrefix("A") {
        print("    trace (ms: top/bottom): " + ys.map { String(format: "%.0f:%d/%d", ($0.t - start) * 1000, $0.top, $0.bottom) }.joined(separator: " "))
    }
}

setFrame(A); Thread.sleep(forTimeInterval: 0.6)
if variant.hasPrefix("key:") {
    // Let the real Panes do it: press ⌘⌥ + key, record what reaches the screen.
    let code = CGKeyCode(Int(variant.dropFirst(4))!)
    duration = 0.4
    print("Panes ⌘⌥ key \(code), from \(A)")
    for i in 0..<4 {
        let src = CGEventSource(stateID: .hidSystemState)
        let start = CACurrentMediaTime()
        for down in [true, false] { let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!; e.flags = [.maskCommand, .maskAlternate]; e.post(tap: .cghidEventTap) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        lock.lock(); let es = edges.filter { $0.t >= start - 0.02 && $0.t <= start + 0.7 }; lock.unlock()
        guard let f = es.first, let l = es.last else { continue }
        report("press \(i + 1)", start, CGRect(x: f.left, y: f.top, width: f.right - f.left, height: f.bottom - f.top), CGRect(x: l.left, y: l.top, width: l.right - l.left, height: l.bottom - l.top))
    }
    stream.stopCapture { _ in sem.signal() }; sem.wait(); exit(0)
}
print("\(variant): duration \(duration), order \(order)")
for _ in 0..<runs {
    let s1 = glide(A, B); RunLoop.main.run(until: Date().addingTimeInterval(0.4)); report("A->B", s1, A, B)
    let s2 = glide(B, A); RunLoop.main.run(until: Date().addingTimeInterval(0.4)); report("B->A", s2, B, A)
}
stream.stopCapture { _ in sem.signal() }; sem.wait()

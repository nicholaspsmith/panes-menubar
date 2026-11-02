// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import ScreenCaptureKit
import CoreMedia

// usage: fpsprobe [seconds]
// How many distinct frames a second can the capture see? Moves a magenta bar
// 2 pt on every display-link tick inside a still window (no resize), and
// counts how often its position changes in the ScreenCaptureKit stream. If
// this reaches the display's rate but a resizing window does not, the limit
// is the resize path, not the capture.
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "3") ?? 3
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!
let rect = NSRect(x: screen.frame.midX - 300, y: screen.frame.midY - 20, width: 600, height: 40)
let win = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
win.backgroundColor = .black
win.level = .floating
let bar = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
bar.wantsLayer = true
bar.layer?.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).cgColor
win.contentView!.addSubview(bar)
win.orderFrontRegardless()

final class Stepper: NSObject {
    var ticks = 0
    @objc func tick(_ l: CADisplayLink) {
        ticks += 1
        var f = bar.frame
        f.origin.x = CGFloat((ticks * 2) % 560)
        bar.frame = f
    }
}
let st = Stepper()
let link = screen.displayLink(target: st, selector: #selector(Stepper.tick(_:)))
link.add(to: .main, forMode: .common)

// Scan row: the bar's centre line, in capture pixels (1 px per point, top-left origin).
let scanY = Int(screen.frame.maxY - rect.midY)
let x0 = Int(rect.minX), x1 = Int(rect.maxX)
var lefts: [(Double, Int)] = []
let lock = NSLock()
final class Out: NSObject, SCStreamOutput {
    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        if let att = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
           let raw = att[.status] as? Int, raw != SCFrameStatus.complete.rawValue { return }
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        var left = -1
        for x in x0..<x1 { let p = base + scanY * bpr + x * 4; if p[2] > 200 && p[1] < 90 && p[0] > 200 { left = x; break } }
        lock.lock(); lefts.append((CMSampleBufferGetPresentationTimeStamp(sb).seconds, left)); lock.unlock()
    }
}
let out = Out()
SCShareableContent.getWithCompletionHandler { c, e in
    guard let d = c?.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { print("capture error \(String(describing: e))"); exit(3) }
    let cfg = SCStreamConfiguration()
    cfg.width = d.width; cfg.height = d.height
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 120)
    cfg.pixelFormat = kCVPixelFormatType_32BGRA
    cfg.queueDepth = 8
    cfg.showsCursor = false
    let s = SCStream(filter: SCContentFilter(display: d, excludingWindows: []), configuration: cfg, delegate: nil)
    try! s.addStreamOutput(out, type: .screen, sampleHandlerQueue: DispatchQueue(label: "cap"))
    s.startCapture { e in if let e { print("capture error \(e)"); exit(3) } }
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.5) {
        s.stopCapture { _ in
            lock.lock(); let ls = lefts.filter { $0.1 >= 0 }; lock.unlock()
            let changes = zip(ls, ls.dropFirst()).filter { $0.0.1 != $0.1.1 }.count
            let span = (ls.last?.0 ?? 0) - (ls.first?.0 ?? 0)
            print(String(format: "display %d Hz, %d display-link ticks; capture: %d frames, %d distinct positions in %.2f s = %.0f per second",
                         screen.maximumFramesPerSecond, st.ticks, ls.count, changes, span, Double(changes) / max(span, 0.001)))
            exit(0)
        }
    }
}
app.run()

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import Metal
import QuartzCore
import DisplayCore

/// One built-in panel's XDR boost: a borderless, click-through window over the
/// whole screen whose `CAMetalLayer` asks for EDR content and draws one
/// uniform value, `factor`, with a multiply compositing filter. The window
/// server multiplies everything beneath it by that value in EDR space, so SDR
/// white lands at `factor` × SDR white, in the headroom the panel grants
/// while an EDR layer is on screen (BrightIntosh's alternate backend).
///
/// Like `DimOverlayController`'s window it sits above everything, joins every
/// Space and full-screen app, takes no clicks, and is left out of screenshots
/// and recordings. It goes with the process, so a crash can't leave it behind.
/// The layer is redrawn only when `factor` changes: the panel keeps its
/// headroom while the layer stays up (measured, 10 s with no redraw).
final class EDRMultiplyOverlay {
    /// 1 or below hides the window, which also lets the panel leave HDR mode.
    var factor: Float = 1 {
        didSet { update() }
    }

    private let displayID: CGDirectDisplayID
    private let window: NSWindow
    private let layer = CAMetalLayer()
    private let queue: MTLCommandQueue?
    /// The value the layer carries now, nil before the first draw.
    private var drawn: Float?
    private var observer: NSObjectProtocol?
    private var closed = false
    /// A uniform value needs no resolution: the layer stretches a tiny
    /// drawable over the screen instead of holding a full-screen half-float
    /// buffer (~60 MB per drawable on a 3456×2234 panel).
    private static let drawableSide: CGFloat = 16

    init(screen: NSScreen) {
        displayID = Self.displayID(of: screen)
        let device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()

        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.sharingType = .none

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        layer.device = device
        layer.wantsExtendedDynamicRangeContent = true
        layer.pixelFormat = .rgba16Float
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.compositingFilter = "multiply"
        layer.isOpaque = false
        layer.framebufferOnly = true
        layer.drawableSize = CGSize(width: Self.drawableSide, height: Self.drawableSide)
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        window.contentView = view
        window.setFrame(screen.frame, display: false)

        if queue == nil { Log.xdr.error("display \(self.displayID): no Metal device for the EDR overlay") }

        // The panel's frame changes with its resolution; refit on every change.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refit() }
    }

    deinit { close() }

    /// Takes the window down for good. Idempotent.
    func close() {
        guard !closed else { return }
        closed = true
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        window.orderOut(nil)
        window.close()
        drawn = nil
    }

    private func update() {
        guard !closed else { return }
        guard factor > 1, queue != nil else {
            if window.isVisible { window.orderOut(nil) }
            drawn = nil
            return
        }
        // Draw before showing, so the window never appears with a stale value.
        if XDRBrightness.shouldRewrite(written: drawn, wanted: factor) {
            draw(factor)
        }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    private func draw(_ value: Float) {
        guard let queue, let drawable = layer.nextDrawable(),
              let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let v = Double(value)
        pass.colorAttachments[0].clearColor = MTLClearColorMake(v, v, v, 1)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
        drawn = value
    }

    private func refit() {
        guard !closed, let screen = NSScreen.screens.first(where: { Self.displayID(of: $0) == displayID }) else { return }
        window.setFrame(screen.frame, display: false)
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import ApplicationServices

/// The window server's id for an AX window. Private, but stable for over a
/// decade and what every window manager uses: it is the only way to tie an
/// AX element to a `CGWindowID`.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Identifies a window across AX lookups (each lookup returns a new element).
struct WindowKey: Hashable {
    let pid: pid_t
    let id: UInt
}

/// A window, through the Accessibility API. Frames are AX coordinates.
struct AXWindow {
    let element: AXUIElement
    let pid: pid_t

    /// AX calls go to the target app's main thread; one that is busy would
    /// otherwise hold up the key tap (the system disables a tap that is slow).
    static let messagingTimeout: Float = 0.3

    /// The focused window of the frontmost app, if it is one Panes can move.
    static func focused() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return focused(of: app.processIdentifier)
    }

    static func focused(of pid: pid_t) -> AXWindow? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let window = AXWindow(element: value as! AXUIElement, pid: pid)
        AXUIElementSetMessagingTimeout(window.element, messagingTimeout)
        return window.isMovable ? window : nil
    }

    /// The window under a screen point (AX coordinates), for edge snapping.
    static func at(_ point: CGPoint) -> AXWindow? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }
        // Climb to the window: its own AXWindow attribute, else parent by parent.
        for _ in 0..<12 {
            if role(of: element) == kAXWindowRole as String { break }
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                element = value as! AXUIElement
                continue
            }
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            element = value as! AXUIElement
        }
        guard role(of: element) == kAXWindowRole as String else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != getpid() else { return nil }
        let window = AXWindow(element: element, pid: pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return window.isMovable ? window : nil
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return value as? String
    }

    var key: WindowKey {
        var id: CGWindowID = 0
        if _AXUIElementGetWindow(element, &id) == .success, id != 0 { return WindowKey(pid: pid, id: UInt(id)) }
        return WindowKey(pid: pid, id: UInt(CFHash(element)))
    }

    /// Standard windows whose position can be set, and not in full screen.
    var isMovable: Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        if bool(kAXMinimizedAttribute) == true { return false }
        if bool("AXFullScreen") == true { return false }
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if let s = subrole as? String, s != kAXStandardWindowSubrole as String, s != kAXDialogSubrole as String {
            return false
        }
        return frame != nil
    }

    var frame: CGRect? {
        guard let origin: CGPoint = value(kAXPositionAttribute, .cgPoint),
              let size: CGSize = value(kAXSizeAttribute, .cgSize) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    var isResizable: Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    @discardableResult
    func setPosition(_ p: CGPoint) -> Bool {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, v) == .success
    }

    @discardableResult
    func setSize(_ s: CGSize) -> Bool {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, v) == .success
    }

    /// Bring this window's app forward and focus it (after the menu's grid
    /// moved it, say).
    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    // MARK: AXEnhancedUserInterface

    /// Some apps (Chromium, Electron, anything that thinks VoiceOver is on)
    /// animate or defer every AX frame change while AXEnhancedUserInterface is
    /// set on the app, which turns a glide into a crawl. Panes switches it off
    /// for the move and puts it back.
    func withEnhancedUIOff(_ body: () -> Void) -> () -> Void {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        var value: CFTypeRef?
        let wasOn = AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &value) == .success
            && (value as? Bool) == true
        if wasOn { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        body()
        return {
            if wasOn { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
        }
    }

    // MARK: Helpers

    private func bool(_ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private func value<T>(_ attribute: String, _ type: AXValueType) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let axValue = raw as! AXValue
        switch type {
        case .cgPoint:
            var p = CGPoint.zero
            return AXValueGetValue(axValue, .cgPoint, &p) ? p as? T : nil
        case .cgSize:
            var s = CGSize.zero
            return AXValueGetValue(axValue, .cgSize, &s) ? s as? T : nil
        default:
            return nil
        }
    }
}

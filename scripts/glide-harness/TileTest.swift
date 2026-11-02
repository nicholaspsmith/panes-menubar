import AppKit

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ n: Notification) {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let winItem = NSMenuItem(); main.addItem(winItem)
        let winMenu = NSMenu(title: "Window"); winItem.submenu = winMenu
        NSApp.mainMenu = main
        NSApp.windowsMenu = winMenu
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 800, height: 500),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Panes tile test"
        // Solid magenta edge to edge, so a capture can find the window's edges.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let nc = NotificationCenter.default
        for n in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.report(n.rawValue) }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.nicholassmith.tiletest.cmd"), object: nil, queue: .main) { [weak self] note in
            guard let self, let sel = note.object as? String else { return }
            self.report("cmd \(sel)")
            if sel == "report" { return }
            self.window.perform(NSSelectorFromString(sel), with: nil)
        }
    }
    func report(_ what: String) {
        NSLog("TILETEST %@ active=%d key=%@ main=%@", what, NSApp.isActive ? 1 : 0, NSApp.keyWindow?.title ?? "nil", NSApp.mainWindow?.title ?? "nil")
    }
}
let app = NSApplication.shared
let d = Delegate(); app.delegate = d
app.setActivationPolicy(.regular)
app.run()

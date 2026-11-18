// App.swift -- status bar item, hotkey wiring, app lifecycle.
import AppKit

/// Keep strong references: NSApplication.delegate and gHotkeyHandler do not own their targets.
var gDelegate: AppDelegate?
var gDemoController: RingController?

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    let controller = RingController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "ImageRing")
        let menu = NSMenu()
        let hk = NSMenuItem(title: "Hotkey: ⌃⌥Space", action: nil, keyEquivalent: "")
        hk.isEnabled = false
        menu.addItem(hk)
        let quit = NSMenuItem(title: "Quit ImageRing", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item

        let c = controller
        gHotkeyHandler = { c.hotkeyEvent($0) }
        let inst = Hotkey.shared.installHandler()
        let reg = Hotkey.shared.registerMain()
        Log.write("START pid=\(getpid()) installHandler=\(inst) registerMain(ctrl+opt+space)=\(reg)")
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let app = AppController()
    private var mainWindow: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        buildMainWindow()
        app.start()
        showMain()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !mainWindow.isVisible { showMain() }
        return true
    }

    // MARK: Windows

    private func buildMainWindow() {
        let root = NativeRootView(app: app) { [weak self] in
            self?.signOut(nil)
        }
        let host = NSHostingController(rootView: root)
        host.sceneBridgingOptions = [.toolbars]
        host.sizingOptions = [.minSize]

        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.title = "CloudPlayer"
        w.titleVisibility = .hidden
        w.toolbarStyle = .unified
        w.setContentSize(Self.standardContentSize)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        w.setFrameAutosaveName("MainWindowNative")
        mainWindow = w
    }

    static let standardContentSize = NSSize(width: 1120, height: 760)

    // MARK: Actions

    @objc func showMain(_ sender: Any? = nil) {
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func signOut(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Sign out of SoundCloud?"
        alert.informativeText = "This clears CloudPlayer's saved SoundCloud session."
        alert.addButton(withTitle: "Sign Out")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            app.signOut()
        }
    }

    // MARK: Menus

    private func item(
        _ title: String,
        _ action: Selector?,
        _ key: String = "",
        _ mods: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = target
        return i
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let m = NSMenu(title: title)
        items.forEach(m.addItem)
        top.submenu = m
        return top
    }

    private func buildMainMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu("CloudPlayer", [
            item("About CloudPlayer", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Sign Out…", #selector(signOut(_:)), target: self),
            .separator(),
            item("Hide CloudPlayer", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit CloudPlayer", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        menu.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        let window = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            .separator(),
            item("Show Main Window", #selector(showMain(_:)), "0", target: self),
        ])
        NSApp.windowsMenu = window.submenu
        menu.addItem(window)
        return menu
    }
}

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let player = WebPlayer()
    private var mainWindow: NSWindow!
    private var miniPanel: NSPanel!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        buildMainWindow()
        buildMiniPanel()
        buildStatusItem()
        player.load()
        showMain()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !mainWindow.isVisible { exitMini() }
        return true
    }

    /// Closing the main window quits the app (which stops playback, see applicationShouldTerminate).
    /// Other windows (the mini player) just hide.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === mainWindow {
            NSApp.terminate(nil)
        } else {
            sender.orderOut(nil)
        }
        return false
    }

    private var isTerminating = false

    /// Quit cleanly: stop and release the audio stream (which also ends WebKit's Now Playing
    /// entry), unload the page so WebKit flushes storage, then exit. Capped at 2 s so quitting can never hang.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTerminating { return .terminateNow }
        isTerminating = true

        var replied = false
        let finish: @MainActor () -> Void = {
            guard !replied else { return }
            replied = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        player.shutdown(completion: finish)
        runOnMainRunLoop(after: 2) { finish() }
        return .terminateLater
    }

    // MARK: Windows

    private func buildMainWindow() {
        let root = MainView(player: player,
                            onMini: { [weak self] in self?.enterMini() },
                            onSignOut: { [weak self] in self?.signOut(nil) })
        let host = NSHostingController(rootView: root)
        host.sceneBridgingOptions = [.toolbars]   // SwiftUI .toolbar/.searchable → the window's toolbar
        host.sizingOptions = [.minSize]           // SwiftUI's layout minimums limit the window

        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.title = "CloudPlayer"
        w.titleVisibility = .hidden
        w.toolbarStyle = .unified
        w.setContentSize(Self.standardContentSize)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        var autosave = true
        #if DEBUG
        // -cpWindowSize 700x500: open at this content size (tests the minimum); no autosave.
        if let spec = UserDefaults.standard.string(forKey: "cpWindowSize") {
            let parts = spec.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { w.setContentSize(NSSize(width: parts[0], height: parts[1])); autosave = false }
        }
        #endif
        if autosave { w.setFrameAutosaveName("MainWindow") }   // restores the saved frame…
        mainWindow = w
        DispatchQueue.main.async { [weak w] in    // …which may predate the minimum: grow it back
            guard let w else { return }
            let content = w.contentRect(forFrameRect: w.frame).size
            let minimum = w.contentMinSize
            if content.width < minimum.width || content.height < minimum.height {
                w.setContentSize(NSSize(width: max(content.width, minimum.width), height: max(content.height, minimum.height)))
            }
        }
    }

    static let standardContentSize = NSSize(width: 1320, height: 880)

    /// Title-bar double-click / Zoom: toggle to a comfortable standard size (fits the screen),
    /// keeping the window's top-left where it is.
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        guard window === mainWindow else { return newFrame }
        let visible = window.screen?.visibleFrame ?? newFrame
        let content = NSSize(width: min(Self.standardContentSize.width, visible.width),
                             height: min(Self.standardContentSize.height, visible.height))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(window.frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(window.frame.maxY - frame.height, visible.minY), visible.maxY - frame.height)
        return frame
    }

    private func buildMiniPanel() {
        // Borderless, so the SwiftUI view owns the whole shape (all four corners rounded alike).
        let p = MiniPanel(contentRect: NSRect(x: 0, y: 0, width: MiniPlayerView.width, height: 150),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        p.isMovableByWindowBackground = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        let host = NSHostingView(rootView: MiniPlayerView(player: player) { [weak self] in self?.exitMini() })
        p.contentView = host
        p.setContentSize(host.fittingSize)   // size to the SwiftUI layout
        p.invalidateShadow()                  // shadow follows the rounded shape

        if !p.setFrameUsingName("MiniPlayerV2"), let screen = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: screen.maxX - p.frame.width - 16, y: screen.maxY - p.frame.height - 16))
        }
        p.setFrameAutosaveName("MiniPlayerV2")
        miniPanel = p
    }

    private func enterMini() {
        mainWindow.orderOut(nil)
        miniPanel.orderFrontRegardless()
    }

    private func exitMini() {
        miniPanel.orderOut(nil)
        showMain()
    }

    // MARK: Actions

    @objc func toggleMini(_ sender: Any?) { miniPanel.isVisible ? exitMini() : enterMini() }
    @objc func showMain(_ sender: Any? = nil) {
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func playPause(_ sender: Any?) { player.playPause() }
    @objc func nextTrack(_ sender: Any?) { player.next() }
    @objc func previousTrack(_ sender: Any?) { player.previous() }
    @objc func toggleLike(_ sender: Any?) { player.toggleLike() }
    @objc func toggleShuffle(_ sender: Any?) { player.toggleShuffle() }
    @objc func cycleRepeat(_ sender: Any?) { player.cycleRepeat() }
    @objc func reloadPage(_ sender: Any?) { player.reload() }
    @objc func back(_ sender: Any?) { player.goBack() }
    @objc func forward(_ sender: Any?) { player.goForward() }
    @objc func reloadCustomCSS(_ sender: Any?) { player.reloadCustomCSS() }
    @objc func openSettings(_ sender: Any?) { showMain(); player.open("/settings") }

    @objc func toggleSidebarColumn(_ sender: Any?) {
        showMain()
        NotificationCenter.default.post(name: .cpToggleSidebar, object: nil)
    }

    @objc func focusSearch(_ sender: Any?) {
        showMain()
        NotificationCenter.default.post(name: .cpFocusSearch, object: nil)
    }

    /// Sidebar destinations; the menu item's tag is the SidebarItem's index.
    @objc func goToSection(_ sender: NSMenuItem) {
        showMain()
        player.open(SidebarItem.allCases[sender.tag].path)
    }

    @objc func signOut(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Sign out of SoundCloud?"
        alert.informativeText = "This clears CloudPlayer's saved login and website data."
        alert.addButton(withTitle: "Sign Out")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { player.signOut() }
    }

    @objc func editCustomCSS(_ sender: Any?) {
        let url = WebPlayer.customCSSURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Injected.customCSSTemplate.write(to: url, atomically: true, encoding: .utf8)
        }
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: Menus

    private func item(_ title: String, _ action: Selector?, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
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
            item("Settings…", #selector(openSettings(_:)), ",", target: self),
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
            .separator(),
            item("Search", #selector(focusSearch(_:)), "f", target: self),
        ]))
        menu.addItem(submenu("View", [
            item("Toggle Sidebar", #selector(toggleSidebarColumn(_:)), "s", [.command, .control], target: self),
            .separator(),
            item("Mini Player", #selector(toggleMini(_:)), "m", [.command, .shift], target: self),
            .separator(),
            item("Reload Page", #selector(reloadPage(_:)), "r", target: self),
            .separator(),
            item("Edit Custom CSS…", #selector(editCustomCSS(_:)), target: self),
            item("Reload Custom CSS", #selector(reloadCustomCSS(_:)), "r", [.command, .shift], target: self),
        ]))
        var go: [NSMenuItem] = [
            item("Back", #selector(back(_:)), "[", target: self),
            item("Forward", #selector(forward(_:)), "]", target: self),
            .separator(),
        ]
        for (i, section) in SidebarItem.allCases.enumerated() {
            let mi = item(section.title, #selector(goToSection(_:)), "\(i + 1)", target: self)
            mi.tag = i
            go.append(mi)
        }
        menu.addItem(submenu("Go", go))
        menu.addItem(submenu("Controls", [
            item("Play/Pause", #selector(playPause(_:)), "p", target: self),
            item("Next", #selector(nextTrack(_:)), String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command, .option], target: self),
            item("Previous", #selector(previousTrack(_:)), String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command, .option], target: self),
            item("Like", #selector(toggleLike(_:)), "l", target: self),
            .separator(),
            item("Shuffle", #selector(toggleShuffle(_:)), "s", [.command, .option], target: self),
            item("Repeat", #selector(cycleRepeat(_:)), "r", [.command, .option], target: self),
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

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "CloudPlayer")
        let m = NSMenu()
        m.delegate = self
        statusItem.menu = m
    }

    /// Rebuilt each time the menu-bar icon is clicked so it shows the current track.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        menu.removeAllItems()
        let s = player.state
        if s.hasTrack {
            let now = NSMenuItem(title: "\(s.title) — \(s.artist)", action: nil, keyEquivalent: "")
            now.isEnabled = false
            menu.addItem(now)
            menu.addItem(.separator())
        }
        menu.addItem(item(s.isPlaying ? "Pause" : "Play", #selector(playPause(_:)), target: self))
        menu.addItem(item("Next", #selector(nextTrack(_:)), target: self))
        menu.addItem(item("Previous", #selector(previousTrack(_:)), target: self))
        menu.addItem(item(s.isLiked ? "Unlike" : "Like", #selector(toggleLike(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(item(miniPanel.isVisible ? "Hide Mini Player" : "Mini Player", #selector(toggleMini(_:)), target: self))
        menu.addItem(item("Show Main Window", #selector(showMain(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(NSApplication.terminate(_:))))
    }
}

/// Borderless panels can't become key by default; the mini player needs to (sliders, buttons).
final class MiniPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

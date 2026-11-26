import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let app = AppController()
    private var mainWindow: NSWindow!
    private var miniPanel: NSPanel!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        buildMainWindow()
        buildMiniPanel()
        buildStatusItem()
        app.start()
        showMain()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !mainWindow.isVisible { exitMini() }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === mainWindow {
            NSApp.terminate(nil)
        } else {
            sender.orderOut(nil)
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        app.shutdown()
    }

    // MARK: Windows

    private func buildMainWindow() {
        let root = NativeRootView(
            app: app,
            onMini: { [weak self] in self?.enterMini() },
            onSignOut: { [weak self] in self?.signOut(nil) }
        )
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

    private func buildMiniPanel() {
        let p = NativeMiniPanel(
            contentRect: NSRect(x: 0, y: 0, width: NativeMiniPlayerView.width, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isMovableByWindowBackground = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self

        let host = NSHostingView(rootView: NativeMiniPlayerView(app: app) { [weak self] in
            self?.exitMini()
        })
        p.contentView = host
        p.setContentSize(host.fittingSize)
        p.invalidateShadow()

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
    @objc func playPause(_ sender: Any?) { app.audio.togglePlayPause() }
    @objc func nextTrack(_ sender: Any?) { app.audio.next() }
    @objc func previousTrack(_ sender: Any?) { app.audio.previous() }
    @objc func toggleLike(_ sender: Any?) { app.toggleLikeCurrentTrack() }
    @objc func toggleShuffle(_ sender: Any?) { app.audio.toggleShuffle() }
    @objc func cycleRepeat(_ sender: Any?) { app.audio.cycleRepeat() }

    @objc func signOut(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Sign out of SoundCloud?"
        alert.informativeText = "This clears CloudPlayer's saved SoundCloud session."
        alert.addButton(withTitle: "Sign Out")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if miniPanel.isVisible { exitMini() }
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
        menu.addItem(submenu("View", [
            item("Mini Player", #selector(toggleMini(_:)), "m", [.command, .shift], target: self),
        ]))
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        menu.removeAllItems()
        let audio = app.audio
        if let track = audio.currentTrack {
            let now = NSMenuItem(title: "\(track.title) — \(track.artistName)", action: nil, keyEquivalent: "")
            now.isEnabled = false
            menu.addItem(now)
            menu.addItem(.separator())
        }
        menu.addItem(item(audio.isPlaying ? "Pause" : "Play", #selector(playPause(_:)), target: self))
        menu.addItem(item("Next", #selector(nextTrack(_:)), target: self))
        menu.addItem(item("Previous", #selector(previousTrack(_:)), target: self))
        menu.addItem(item(app.isCurrentTrackLiked() ? "Unlike" : "Like", #selector(toggleLike(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(item(miniPanel.isVisible ? "Hide Mini Player" : "Mini Player", #selector(toggleMini(_:)), target: self))
        menu.addItem(item("Show Main Window", #selector(showMain(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(NSApplication.terminate(_:))))
    }
}

private final class NativeMiniPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

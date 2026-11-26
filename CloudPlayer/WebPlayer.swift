import AppKit
import SwiftUI
import WebKit

enum RepeatMode: String { case none, one, all }

/// Whether SoundCloud has a signed-in session in the app's cookie store.
enum AuthState { case unknown, signedOut, signedIn }

enum SwipeDirection: Equatable { case next, previous }

/// Directional page-swipe overlay used when following the Now Playing track page.
/// The outgoing snapshot begins sliding immediately on Next/Prev to give instant UI response
/// while buying time for the incoming track page to paint before it glides into view.
struct PageSwipeTransition: Equatable {
    let id: Int
    let direction: SwipeDirection
    let snapshot: NSImage
    var outgoingExited: Bool
    var incomingReady: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.direction == rhs.direction
            && lhs.outgoingExited == rhs.outgoingExited && lhs.incomingReady == rhs.incomingReady
    }
}

/// A SoundCloud notification ("… was saved to your Library"), shown in the sidebar.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let artworkURL: URL?
}

/// Position and state of the native Liquid Glass play button hovering over a tile.
struct HoverPlay: Equatable {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let isPlaying: Bool
}

struct TrackState: Equatable {
    var hasTrack = false
    var title = ""
    var artist = ""
    var trackPath = ""
    var artistPath = ""
    var artworkURL: URL?
    var isPlaying = false
    var position: Double = 0
    var duration: Double = 0
    var isLiked = false
    var shuffle = false
    var repeatMode = RepeatMode.none
    var queueVisible = false
    var albumPath = ""
}

/// Owns the SoundCloud web view (the audio engine) and exposes its state + controls.
/// Runs `body` on the main run loop after `delay`, including while AppKit waits on a
/// `.terminateLater` reply: it then spins the run loop in modal-panel mode, where
/// `DispatchQueue.main` blocks don't run, so a plain asyncAfter would never fire.
func runOnMainRunLoop(after delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
    let timer = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { body() } }
    for mode in [RunLoop.Mode.common, .modalPanel] { RunLoop.main.add(timer, forMode: mode) }
}

@MainActor
final class WebPlayer: NSObject, ObservableObject {
    @Published private(set) var state = TrackState()
    @Published private(set) var currentPath = "/"
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var profilePath = ""
    @Published private(set) var volume: Double
    @Published var toast: Toast?
    @Published private(set) var hoverPlay: HoverPlay?
    @Published private(set) var pageSwipe: PageSwipeTransition?
    @Published private(set) var auth = AuthState.unknown
    /// Signed out: SoundCloud's sign-in form has drawn (until then the window shows a spinner).
    @Published private(set) var signInReady = false
    private var authCheck: DispatchWorkItem?
    /// Signed in, but since then pages have shown no user, and how many times the page has
    /// reloaded meanwhile (see dropDeadSession).
    private var noUserSince: Date?
    private var noUserReloads = 0
    /// Just signed in: the old signed-out page may still report until the new one commits.
    private var awaitingFreshPage = false
    private var lastTrackPath = ""
    private var pendingSwipeDirection: (dir: SwipeDirection, at: Date)?
    private var swipeGeneration = 0
    private var swipeTargetPath = ""
    private var swipeFallbackWork: DispatchWorkItem?
    private var hoverLeaveWork: DispatchWorkItem?
    private var scrollMonitor: Any?
    var isHoveringPlayButton = false {
        didSet {
            guard isHoveringPlayButton != oldValue else { return }
            if isHoveringPlayButton {
                hoverLeaveWork?.cancel()
                hoverLeaveWork = nil
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self, self.isHoveringPlayButton, event.window == self.webView.window else { return event }
                    self.hoverPlay = nil
                    self.isHoveringPlayButton = false
                    self.run("CP.clearHoverTile()")
                    self.webView.scrollWheel(with: event)
                    return nil
                }
            } else {
                if let m = scrollMonitor {
                    NSEvent.removeMonitor(m)
                    scrollMonitor = nil
                }
                if hoverPlay != nil {
                    hoverLeaveWork?.cancel()
                    // Let WebKit see the pointer first, then ask JS whether it is still on the tile:
                    // it re-posts the button (hoverPlay message) or clears it (hoverPlay null).
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, !self.isHoveringPlayButton else { return }
                        self.run("CP.resyncHoverTile()")
                    }
                    hoverLeaveWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
                }
            }
        }
    }

    let webView: WKWebView
    private var popups: [NSWindow] = []
    private var signInBusyWork: DispatchWorkItem?
    private var theme: Theme.Snapshot
    private var observations: [NSKeyValueObservation] = []
    #if DEBUG
    private var debugFirstLoad = true
    fileprivate var debugNavGeneration = 0
    #endif

    static let home = URL(string: "https://soundcloud.com/discover")!
    static let customCSSURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CloudPlayer/custom.css")

    override init() {
        volume = UserDefaults.standard.object(forKey: "volume") as? Double ?? 1
        theme = Theme.current()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // persistent cookies → stay logged in
        #if DEBUG
        // -cpEphemeral YES: throwaway cookies/storage (test the signed-out flow without logging out).
        if UserDefaults.standard.bool(forKey: "cpEphemeral") { config.websiteDataStore = .nonPersistent() }
        // -cpAuthClick facebook|google|apple: the sign-in form clicks that button by itself, so
        // its popup must be allowed without a real click.
        if UserDefaults.standard.string(forKey: "cpAuthClick") != nil {
            config.preferences.javaScriptCanOpenWindowsAutomatically = true
        }
        #endif
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        webView = PageWebView(frame: .zero, configuration: config)
        super.init()
        installUserScripts()
        webView.configuration.userContentController.add(WeakMessageHandler(self), name: "cp")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true            // right-click → Inspect Element
        webView.underPageBackgroundColor = .textBackgroundColor

        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated {
                    guard let self, let url = wv.url else { return }
                    let path = url.path.isEmpty ? "/" : url.path
                    let full = url.query.map { "\(path)?\($0)" } ?? path
                    if self.currentPath != full {
                        self.currentPath = full
                        #if DEBUG
                        self.scheduleNavigationDump()
                        #endif
                    }
                }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.canGoBack = wv.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.canGoForward = wv.canGoForward }
            },
            // Light/dark switches
            NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refreshTheme() }
            },
        ]
        // Accent colour changes
        NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTheme() }
        }
    }

    func load() {
        Task {
            // Install the blocklist before the first request so nothing slips through.
            var block = true
            #if DEBUG
            block = !UserDefaults.standard.bool(forKey: "cpNoBlocklist")   // debug: -cpNoBlocklist YES
            #endif
            if block { await Blocklist.install(on: webView.configuration.userContentController) }
            webView.configuration.websiteDataStore.httpCookieStore.add(self)
            await refreshAuth()
            var url = Self.home
            #if DEBUG
            if let path = UserDefaults.standard.string(forKey: "cpStartPath"),
               let u = URL(string: "https://soundcloud.com" + path) { url = u }
            #endif
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: Navigation

    /// Navigates inside SoundCloud's single-page app (keeps playback going).
    /// `replace`: replace the current history entry instead of adding one.
    func open(_ path: String, replace: Bool = false) {
        guard !path.isEmpty else { return }
        let p = Injected.js(path)
        let fallback = replace ? "location.replace(\(p))" : "location.assign(\(p))"
        webView.evaluateJavaScript("window.CP ? CP.open(\(p), \(replace)) : \(fallback)", completionHandler: nil)
    }

    func search(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        open("/search?q=\(encoded)")
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    /// Clears the app's cookies/storage (logs out of SoundCloud) and returns to the start page.
    func signOut() {
        let store = webView.configuration.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            guard let self else { return }
            self.state = TrackState()
            self.profilePath = ""
            self.setAuth(.signedOut)
            self.webView.load(URLRequest(url: URL(string: "https://soundcloud.com/")!))
        }
    }

    // MARK: Auth

    /// Signed in = SoundCloud's session cookies are present (the refresh token alone is
    /// enough: the page renews the access token itself).
    private func refreshAuth() async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let now = Date()
        let session = cookies.filter {
            ($0.name == "oauth_token" || $0.name == "oauth_refresh_token") && !$0.value.isEmpty
                && ($0.domain == "soundcloud.com" || $0.domain.hasSuffix(".soundcloud.com"))
                && ($0.expiresDate.map { $0 > now } ?? true)
        }
        setAuth(session.isEmpty ? .signedOut : .signedIn)
    }

    /// The page's view of the session, from each state report: a real profile link means a
    /// user; SoundCloud's "Sign in" header or a profile link to "/undefined" means none.
    private func notePageUser(profilePath: String, noUser: Bool) {
        guard auth == .signedIn, !awaitingFreshPage else { return }
        if !profilePath.isEmpty && !profilePath.hasSuffix("/undefined") {
            noUserSince = nil
        } else if noUser {
            guard let since = noUserSince else {
                noUserSince = Date()
                noUserReloads = 0
                return
            }
            if Date().timeIntervalSince(since) > 12 && noUserReloads >= 3 { dropDeadSession() }
        }
    }

    /// A stored session SoundCloud no longer accepts (expired / revoked): its pages show no
    /// user and keep reloading themselves every couple of seconds. Both must hold (so an API
    /// hiccup never signs anyone out). Forget just the dead tokens, which shows the sign-in
    /// screen and lets SoundCloud load as signed out.
    private func dropDeadSession() {
        noUserSince = nil
        #if DEBUG
        debugAuthLog("dropping dead session")
        #endif
        let store = webView.configuration.websiteDataStore.httpCookieStore
        Task {
            for c in await store.allCookies()
            where (c.name == "oauth_token" || c.name == "oauth_refresh_token")
                && (c.domain == "soundcloud.com" || c.domain.hasSuffix(".soundcloud.com")) {
                await store.deleteCookie(c)
            }
            await refreshAuth()
            webView.load(URLRequest(url: URL(string: "https://soundcloud.com/")!))
        }
    }

    fileprivate func scheduleAuthCheck() {
        authCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { await self?.refreshAuth() } }
        authCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func setAuth(_ new: AuthState) {
        guard new != auth else { return }
        let old = auth
        auth = new
        #if DEBUG
        debugAuthLog("\(old) → \(new)")
        #endif
        switch new {
        case .signedOut:
            signInReady = false
            noUserSince = nil
            profilePath = ""
            run("CP.setSignIn(true)")
        case .signedIn:
            run("CP.setSignIn(false)")
            // Just signed in: start fresh on Home (SoundCloud would otherwise stay on its
            // signed-out landing page until it reloads).
            if old == .signedOut {
                awaitingFreshPage = true
                webView.load(URLRequest(url: Self.home))
            }
        case .unknown:
            break
        }
    }

    // MARK: Playback commands

    func playPause() { cmd("toggle") }
    func play() { if !state.isPlaying { playPause() } }
    func pause() { if state.isPlaying { playPause() } }

    /// Before quitting: stop playback, tear down the media element so the stream's network
    /// connection and buffers are released, then unload the page so its pagehide/unload handlers
    /// run and WebKit commits localStorage/cookies before the app exits.
    func shutdown(completion: @escaping @MainActor () -> Void) {
        let js = """
        (() => {
          const els = new Set(document.querySelectorAll('audio, video'));
          if (window.CP && CP.media) els.add(CP.media);
          for (const m of els) {
            try { m.pause(); m.removeAttribute('src'); m.srcObject = null; m.load(); } catch (e) {}
          }
          return els.size;
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            guard let self else { completion(); return }
            self.webView.stopLoading()
            self.webView.load(URLRequest(url: URL(string: "about:blank")!))
            runOnMainRunLoop(after: 0.4) { completion() }
        }
    }
    func next() {
        pendingSwipeDirection = (.next, Date())
        if isViewingNowPlaying { startImmediateSwipe(direction: .next) }
        cmd("next")
    }
    func previous() {
        pendingSwipeDirection = (.previous, Date())
        // Pressing Previous past ~3s restarts the current track at 0:00 instead of changing tracks.
        if isViewingNowPlaying && state.position <= 3.5 { startImmediateSwipe(direction: .previous) }
        cmd("prev")
    }

    private var isViewingNowPlaying: Bool {
        let cur = Self.normPath(currentPath)
        let track = Self.normPath(state.trackPath.isEmpty ? lastTrackPath : state.trackPath)
        return !track.isEmpty && (cur == track || (!swipeTargetPath.isEmpty && swipeTargetPath == track))
    }
    func toggleLike() { cmd("like") }
    func toggleShuffle() { cmd("shuffle") }
    func cycleRepeat() { cmd("repeat") }
    func toggleQueue() { cmd("queue") }

    func seek(fraction: Double) { cmd("seek", min(max(fraction, 0), 1)) }

    func seek(seconds: Double) {
        guard state.duration > 0 else { return }
        seek(fraction: seconds / state.duration)
    }

    func setVolume(_ v: Double) {
        let v = min(max(v, 0), 1)
        volume = v
        UserDefaults.standard.set(v, forKey: "volume")
        cmd("volume", v)
    }

    private func cmd(_ name: String, _ arg: Double? = nil) {
        run("CP.cmd('\(name)'\(arg.map { ", \($0)" } ?? ""))")
    }

    // MARK: Styling

    func reloadCustomCSS() {
        let css = (try? String(contentsOf: Self.customCSSURL, encoding: .utf8)) ?? ""
        run("CP.setCustomCSS(\(Injected.js(css)))")
    }

    private func refreshTheme() {
        let t = Theme.current()
        guard t != theme else { return }
        theme = t
        installUserScripts()   // for future page loads
        run("CP.setTheme(\(t.isDark), \(Injected.js(Theme.css(t))), \(Injected.js(Theme.frameCSS(t))))")
    }

    private func installUserScripts() {
        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        ucc.addUserScript(WKUserScript(source: Injected.mediaSessionShim,
                                       injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ucc.addUserScript(WKUserScript(source: Injected.bootstrap(theme: theme, volume: volume),
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: Injected.frameScript(theme: theme),
                                       injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ucc.addUserScript(WKUserScript(source: Injected.authFrameScript(),
                                       injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }

    private func run(_ js: String) {
        webView.evaluateJavaScript("window.CP && \(js)", completionHandler: nil)
    }

    func triggerHoverPlay() {
        run("CP.clickHoverPlay()")
    }

    /// Shows a native toast card at the bottom of the left sidebar, auto-dismissing after `duration`s.
    func showToast(_ text: String, artworkURL: URL? = nil, duration: TimeInterval = 4) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let t = Toast(text: trimmed, artworkURL: artworkURL)
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }
}

// MARK: - State from JS

extension WebPlayer: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any] else { return }
        if let hp = d["hoverPlay"] {
            hoverLeaveWork?.cancel()
            hoverLeaveWork = nil
            if let dict = hp as? [String: Any],
               let x = (dict["x"] as? NSNumber)?.doubleValue,
               let y = (dict["y"] as? NSNumber)?.doubleValue,
               let size = (dict["size"] as? NSNumber)?.doubleValue {
                let z = webView.pageZoom
                let playing = dict["playing"] as? Bool ?? false
                let next = HoverPlay(x: x * z, y: y * z, size: size * z, isPlaying: playing)
                if hoverPlay != next { hoverPlay = next }
            } else if let s = hp as? String, s == "leave" {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, !self.isHoveringPlayButton else { return }
                    self.hoverPlay = nil
                    self.run("CP.clearHoverTile()")
                }
                hoverLeaveWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
            } else if hoverPlay != nil {
                hoverPlay = nil
            }
            return
        }
        #if DEBUG
        if let text = d["debugAuthLog"] as? String {
            debugAuthLog("page: \(text)")
            return
        }
        #endif
        if d["authFrameReady"] as? Bool == true {
            if auth == .signedOut && !signInReady { signInReady = true }
            return
        }
        if let readyPath = d["trackPageReady"] as? String {
            handleTrackPageReady(readyPath)
            return
        }
        if let menu = d["menu"] as? [String: Any] {
            presentMenu(menu, frame: message.frameInfo)
            return
        }
        if let share = d["share"] as? [String: Any] {
            presentShare(share)
            return
        }
        if let text = d["toast"] as? String, !text.isEmpty {
            let art = (d["toastArt"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
            showToast(text, artworkURL: art)
            return
        }
        for (key, file) in [("debugToast", "debug-toast.html"), ("debugAuth", "debug-auth.html")] {
            if let html = d[key] as? String {
                #if DEBUG
                try? html.write(to: Self.debugDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
                #endif
                return
            }
        }
        var s = TrackState()
        s.hasTrack = d["hasTrack"] as? Bool ?? false
        s.title = d["title"] as? String ?? ""
        s.artist = d["artist"] as? String ?? ""
        s.trackPath = d["trackPath"] as? String ?? ""
        s.artistPath = d["artistPath"] as? String ?? ""
        s.artworkURL = (d["artwork"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        s.isPlaying = d["playing"] as? Bool ?? false
        s.position = (d["position"] as? NSNumber)?.doubleValue ?? 0
        s.duration = (d["duration"] as? NSNumber)?.doubleValue ?? 0
        s.isLiked = d["liked"] as? Bool ?? false
        s.shuffle = d["shuffle"] as? Bool ?? false
        s.repeatMode = RepeatMode(rawValue: d["repeat"] as? String ?? "") ?? .none
        s.queueVisible = d["queueVisible"] as? Bool ?? false
        s.albumPath = d["albumPath"] as? String ?? ""
        let prevTrack = lastTrackPath
        if !s.trackPath.isEmpty { lastTrackPath = s.trackPath }
        if s != state { state = s }
        if let p = d["profilePath"] as? String, !p.isEmpty, !p.hasSuffix("/undefined"), p != profilePath { profilePath = p }
        notePageUser(profilePath: d["profilePath"] as? String ?? "", noUser: d["noUser"] as? Bool ?? false)

        // If the user is currently viewing the Now Playing track page and playback moves to
        // another track, follow it with a directional next/prev swipe animation.
        let oldNorm = Self.normPath(prevTrack)
        let newNorm = Self.normPath(s.trackPath)
        let onNowPlaying = Self.normPath(currentPath) == oldNorm
            || (!swipeTargetPath.isEmpty && swipeTargetPath == oldNorm)
            || (pageSwipe != nil && swipeTargetPath.isEmpty)
        if !oldNorm.isEmpty, !newNorm.isEmpty, oldNorm != newNorm, onNowPlaying {
            let dir: SwipeDirection
            if let pending = pendingSwipeDirection, Date().timeIntervalSince(pending.at) < 4 {
                dir = pending.dir
                pendingSwipeDirection = nil
            } else {
                dir = .next
            }
            followNowPlaying(to: s.trackPath, direction: dir)
        }
    }

    private static func normPath(_ path: String) -> String {
        var p = path.split(separator: "?").first.map(String.init) ?? path
        if p.hasPrefix("/n/") { p.removeFirst(2) }
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// Starts the outgoing swipe immediately on Next/Prev (before SoundCloud even switches tracks),
    /// giving instant visual feedback while buying time for the new track page to load.
    private func startImmediateSwipe(direction: SwipeDirection) {
        swipeGeneration += 1
        let gen = swipeGeneration
        swipeTargetPath = ""
        swipeFallbackWork?.cancel()
        hoverPlay = nil

        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            MainActor.assumeIsolated {
                guard let self, self.swipeGeneration == gen, let image else { return }
                self.pageSwipe = PageSwipeTransition(id: gen, direction: direction, snapshot: image,
                                                     outgoingExited: false, incomingReady: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                    guard let self, self.swipeGeneration == gen, var cur = self.pageSwipe, cur.id == gen else { return }
                    withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.56)) {
                        cur.outgoingExited = true
                        self.pageSwipe = cur
                    }
                }
                // Safety net: if the track didn't actually change (e.g. end of queue), reveal again.
                let fallback = DispatchWorkItem { [weak self] in
                    self?.revealIncoming(generation: gen)
                }
                self.swipeFallbackWork = fallback
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: fallback)
            }
        }
    }

    private func followNowPlaying(to path: String, direction: SwipeDirection) {
        let target = Self.normPath(path)
        // If an immediate swipe is already in flight from next()/previous(), reuse it and navigate now.
        if let existing = pageSwipe, swipeTargetPath.isEmpty, existing.id == swipeGeneration {
            let gen = existing.id
            swipeTargetPath = target
            swipeFallbackWork?.cancel()
            open(path, replace: true)
            let fallback = DispatchWorkItem { [weak self] in
                self?.revealIncoming(generation: gen)
            }
            swipeFallbackWork = fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: fallback)
            return
        }

        // Auto-advance (track ended) or track switch without a pre-started swipe.
        swipeGeneration += 1
        let gen = swipeGeneration
        swipeTargetPath = target
        swipeFallbackWork?.cancel()
        hoverPlay = nil

        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            MainActor.assumeIsolated {
                guard let self, self.swipeGeneration == gen else { return }
                if let image {
                    self.pageSwipe = PageSwipeTransition(id: gen, direction: direction, snapshot: image,
                                                         outgoingExited: false, incomingReady: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                        guard let self, self.swipeGeneration == gen, var cur = self.pageSwipe, cur.id == gen else { return }
                        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.56)) {
                            cur.outgoingExited = true
                            self.pageSwipe = cur
                        }
                    }
                }
                self.open(path, replace: true)
                let fallback = DispatchWorkItem { [weak self] in
                    self?.revealIncoming(generation: gen)
                }
                self.swipeFallbackWork = fallback
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: fallback)
            }
        }
    }

    private func handleTrackPageReady(_ path: String) {
        guard !swipeTargetPath.isEmpty, Self.normPath(path) == swipeTargetPath else { return }
        revealIncoming(generation: swipeGeneration)
    }

    private func revealIncoming(generation gen: Int) {
        guard swipeGeneration == gen, var cur = pageSwipe, cur.id == gen, !cur.incomingReady else { return }
        swipeFallbackWork?.cancel()
        swipeFallbackWork = nil
        swipeTargetPath = ""

        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.42)) {
            cur.incomingReady = true
            cur.outgoingExited = true
            pageSwipe = cur
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { [weak self] in
            guard let self, self.swipeGeneration == gen else { return }
            self.pageSwipe = nil
        }
    }
}

// MARK: - Session cookies

extension WebPlayer: WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in self.scheduleAuthCheck() }
    }
}

// MARK: - Navigation & popups

extension WebPlayer: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === self.webView else {
            #if DEBUG
            debugAuthLog("popup commit \(webView.url.map { "\($0.host ?? "")\($0.path)" } ?? "")")
            #endif
            return
        }
        awaitingFreshPage = false
        if noUserSince != nil { noUserReloads += 1 }
        #if DEBUG
        debugAuthLog("commit \(webView.url?.absoluteString ?? "")")
        #endif
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        reloadCustomCSS()
        run("CP.setVolume(\(volume))")
        if auth == .signedOut { run("CP.setSignIn(true)") }
        #if DEBUG
        scheduleDebugCapture()
        #endif
    }

    /// target=_blank / window.open: SoundCloud links load in place, login providers get a
    /// real popup window (they need to talk back to the opener), everything else → browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        let host = url?.host?.lowercased() ?? ""

        if !host.isEmpty && !Self.isAuthHost(host) {
            // Signed out, the page is only the sign-in form: its links (Terms, Privacy, Need
            // help?) would replace it, so they go to the browser.
            if let url, auth == .signedIn, host == "soundcloud.com" || host.hasSuffix(".soundcloud.com") {
                open(url.path + (url.query.map { "?\($0)" } ?? ""))
            } else if let url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        // Google / Apple / Facebook sign-in: a real window (the provider talks back to its
        // opener), centred over the app window.
        let size = NSSize(width: max(windowFeatures.width?.doubleValue ?? 0, 480),
                          height: max(windowFeatures.height?.doubleValue ?? 0, 640))
        let popup = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        popup.uiDelegate = self
        #if DEBUG
        popup.navigationDelegate = self   // logs its pages (didCommit)
        debugAuthLog("popup opened for \(url?.absoluteString ?? "nil")")
        #endif
        let win = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable],
                           backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.title = Self.providerTitle(host)
        win.contentView = popup
        if let parent = self.webView.window, parent.isVisible {
            let p = parent.frame
            win.setFrameOrigin(NSPoint(x: p.midX - win.frame.width / 2, y: p.midY - win.frame.height / 2))
        } else {
            win.center()
        }
        win.makeKeyAndOrderFront(nil)
        popups.append(win)
        // Closed with its close button (not by the page): forget it too.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main) { [weak self, weak win] _ in
            MainActor.assumeIsolated {
                guard let self, let win, let i = self.popups.firstIndex(of: win) else { return }
                self.popups.remove(at: i)
                self.popupsChanged()
            }
        }
        popupsChanged()
        return popup
    }

    /// A provider sign-in is in flight while its popup is open, and for a moment after it
    /// closes (SoundCloud is still exchanging the result for a session): the page must not
    /// restart its sign-in meanwhile (CP.setSignIn).
    private func popupsChanged() {
        signInBusyWork?.cancel()
        if !popups.isEmpty {
            run("CP.signInBusy = true")
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.run("CP.signInBusy = false") }
        signInBusyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private static func providerTitle(_ host: String) -> String {
        if host.contains("google") { return "Sign in with Google" }
        if host.contains("apple") { return "Sign in with Apple" }
        if host.contains("facebook") { return "Sign in with Facebook" }
        return "Sign in to SoundCloud"
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let i = popups.firstIndex(where: { $0.contentView === webView }) else { return }
        popups[i].close()   // willClose observer removes it
    }

    private static func isAuthHost(_ host: String) -> Bool {
        let auth = ["accounts.google.com", "appleid.apple.com", "facebook.com",
                    "secure.soundcloud.com", "api-auth.soundcloud.com"]
        return auth.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

// MARK: - Debug tooling (debug builds only)

#if DEBUG
extension WebPlayer {
    /// Sign-in state changes and page loads, appended to debug-auth-log.txt.
    func debugAuthLog(_ text: String) {
        let line = "\(Date()) \(text)\n"
        let logURL = Self.debugDir.appendingPathComponent("debug-auth-log.txt")
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
    }

    /// -cpDebugDir <path>: write captures there instead (keeps parallel test instances apart).
    static let debugDir = UserDefaults.standard.string(forKey: "cpDebugDir").map { URL(fileURLWithPath: $0) }
        ?? customCSSURL.deletingLastPathComponent()

    /// After a page load, saves debug-dom.json (DOM, player state, requests, checks) and
    /// debug-window.png (the whole window, native UI + web content).
    /// Launch arguments: -cpStartPath /you/likes   -cpDebugEval "<js run 4s after first load>"
    ///                   -cpDebugScroll YES (scroll to the bottom first, for lazy-loaded content)
    fileprivate func scheduleDebugCapture() {
        let first = debugFirstLoad
        debugFirstLoad = false
        let defaults = UserDefaults.standard
        if first, let specPath = defaults.string(forKey: "cpTourSpec"),
           let outDir = defaults.string(forKey: "cpTourOut") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.startDebugTour(specPath: specPath, outDir: outDir)
            }
            return
        }
        if first, let js = defaults.string(forKey: "cpDebugEval") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.webView.evaluateJavaScript("window.__cpMarker = 1; window.__cpEval = (() => { try { return String(eval(\(Injected.js(js)))); } catch (e) { return 'ERR ' + e; } })()", completionHandler: nil)
            }
        }
        if first, defaults.bool(forKey: "cpDebugScroll") {
            for t in [4.0, 5.5, 7.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                    self?.webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight)", completionHandler: nil)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (first ? 9.5 : 8)) { [weak self] in
            self?.dumpDOM()
            self?.snapshotWindow()
            if first, defaults.bool(forKey: "cpDebugScroll") {
                self?.webView.evaluateJavaScript("window.scrollTo(0, 0)", completionHandler: nil)
            }
            // -cpQuitAfterCapture YES: a throwaway test instance exits by itself once captured.
            if first, defaults.bool(forKey: "cpQuitAfterCapture") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
            }
        }
    }

    /// In-app (single-page) navigation doesn't fire didFinish, so also capture a few seconds
    /// after the URL changes; a newer navigation supersedes a pending capture.
    fileprivate func scheduleNavigationDump() {
        if UserDefaults.standard.string(forKey: "cpTourSpec") != nil { return }
        debugNavGeneration += 1
        let generation = debugNavGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, generation == self.debugNavGeneration else { return }
            self.dumpDOM()
            self.snapshotWindow()
        }
    }

    func dumpDOM() {
        let probe = UserDefaults.standard.string(forKey: "cpDebugEval").map {
            "(() => { try { return String(eval(\(Injected.js($0)))); } catch (e) { return 'ERR ' + e; } })()"
        } ?? "null"
        let js = """
        JSON.stringify({url: location.href, state: window.CP ? CP.state() : null,
          marker: window.__cpMarker || null, evalResult: window.__cpEval || null, probe: \(probe),
          errors: (window.CP && CP.debugErrors) || [],
          bodyClass: document.body.className,
          visible: [...document.querySelectorAll('.l-sidebar-right .sidebarModule, .l-footer, [id^="div-gpt-ad"], .header')]
            .map(e => [e.className.slice(0, 80), getComputedStyle(e).display]),
          sections: [...document.querySelectorAll('li.mixedModularHome__item')]
            .map(li => [((li.querySelector('h2') || {}).textContent || '').trim(), getComputedStyle(li).display]),
          resources: performance.getEntriesByType('resource')
            .map(e => [e.name, e.initiatorType, e.transferSize, e.encodedBodySize]),
          iframes: [...document.querySelectorAll('iframe')]
            .map(f => [f.src, f.className, getComputedStyle(f).display]),
          html: document.documentElement.outerHTML})
        """
        webView.evaluateJavaScript(js) { result, _ in
            guard let s = result as? String else { return }
            try? FileManager.default.createDirectory(at: Self.debugDir, withIntermediateDirectories: true)
            try? s.write(to: Self.debugDir.appendingPathComponent("debug-dom.json"), atomically: true, encoding: .utf8)
        }
    }

    /// Writes the window's accessibility tree (roles + labels), which shows native UI that the
    /// bitmap capture can't render (e.g. the translucent sidebar).
    func dumpAccessibility() {
        guard let window = webView.window, let root = window.contentView?.superview else { return }
        var lines: [String] = [
            "window frame=\(window.frame) contentLayoutRect=\(window.contentLayoutRect) styleMask=\(window.styleMask.rawValue) fullScreen=\(window.styleMask.contains(.fullScreen))",
            "toolbar=\(window.toolbar.map { "visible=\($0.isVisible) items=\($0.items.map { $0.itemIdentifier.rawValue })" } ?? "nil") toolbarStyle=\(window.toolbarStyle.rawValue) titleVisibility=\(window.titleVisibility.rawValue)",
            "closeButton hidden=\(window.standardWindowButton(.closeButton)?.isHidden as Any) superviewHidden=\(window.standardWindowButton(.closeButton)?.superview?.isHidden as Any)",
        ]
        func walk(_ el: Any, _ depth: Int) {
            guard depth < 40, let e = el as? NSAccessibilityElementProtocol & NSObject else { return }
            let role = (e.value(forKey: "accessibilityRole") as? NSAccessibility.Role)?.rawValue ?? "?"
            let label = (e.value(forKey: "accessibilityLabel") as? String) ?? ""
            let title = (e.value(forKey: "accessibilityTitle") as? String) ?? ""
            let value = (e.value(forKey: "accessibilityValue")).map { "\($0)" } ?? ""
            let text = [label, title, value].filter { !$0.isEmpty }.joined(separator: " | ")
            if role != "AXWebArea" {
                if !text.isEmpty || role.contains("Row") || role.contains("Toolbar") { lines.append(String(repeating: "  ", count: depth) + "\(role): \(text)") }
                for child in (e.value(forKey: "accessibilityChildren") as? [Any]) ?? [] { walk(child, depth + 1) }
            }
        }
        walk(root, 0)
        try? lines.joined(separator: "\n").write(to: Self.debugDir.appendingPathComponent("debug-ax.txt"), atomically: true, encoding: .utf8)
    }

    /// Renders the window (toolbar, sidebar, player bar) and composites the web content into it.
    func snapshotWindow() {
        dumpAccessibility()
        guard let window = webView.window, window.isVisible,
              let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        let webRect = webView.convert(webView.bounds, to: frameView)
        let size = frameView.bounds.size
        // Signed out, the page sits on an opaque background (SignInView) with nothing above it.
        let webOnTop = auth != .signedIn
        let webAlpha = webOnTop && !signInReady ? 0.0 : 1.0
        webView.takeSnapshot(with: nil) { image, _ in
            let out = NSImage(size: size)
            out.lockFocus()
            // Web content first, then the window on top, so overlays above the page (the
            // floating player) stay visible. The web view itself caches as transparent.
            if !webOnTop { image?.draw(in: webRect) }
            rep.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if webOnTop { image?.draw(in: webRect, from: .zero, operation: .sourceOver, fraction: webAlpha) }
            out.unlockFocus()
            guard let tiff = out.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: Self.debugDir.appendingPathComponent("debug-window.png"))
        }
    }

    fileprivate func startDebugTour(specPath: String, outDir: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: specPath)),
              let steps = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            NSApp.terminate(nil)
            return
        }
        let outURL = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
        var vars: [String: String] = [:]
        runTourStep(index: 0, steps: steps, outURL: outURL, vars: &vars)
    }

    private func runTourStep(index: Int, steps: [[String: Any]], outURL: URL, vars: inout [String: String]) {
        guard index < steps.count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            return
        }
        if !profilePath.isEmpty { vars["$PROFILE"] = profilePath }
        let step = steps[index]
        let name = (step["name"] as? String) ?? String(format: "step-%02d", index)
        var path = (step["path"] as? String) ?? ""
        for (k, v) in vars where !v.isEmpty {
            path = path.replacingOccurrences(of: k, with: v)
        }
        let wait = (step["wait"] as? NSNumber)?.doubleValue ?? 4.5
        let evalJS = step["eval"] as? String
        let evalDelay = (step["evalDelay"] as? NSNumber)?.doubleValue ?? 2.2
        let snapshotVars = vars

        if path.contains("$") {
            // Unresolved placeholder; skip cleanly and record note.
            try? "{\"skipped\": \(Injected.js(path))}".write(
                to: outURL.appendingPathComponent("\(name).json"), atomically: true, encoding: .utf8)
            var nextVars = snapshotVars
            runTourStep(index: index + 1, steps: steps, outURL: outURL, vars: &nextVars)
            return
        }

        if !path.isEmpty {
            if step["hardLoad"] as? Bool == true, let u = URL(string: "https://soundcloud.com" + path) {
                webView.load(URLRequest(url: u))
            } else {
                open(path)
            }
        }

        if let evalJS {
            DispatchQueue.main.asyncAfter(deadline: .now() + evalDelay) { [weak self] in
                self?.webView.evaluateJavaScript(evalJS) { res, _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if let dict = res as? [String: String] {
                            self.tourExtraVars.merge(dict) { _, new in new }
                        } else if let s = res as? String, let d = s.data(using: .utf8),
                                  let dict = (try? JSONSerialization.jsonObject(with: d)) as? [String: String] {
                            self.tourExtraVars.merge(dict) { _, new in new }
                        }
                    }
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.captureTourArtifact(name: name, outURL: outURL) { [weak self] in
                guard let self else { return }
                var nextVars = snapshotVars
                nextVars.merge(self.tourExtraVars) { _, new in new }
                if !self.profilePath.isEmpty { nextVars["$PROFILE"] = self.profilePath }
                self.runTourStep(index: index + 1, steps: steps, outURL: outURL, vars: &nextVars)
            }
        }
    }

    private var tourExtraVars: [String: String] {
        get { (objc_getAssociatedObject(self, &Self.tourVarsKey) as? [String: String]) ?? [:] }
        set { objc_setAssociatedObject(self, &Self.tourVarsKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    private static var tourVarsKey: UInt8 = 0

    private func captureTourArtifact(name: String, outURL: URL, completion: @escaping @MainActor () -> Void) {
        let inspectJS = #"""
        (() => {
          const vis = (el) => {
            if (!el) return false;
            const cs = getComputedStyle(el);
            if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) === 0) return false;
            const r = el.getBoundingClientRect();
            return r.width > 1 && r.height > 1;
          };
          const rect = (el) => { const r = el.getBoundingClientRect(); return [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)]; };
          const summarizeDoc = (doc, label) => {
            if (!doc) return null;
            const headings = [...doc.querySelectorAll('h1, h2, h3, .sidebarHeader__title, .searchTitle__text, .collectionSection__subHeading')]
              .filter(vis).slice(0, 40).map(e => ({ tag: e.tagName, cls: String(e.className || '').slice(0, 80), text: (e.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 100), r: rect(e) }));
            const tabs = [...doc.querySelectorAll('.g-tabs, .g-tabs-link, [role="tablist"], [role="tab"], .profileTabs, .userInfoBar, .networkTabs, .settingsTabs, .tabs')]
              .filter(vis).slice(0, 40).map(e => ({ tag: e.tagName, cls: String(e.className || '').slice(0, 80), text: (e.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 100), href: e.getAttribute && e.getAttribute('href'), r: rect(e) }));
            const sidebars = [...doc.querySelectorAll('.l-sidebar-right, .l-sidebar-right > *, .l-sidebar-right .sidebarModule, .l-listen-wrapper .l-about-right, aside, [class*="sidebar" i], [class*="RightRail" i]')]
              .filter(vis).slice(0, 40).map(e => ({ tag: e.tagName, cls: String(e.className || '').slice(0, 100), text: (e.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 160), r: rect(e) }));
            const links = [...new Set([...doc.querySelectorAll('a[href]')].filter(vis).map(a => a.getAttribute('href')).filter(Boolean))].slice(0, 120);
            const buttons = [...doc.querySelectorAll('button, .sc-button, [role="button"]')].filter(vis).slice(0, 60)
              .map(b => ({ cls: String(b.className || '').slice(0, 80), label: (b.getAttribute('aria-label') || b.getAttribute('title') || b.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 80), r: rect(b) }));
            return { label, url: doc.location ? doc.location.href : '', bodyClass: doc.body ? doc.body.className : '', scrollHeight: doc.documentElement ? doc.documentElement.scrollHeight : 0, headings, tabs, sidebars, buttons, links };
          };
          const frames = [];
          for (const f of document.querySelectorAll('iframe')) {
            if (!vis(f)) continue;
            try { frames.push(summarizeDoc(f.contentDocument, f.src || 'iframe')); } catch (e) { frames.push({ label: f.src, crossOrigin: true, r: rect(f) }); }
          }
          return JSON.stringify({
            url: location.href,
            state: window.CP ? CP.state() : null,
            main: summarizeDoc(document, 'main'),
            frames
          }, null, 2);
        })()
        """#
        webView.evaluateJavaScript(inspectJS) { [weak self] res, _ in
            MainActor.assumeIsolated {
                guard let self else { completion(); return }
                if let s = res as? String {
                    try? s.write(to: outURL.appendingPathComponent("\(name).json"), atomically: true, encoding: .utf8)
                }
                guard let window = self.webView.window, window.isVisible,
                      let frameView = window.contentView?.superview,
                      let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
                    completion()
                    return
                }
                frameView.cacheDisplay(in: frameView.bounds, to: rep)
                let webRect = self.webView.convert(self.webView.bounds, to: frameView)
                let size = frameView.bounds.size
                self.webView.takeSnapshot(with: nil) { image, _ in
                    MainActor.assumeIsolated {
                        let out = NSImage(size: size)
                        out.lockFocus()
                        image?.draw(in: webRect)
                        rep.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                        out.unlockFocus()
                        if let tiff = out.tiffRepresentation,
                           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                            try? png.write(to: outURL.appendingPathComponent("\(name).png"))
                        }
                        completion()
                    }
                }
            }
        }
    }
}
#endif

/// Avoids a retain cycle between WKUserContentController and WebPlayer.
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

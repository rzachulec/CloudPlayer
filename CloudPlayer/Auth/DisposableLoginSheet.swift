import AppKit
import Observation
import SwiftUI
import WebKit

/// The ONLY file in the native rewrite that touches WebKit.
///
/// Instantiated solely when the user is signed out so SoundCloud's DataDome-protected login
/// and OAuth providers (Google, Apple, Facebook) work reliably. The moment `oauth_token` is
/// captured from the cookie store, `teardown()` destroys the `WKWebView`, closes any popups,
/// and releases all WebKit references so WebKit's XPC processes exit completely.
@MainActor
@Observable
final class DisposableLoginController: NSObject {
    private(set) var isReady = false
    private(set) var isCapturing = false
    private(set) var webView: WKWebView?

    private var popups: [NSWindow] = []
    private var signInBusyWork: DispatchWorkItem?
    private var cookieCheckWork: DispatchWorkItem?
    private var capturedClientID = ""
    private var completed = false
    private var onAuthenticated: ((SoundCloudSession) -> Void)?

    func start(onAuthenticated: @escaping (SoundCloudSession) -> Void) {
        teardown()
        self.onAuthenticated = onAuthenticated
        self.completed = false
        self.isReady = false
        self.isCapturing = false
        self.capturedClientID = ""

        let config = WKWebViewConfiguration()
        // Non-persistent data store: leaves zero WebKit cookies/caches on disk once torn down.
        config.websiteDataStore = .nonPersistent()
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"

        let ucc = config.userContentController
        ucc.add(WeakLoginMessageHandler(self), name: "cpLogin")
        ucc.addUserScript(WKUserScript(
            source: Self.mainFrameScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        ucc.addUserScript(WKUserScript(
            source: Self.authFrameScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.underPageBackgroundColor = .textBackgroundColor
        #if DEBUG
        wv.isInspectable = true
        #endif

        config.websiteDataStore.httpCookieStore.add(self)
        self.webView = wv
        wv.load(URLRequest(url: URL(string: "https://soundcloud.com/")!))
    }

    func reload() {
        isReady = false
        webView?.load(URLRequest(url: URL(string: "https://soundcloud.com/")!))
    }

    /// Completely tears down WebKit and releases every reference so WebContent/Networking processes terminate.
    func teardown() {
        cookieCheckWork?.cancel()
        cookieCheckWork = nil
        signInBusyWork?.cancel()
        signInBusyWork = nil

        for win in popups {
            win.close()
        }
        popups.removeAll()

        if let wv = webView {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.uiDelegate = nil
            wv.configuration.websiteDataStore.httpCookieStore.remove(self)
            wv.configuration.userContentController.removeScriptMessageHandler(forName: "cpLogin")
            wv.configuration.userContentController.removeAllUserScripts()
            wv.load(URLRequest(url: URL(string: "about:blank")!))
            wv.removeFromSuperview()
        }
        webView = nil
        isReady = false
        isCapturing = false
    }

    private func scheduleCookieCheck() {
        guard !completed else { return }
        cookieCheckWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.checkSessionCookies() }
        }
        cookieCheckWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func checkSessionCookies() async {
        guard !completed, let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        let cookies = await store.allCookies()
        let now = Date()
        let scCookies = cookies.filter {
            ($0.domain == "soundcloud.com" || $0.domain.hasSuffix(".soundcloud.com"))
                && !$0.value.isEmpty
                && ($0.expiresDate.map { $0 > now } ?? true)
        }
        guard let oauth = scCookies.first(where: { $0.name == "oauth_token" })?.value else {
            return
        }
        let refresh = scCookies.first(where: { $0.name == "oauth_refresh_token" })?.value
        completed = true
        isCapturing = true

        let session = SoundCloudSession(
            oauthToken: oauth,
            refreshToken: refresh,
            clientID: capturedClientID
        )
        let callback = onAuthenticated
        onAuthenticated = nil
        teardown()
        callback?(session)
    }

    private func popupsChanged() {
        signInBusyWork?.cancel()
        if !popups.isEmpty {
            webView?.evaluateJavaScript("window.CPAuthSignInBusy = true;", completionHandler: nil)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.webView?.evaluateJavaScript("window.CPAuthSignInBusy = false;", completionHandler: nil)
        }
        signInBusyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }
}

// MARK: - WKScriptMessageHandler

extension DisposableLoginController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        if dict["authFrameReady"] as? Bool == true {
            isReady = true
            return
        }
        if let cid = dict["clientId"] as? String, !cid.isEmpty {
            capturedClientID = cid
            return
        }
    }
}

// MARK: - WKHTTPCookieStoreObserver

extension DisposableLoginController: WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in
            self.scheduleCookieCheck()
        }
    }
}

// MARK: - WKNavigationDelegate & WKUIDelegate

extension DisposableLoginController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        scheduleCookieCheck()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let url = navigationAction.request.url
        let host = url?.host?.lowercased() ?? ""

        if !host.isEmpty && !Self.isAuthHost(host) {
            if let url { NSWorkspace.shared.open(url) }
            return nil
        }

        let size = NSSize(
            width: max(windowFeatures.width?.doubleValue ?? 0, 480),
            height: max(windowFeatures.height?.doubleValue ?? 0, 640)
        )
        let popup = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        popup.uiDelegate = self

        let win = NSWindow(
            contentRect: popup.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.title = Self.providerTitle(host)
        win.contentView = popup
        if let parent = self.webView?.window, parent.isVisible {
            let p = parent.frame
            win.setFrameOrigin(NSPoint(x: p.midX - win.frame.width / 2, y: p.midY - win.frame.height / 2))
        } else {
            win.center()
        }
        win.makeKeyAndOrderFront(nil)
        popups.append(win)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self, weak win] _ in
            MainActor.assumeIsolated {
                guard let self, let win, let idx = self.popups.firstIndex(of: win) else { return }
                self.popups.remove(at: idx)
                self.popupsChanged()
            }
        }
        popupsChanged()
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let idx = popups.firstIndex(where: { $0.contentView === webView }) else { return }
        popups[idx].close()
    }

    private static func isAuthHost(_ host: String) -> Bool {
        let hosts = [
            "accounts.google.com",
            "appleid.apple.com",
            "facebook.com",
            "secure.soundcloud.com",
            "api-auth.soundcloud.com",
        ]
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func providerTitle(_ host: String) -> String {
        if host.contains("google") { return "Sign in with Google" }
        if host.contains("apple") { return "Sign in with Apple" }
        if host.contains("facebook") { return "Sign in with Facebook" }
        return "Sign in to SoundCloud"
    }
}

// MARK: - Self-Contained Login Scripts & Styling

private extension DisposableLoginController {
    static func jsString(_ s: String) -> String {
        String(decoding: (try? JSONEncoder().encode(s)) ?? Data("\"\"".utf8), as: UTF8.self)
    }

    static func colorTokens(for appearance: NSAppearance) -> String {
        var tokens = ""
        appearance.performAsCurrentDrawingAppearance {
            let bg = NSColor.textBackgroundColor
            let colors: [(String, NSColor)] = [
                ("bg", bg),
                ("label", .labelColor),
                ("secondary", .secondaryLabelColor),
                ("accent", .controlAccentColor),
            ]
            for (name, color) in colors {
                let c = color.usingColorSpace(.sRGB) ?? .gray
                let b = bg.usingColorSpace(.sRGB) ?? .white
                let a = c.alphaComponent
                let r = Int(((c.redComponent * a + b.redComponent * (1 - a)) * 255).rounded())
                let g = Int(((c.greenComponent * a + b.greenComponent * (1 - a)) * 255).rounded())
                let bl = Int(((c.blueComponent * a + b.blueComponent * (1 - a)) * 255).rounded())
                tokens += "--cp-\(name):rgb(\(r),\(g),\(bl));--cp-\(name)-rgb:\(r),\(g),\(bl);"
            }
        }
        return tokens
    }

    static func authCSS() -> String {
        let light = colorTokens(for: NSAppearance(named: .aqua)!)
        let dark = colorTokens(for: NSAppearance(named: .darkAqua)!)
        return """
        :root, html body, html body.dark { \(light) color-scheme: light; }
        @media (prefers-color-scheme: dark) { :root, html body, html body.dark { \(dark) color-scheme: dark; } }
        :root, html body, html body.dark, .web-library-surface {
          --primary-rgb: var(--cp-label-rgb);
          --primary-color: var(--cp-label);
          --secondary-color: var(--cp-secondary);
          --font-primary-color: var(--cp-label);
          --font-secondary-color: var(--cp-secondary);
          --font-special-color: var(--cp-accent);
          --link-standard-color: var(--cp-accent);
          --background-dark-color: var(--cp-bg);
          --background-light-color: var(--cp-bg);
          --background-surface-color: var(--cp-bg);
          --button-primary-background-color: var(--cp-accent);
          --button-primary-font-color: #fff;
          --input-default-background-color: rgba(var(--cp-label-rgb), .05);
          --input-default-border-color: rgba(var(--cp-label-rgb), .14);
          --input-focused-border-color: var(--cp-accent);
          --font-sans-serif-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
          --wl-font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
        }
        html, body, #app, main, .web-library-surface { background: var(--cp-bg) !important; }
        body.auth-ui-in-iframe #app { border: 0 !important; border-radius: 0 !important; padding: 0 !important; }
        html body, html body * { font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif !important; }
        html body { -webkit-font-smoothing: antialiased; color: var(--cp-label); }
        main.vertically-centered { padding: 8px 4px 24px !important; min-height: 0 !important; justify-content: flex-start !important; }
        .sign-in-up-form, .web-library-surface > div { max-width: 360px; margin: 0 auto; }
        .entry-screen-title, .web-library-surface .entry-screen-title, .wl-title {
          font-size: 17px !important; font-weight: 600 !important; line-height: 22px !important;
          text-align: center !important; padding: 0 !important; margin: 0 0 20px !important; color: var(--cp-label) !important;
        }
        .web-library-surface .wl-button {
          border-radius: 9px !important; min-height: 38px !important; padding: 0 14px !important;
          font-size: 13px !important; font-weight: 500 !important;
        }
        .web-library-surface .wl-button--secondary {
          background: rgba(var(--cp-label-rgb), .05) !important;
          border: 1px solid rgba(var(--cp-label-rgb), .12) !important; color: var(--cp-label) !important;
        }
        .web-library-surface .wl-button--primary { background: var(--cp-accent) !important; border-color: transparent !important; color: #fff !important; }
        .web-library-surface .provider-buttons-ui-evo > div + div { margin-top: 8px !important; }
        .or-divider { margin: 18px 0 !important; font-size: 11px !important; color: var(--cp-secondary) !important; gap: 10px; }
        label:has(> .ui-evo-input), label:has(select) {
          height: 44px !important; border-radius: 9px !important;
          background: rgba(var(--cp-label-rgb), .05) !important;
          border: 1px solid rgba(var(--cp-label-rgb), .14) !important;
        }
        .ui-evo-input, select { color: var(--cp-label) !important; font-size: 13px !important; caret-color: var(--cp-accent) !important; }
        .disclaimer-message, .wl-helper-text, .wl-body-text { font-size: 11px !important; color: var(--cp-secondary) !important; text-align: center; }
        a, .wl-helper-link, .need-help-link { color: var(--cp-accent) !important; font-size: 12px !important; font-weight: 500 !important; }
        """
    }

    static func mainFrameScript() -> String {
        let light = colorTokens(for: NSAppearance(named: .aqua)!)
        let dark = colorTokens(for: NSAppearance(named: .darkAqua)!)
        let pageCSS = """
        :root { \(light) }
        @media (prefers-color-scheme: dark) { :root { \(dark) } }
        html, body { background: var(--cp-bg) !important; overflow: hidden !important; }
        body > :not(.webAuthContainerWrapper) { display: none !important; }
        .webAuthContainerWrapper {
          display: block !important; visibility: visible !important; opacity: 1 !important;
          position: fixed !important; inset: 0 !important; width: 100% !important; height: 100% !important;
          margin: 0 !important; padding: 0 !important; transform: none !important;
          background: var(--cp-bg) !important; z-index: 2147483647 !important;
        }
        .webAuthContainerWrapper > :not(iframe) { display: none !important; }
        .webAuthContainerWrapper > iframe {
          display: block !important; position: absolute !important; inset: 0 !important;
          width: 100% !important; height: 100% !important; max-width: none !important; max-height: none !important;
          margin: 0 !important; border: 0 !important; border-radius: 0 !important; box-shadow: none !important;
          transform: none !important; background: var(--cp-bg) !important;
        }
        """
        return """
        (() => {
          if (window.__cpDisposableMain) return;
          window.__cpDisposableMain = true;
          window.CPAuthSignInBusy = false;

          const post = (m) => { try { window.webkit.messageHandlers.cpLogin.postMessage(m); } catch (e) {} };
          let sentCid = '';
          const sniff = (u) => {
            if (typeof u !== 'string' || u.indexOf('api-v2.soundcloud.com') < 0) return;
            const m = u.match(/[?&]client_id=([^&]+)/);
            if (m && m[1] && m[1] !== sentCid) {
              sentCid = decodeURIComponent(m[1]);
              post({ clientId: sentCid });
            }
          };
          const origFetch = window.fetch;
          window.fetch = function (input) {
            sniff(typeof input === 'string' ? input : (input && input.url));
            return origFetch.apply(this, arguments);
          };
          const origOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function (method, url) {
            sniff(url);
            return origOpen.apply(this, arguments);
          };

          const st = document.createElement('style');
          st.textContent = \(jsString(pageCSS));
          const mount = () => (document.head || document.documentElement).appendChild(st);
          mount();
          document.addEventListener('DOMContentLoaded', mount);

          let opened = false, closedTicks = 0;
          const keepOpen = () => {
            const w = document.querySelector('.webAuthContainerWrapper');
            if ((w && !w.classList.contains('hidden')) || window.CPAuthSignInBusy) { closedTicks = 0; return; }
            if (opened && ++closedTicks < 6) return;
            const b = document.querySelector('button.loginButton');
            if (!b) return;
            opened = true; closedTicks = 0;
            b.click();
          };
          setInterval(keepOpen, 600);
          document.addEventListener('DOMContentLoaded', keepOpen);
        })();
        """
    }

    static func authFrameScript() -> String {
        """
        (() => {
          if (location.hostname !== 'secure.soundcloud.com' || window === window.top || window.__cpDisposableAuth) return;
          window.__cpDisposableAuth = true;
          const st = document.createElement('style');
          st.textContent = \(jsString(authCSS()));
          const mount = () => {
            const root = document.head || document.documentElement;
            if (root.lastElementChild !== st) root.appendChild(st);
          };
          mount();
          document.addEventListener('DOMContentLoaded', mount);

          let posted = false;
          const post = (m) => { try { window.webkit.messageHandlers.cpLogin.postMessage(m); } catch (e) {} };
          const check = () => {
            if (posted || !/[#&]is_visible=true\\b/.test(location.hash)) return;
            if (!document.querySelector('#app main button, #app main input')) return;
            posted = true;
            setTimeout(() => post({ authFrameReady: true }), 60);
          };
          window.addEventListener('hashchange', check);
          new MutationObserver(() => { mount(); check(); }).observe(document, { subtree: true, childList: true });
        })();
        """
    }
}

private final class WeakLoginMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: DisposableLoginController?
    init(_ target: DisposableLoginController) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - SwiftUI Sign-In View

struct DisposableSignInView: View {
    let onAuthenticated: (SoundCloudSession) -> Void
    @State private var controller = DisposableLoginController()

    static let minWidth: CGFloat = 520
    static let minHeight: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .padding(.bottom, 4)
                Text("Welcome to CloudPlayer")
                    .font(.system(size: 22, weight: .bold))
                Text("Sign in with your SoundCloud account. WebKit is destroyed immediately after login.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 22)

            ZStack {
                if let wv = controller.webView {
                    DisposableWebViewHost(webView: wv)
                        .opacity(controller.isReady && !controller.isCapturing ? 1 : 0)
                }
                if !controller.isReady || controller.isCapturing {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(controller.isCapturing ? "Securing session…" : "Loading SoundCloud sign-in…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 400)
            .frame(minHeight: 360, maxHeight: 540)
            .animation(.easeOut(duration: 0.25), value: controller.isReady)

            Spacer(minLength: 12)
            HStack(spacing: 12) {
                Text("Unofficial. Not affiliated with or endorsed by SoundCloud.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Button("Reload") { controller.reload() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
        .frame(minWidth: Self.minWidth, minHeight: Self.minHeight)
        .onAppear {
            controller.start(onAuthenticated: onAuthenticated)
        }
        .onDisappear {
            controller.teardown()
        }
    }
}

private struct DisposableWebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

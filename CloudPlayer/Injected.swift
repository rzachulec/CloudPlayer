import Foundation

/// Everything that gets injected into soundcloud.com.
enum Injected {
    /// Encodes a Swift value as a JS literal.
    static func js<T: Encodable>(_ value: T) -> String {
        String(decoding: (try? JSONEncoder().encode(value)) ?? Data("null".utf8), as: UTF8.self)
    }

    static func jsString(_ s: String) -> String { js(s) }

    /// Built-in debloat rules. SoundCloud's class names drift over time:
    /// right-click → Inspect Element to find new ones, and put your own rules in
    /// custom.css (View → Edit Custom CSS…) rather than editing this.
    /// (SoundCloud's header and player bar are replaced by native UI; see Theme.nativeCSS.)
    static let debloatCSS = """
    /* Upsells: "Upgrade now", Go+/Artist Pro promos, banners, OneTrust cookie SDK UI */
    [class*="upsell" i],
    .creatorSubscriptionsButton,
    .l-product-banners,
    .announcements,
    #onetrust-consent-sdk,
    #onetrust-banner-sdk,
    #onetrust-pc-sdk,
    .onetrust-pc-dark-filter,
    #ot-sdk-btn-floating,
    .ot-sdk-container
    { display: none !important; }

    /* Right sidebar. Kept only where needed; dropped on Home, Profiles, Tags, and Listen/Set pages
       so content uses the full window width without duplicating the native left sidebar. */
    .sidebarModule:has(> .sidebarModule__webiEmbeddedModule),
    .sidebarModule.artistShortcutsModule,
    .sidebarModule.whoToFollowModule,
    .sidebarModule.mobileApps,
    .sidebarModule.empty,
    .footerModule
    { display: none !important; }

    .l-fluid-fixed:has(.modular-home-mixed-selection, .l-user-main, .tagsMain, .l-listen-wrapper, .systemPlaylistTrackList, .systemPlaylistTrackList__item, .listenDetails) > .l-sidebar-right,
    #content:has(.l-listen-wrapper, .systemPlaylistTrackList, .systemPlaylistTrackList__item, .listenDetails, .l-hero-banner) .l-sidebar-right,
    .l-sidebar-right:has(.listenNetworkSidebar),
    .l-user-sidebar-right,
    .l-listen--main > .l-sidebar-right
    { display: none !important; }
    .l-fluid-fixed:has(.modular-home-mixed-selection, .l-user-main, .tagsMain, .l-listen-wrapper, .systemPlaylistTrackList, .systemPlaylistTrackList__item, .listenDetails) > .l-main,
    #content:has(.l-listen-wrapper, .systemPlaylistTrackList, .systemPlaylistTrackList__item, .listenDetails, .l-hero-banner) .l-main,
    .l-listen--main > .l-main {
      width: auto !important; max-width: none !important; float: none !important;
      margin-right: 0 !important; padding-right: 0 !important; border-right: 0 !important;
    }

    /* Footer: Legal/Privacy/Cookies/Imprint/… links and the language picker; ad slots */
    .l-footer,
    [id^="div-gpt-ad"]
    { display: none !important; }

    /* Artist / user hover preview tooltip */
    .dialog:has(.userDialogBadge),
    .userDialogBadge
    { display: none !important; pointer-events: none !important; }

    /* SoundCloud positions the sticky sidebar from its original height; reset it
       now that it is shorter, so it doesn't sit scrolled out of view. */
    .l-sidebar-right .streamSidebar { top: 0 !important; }

    /* Tile play buttons are rendered as a native macOS 26 Liquid Glass overlay in MainView. */
    .playableTile__playButton { opacity: 0 !important; pointer-events: none !important; }

    /* Search page: Play All / Play Tracks pill button */
    .l-search .searchOptions__container .cp-play-all {
      appearance: none !important; -webkit-appearance: none !important;
      display: inline-flex !important; align-items: center !important; justify-content: center !important;
      gap: 5px !important; height: 26px !important; padding: 0 12px 0 10px !important;
      margin: 0 0 0 auto !important; border: 0 !important; border-radius: 13px !important;
      background: var(--cp-accent) !important; color: #fff !important;
      font-family: -apple-system, BlinkMacSystemFont, system-ui !important;
      font-size: 13px !important; font-weight: 600 !important; line-height: 1 !important;
      white-space: nowrap !important; cursor: pointer !important; flex: none !important;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.16) !important;
      transition: filter 0.12s ease, transform 0.12s ease, opacity 0.12s ease !important;
    }
    .l-search .searchOptions__container .cp-play-all[hidden] { display: none !important; }
    .l-search .searchOptions__container .cp-play-all:hover { filter: brightness(1.08) !important; }
    .l-search .searchOptions__container .cp-play-all:active { filter: brightness(0.94) !important; transform: scale(0.97) !important; }
    .l-search .searchOptions__container .cp-play-all:focus-visible { outline: 2px solid var(--cp-accent) !important; outline-offset: 2px !important; }
    .l-search .searchOptions__container .cp-play-all:disabled { opacity: 0.6 !important; cursor: default !important; pointer-events: none !important; }
    .l-search .searchOptions__container .cp-play-all svg {
      width: 10px !important; height: 10px !important; flex: none !important; display: block !important; fill: currentColor !important;
    }
    .l-search .searchOptions__container .cp-view-toggle-wrap { margin-left: auto !important; flex: none !important; }
    .l-search .searchOptions__container .cp-view-toggle-wrap:not([hidden]) ~ .cp-play-all { margin-left: 0 !important; }

    /* Likes page: Play & Shuffle pill buttons in the library header */
    .collectionSection__top .cp-likes-actions {
      display: inline-flex !important; align-items: center !important; gap: 6px !important;
      margin: 0 !important; padding: 0 !important; flex: none !important;
    }
    .collectionSection__top .cp-likes-actions[hidden] { display: none !important; }
    .collectionSection__top .cp-likes-btn {
      appearance: none !important; -webkit-appearance: none !important;
      display: inline-flex !important; align-items: center !important; justify-content: center !important;
      gap: 5px !important; height: 26px !important; padding: 0 12px 0 10px !important;
      margin: 0 !important; border-radius: 13px !important; box-sizing: border-box !important;
      font-family: -apple-system, BlinkMacSystemFont, system-ui !important;
      font-size: 13px !important; line-height: 1 !important;
      white-space: nowrap !important; cursor: pointer !important; flex: none !important;
      transition: filter 0.12s ease, background-color 0.12s ease, transform 0.12s ease, opacity 0.12s ease !important;
    }
    .collectionSection__top .cp-likes-play {
      border: 0 !important; background: var(--cp-accent) !important; color: #fff !important;
      font-weight: 600 !important; box-shadow: 0 1px 3px rgba(0, 0, 0, 0.16) !important;
    }
    .collectionSection__top .cp-likes-play:hover { filter: brightness(1.08) !important; }
    .collectionSection__top .cp-likes-play:active { filter: brightness(0.94) !important; transform: scale(0.97) !important; }
    .collectionSection__top .cp-likes-shuffle {
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.12) !important;
      background: rgba(var(--cp-label-rgb), 0.08) !important; color: var(--cp-label) !important;
      font-weight: 500 !important; box-shadow: none !important;
    }
    .collectionSection__top .cp-likes-shuffle:hover { background: rgba(var(--cp-label-rgb), 0.14) !important; }
    .collectionSection__top .cp-likes-shuffle:active { background: rgba(var(--cp-label-rgb), 0.2) !important; transform: scale(0.97) !important; }
    .collectionSection__top .cp-likes-btn:focus-visible { outline: 2px solid var(--cp-accent) !important; outline-offset: 2px !important; }
    .collectionSection__top .cp-likes-btn:disabled { opacity: 0.6 !important; cursor: default !important; pointer-events: none !important; }
    .collectionSection__top .cp-likes-play svg {
      width: 10px !important; height: 10px !important; flex: none !important; display: block !important; fill: currentColor !important;
    }
    .collectionSection__top .cp-likes-shuffle svg {
      width: 13px !important; height: 13px !important; flex: none !important; display: block !important;
    }
    html.cp-hide-queue .playControls__queue, html.cp-hide-queue .playControls__queue * {
      visibility: hidden !important; transition: none !important;
    }
    html.cp-hide-queue body { transition: none !important; padding-right: 0 !important; }
    """

    /// Home page sections to hide, matched against the start of each section's heading
    /// (case-insensitive). Headings like "Mixed for <username>" are personalised, which is
    /// why this is matched by text in JS rather than in CSS.
    static let hiddenHomeSections = [
        "Mixed for",
        "Events near you",
        "Discover with Stations",
        "Grab the keys and crank the radio",
        "Trending by genre",
        "Artists to watch out for",
        "Made for you",
        "Curated by SoundCloud",
    ]

    /// macOS Now Playing comes from WebKit: it publishes one entry for the page's playing audio
    /// (from navigator.mediaSession, or else the page title and icon), and that can't be turned
    /// off, so CloudPlayer uses it as its only entry. This shim tidies what SoundCloud reports:
    /// title + artist without the empty album (shown as a stray "–"), 500px artwork, and
    /// Next/Previous wired to CloudPlayer's player, since SoundCloud doesn't register them.
    /// Runs in every frame before SoundCloud's scripts.
    static let mediaSessionShim = #"""
    (() => {
      const ms = navigator.mediaSession;
      if (!ms || window.__cpMediaShim) return;
      window.__cpMediaShim = true;
      const proto = Object.getPrototypeOf(ms);
      const metaDesc = Object.getOwnPropertyDescriptor(proto, 'metadata');
      const setHandler = proto.setActionHandler;
      if (!metaDesc || !metaDesc.set || !setHandler) return;

      let original = null;
      const tidy = (m) => {
        if (!m) return null;
        try {
          const art = [...(m.artwork || [])].pop();
          const src = art && art.src ? art.src.replace(/-(t\d+x\d+|large|small|badge|tiny|crop)\./, '-t500x500.') : '';
          return new MediaMetadata({
            title: m.title || '', artist: m.artist || '',
            artwork: src ? [{ src, sizes: '500x500', type: art.type || 'image/jpeg' }] : [],
          });
        } catch (e) { return m; }
      };
      try {
        Object.defineProperty(ms, 'metadata', {
          configurable: true,
          get: () => original,
          set: (v) => { original = v; metaDesc.set.call(ms, tidy(v)); },
        });
      } catch (e) {}

      const cp = (name) => () => { const CP = (window.top || window).CP; if (CP) CP.cmd(name); };
      const ours = { nexttrack: cp('next'), previoustrack: cp('prev') };
      ms.setActionHandler = (action, handler) => setHandler.call(ms, action, ours[action] || handler);
      for (const [action, handler] of Object.entries(ours)) {
        try { setHandler.call(ms, action, handler); } catch (e) {}
      }
    })();
    """#

    /// Runs in SoundCloud's same-origin "/n/…" iframes (track pages): styles the track header.
    static func frameScript(theme: Theme.Snapshot) -> String {
        """
        (() => {
        if (window === window.top || !location.pathname.startsWith('/n/') || window.CPFrame) return;
        // SoundCloud asks for its own theme setting; load the one macOS is using instead.
        const wantTheme = '\(theme.isDark ? "dark" : "light")';
        const m = location.search.match(/[?&]theme=(dark|light)\\b/);
        if (m && m[1] !== wantTheme) {
          location.replace(location.href.replace(/([?&]theme=)(dark|light)\\b/, '$1' + wantTheme));
          return;
        }
        const st = document.createElement('style'); st.id = 'cp-frame';
        st.textContent = \(js(Theme.frameCSS(theme)));
        const mount = () => (document.head || document.documentElement).appendChild(st);
        mount(); document.addEventListener('DOMContentLoaded', mount);
        window.CPFrame = { setCSS(css) { st.textContent = css; } };
        // In-app navigation reuses this frame: the host posts {kind: "navigate", href: "…&theme=…"}
        // with SoundCloud's own theme setting. Rewrite it before SoundCloud's listener sees it,
        // and note the outgoing heading so we only signal trackPageReady once the new track paints.
        let navPending = false, navPrevTitle = '', lastReadyPath = '';
        const frameTrackPath = () => location.pathname.replace(/^\\/n(?=\\/)/, '').replace(/\\/+$/, '');
        window.addEventListener('message', (e) => {
          const d = e.data;
          if (d && typeof d === 'object' && typeof d.href === 'string') {
            d.href = d.href.replace(/([?&]theme=)(dark|light)\\b/, '$1' + wantTheme);
            if (d.kind === 'navigate') {
              const h1 = document.querySelector('section[aria-label="Track header"] h1');
              navPrevTitle = h1 ? (h1.textContent || '').trim() : '';
              navPending = true;
            }
          }
        }, true);
        const notifyTrackReady = (s) => {
          const p = frameTrackPath();
          if (!p || p === lastReadyPath) return;
          const h1 = s.querySelector('h1');
          const title = h1 ? (h1.textContent || '').trim() : '';
          if (!title) return;
          if (navPending && navPrevTitle && title === navPrevTitle) return;
          navPending = false;
          lastReadyPath = p;
          requestAnimationFrame(() => {
            try { window.webkit.messageHandlers.cp.postMessage({ trackPageReady: p }); } catch (e) {}
          });
        };
        // The header's artwork is its largest image: tag it, and feed it to the blurred backdrop.
        const tag = () => {
          const s = document.querySelector('section[aria-label="Track header"]');
          if (!s) return;
          let best = null, area = 0;
          for (const img of s.querySelectorAll('img')) {
            const r = img.getBoundingClientRect();
            if (r.width * r.height > area) { area = r.width * r.height; best = img; }
          }
          if (!best || area < 10000) return;
          if (!best.classList.contains('cp-art')) best.classList.add('cp-art');
          const u = best.currentSrc || best.src;
          if (u && s.dataset.cpArt !== u) { s.dataset.cpArt = u; s.style.setProperty('--cp-art', 'url("' + u + '")'); }
          notifyTrackReady(s);
        };
        // Footer list of legal links (Legal · Privacy · Cookie Policy · Imprint · … · Language).
        const hideLegal = () => {
          for (const ul of document.querySelectorAll('ul:not([data-cp-legal])')) {
            const t = ul.textContent || '';
            if (/Privacy/.test(t) && /Cookie/.test(t) && /Imprint/.test(t)) { ul.dataset.cpLegal = '1'; ul.style.setProperty('display', 'none', 'important'); }
          }
        };
        // Track page cleanup: hide gamified Fans leaderboard & Message button, fix Details fade gradient,
        // and soften dark right-rail card surfaces.
        // Elements already inspected (computed-style checks are costly and this runs per mutation frame).
        const tidyChecked = new WeakSet();
        const FADE_SKIP = 'section[aria-label="Track header"], .MuiAvatar-root, .MuiChip-root, button, a, [role="button"], img, [class*="artwork" i], [class*="badge" i], [class*="skeleton" i]';
        const tidyTrackFrame = () => {
          const aside = document.querySelector('aside');
          if (aside) {
            const isFansText = (t) => t === 'Fans' || t === 'Climb the leaderboard' || t.startsWith('Fans who have played this track');
            // True when el holds another rail module's heading (Likes, Reposts, …), so it isn't the Fans module alone.
            const hasOtherModule = (el) => [...el.querySelectorAll('h2, h3')].some((x) => !isFansText((x.textContent || '').trim()));
            for (const h of aside.querySelectorAll('h2, h3, [class*="MuiTypography-"]')) {
              const txt = (h.textContent || '').trim();
              if (isFansText(txt)) {
                let mod = h;
                while (mod.parentElement && mod.parentElement !== aside && !hasOtherModule(mod.parentElement)) mod = mod.parentElement;
                if (mod !== h && !hasOtherModule(mod) && !/Related Tracks|In Playlists|In Albums/i.test(mod.textContent || '')) {
                  mod.style.setProperty('display', 'none', 'important');
                }
              }
            }
            for (const b of aside.querySelectorAll('button, a[role="button"]')) {
              const lbl = (b.getAttribute('aria-label') || b.textContent || '').trim();
              if (/^(message|send a message)$/i.test(lbl)) {
                b.style.setProperty('display', 'none', 'important');
              }
            }
            for (const div of aside.querySelectorAll('div, section, article, a')) {
              if (tidyChecked.has(div)) continue;
              tidyChecked.add(div);
              if (div.classList.contains('cp-rail-card') || div.matches('button, [role="button"], .MuiAvatar-root, .MuiChip-root')) continue;
              const cs = getComputedStyle(div);
              const bg = cs.backgroundColor || '';
              if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') {
                const r = div.getBoundingClientRect();
                if (!r.width) { tidyChecked.delete(div); continue; } // not laid out yet: retry next pass
                if (r.width >= 70 && r.width <= 380 && r.height >= 44 && r.height <= 260) {
                  div.classList.add('cp-rail-card');
                }
              }
            }
          }
          const mainEl = document.getElementById('main') || document.querySelector('main');
          if (mainEl) {
            for (const el of mainEl.querySelectorAll('div, p, section, span')) {
              if (tidyChecked.has(el)) continue;
              tidyChecked.add(el);
              if (el.closest(FADE_SKIP)) continue;
              const cs = getComputedStyle(el);
              // Only the "Show more" fade: an empty, absolutely positioned overlay (not artwork
              // placeholders, badges or buttons that also use gradients).
              if (cs.backgroundImage && cs.backgroundImage.includes('linear-gradient') &&
                  cs.position === 'absolute' && !el.firstElementChild && !(el.textContent || '').trim()) {
                el.style.setProperty('background-image', 'linear-gradient(to bottom, rgba(var(--cp-bg-rgb), 0), var(--cp-bg))', 'important');
                el.style.setProperty('background-color', 'transparent', 'important');
              }
              const afterBg = getComputedStyle(el, '::after').backgroundImage || '';
              const beforeBg = getComputedStyle(el, '::before').backgroundImage || '';
              if (afterBg.includes('gradient') || beforeBg.includes('gradient')) {
                el.classList.add('cp-fade-mask');
              }
            }
          }
          if (st.parentElement && st.nextElementSibling) st.parentElement.appendChild(st);
        };
        // Forward track-page toasts (MUI Snackbars / alerts / fixed toast cards) to the native sidebar toast.
        const TOAST_RE = /\\b(was|were) (saved to|removed from|added to)\\b|\\b(added to|removed from|saved to)\\b|\\bnext up\\b|copied|\\breposted\\b|\\bunreposted\\b|\\bnow following\\b|\\bunfollowed\\b|\\bplaylist (created|updated|deleted)\\b|\\bcomment (posted|deleted)\\b/i;
        const TOAST_IGNORE = /sorry,?\\s*something went wrong/i;
        const TOAST_SEL = '.MuiSnackbar-root, [class*="toast" i]:not(.cp-toast), [class*="snackbar" i]:not(.cp-toast), [role="alert"], [role="status"]';
        const TOAST_SKIP = '.cp-toast, [role="dialog"], [role="menu"], [role="tooltip"], .MuiDialog-root, .MuiMenu-root, .MuiPopover-root';
        const tagFrameToasts = () => {
          const headerArt = (document.querySelector('section[aria-label="Track header"]') || {}).dataset?.cpArt || '';
          for (const el of document.querySelectorAll(TOAST_SEL)) {
            if (el.closest(TOAST_SKIP)) continue;
            const msg = (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
            if (!msg || msg.length > 300 || TOAST_IGNORE.test(msg)) continue;
            const isExplicit = el.classList.contains('MuiSnackbar-root') || /toast|snackbar/i.test(String(el.className || ''));
            if (!isExplicit && !TOAST_RE.test(msg)) continue;
            el.classList.add('cp-toast');
            const img = el.querySelector('img');
            const art = (img && (img.currentSrc || img.src)) || headerArt;
            try { window.webkit.messageHandlers.cp.postMessage({ toast: msg, toastArt: art }); } catch (e) {}
          }
        };
        let queued = false;
        const runFramePass = () => { tag(); hideLegal(); tidyTrackFrame(); tagFrameToasts(); };
        document.addEventListener('DOMContentLoaded', runFramePass);
        new MutationObserver(() => { if (!queued) { queued = true; requestAnimationFrame(() => { queued = false; runFramePass(); }); } })
          .observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ['src'] });
        \(Menus.js)
        })();
        """
    }

    static func bootstrap(theme: Theme.Snapshot, volume: Double?) -> String {
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        return """
        (() => {
        const DEBUG = \(debug);
        const BASE_CSS = \(js(debloatCSS));
        const HIDE_SECTIONS = \(js(hiddenHomeSections.map { $0.lowercased() }));
        const INITIAL_THEME = { dark: \(theme.isDark), css: \(js(Theme.css(theme))) };
        const INITIAL_VOLUME = \(volume.map { String($0) } ?? "null");
        \(bootstrapBody)
        \(Menus.js)
        })();
        """
    }

    /// Runs at document start. Exposes window.CP: reads player state, sends commands,
    /// and pushes state to Swift via webkit.messageHandlers.cp.
    private static let bootstrapBody = #"""
    if (window.CP) return;
    try { performance.setResourceTimingBufferSize(10000); } catch (e) {}   // for the debug request log

    // Debug builds: record page errors and failed requests (blocked ones fail with a TypeError).
    // Always sniff SoundCloud's api-v2 client_id so profile overview shelves can fetch previews.
    const debugErrors = [];
    let scClientId = '';
    const sniffApiUrl = (url) => {
      if (typeof url !== 'string' || url.indexOf('api-v2.soundcloud.com') < 0) return;
      if (!scClientId) {
        const m = url.match(/[?&]client_id=([^&]+)/);
        if (m) scClientId = decodeURIComponent(m[1]);
      }
    };
    const origFetch = window.fetch;
    window.fetch = function (input) {
      const url = typeof input === 'string' ? input : (input && input.url);
      sniffApiUrl(url);
      const p = origFetch.apply(this, arguments);
      if (DEBUG) return p.catch((err) => { if (debugErrors.length < 100) debugErrors.push('fetch failed: ' + String(url + ' — ' + err).slice(0, 300)); throw err; });
      return p;
    };
    // CP.open(path, true): SoundCloud's router pushes a history entry for the navigation; turn
    // that one push into a replace.
    let replaceNextPush = false;
    const origPushState = history.pushState;
    history.pushState = function (state, title, url) {
      if (replaceNextPush) { replaceNextPush = false; return history.replaceState(state, title, url); }
      return origPushState.apply(this, arguments);
    };
    const origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      sniffApiUrl(url);
      if (DEBUG) {
        this.addEventListener('error', () => { if (debugErrors.length < 100) debugErrors.push('xhr failed: ' + String(url).slice(0, 300)); });
        this.addEventListener('load', () => { if (this.status >= 400 && debugErrors.length < 100) debugErrors.push('xhr ' + this.status + ': ' + String(url).slice(0, 300)); });
      }
      return origOpen.apply(this, arguments);
    };
    if (DEBUG) {
      const note = (kind, detail) => { if (debugErrors.length < 100) debugErrors.push(kind + ': ' + String(detail).slice(0, 300)); };
      window.addEventListener('error', (e) => note('error', (e.message || '') + ' @ ' + (e.filename || (e.target && (e.target.src || e.target.href)) || '')), true);
      window.addEventListener('unhandledrejection', (e) => note('rejection', e.reason && (e.reason.stack || e.reason.message || e.reason)));
    }

    const $ = (sel) => document.querySelector(sel);
    const textOf = (sel) => { const el = $(sel); return el ? (el.textContent || '').trim() : ''; };
    const titleOf = (sel) => { const el = $(sel); return el ? (el.getAttribute('title') || el.textContent || '').trim() : ''; };
    const hrefOf = (sel) => { const el = $(sel); return el ? (el.getAttribute('href') || '') : ''; };
    const toSeconds = (t) => (t || '').split(':').reduce((acc, v) => acc * 60 + (parseFloat(v) || 0), 0);
    const round = (x) => Math.round(x * 10) / 10;
    const bgURL = (el) => {
      if (!el) return '';
      const bg = el.style.backgroundImage || getComputedStyle(el).backgroundImage || '';
      const m = bg.match(/url\(["']?(.*?)["']?\)/);
      return m ? m[1] : '';
    };
    const bigArt = (u) => u.replace(/-(t\d+x\d+|large|small|badge|tiny)\./, '-t500x500.');

    // Remember the media element SoundCloud plays through, for exact timing and volume.
    // During a silentTransition (e.g. Likes Shuffle starting track #1 to populate the queue
    // before skipping to a random track), keep audio muted and pause native state reports.
    let silentTransition = false;
    const setSilentTransition = (on) => {
      silentTransition = on;
      const els = new Set(document.querySelectorAll('audio, video'));
      if (CP && CP.media) els.add(CP.media);
      const vol = (CP && CP.volume != null) ? CP.volume : 1;
      for (const el of els) {
        el.muted = on;
        el.volume = on ? 0 : vol;
      }
      if (!on && window.CP) CP.report();
    };
    const origPlay = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function () {
      CP.media = this;
      if (silentTransition) {
        this.muted = true;
        this.volume = 0;
      } else {
        if (this.muted) this.muted = false;
        if (CP.volume != null) this.volume = CP.volume;
      }
      return origPlay.apply(this, arguments);
    };
    // SoundCloud re-applies its own volume on track changes; keep ours.
    document.addEventListener('volumechange', (e) => {
      const el = e.target;
      if (!(el instanceof HTMLMediaElement)) return;
      if (silentTransition) {
        if (!el.muted) el.muted = true;
        if (el.volume !== 0) el.volume = 0;
      } else if (CP.volume != null && Math.abs(el.volume - CP.volume) > 0.001) {
        el.volume = CP.volume;
      }
    }, true);

    // Styles: debloat, native theme, user custom.css. Re-mounted after DOMContentLoaded
    // so they sit after SoundCloud's own stylesheets.
    const style = (id, css) => { const s = document.createElement('style'); s.id = id; s.textContent = css; return s; };
    const baseStyle = style('cp-base', BASE_CSS);
    const themeStyle = style('cp-theme', INITIAL_THEME.css);
    const userStyle = style('cp-user', '');
    const mountStyles = () => {
      const root = document.head || document.documentElement;
      root.appendChild(baseStyle); root.appendChild(themeStyle); root.appendChild(userStyle);
    };
    mountStyles();
    document.addEventListener('DOMContentLoaded', mountStyles);

    // Light/dark follows macOS, not SoundCloud's own theme setting: keep body's theme class in sync.
    let themeDark = INITIAL_THEME.dark;
    // Newer pages (tracks) run in a "/n/…?theme=dark|light" iframe whose look is fixed at load;
    // on an appearance change, reload it at its current page with the new theme.
    const rethemeFrames = () => {
      for (const f of document.querySelectorAll('iframe')) {
        try {
          const loc = f.contentWindow.location;
          if (!loc.pathname.startsWith('/n/')) continue;
          const want = loc.href.replace(/([?&]theme=)(dark|light)\b/, '$1' + (themeDark ? 'dark' : 'light'));
          if (want !== loc.href) loc.replace(want);
        } catch (e) {}
      }
    };
    let bodyWatched = false;
    const applyThemeClass = () => {
      const b = document.body;
      if (!b) return;
      const want = themeDark ? 'theme-dark' : 'theme-light';
      const other = themeDark ? 'theme-light' : 'theme-dark';
      if (b.classList.contains(other)) b.classList.remove(other);
      if (!b.classList.contains(want)) b.classList.add(want);
      if (!bodyWatched) {
        bodyWatched = true;
        new MutationObserver(applyThemeClass).observe(b, { attributes: true, attributeFilter: ['class'] });
      }
    };

    // Home page: hide sections by heading text as they render (they lazy-load on scroll).
    const hideSections = () => {
      for (const li of document.querySelectorAll('li.mixedModularHome__item:not([data-cp-checked])')) {
        const h = li.querySelector('h2');
        const t = h ? h.textContent.trim().toLowerCase() : '';
        if (!t) continue;                       // heading not rendered yet; check again later
        li.dataset.cpChecked = '1';
        if (HIDE_SECTIONS.some((p) => t.startsWith(p))) li.style.setProperty('display', 'none', 'important');
      }
    };
    // Display mode toggles: Tiles, Compact List, and Full Waveform (where applicable).
    // Remembers the chosen mode per section in localStorage.
    const VIEW_MODES = ['tiles', 'compact', 'waveform'];
    const VIEW_META = {
      tiles: { cls: 'cp-view-btn-tiles', title: 'Tiles' },
      compact: { cls: 'cp-view-btn-compact', title: 'Compact List' },
      waveform: { cls: 'cp-view-btn-waveform', title: 'Waveform' },
    };
    const viewKeyFor = (sec) => {
      const p = location.pathname.replace(/\/+$/, '');
      if (p === '/you/likes') return 'likes';
      if (p === '/you/history') return 'history';
      if (p === '/you/sets') return 'sets';
      if (p === '/you/albums') return 'albums';
      if (p === '/you/stations') return 'stations';
      if (p === '/you/following') return 'following';
      if (p === '/search/people') return 'search-people';
      if (p.startsWith('/search')) return 'search';
      if (p.startsWith('/tags/')) return p.endsWith('/playlists') ? 'tags-playlists' : 'tags';
      if (sec && sec.closest('.listenNetwork')) {
        return /\/(likes|reposts)$/.test(p) ? 'listen-net-badges' : 'listen-net-sounds';
      }
      if (sec && sec.closest('.userNetwork')) {
        return /\/(following|followers)$/.test(p) ? 'user-net-people' : 'user-net-likes';
      }
      if (sec && sec.closest('.userMain')) {
        return /\/(albums|sets)$/.test(p) ? 'profile-collections' : 'profile-sounds';
      }
      return 'default';
    };
    const readViewPref = (key, allowed, def) => {
      let v = null;
      try {
        v = localStorage.getItem('cp-view:' + key);
        if (!v && key === 'likes') {
          const old = localStorage.getItem('cp-view');
          if (old === 'grid') v = 'tiles';
          else if (old === 'list') v = 'compact';
        }
      } catch (err) {}
      return allowed.includes(v) ? v : def;
    };
    const writeViewPref = (key, mode) => {
      try { localStorage.setItem('cp-view:' + key, mode); } catch (err) {}
    };
    const applyViewMode = (container, mode, optsEl) => {
      if (!container) return;
      const changed = container.dataset.cpView !== mode;
      container.dataset.cpView = mode;
      for (const m of VIEW_MODES) container.classList.toggle('cp-view-' + m, m === mode);
      if (optsEl && optsEl.dataset.cpMode !== mode) optsEl.dataset.cpMode = mode;
      if (changed) {
        if (typeof clearHoverPlay === 'function') clearHoverPlay();
        requestAnimationFrame(() => {
          for (const el of container.querySelectorAll('[data-cp-art500]')) shrinkArt(el);
        });
      }
    };
    const makeToggleButton = (mode) => {
      const meta = VIEW_META[mode];
      const li = document.createElement('li');
      li.className = 'sc-mr-1x cp-view-item-' + mode;
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = meta.cls + ' sc-button sc-button-secondary sc-button-medium sc-button-icon';
      btn.dataset.cpTargetMode = mode;
      btn.title = meta.title;
      btn.setAttribute('aria-label', meta.title);
      btn.innerHTML = '<div><svg viewBox="0 0 16 16" aria-hidden="true"></svg></div>';
      li.appendChild(btn);
      return li;
    };
    const ensureSyntheticToggle = (container, host, insertBefore, key, allowed, def) => {
      const modesKey = allowed.join(',');
      let wrap = host.querySelector(':scope > .cp-view-toggle-wrap');
      if (wrap && wrap.dataset.cpModes !== modesKey) { wrap.remove(); wrap = null; }
      if (!wrap) {
        wrap = document.createElement('div');
        wrap.className = 'collectionSection__action cp-view-toggle-wrap';
        wrap.dataset.cpModes = modesKey;
        const toggle = document.createElement('div');
        toggle.className = 'listDisplayToggle g-flex-row-centered';
        const ul = document.createElement('ul');
        ul.className = 'listDisplayToggle__options cp-view-options sc-list-nostyle g-flex-row-centered';
        for (const m of allowed) ul.appendChild(makeToggleButton(m));
        ul.addEventListener('click', (ev) => {
          const btn = ev.target instanceof Element && ev.target.closest('button[data-cp-target-mode]');
          if (!btn) return;
          ev.preventDefault();
          ev.stopPropagation();
          const next = btn.dataset.cpTargetMode;
          const k = viewKeyFor(container);
          writeViewPref(k, next);
          applyViewMode(container, next, ul);
        });
        toggle.appendChild(ul);
        wrap.appendChild(toggle);
        if (insertBefore && insertBefore.parentElement === host) host.insertBefore(wrap, insertBefore);
        else host.appendChild(wrap);
      } else if (insertBefore && insertBefore.parentElement === host && wrap.nextElementSibling !== insertBefore) {
        host.insertBefore(wrap, insertBefore);
      }
      const ul = wrap.querySelector('.listDisplayToggle__options');
      const pref = readViewPref(key, allowed, def);
      applyViewMode(container, pref, ul);
    };
    const syncViewToggles = () => {
      // 1. Native SoundCloud toggle (e.g. /you/likes): extend with Waveform as a 3rd option.
      for (const opts of document.querySelectorAll('.listDisplayToggle__options:not(.cp-view-options)')) {
        const container = opts.closest('.collectionSection') || opts.closest('.l-collection') || opts.parentElement;
        if (!container) continue;
        const key = viewKeyFor(container);
        const allowed = VIEW_MODES;
        if (!opts.dataset.cpEnhanced) {
          opts.dataset.cpEnhanced = '1';
          const badgeBtn = opts.querySelector('.listDisplayToggle__badgeToggle');
          const listBtn = opts.querySelector('.listDisplayToggle__listToggle');
          if (badgeBtn) { badgeBtn.title = 'Tiles'; badgeBtn.setAttribute('aria-label', 'Tiles'); }
          if (listBtn) { listBtn.title = 'Compact List'; listBtn.setAttribute('aria-label', 'Compact List'); }
          if (!opts.querySelector('.cp-view-btn-waveform')) opts.appendChild(makeToggleButton('waveform'));
          opts.addEventListener('click', (ev) => {
            if (!ev.isTrusted || !(ev.target instanceof Element)) return;
            const b = ev.target.closest('button');
            if (!b) return;
            const k = viewKeyFor(container);
            if (b.classList.contains('listDisplayToggle__badgeToggle')) {
              writeViewPref(k, 'tiles');
              applyViewMode(container, 'tiles', opts);
            } else if (b.classList.contains('listDisplayToggle__listToggle')) {
              writeViewPref(k, 'compact');
              applyViewMode(container, 'compact', opts);
            } else if (b.classList.contains('cp-view-btn-waveform')) {
              ev.preventDefault();
              ev.stopPropagation();
              writeViewPref(k, 'waveform');
              const lb = opts.querySelector('.listDisplayToggle__listToggle');
              if (lb && !lb.classList.contains('sc-button-selected')) lb.click();
              applyViewMode(container, 'waveform', opts);
            }
          }, true);
        }
        const pref = readViewPref(key, allowed, 'compact');
        if (!opts.dataset.cpInit) {
          opts.dataset.cpInit = '1';
          const badgeBtn = opts.querySelector('.listDisplayToggle__badgeToggle');
          const listBtn = opts.querySelector('.listDisplayToggle__listToggle');
          if (pref === 'tiles') {
            if (badgeBtn && !badgeBtn.classList.contains('sc-button-selected')) badgeBtn.click();
          } else {
            if (listBtn && !listBtn.classList.contains('sc-button-selected')) listBtn.click();
          }
        }
        applyViewMode(container, pref, opts);
      }

      // 2. Library sections without a native toggle (Playlists, Albums, Stations, Following).
      for (const sec of document.querySelectorAll('.collectionSection')) {
        if (sec.querySelector('.listDisplayToggle__options:not(.cp-view-options)')) continue;
        const top = sec.querySelector(':scope > .collectionSection__top');
        if (!top) continue;
        const hasSounds = !!sec.querySelector('.soundList, .soundList__item, .historicalPlays__item');
        const hasBadges = !hasSounds && !!sec.querySelector('.badgeList__item');
        if (!hasSounds && !hasBadges) continue;
        const allowed = hasSounds ? VIEW_MODES : ['tiles', 'compact'];
        const def = hasSounds ? 'compact' : 'tiles';
        const insertBefore = top.querySelector(':scope > .collectionSection__filters');
        ensureSyntheticToggle(sec, top, insertBefore, viewKeyFor(sec), allowed, def);
      }

      // 2b. Listening History (/you/history): "Hear the tracks you've played:" uses
      // .playHistory__top + .playHistory__plays > .historicalPlays > li.historicalPlays__item.
      for (const plays of document.querySelectorAll('.playHistory__plays')) {
        if (!plays.querySelector('.historicalPlays__item, .soundList__item')) continue;
        const top = plays.previousElementSibling;
        if (!top || !top.classList.contains('playHistory__top')) continue;
        ensureSyntheticToggle(plays, top, null, 'history', VIEW_MODES, 'compact');
      }

      // 3. Search pages with track / playlist / album / people results.
      const search = document.querySelector('.l-search');
      if (search) {
        const bar = search.querySelector('.searchOptions__container');
        const hasSounds = !!search.querySelector('.searchList__item .sound');
        const hasPeople = !hasSounds && !!search.querySelector('.searchList__item .userItem');
        if (bar && (hasSounds || hasPeople)) {
          const insertBefore = bar.querySelector(':scope > .cp-play-all') || bar.querySelector(':scope > .searchTags');
          const allowed = hasSounds ? VIEW_MODES : ['tiles', 'compact'];
          ensureSyntheticToggle(search, bar, insertBefore, viewKeyFor(search), allowed, 'compact');
        } else if (bar) {
          const old = bar.querySelector(':scope > .cp-view-toggle-wrap');
          if (old) old.remove();
        }
      }

      // 3b. Tag / genre pages (/tags/<tag>, /tags/<tag>/popular-tracks, /tags/<tag>/playlists).
      const tagsMain = document.querySelector('.tagsMain');
      if (tagsMain) {
        const gTabs = tagsMain.querySelector('.tabs .g-tabs, .g-tabs');
        const hasSounds = !!tagsMain.querySelector('.soundList, .soundList__item, .tagsList__item .sound, .sound');
        const hasBadges = !hasSounds && !!tagsMain.querySelector('.badgeList__item');
        if (gTabs && (hasSounds || hasBadges)) {
          const allowed = hasSounds ? VIEW_MODES : ['tiles', 'compact'];
          ensureSyntheticToggle(tagsMain, gTabs, null, viewKeyFor(tagsMain), allowed, 'compact');
        } else {
          if (gTabs) {
            const old = gTabs.querySelector(':scope > .cp-view-toggle-wrap');
            if (old) old.remove();
          }
          applyViewMode(tagsMain, 'compact', null);
        }
      }

      // 4. User profile pages: force compact on overview, mount toggle inside .cp-profile-subhead on sub-pages.
      for (const sec of document.querySelectorAll('.userMain')) {
        if (sec.closest('.l-collection, .l-search')) continue;
        for (const oldBar of sec.querySelectorAll('.cp-profile-view-bar')) oldBar.remove();
        const subhead = sec.querySelector('.cp-profile-subhead');
        if (!subhead) {
          for (const w of sec.querySelectorAll('.cp-view-toggle-wrap')) w.remove();
          applyViewMode(sec, 'compact', null);
          const stream = sec.querySelector('.userStream');
          if (stream) applyViewMode(stream, 'compact', null);
          continue;
        }
        const hasSounds = !!sec.querySelector('.soundList, .soundList__item');
        const hasBadges = !hasSounds && !!sec.querySelector('.badgeList__item');
        if (!hasSounds && !hasBadges) {
          const old = subhead.querySelector(':scope > .cp-view-toggle-wrap');
          if (old) old.remove();
          continue;
        }
        const isCol = /\/(albums|sets)\/?$/.test(location.pathname);
        const allowed = isCol ? ['tiles', 'compact'] : (hasSounds ? VIEW_MODES : ['tiles', 'compact']);
        const def = isCol ? 'tiles' : (hasSounds ? 'compact' : 'tiles');
        ensureSyntheticToggle(sec, subhead, null, viewKeyFor(sec), allowed, def);
      }

      // 4b. User & Track/Playlist network engagement sub-pages (.userNetwork, .listenNetwork).
      for (const sec of document.querySelectorAll('.userNetwork, .listenNetwork')) {
        if (sec.closest('.l-collection, .l-search')) continue;
        for (const oldBar of sec.querySelectorAll('.cp-profile-view-bar')) oldBar.remove();
        const col = sec.closest('.l-fixed-top-one-column') || sec;
        const subhead = col.querySelector('.cp-profile-subhead');
        if (!subhead) continue;
        const hasSounds = !!sec.querySelector('.soundList, .soundList__item');
        const hasBadges = !hasSounds && !!sec.querySelector('.badgeList__item');
        if (!hasSounds && !hasBadges) {
          const old = subhead.querySelector(':scope > .cp-view-toggle-wrap');
          if (old) old.remove();
          continue;
        }
        const isLikes = /\/likes\/?$/.test(location.pathname) && sec.classList.contains('userNetwork');
        const allowed = hasSounds ? VIEW_MODES : ['tiles', 'compact'];
        const def = (hasSounds || isLikes) ? 'compact' : 'tiles';
        ensureSyntheticToggle(sec, subhead, null, viewKeyFor(sec), allowed, def);
      }

      // 5. Fallback: any remaining .soundList (and /messages conversations) stays compact.
      for (const list of document.querySelectorAll('.soundList')) {
        if (!list.closest('[data-cp-view]')) list.classList.add('cp-view-compact');
      }
      // Messages: the compact rules need an ancestor of .conversation, so tag the messages list
      // container (only on /messages, and untag on leaving, as containers can outlive navigation).
      const onMessages = /^\/messages(\/|$)/.test(location.pathname);
      for (const el of document.querySelectorAll('[data-cp-msg-compact]')) {
        if (onMessages) continue;
        el.classList.remove('cp-view-compact');
        delete el.dataset.cpMsgCompact;
      }
      if (onMessages) {
        for (const conv of document.querySelectorAll('.l-messages, .inbox, .conversation')) {
          const host = conv.matches('.conversation') ? (conv.closest('.l-messages, .inbox') || conv.parentElement || conv) : conv;
          for (const el of new Set([host, conv])) {
            if (el.dataset.cpMsgCompact) continue;
            el.dataset.cpMsgCompact = '1';
            el.classList.add('cp-view-compact');
          }
        }
      }
    };
    // Toasts ("… was saved to your Library", "Added to Next up", etc.): intercept every
    // SoundCloud toast (by container selector or text), hide it in the page (.cp-toast),
    // and forward it to the native toast card at the bottom of the left sidebar.
    let suppressToasts = false, suppressToastsUntil = 0;
    const TOAST_SEL = '.gritter-item-wrapper, .gritter-item, [class*="toast" i]:not(.cp-toast), [class*="snackbar" i]:not(.cp-toast), [role="alert"], [role="status"]';
    const TOAST_SKIP = '.cp-toast, .header, .l-container, .playControls, .dropdownMenu, .modal, .tooltip, [role="dialog"], [role="menu"], [role="tooltip"]';
    const TOAST_TEXT = /\b(was|were) (saved to|removed from|added to)\b|\b(added to|removed from|saved to) (next up|your library|playlist)\b|copied|\breposted\b|\bunreposted\b|\bnow following\b|\bunfollowed\b|\bplaylist (created|updated|deleted)\b|\bqueue cleared\b|\bcomment (posted|deleted)\b/i;
    const TOAST_IGNORE = /sorry,?\s*something went wrong/i;
    const toastMsg = (el) => {
      const parts = [];
      const w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
      for (let t; (t = w.nextNode()); ) { const s = t.nodeValue.trim(); if (s) parts.push(s); }
      return parts.join(' ').replace(/\s+([.,!?])/g, '$1');
    };
    const tagToasts = (nodes) => {
      for (const n of nodes) {
        const el = n instanceof HTMLElement ? n : n.parentElement;
        if (!el || el.closest(TOAST_SKIP)) continue;
        const matchedEl = el.matches(TOAST_SEL) ? el : el.querySelector(TOAST_SEL);
        const target = matchedEl || el;
        if (target.id === 'app' || target.closest(TOAST_SKIP) || target.querySelector('.l-container, .playControls, .header')) continue;
        const text = toastMsg(target);
        if (!text || text.length > 300 || TOAST_IGNORE.test(text)) continue;
        const isExplicit = !!matchedEl && (matchedEl.classList.contains('gritter-item-wrapper') || matchedEl.classList.contains('gritter-item') || /toast|snackbar/i.test(String(matchedEl.className || '')));
        if (!isExplicit && !TOAST_TEXT.test(text)) continue;
        // Tag the individual toast card (never #app or the persistent #gritter-notice-wrapper
        // container, so subsequent toasts added inside it are still intercepted).
        let card = target.closest('.gritter-item-wrapper') || target;
        let isFixed = !!target.closest('#gritter-notice-wrapper') || isExplicit;
        if (card === target) {
          for (let e = target; e && e !== document.body && e.id !== 'app' && e.id !== 'gritter-notice-wrapper'; e = e.parentElement) {
            if (e.querySelector('.l-container, .playControls, .header')) break;
            const r = e.getBoundingClientRect();
            if (r.width > 700 || r.height > 250) break;
            card = e;
            if (getComputedStyle(e).position === 'fixed') { isFixed = true; break; }
          }
        }
        if (!isFixed || card.classList.contains('cp-toast')) continue;
        card.classList.add('cp-toast');
        if (suppressToasts || Date.now() < suppressToastsUntil) continue;
        let art = '';
        const img = card.querySelector('img');
        if (img && img.src) art = img.src;
        else for (const e of card.querySelectorAll('*')) { const u = bgURL(e); if (u) { art = u; break; } }
        const msg = toastMsg(card);
        if (!msg || TOAST_IGNORE.test(msg)) continue;
        window.webkit.messageHandlers.cp.postMessage({ toast: msg, toastArt: art ? bigArt(art) : '' });
        if (DEBUG) window.webkit.messageHandlers.cp.postMessage({ debugToast: card.outerHTML });
      }
    };
    // Search filters: SoundCloud sets an inline `overflow: hidden !important` on the filter
    // column, which clips the option menus and can't be beaten from a stylesheet. Override it
    // inline and re-apply whenever SoundCloud rewrites the style.
    const unclipSearchOptions = () => {
      for (const el of document.querySelectorAll('.searchOptions__scrollable:not([data-cp-unclip])')) {
        el.dataset.cpUnclip = '1';
        const fix = () => {
          if (el.style.getPropertyValue('overflow') !== 'visible' || el.style.getPropertyPriority('overflow') !== 'important') {
            el.style.setProperty('overflow', 'visible', 'important');
          }
        };
        fix();
        new MutationObserver(fix).observe(el, { attributes: true, attributeFilter: ['style'] });
      }
      // Details line: child elements (links, badges) are kept and joined with " · " in CSS
      // (Theme.nativeCSS). Only a plain multi-line text node is rewritten, and only once it has text.
      for (const det of document.querySelectorAll('.l-search .userItem__details:not([data-cp-tidy])')) {
        if (det.firstElementChild) continue;
        const text = det.textContent || '';
        if (!text.trim()) continue;
        det.dataset.cpTidy = '1';
        det.textContent = text.split('\n').map((s) => s.trim()).filter(Boolean).join(' · ');
      }
    };
    // Playlist / album / station pages: move the action buttons (like, repost, share…) from
    // below the hero into it, next to the track count, as on track pages. The row lives in
    // .fullHero__tracksSummary (bottom-left of the hero); Theme.nativeCSS styles .cp-hero-row.
    // Moving the view's element keeps its (delegated) event handlers. If SoundCloud re-renders
    // the hero, the moved row goes with it and is put back into the new one.
    // The row stays while the playlist plays too (SoundCloud then drops m-showTracksSummary
    // and shows the playing track's waveform, which Theme.nativeCSS lifts above the row).
    // The hero is also made to match the track header: blurred-artwork backdrop (--cp-art),
    // "artist · 7 years ago" line, and a white waveform (SVG filters, see heroWaveFilters).
    let heroMoved = null, heroMovedPath = '';
    const heroWaveFilters = () => {
      if (document.getElementById('cp-hero-filters')) return;
      const ns = 'http://www.w3.org/2000/svg';
      const svg = document.createElementNS(ns, 'svg');
      svg.id = 'cp-hero-filters';
      svg.setAttribute('aria-hidden', 'true');
      svg.setAttribute('style', 'position:absolute;width:0;height:0;overflow:hidden');
      // Bars: SoundCloud paints played bars orange and unplayed ones white (lighter tints in the
      // reflection). Make everything white; opacity = alpha × (1 − 0.55·blue), so played (no
      // blue) stays solid and unplayed drops to ~45%, like the track header's waveform.
      // Time labels: black boxes with orange / grey digits → plain white digits (alpha = red).
      svg.innerHTML =
        '<filter id="cp-wave-bars" x="0" y="0" width="1" height="1" color-interpolation-filters="sRGB">' +
          '<feColorMatrix in="SourceGraphic" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 -0.55 0 1" result="w"/>' +
          '<feComposite in="w" in2="SourceAlpha" operator="in"/>' +
        '</filter>' +
        '<filter id="cp-wave-time" x="0" y="0" width="1" height="1" color-interpolation-filters="sRGB">' +
          '<feColorMatrix in="SourceGraphic" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  1 0 0 0 0"/>' +
        '</filter>';
      document.body.appendChild(svg);
    };
    const heroLook = () => {
      const hero = document.querySelector(':is(.l-listen-hero, .l-hero-banner) .fullHero');
      if (!hero) return;
      heroWaveFilters();
      let u = '';
      for (const el of hero.querySelectorAll('.fullHero__artwork span.sc-artwork, .fullHero__artwork .image span, .fullHero__artwork .sc-artwork, .fullHero__artwork span')) {
        u = bgURL(el);
        if (u) break;
      }
      if (!u) {
        const img = hero.querySelector('.fullHero__artwork img');
        if (img) u = img.currentSrc || img.src || '';
      }
      if (u) {
        const art = bigArt(u);
        if (hero.dataset.cpArt !== art) { hero.dataset.cpArt = art; hero.style.setProperty('--cp-art', 'url("' + art + '")'); }
      }
      const user = hero.querySelector('.soundTitle__usernameHeroContainer');
      const t = hero.querySelector('.fullHero__uploadTime time');
      const time = t && (t.querySelector('[aria-hidden="true"]') || t);
      if (user && time) {
        const text = '· ' + (time.textContent || '').trim();
        let meta = user.querySelector(':scope > .cp-hero-meta');
        if (!meta) { meta = document.createElement('span'); meta.className = 'cp-hero-meta'; user.appendChild(meta); }
        if (meta.textContent !== text) meta.textContent = text;
      }
    };
    const heroActions = () => {
      heroLook();
      const host = document.querySelector(':is(.l-listen-hero, .l-hero-banner) .fullHero .fullHero__tracksSummary');
      if (!host) return;
      if (!host.classList.contains('cp-hero-row')) host.classList.add('cp-hero-row');
      const fresh = document.querySelector('.listenEngagement__footer .listenEngagement__actions, .systemPlaylistDetails__controls:not(.cp-moved)');
      if (fresh) {
        for (const old of host.querySelectorAll(':scope > .cp-moved')) old.remove();
        fresh.classList.add('cp-moved');
        host.appendChild(fresh);
        heroMoved = fresh; heroMovedPath = location.pathname;
      } else if (heroMoved && !heroMoved.isConnected && heroMovedPath === location.pathname) {
        host.appendChild(heroMoved);
      }
    };

    // Profile pages: Apple Music style — drop the underline tab bar, move actions into the
    // hero card, show curated sections with "Title ›" / "See All" drill-downs on the overview,
    // and show a "‹ Artist  Section" header on drill-down sub-pages.
    const PROFILE_SECTIONS = {
      'popular-tracks': 'Popular Tracks',
      'tracks': 'Tracks',
      'albums': 'Albums',
      'sets': 'Playlists',
      'reposts': 'Reposts',
    };
    const CHEVRON_RIGHT_SVG = '<svg class="cp-section__chevron" viewBox="0 0 12 12" aria-hidden="true"><path d="M4.25 2.25L8 6l-3.75 3.75" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    const CHEVRON_LEFT_SVG = '<svg width="11" height="11" viewBox="0 0 12 12" aria-hidden="true"><path d="M7.75 2.25L4 6l3.75 3.75" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    const profileCache = new Map();
    const profileInflight = new Set();
    let profileBtnsMoved = null, profileBtnsBase = '';

    const findClientId = () => {
      if (scClientId) return scClientId;
      try {
        for (const e of performance.getEntriesByType('resource')) {
          if (e.name && e.name.indexOf('api-v2.soundcloud.com') >= 0) {
            const m = e.name.match(/[?&]client_id=([^&]+)/);
            if (m) { scClientId = decodeURIComponent(m[1]); return scClientId; }
          }
        }
      } catch (e) {}
      return '';
    };
    // The album a track is on (for "Go to Album"): /resolve → /tracks/{id}/albums, preferring an
    // album by the track's own artist. Cached per track path: { path, title } or null.
    const albumCache = new Map();
    const albumInflight = new Map();
    const albumFor = (trackPath) => {
      const key = String(trackPath || '').split('?')[0].replace(/^\/n(?=\/)/, '').replace(/\/+$/, '');
      if (!key || key.split('/').filter(Boolean).length < 2) return Promise.resolve(null);
      if (albumCache.has(key)) return Promise.resolve(albumCache.get(key));
      if (albumInflight.has(key)) return albumInflight.get(key);
      const p = (async () => {
        let cid = findClientId();
        for (let i = 0; !cid && i < 10; i++) { await sleep(200); cid = findClientId(); }
        if (!cid) return null;   // not cached: try again later
        let result = null;
        try {
          const r = await origFetch(`https://api-v2.soundcloud.com/resolve?url=${encodeURIComponent('https://soundcloud.com' + key)}&client_id=${encodeURIComponent(cid)}`);
          const t = r.ok ? await r.json() : null;
          if (t && t.kind === 'track' && t.id) {
            const ar = await origFetch(`https://api-v2.soundcloud.com/tracks/${t.id}/albums?client_id=${encodeURIComponent(cid)}&limit=10`);
            const j = ar.ok ? await ar.json() : null;
            const list = (j && Array.isArray(j.collection)) ? j.collection : [];
            const own = list.find((a) => a && a.user && a.user.id === t.user_id) || list[0];
            if (own && own.permalink_url) result = { path: new URL(own.permalink_url).pathname, title: own.title || '' };
          }
        } catch (e) { result = null; }
        albumCache.set(key, result);
        return result;
      })().finally(() => albumInflight.delete(key));
      albumInflight.set(key, p);
      return p;
    };
    const findProfileUserId = (basePath) => {
      const st = document.querySelector('.sc-button-startstation[href*="artist-stations:"]');
      if (st) {
        const m = (st.getAttribute('href') || '').match(/artist-stations:(\d+)/);
        if (m) return m[1];
      }
      try {
        const entries = performance.getEntriesByType('resource');
        for (let i = entries.length - 1; i >= 0; i--) {
          const u = entries[i].name || '';
          const m = u.match(/api-v2\.soundcloud\.com\/users\/(\d+)\/(?:spotlight|featured-profiles|relatedartists)/);
          if (m) return m[1];
        }
      } catch (e) {}
      return '';
    };
    const artURL = (item, size) => {
      let u = item.artwork_url || '';
      if (!u && item.tracks && item.tracks.length) {
        for (const t of item.tracks) { if (t && t.artwork_url) { u = t.artwork_url; break; } }
      }
      if (!u && item.user && item.user.avatar_url) u = item.user.avatar_url;
      if (!u) return '';
      return u.replace(/-(large|t\d+x\d+|crop)\./, '-' + size + '.');
    };
    const toPath = (permalink) => {
      if (!permalink) return '';
      try { return new URL(permalink).pathname; } catch (e) { return permalink.startsWith('/') ? permalink : ''; }
    };
    const fmtDuration = (ms) => {
      if (!ms || !isFinite(ms)) return '';
      const s = Math.round(ms / 1000);
      const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
      const pad = (n) => (n < 10 ? '0' : '') + n;
      return h ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
    };
    const fmtPlays = (n) => {
      if (!n || !isFinite(n)) return '';
      if (n >= 1e6) return (n / 1e6).toFixed(1).replace(/\.0$/, '') + 'M';
      if (n >= 1e3) return (n / 1e3).toFixed(1).replace(/\.0$/, '') + 'K';
      return String(n);
    };
    const makeNavLink = (href, cls, html) => {
      const a = document.createElement('a');
      a.href = href;
      a.className = cls;
      a.innerHTML = html;
      a.addEventListener('click', (ev) => {
        if (ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
        ev.preventDefault();
        CP.open(href);
      });
      return a;
    };
    const makeSectionHeader = (title, href) => {
      const head = document.createElement('div');
      head.className = 'cp-section__header';
      const titleLink = makeNavLink(href, 'cp-section__title', '');
      titleLink.appendChild(document.createTextNode(title));
      titleLink.insertAdjacentHTML('beforeend', CHEVRON_RIGHT_SVG);
      const seeAll = makeNavLink(href, 'cp-section__seeAll', 'See All');
      head.appendChild(titleLink);
      head.appendChild(seeAll);
      return head;
    };
    const makeTrackSection = (title, href, items) => {
      const sec = document.createElement('section');
      sec.className = 'cp-section';
      sec.appendChild(makeSectionHeader(title, href));
      const ul = document.createElement('div');
      ul.className = 'cp-track-list';
      for (const raw of items.slice(0, 5)) {
        const it = raw.track || raw.playlist || raw;
        if (!it || !it.title) continue;
        const path = toPath(it.permalink_url);
        if (!path) continue;
        const row = makeNavLink(path, 'cp-track-row', '');
        const art = document.createElement('div');
        art.className = 'cp-track-row__art';
        const u = artURL(it, 't120x120');
        if (u) art.style.backgroundImage = 'url("' + u + '")';
        const meta = document.createElement('div');
        meta.className = 'cp-track-row__meta';
        const t = document.createElement('div');
        t.className = 'cp-track-row__title';
        t.textContent = it.title;
        const sub = document.createElement('div');
        sub.className = 'cp-track-row__sub';
        const artist = (it.user && it.user.username) || '';
        const plays = fmtPlays(it.playback_count);
        sub.textContent = plays ? `${artist} · ${plays} plays` : artist;
        meta.appendChild(t);
        meta.appendChild(sub);
        const right = document.createElement('div');
        right.className = 'cp-track-row__right';
        right.textContent = fmtDuration(it.duration);
        row.appendChild(art);
        row.appendChild(meta);
        row.appendChild(right);
        ul.appendChild(row);
      }
      if (!ul.childElementCount) return null;
      sec.appendChild(ul);
      return sec;
    };
    const makeShelfSection = (title, href, items, kindLabel) => {
      const sec = document.createElement('section');
      sec.className = 'cp-section';
      sec.appendChild(makeSectionHeader(title, href));
      const shelf = document.createElement('div');
      shelf.className = 'cp-shelf';
      for (const it of items.slice(0, 12)) {
        if (!it || !it.title) continue;
        const path = toPath(it.permalink_url);
        if (!path) continue;
        const card = makeNavLink(path, 'cp-card', '');
        const art = document.createElement('div');
        art.className = 'cp-card__art';
        const u = artURL(it, 't300x300');
        if (u) art.style.backgroundImage = 'url("' + u + '")';
        const t = document.createElement('div');
        t.className = 'cp-card__title';
        t.textContent = it.title;
        const sub = document.createElement('div');
        sub.className = 'cp-card__sub';
        const year = (it.release_date || it.created_at || '').slice(0, 4);
        const count = it.track_count ? `${it.track_count} tracks` : kindLabel;
        sub.textContent = year ? `${year} · ${count}` : count;
        card.appendChild(art);
        card.appendChild(t);
        card.appendChild(sub);
        shelf.appendChild(card);
      }
      if (!shelf.childElementCount) return null;
      sec.appendChild(shelf);
      return sec;
    };
    const makeArtistShelfSection = (title, items) => {
      const sec = document.createElement('section');
      sec.className = 'cp-section';
      const head = document.createElement('div');
      head.className = 'cp-section__header';
      const h = document.createElement('h2');
      h.className = 'cp-section__headingText';
      h.textContent = title;
      head.appendChild(h);
      sec.appendChild(head);
      const shelf = document.createElement('div');
      shelf.className = 'cp-artist-shelf';
      for (const it of (items || []).slice(0, 14)) {
        const uObj = it && (it.user || it);
        const name = uObj && (uObj.username || uObj.title);
        const path = toPath(uObj && (uObj.permalink_url || uObj.href));
        if (!name || !path) continue;
        const card = makeNavLink(path, 'cp-artist-card', '');
        const av = document.createElement('div');
        av.className = 'cp-artist-card__avatar';
        const raw = (uObj.avatar_url || uObj.artwork_url || '');
        const u = raw ? raw.replace(/-(large|t\d+x\d+|badge|small|tiny|crop)\./, '-t300x300.') : '';
        if (u) av.style.backgroundImage = 'url("' + u + '")';
        const lbl = document.createElement('div');
        lbl.className = 'cp-artist-card__name';
        lbl.textContent = name;
        card.appendChild(av);
        card.appendChild(lbl);
        shelf.appendChild(card);
      }
      if (!shelf.childElementCount) return null;
      sec.appendChild(shelf);
      return sec;
    };
    const renderProfileSections = (box, basePath, tabs, data) => {
      box.innerHTML = '';
      box.dataset.cpRendered = basePath + ':' + (data ? 'data' : 'fallback');
      if (data) {
        const specs = [
          ['popular-tracks', () => data.popular.length ? makeTrackSection('Popular Tracks', tabs['popular-tracks'] || basePath + '/popular-tracks', data.popular) : null],
          ['albums', () => data.albums.length ? makeShelfSection('Albums', tabs['albums'] || basePath + '/albums', data.albums, 'Album') : null],
          ['sets', () => data.playlists.length ? makeShelfSection('Playlists', tabs['sets'] || basePath + '/sets', data.playlists, 'Playlist') : null],
          ['reposts', () => data.reposts.length ? makeTrackSection('Reposts', tabs['reposts'] || basePath + '/reposts', data.reposts) : null],
        ];
        for (const [key, build] of specs) {
          if (!tabs[key]) continue;
          const el = build();
          if (el) box.appendChild(el);
        }
        return;
      }
      const row = document.createElement('div');
      row.className = 'cp-browse-row';
      for (const [key, label] of Object.entries(PROFILE_SECTIONS)) {
        if (!tabs[key]) continue;
        const pill = makeNavLink(tabs[key], 'cp-browse-pill', '');
        pill.appendChild(document.createTextNode(label));
        pill.insertAdjacentHTML('beforeend', CHEVRON_RIGHT_SVG);
        row.appendChild(pill);
      }
      if (row.childElementCount) box.appendChild(row);
    };
    const loadProfileOverview = async (basePath, tabs) => {
      if (profileCache.has(basePath) || profileInflight.has(basePath)) return;
      profileInflight.add(basePath);
      try {
        let cid = findClientId();
        for (let i = 0; !cid && i < 15; i++) { await sleep(200); cid = findClientId(); }
        if (!cid) { profileCache.set(basePath, null); profileView(); return; }
        let uid = findProfileUserId(basePath);
        let userObj = null;
        if (!uid) {
          const r = await origFetch(`https://api-v2.soundcloud.com/resolve?url=${encodeURIComponent('https://soundcloud.com' + basePath)}&client_id=${encodeURIComponent(cid)}`);
          if (r.ok) { const j = await r.json(); if (j && j.id) { uid = String(j.id); userObj = j; } }
        }
        if (!uid) { profileCache.set(basePath, null); profileView(); return; }
        const getCol = async (ep) => {
          try {
            const r = await origFetch(`https://api-v2.soundcloud.com/${ep}?client_id=${encodeURIComponent(cid)}&limit=12`);
            if (!r.ok) return [];
            const j = await r.json();
            return Array.isArray(j && j.collection) ? j.collection : (Array.isArray(j) ? j : []);
          } catch (e) { return []; }
        };
        const getJson = async (ep) => {
          try {
            const r = await origFetch(`https://api-v2.soundcloud.com/${ep}?client_id=${encodeURIComponent(cid)}`);
            return r.ok ? await r.json() : null;
          } catch (e) { return null; }
        };
        const [popular, albums, playlists, reposts, related, fetchedUser, webProfiles] = await Promise.all([
          tabs['popular-tracks'] ? getCol(`users/${uid}/toptracks`) : [],
          tabs['albums'] ? getCol(`users/${uid}/albums`) : [],
          tabs['sets'] ? getCol(`users/${uid}/playlists_without_albums`) : [],
          tabs['reposts'] ? getCol(`stream/users/${uid}/reposts`) : [],
          getCol(`users/${uid}/relatedartists`),
          userObj ? Promise.resolve(userObj) : getJson(`users/${uid}`),
          getJson(`users/soundcloud:users:${uid}/web-profiles`),
        ]);
        profileCache.set(basePath, {
          popular, albums, playlists, reposts, related,
          user: fetchedUser || userObj || null,
          webProfiles: Array.isArray(webProfiles) ? webProfiles : [],
        });
        profileView();
      } catch (e) {
        profileCache.set(basePath, null);
        profileView();
      } finally {
        profileInflight.delete(basePath);
      }
    };
    // The signed-in user's profile path, from SoundCloud's (hidden) header.
    const isOwnProfile = (basePath) => {
      const own = (hrefOf('.header__userNavUsernameButton') || '').split('?')[0].replace(/\/+$/, '').toLowerCase();
      return !!own && own === String(basePath || '').toLowerCase();
    };
    const syncProfileHeroMeta = (hero, basePath) => {
      const infoContent = hero.querySelector('.profileHeaderInfo__content') || hero.querySelector('.profileHeaderInfo');
      if (!infoContent) return;
      const cached = profileCache.get(basePath);
      const u = cached && cached.user;

      let followersTxt = '', followingTxt = '', likesTxt = '', tracksTxt = '';
      for (const a of document.querySelectorAll('.infoStats__statLink, .infoStats a[href]')) {
        const h = normHref(a.getAttribute('href'));
        const valEl = a.querySelector('.infoStats__value');
        const val = (valEl ? valEl.textContent : '').trim();
        if (h === basePath + '/followers' && val) followersTxt = `${val} Followers`;
        else if (h === basePath + '/following' && val) followingTxt = `${val} Following`;
        else if (h === basePath + '/tracks' && val && val !== '0') tracksTxt = `${val} ${val === '1' ? 'Track' : 'Tracks'}`;
      }
      if (!tracksTxt && u && typeof u.track_count === 'number' && u.track_count > 0) {
        tracksTxt = `${fmtPlays(u.track_count)} ${u.track_count === 1 ? 'Track' : 'Tracks'}`;
      }
      // Own profile: the right sidebar (hidden here) was the way to your comments.
      const own = isOwnProfile(basePath);
      const likesHdr = document.querySelector('.likesModule a.sidebarHeader .sidebarHeader__actualTitle');
      if (likesHdr) {
        const m = (likesHdr.textContent || '').trim().match(/^([\d.,KMB]+)\s+likes?/i);
        if (m) likesTxt = `${m[1]} Likes`;
      }
      if (!followersTxt && u && typeof u.followers_count === 'number') followersTxt = `${fmtPlays(u.followers_count) || '0'} Followers`;
      if (!followingTxt && u && typeof u.followings_count === 'number') followingTxt = `${fmtPlays(u.followings_count) || '0'} Following`;
      if (!likesTxt && u && typeof u.likes_count === 'number' && u.likes_count > 0) likesTxt = `${fmtPlays(u.likes_count)} Likes`;

      const fLabel = followersTxt || 'Followers';
      const gLabel = followingTxt || 'Following';
      const lLabel = likesTxt || 'Likes';
      const sig = `${basePath}|${fLabel}|${gLabel}|${lLabel}|${tracksTxt}|${own}`;
      let row = infoContent.querySelector(':scope > .cp-profile-meta-links');
      if (row && row.dataset.cpSig === sig) return;
      if (row) row.remove();
      row = document.createElement('div');
      row.className = 'cp-profile-meta-links';
      row.dataset.cpSig = sig;
      row.appendChild(makeNavLink(basePath + '/followers', 'cp-profile-meta-link', fLabel));
      row.appendChild(makeNavLink(basePath + '/following', 'cp-profile-meta-link', gLabel));
      row.appendChild(makeNavLink(basePath + '/likes', 'cp-profile-meta-link', lLabel));
      if (tracksTxt) row.appendChild(makeNavLink(basePath + '/tracks', 'cp-profile-meta-link', tracksTxt));
      if (own) row.appendChild(makeNavLink(basePath + '/comments', 'cp-profile-meta-link', 'Comments'));
      infoContent.appendChild(row);
    };
    const syncProfileAbout = (mainContent, basePath, isOverview) => {
      if (!isOverview) {
        for (const a of mainContent.querySelectorAll(':scope > .cp-profile-about')) a.remove();
        return;
      }
      const cached = profileCache.get(basePath);
      let bio = (cached && cached.user && cached.user.description) ? String(cached.user.description).trim() : '';
      if (!bio) {
        const domBio = document.querySelector('.l-sidebar-right .truncatedUserDescription__content, .userSidebar .truncatedUserDescription__content');
        if (domBio) bio = (domBio.textContent || '').trim();
      }
      const links = [];
      const seenUrls = new Set();
      if (cached && Array.isArray(cached.webProfiles)) {
        for (const wp of cached.webProfiles) {
          if (!wp || !wp.url || seenUrls.has(wp.url)) continue;
          seenUrls.add(wp.url);
          links.push({ title: (wp.title || wp.service || 'Website').trim(), url: wp.url });
        }
      }
      if (!links.length) {
        for (const a of document.querySelectorAll('.web-profiles a[href], .userSidebar a.web-profile[href]')) {
          const url = a.href;
          const title = (a.textContent || '').trim();
          if (!url || !title || seenUrls.has(url)) continue;
          seenUrls.add(url);
          links.push({ title, url });
        }
      }
      if (!bio && !links.length) {
        for (const a of mainContent.querySelectorAll(':scope > .cp-profile-about')) a.remove();
        return;
      }
      const sig = `${basePath}|${bio.slice(0, 80)}|${links.length}`;
      let about = mainContent.querySelector(':scope > .cp-profile-about');
      if (about && about.dataset.cpSig === sig) return;
      if (about) about.remove();
      about = document.createElement('section');
      about.className = 'cp-profile-about';
      about.dataset.cpSig = sig;
      const h = document.createElement('h2');
      h.className = 'cp-section__headingText';
      h.textContent = 'About';
      about.appendChild(h);
      const card = document.createElement('div');
      card.className = 'cp-profile-about__card';
      if (bio) {
        const p = document.createElement('p');
        p.className = 'cp-profile-about__bio';
        p.textContent = bio;
        card.appendChild(p);
      }
      if (links.length) {
        const pills = document.createElement('div');
        pills.className = 'cp-profile-about__links';
        for (const l of links.slice(0, 10)) {
          const a = document.createElement('a');
          a.className = 'cp-profile-about__link';
          a.href = l.url;
          a.target = '_blank';
          a.rel = 'noopener noreferrer';
          a.textContent = l.title;
          pills.appendChild(a);
        }
        card.appendChild(pills);
      }
      about.appendChild(card);
      const rel = mainContent.querySelector(':scope > .cp-profile-related');
      if (rel) mainContent.insertBefore(about, rel);
      else mainContent.appendChild(about);
    };
    const syncProfileRelated = (mainContent, basePath, isOverview) => {
      if (!isOverview) {
        for (const r of mainContent.querySelectorAll(':scope > .cp-profile-related')) r.remove();
        return;
      }
      const cached = profileCache.get(basePath);
      let related = (cached && Array.isArray(cached.related) && cached.related.length) ? cached.related : [];
      if (!related.length) {
        related = [...document.querySelectorAll('.relatedArtistsModule a.userBadgeListItem__heading[href], .relatedArtistsModule .userBadgeListItem')]
          .map((el) => {
            const a = el.matches('a') ? el : el.querySelector('a[href]');
            const art = bgURL(el.closest('li, .userBadgeListItem')?.querySelector('.sc-artwork, .image span'));
            return a ? { username: (a.textContent || '').trim(), permalink_url: a.getAttribute('href'), avatar_url: art } : null;
          }).filter(Boolean);
        if (cached && related.length) cached.related = related;
      }
      if (!related.length) {
        for (const r of mainContent.querySelectorAll(':scope > .cp-profile-related')) r.remove();
        return;
      }
      const firstRef = (related[0] && ((related[0].user || related[0]).permalink_url || (related[0].user || related[0]).href)) || '';
      const sig = `${basePath}|${related.length}|${firstRef}`;
      const existing = mainContent.querySelector(':scope > .cp-profile-related');
      if (existing && existing.dataset.cpSig === sig) return;
      if (existing) existing.remove();
      const relEl = makeArtistShelfSection('Similar Artists', related);
      if (!relEl) return;
      relEl.classList.add('cp-profile-related');
      relEl.dataset.cpSig = sig;
      mainContent.appendChild(relEl);
    };
    const profileView = () => {
      const hero = document.querySelector('.l-user-hero .profileHeader');
      const infoBar = document.querySelector('.userInfoBar');
      if (!hero || !infoBar) return;

      const tabLinks = [...infoBar.querySelectorAll('.profileTabs a.g-tabs-link')];
      if (!tabLinks.length) return;
      const basePath = normHref(tabLinks[0].getAttribute('href'));
      if (!basePath) return;

      const baseLower = basePath.toLowerCase();
      const tabs = {};
      for (const a of tabLinks) {
        const h = normHref(a.getAttribute('href'));
        if (h.toLowerCase().startsWith(baseLower + '/')) {
          tabs[h.slice(basePath.length + 1).toLowerCase()] = h;
        }
      }

      // Move action buttons (Station, Follow, Share, More) into the profile hero card; hide Insights & DM buttons.
      const freshBtns = infoBar.querySelector('.userInfoBar__buttons:not(.cp-profile-actions)');
      if (freshBtns) {
        for (const old of hero.querySelectorAll(':scope > .cp-profile-actions')) old.remove();
        freshBtns.classList.add('cp-profile-actions');
        hero.appendChild(freshBtns);
        profileBtnsMoved = freshBtns;
        profileBtnsBase = basePath;
      } else if (profileBtnsMoved && !profileBtnsMoved.isConnected && profileBtnsBase === basePath) {
        hero.appendChild(profileBtnsMoved);
      }
      // Insights stays on the signed-in user's own profile (it's theirs to see); hidden elsewhere.
      const isOwn = isOwnProfile(basePath);
      for (const b of hero.querySelectorAll('.cp-profile-actions button, .cp-profile-actions a')) {
        const lbl = (b.getAttribute('aria-label') || b.getAttribute('title') || b.textContent || '').replace(/\s+/g, ' ').trim();
        const insights = /\binsights\b/i.test(lbl) || b.classList.contains('sc-button-insights') || (b.getAttribute('href') || '').includes('/insights');
        if ((insights && !isOwn) || /^(send a message|message)$/i.test(lbl)) {
          b.style.setProperty('display', 'none', 'important');
        } else if (insights) {
          b.style.removeProperty('display');
        }
      }

      syncProfileHeroMeta(hero, basePath);

      const mainContent = document.querySelector('.l-user-main .userMain__content');
      if (!mainContent) return;

      const cur = normHref(location.pathname);
      const curLower = cur.toLowerCase();
      const subKey = curLower.startsWith(baseLower + '/') ? curLower.slice(baseLower.length + 1) : '';
      const subTitle = PROFILE_SECTIONS[subKey] || '';

      if (subTitle) {
        mainContent.classList.remove('cp-profile-overview');
        delete mainContent.dataset.cpTrimmed;
        for (const el of mainContent.querySelectorAll('.cp-trimmed-extra')) el.classList.remove('cp-trimmed-extra');
        for (const s of mainContent.querySelectorAll(':scope > .cp-profile-sections, .userStream > .cp-profile-sections')) s.remove();
        syncProfileAbout(mainContent, basePath, false);
        syncProfileRelated(mainContent, basePath, false);
        const nameEl = hero.querySelector('.profileHeaderInfo__userName');
        const artistName = (nameEl ? (nameEl.childNodes[0] && nameEl.childNodes[0].textContent || nameEl.textContent) : '').trim() || 'Artist';
        let subhead = mainContent.querySelector(':scope > .cp-profile-subhead');
        const key = baseLower + '|' + subKey;
        if (!subhead || subhead.dataset.cpKey !== key) {
          if (subhead) subhead.remove();
          subhead = document.createElement('div');
          subhead.className = 'cp-profile-subhead';
          subhead.dataset.cpKey = key;
          const left = document.createElement('div');
          left.className = 'cp-profile-subhead__left';
          const back = makeNavLink(basePath, 'cp-profile-subhead__back', CHEVRON_LEFT_SVG);
          back.appendChild(document.createTextNode(artistName));
          const h = document.createElement('h2');
          h.className = 'cp-profile-subhead__title';
          h.textContent = subTitle;
          left.appendChild(back);
          left.appendChild(h);
          subhead.appendChild(left);
          mainContent.insertBefore(subhead, mainContent.firstChild);
        }
        return;
      }

      // Overview page (/<user>)
      for (const sh of mainContent.querySelectorAll(':scope > .cp-profile-subhead')) sh.remove();
      if (curLower !== baseLower) {
        mainContent.classList.remove('cp-profile-overview');
        delete mainContent.dataset.cpTrimmed;
        for (const el of mainContent.querySelectorAll('.cp-trimmed-extra')) el.classList.remove('cp-trimmed-extra');
        syncProfileAbout(mainContent, basePath, false);
        syncProfileRelated(mainContent, basePath, false);
        return;
      }
      mainContent.classList.add('cp-profile-overview');

      // Turn "Recent" header into an Apple Music section header linking to Tracks (with fallback to other tabs).
      const recentH = mainContent.querySelector('.userstream__header');
      const recentHref = tabs['tracks'] || tabs['sets'] || tabs['albums'] || tabs['reposts'] || '';
      const recentEnhKey = baseLower + '|' + recentHref;
      if (recentH && recentHref && recentH.dataset.cpEnhanced !== recentEnhKey) {
        const label = recentH.dataset.cpOrigLabel || (recentH.textContent || 'Recent').trim() || 'Recent';
        recentH.dataset.cpOrigLabel = label;
        recentH.dataset.cpEnhanced = recentEnhKey;
        recentH.classList.add('cp-section-heading');
        recentH.textContent = '';
        const titleLink = makeNavLink(recentHref, 'cp-section__title', '');
        titleLink.appendChild(document.createTextNode(label));
        titleLink.insertAdjacentHTML('beforeend', CHEVRON_RIGHT_SVG);
        const seeAll = makeNavLink(recentHref, 'cp-section__seeAll', 'See All');
        recentH.appendChild(titleLink);
        recentH.appendChild(seeAll);
      }

      let shown = 0;
      for (const li of mainContent.querySelectorAll('.soundList__item')) {
        if (li.closest('.spotlight')) continue;
        if (!li.querySelector('.sound')) continue;
        shown++;
        li.classList.toggle('cp-trimmed-extra', shown > 10);
      }
      mainContent.dataset.cpTrimmed = '1';

      const stream = mainContent.querySelector('.userStream');
      const host = stream || mainContent;
      let box = host.querySelector(':scope > .cp-profile-sections');
      if (!box) {
        box = document.createElement('div');
        box.className = 'cp-profile-sections';
        const spotlight = host.querySelector(':scope > .spotlight');
        if (spotlight && spotlight.nextSibling) host.insertBefore(box, spotlight.nextSibling);
        else if (spotlight) host.appendChild(box);
        else host.insertBefore(box, host.firstChild);
      }
      if (profileCache.has(basePath)) {
        const data = profileCache.get(basePath);
        const want = basePath + ':' + (data ? 'data' : 'fallback');
        if (box.dataset.cpRendered !== want) {
          renderProfileSections(box, basePath, tabs, data);
          box.dataset.cpRendered = want;
        }
      } else {
        loadProfileOverview(basePath, tabs);
      }
      syncProfileAbout(mainContent, basePath, true);
      syncProfileRelated(mainContent, basePath, true);
    };

    // Network & Engagement drill-down sub-pages:
    // - User network: /<user>/(likes|following|followers|comments)
    // - Track/Set engagement: /<user>/<track>/(likes|reposts|albums|sets|recommended) and /<user>/sets/<set>/(likes|reposts)
    const USER_NET_TITLES = { likes: 'Likes', following: 'Following', followers: 'Followers', comments: 'Comments' };
    const LISTEN_NET_TITLES = {
      likes: 'Liked By', reposts: 'Reposted By', albums: 'Appears On Albums',
      sets: 'In Playlists', recommended: 'Related Tracks',
    };
    const networkView = () => {
      if (location.pathname.startsWith('/you/') || document.querySelector('.l-collection')) return;
      const cur = normHref(location.pathname);
      const parts = cur.split('/').filter(Boolean);

      // 1. User network pages
      const userNet = document.querySelector('.userNetwork');
      if (userNet && parts.length === 2 && USER_NET_TITLES[parts[1]]) {
        const basePath = '/' + parts[0];
        const subTitle = USER_NET_TITLES[parts[1]];
        const rawH1 = (textOf('.userNetworkTop__title') || '').trim();
        const artistName = rawH1.replace(/^(Likes|Following|Followers|Comments)\s+(?:by|of|from)\s+/i, '').trim() || parts[0];
        let avatar = '';
        for (const el of document.querySelectorAll('.userNetworkTop span.sc-artwork, .userNetworkTop .sc-artwork, .userNetworkTop .image span')) {
          avatar = bgURL(el);
          if (avatar) break;
        }
        const main = userNet.closest('.l-fixed-top-one-column')?.querySelector(':scope > .l-main') || userNet;
        const key = `${cur}|${artistName}|${avatar ? '1' : '0'}`;
        let subhead = main.querySelector(':scope > .cp-profile-subhead');
        if (!subhead || subhead.dataset.cpKey !== key) {
          if (subhead) subhead.remove();
          subhead = document.createElement('div');
          subhead.className = 'cp-profile-subhead';
          subhead.dataset.cpKey = key;
          const left = document.createElement('div');
          left.className = 'cp-profile-subhead__left';
          if (avatar) {
            const av = document.createElement('span');
            av.className = 'cp-profile-subhead__avatar';
            av.style.backgroundImage = `url("${avatar}")`;
            left.appendChild(av);
          }
          const back = makeNavLink(basePath, 'cp-profile-subhead__back', CHEVRON_LEFT_SVG);
          back.appendChild(document.createTextNode(artistName));
          const h = document.createElement('h2');
          h.className = 'cp-profile-subhead__title';
          h.textContent = subTitle;
          left.appendChild(back);
          left.appendChild(h);
          subhead.appendChild(left);
          main.insertBefore(subhead, main.firstChild);
        }
        return;
      }

      // 2. Track / Playlist engagement network pages
      const listenNet = document.querySelector('.listenNetwork');
      if (listenNet && parts.length >= 3) {
        const subKey = parts[parts.length - 1];
        const subTitle = LISTEN_NET_TITLES[subKey];
        if (!subTitle) return;
        const parentPath = '/' + parts.slice(0, -1).join('/');
        const itemTitle = (textOf('.listenNetworkInfo__title') || parts[parts.length - 2] || 'Back').trim();
        let art = '';
        for (const el of document.querySelectorAll('.listenNetworkInfo span.sc-artwork, .listenNetworkInfo .sc-artwork, .listenNetworkInfo .image span')) {
          art = bgURL(el);
          if (art) break;
        }
        const main = listenNet.closest('.l-fixed-top-one-column')?.querySelector(':scope > .l-main') || listenNet;
        const key = `${cur}|${itemTitle}|${art ? '1' : '0'}`;
        let subhead = main.querySelector(':scope > .cp-profile-subhead');
        if (!subhead || subhead.dataset.cpKey !== key) {
          if (subhead) subhead.remove();
          subhead = document.createElement('div');
          subhead.className = 'cp-profile-subhead';
          subhead.dataset.cpKey = key;
          const left = document.createElement('div');
          left.className = 'cp-profile-subhead__left';
          if (art) {
            const thumb = document.createElement('span');
            thumb.className = 'cp-profile-subhead__art';
            thumb.style.backgroundImage = `url("${art}")`;
            left.appendChild(thumb);
          }
          const back = makeNavLink(parentPath, 'cp-profile-subhead__back', CHEVRON_LEFT_SVG);
          const backSpan = document.createElement('span');
          backSpan.className = 'cp-profile-subhead__backText';
          backSpan.textContent = itemTitle;
          back.appendChild(backSpan);
          const h = document.createElement('h2');
          h.className = 'cp-profile-subhead__title';
          h.textContent = subTitle;
          left.appendChild(back);
          left.appendChild(h);
          subhead.appendChild(left);
          main.insertBefore(subhead, main.firstChild);
        }
      }
    };

    // Settings cleanup: hide web-only "Change theme" and "Cookies" sections cleanly by heading text.
    const settingsView = () => {
      for (const sec of document.querySelectorAll('.settingsMain .g-form-section:not([data-cp-settings-checked])')) {
        const h = sec.querySelector(':scope > .g-form-section-head h3, :scope > div > .g-form-section-head h3');
        if (!h) continue;
        sec.dataset.cpSettingsChecked = '1';
        const txt = (h.textContent || '').trim();
        if (/^(change theme|cookies)$/i.test(txt)) {
          sec.style.setProperty('display', 'none', 'important');
        }
      }
    };
    // Horizontal tile streams (.tileGallery): enable native horizontal scrolling, lazy-hydrate
    // off-screen slides as you scroll, keep prev/next buttons synced, and centre them on artwork.
    const galleryRO = new ResizeObserver((entries) => {
      for (const e of entries) {
        const g = e.target.closest('.tileGallery');
        if (g && g._cpSync) g._cpSync();
      }
    });
    const setupTileGalleries = () => {
      for (const g of document.querySelectorAll('.tileGallery')) {
        if (g.dataset.cpScroll) {
          if (!g.dataset.cpMeasured && g._cpSync) g._cpSync();
          continue;
        }
        const slider = g.querySelector('.tileGallery__slider');
        if (!slider) continue;
        g.dataset.cpScroll = '1';

        let hydrating = false;
        const hydrate = () => {
          if (hydrating) return;
          const fwd = g.querySelector('.tileGallery__slideForwardButton');
          if (!fwd) return;
          hydrating = true;
          try {
            for (let i = 0; i < 12; i++) {
              const empty = [...g.querySelectorAll('.tileGallery__sliderPanelSlide')].find((s) => !s.firstElementChild);
              if (!empty || !g.classList.contains('m-hasItemsForward')) break;
              const sr = slider.getBoundingClientRect();
              const er = empty.getBoundingClientRect();
              if (sr.width === 0 || er.left > sr.right + sr.width * 0.8) break;
              fwd.click();
            }
          } finally { hydrating = false; }
        };

        const sync = () => {
          const max = slider.scrollWidth - slider.clientWidth;
          g.classList.toggle('cp-can-back', slider.scrollLeft > 4);
          g.classList.toggle('cp-can-forward', max > 4 && slider.scrollLeft < max - 4);
          const art = g.querySelector('.playableTile__artwork, .artistShortcutTile__artwork, .userBadge__avatar, .image');
          if (art) {
            const gr = g.getBoundingClientRect();
            const ar = art.getBoundingClientRect();
            if (ar.height > 0) {
              g.style.setProperty('--cp-btn-top', Math.round(ar.top - gr.top + ar.height / 2) + 'px');
              if (!g.dataset.cpMeasured) { g.dataset.cpMeasured = '1'; galleryRO.observe(art); }
            }
          }
          hydrate();
        };
        g._cpSync = sync;

        let raf = 0;
        slider.addEventListener('scroll', () => {
          if (raf) return;
          raf = requestAnimationFrame(() => { raf = 0; sync(); });
        }, { passive: true });

        g.addEventListener('click', (ev) => {
          if (!ev.isTrusted || !(ev.target instanceof Element)) return;
          const btn = ev.target.closest('.tileGallery__slideForwardButton, .tileGallery__slideBackwardButton');
          if (!btn) return;
          ev.preventDefault();
          ev.stopImmediatePropagation();
          const dir = btn.classList.contains('tileGallery__slideForwardButton') ? 1 : -1;
          if (dir > 0) hydrate();
          const slide = g.querySelector('.tileGallery__sliderPanelSlide');
          const slideW = slide ? slide.getBoundingClientRect().width : 0;
          const visible = slideW > 0 ? Math.max(1, Math.floor(slider.clientWidth / slideW)) : 3;
          const step = slideW > 0 ? Math.round(slideW * visible) : Math.round(slider.clientWidth * 0.85);
          slider.scrollBy({ left: dir * step, behavior: 'smooth' });
        }, true);

        galleryRO.observe(slider);
        requestAnimationFrame(sync);
      }
    };
    // Search page: "Play All" (Tracks) / "Play Tracks" (Everything) button that starts playback
    // on the first rendered track and quietly queues the remaining tracks into Up Next in order.
    const SEARCH_MAX_QUEUE = 50;
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const waitFor = async (fn, ms = 350) => {
      const first = fn();
      if (first) return first;
      for (const t0 = Date.now(); Date.now() - t0 < ms; await sleep(16)) {
        const v = fn();
        if (v) return v;
      }
      return fn();
    };
    const searchPlayLabel = () => {
      const p = location.pathname.replace(/\/+$/, '');
      if (p === '/search/sounds') return 'Play All';
      if (p === '/search') return 'Play Tracks';
      return '';
    };
    const getSearchTrackRows = () =>
      [...document.querySelectorAll('.searchList__item:has(.sound:not(.playlist))')]
        .filter((row) => !!row.querySelector('.soundTitle__playButton .sc-button-play'));

    let searchQueueing = false;
    const playSearchTracks = async (btn) => {
      if (searchQueueing) return;
      const rows = getSearchTrackRows().slice(0, SEARCH_MAX_QUEUE);
      if (!rows.length) return;
      const firstPlay = rows[0].querySelector('.soundTitle__playButton .sc-button-play');
      if (!firstPlay) return;

      searchQueueing = true;
      const startURL = location.pathname + location.search;
      const lbl = btn && btn.querySelector('.cp-play-all__label');
      if (btn) { btn.disabled = true; btn.setAttribute('aria-busy', 'true'); }
      if (lbl) lbl.textContent = 'Queueing…';

      const firstArt = bgURL(rows[0].querySelector('.sound__artwork .image span, .sound__artwork .sc-artwork span'));
      let queued = 0;

      // Start playback on the first track (leave it playing if it already is).
      if (!firstPlay.classList.contains('sc-button-pause')) firstPlay.click();

      const rest = rows.slice(1);
      if (rest.length) {
        // Let SoundCloud initialize playback & its Up Next queue before appending #2..N.
        await sleep(150);
        suppressToasts = true;
        document.documentElement.classList.add('cp-quiet');
        try {
          for (const row of rest) {
            if (location.pathname + location.search !== startURL || !row.isConnected) break;
            const moreBtn = row.querySelector('.sc-button-more');
            if (!moreBtn) continue;
            const before = new Set(document.querySelectorAll('.dropdownMenu'));
            moreBtn.click();
            const menu = await waitFor(() => {
              const id = moreBtn.getAttribute('aria-owns');
              const owned = id && document.getElementById(id);
              if (owned && owned.isConnected) return owned;
              return [...document.querySelectorAll('.dropdownMenu')].find((m) => !before.has(m))
                || [...document.querySelectorAll('.dropdownMenu')].pop()
                || null;
            }, 350);
            if (!menu) continue;
            const qBtn = await waitFor(() =>
              menu.querySelector('.sc-button-queue')
              || [...menu.querySelectorAll('.moreActions__button, button')].find((b) =>
                /add to next up/i.test((b.getAttribute('aria-label') || b.getAttribute('title') || b.textContent || '').trim())
              ), 200);
            if (qBtn) {
              qBtn.click();
              queued++;
            }
            if (menu.isConnected) moreBtn.click();
            if (menu.isConnected) document.body.click();
            await sleep(25);
          }
        } finally {
          document.documentElement.classList.remove('cp-quiet');
          suppressToasts = false;
          suppressToastsUntil = Date.now() + 800;
        }
      }

      searchQueueing = false;
      if (btn && btn.isConnected) {
        btn.disabled = false;
        btn.removeAttribute('aria-busy');
        const nextLabel = searchPlayLabel();
        if (lbl && nextLabel) lbl.textContent = nextLabel;
      }
      syncSearchPlayAll();

      const total = 1 + queued;
      const summary = total > 1 ? 'Queued ' + total + ' tracks' : 'Playing 1 track';
      try {
        window.webkit.messageHandlers.cp.postMessage({ toast: summary, toastArt: firstArt ? bigArt(firstArt) : '' });
      } catch (e) {}
    };

    const syncSearchPlayAll = () => {
      const label = searchPlayLabel();
      const container = label ? document.querySelector('.l-search .searchOptions__container') : null;
      if (!label || !container) {
        for (const b of document.querySelectorAll('.cp-play-all')) b.remove();
        return;
      }
      const existing = [...document.querySelectorAll('.cp-play-all')];
      let btn = existing.find((b) => b.parentElement === container) || null;
      for (const b of existing) if (b !== btn) b.remove();

      const hasTracks = getSearchTrackRows().length > 0;
      if (!hasTracks && !searchQueueing) {
        if (btn && !btn.hidden) btn.hidden = true;
        return;
      }
      if (!btn) {
        btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'cp-play-all';
        btn.innerHTML = '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2.5 1.4a.8.8 0 0 1 1.2-.69l7.1 4.1a.8.8 0 0 1 0 1.38l-7.1 4.1A.8.8 0 0 1 2.5 9.6V1.4z"/></svg><span class="cp-play-all__label"></span>';
        btn.addEventListener('click', (ev) => {
          ev.preventDefault();
          ev.stopPropagation();
          playSearchTracks(btn);
        });
        const tags = container.querySelector(':scope > .searchTags');
        if (tags) container.insertBefore(btn, tags);
        else container.appendChild(btn);
      } else {
        const tags = container.querySelector(':scope > .searchTags');
        if (tags) {
          if (btn.nextElementSibling !== tags) container.insertBefore(btn, tags);
        } else if (btn !== container.lastElementChild) {
          container.appendChild(btn);
        }
      }
      if (btn.hidden) btn.hidden = false;
      if (!searchQueueing) {
        const lbl = btn.querySelector('.cp-play-all__label');
        if (lbl && lbl.textContent !== label) lbl.textContent = label;
      }
    };

    // Likes page: Play & Shuffle buttons in the header. Clicking Play on the first track in
    // /you/likes makes SoundCloud populate Up Next with the Likes collection automatically.
    // Shuffle enables SoundCloud's shuffle mode, starts track #1 silently behind the scenes
    // to load the Likes queue, and immediately skips Next to land on a random liked track.
    const normHref = (h) => (h || '').split('?')[0].replace(/\/+$/, '');

    // System playlists (/discover/sets/…: mixes, stations, charts): the tracklist sits in
    // SoundCloud's narrower main column. Mark each element from the first row up to .l-main
    // (Theme.nativeCSS widens .cp-fullwidth) so the list spans the window like other playlists.
    const widenSystemPlaylist = () => {
      const on = /^\/discover\/sets\//.test(location.pathname);
      const keep = new Set();
      const first = on && document.querySelector('.systemPlaylistTrackList__item');
      if (first) {
        for (let e = first.parentElement; e && e !== document.body && e.id !== 'content'; e = e.parentElement) {
          keep.add(e);
          if (!e.classList.contains('cp-fullwidth')) e.classList.add('cp-fullwidth');
          if (e.classList.contains('l-main')) break;
        }
      }
      for (const e of document.querySelectorAll('.cp-fullwidth')) if (!keep.has(e)) e.classList.remove('cp-fullwidth');
    };

    const isLikesPage = () => location.pathname.replace(/\/+$/, '') === '/you/likes';
    const isShuffling = () => {
      const b = $('button.shuffleControl');
      return !!(b && /\b(m-shuffling|sc-button-selected|m-active)\b/.test(b.className));
    };
    const setShuffle = (want) => {
      const b = $('button.shuffleControl');
      if (b && isShuffling() !== want) b.click();
    };
    const getLikesTracks = () =>
      [...document.querySelectorAll('.collectionSection .playableTile, .collectionSection .soundList__item')]
        .map((item) => {
          const playBtn = item.querySelector('.playableTile__playButton .sc-button-play, .soundTitle__playButton .sc-button-play');
          if (!playBtn) return null;
          const link = item.querySelector('.playableTile__heading, .soundTitle__title');
          return { playBtn, href: normHref(link && link.getAttribute('href')) };
        })
        .filter(Boolean);
    const getFirstLikesTrack = () => getLikesTracks()[0] || null;

    // Quietly clears any leftover tracks in SoundCloud's Up Next queue (e.g. from a previous
    // station or search queue) without visibly opening the Up Next sidebar or showing a toast.
    const clearQueueQuietly = async () => {
      const qBtn = $('.playbackSoundBadge__showQueue');
      if (!qBtn) return;
      const wasVis = !!$('.playControls.m-queueVisible');
      suppressToasts = true;
      if (!wasVis) document.documentElement.classList.add('cp-hide-queue');
      try {
        if (!wasVis) qBtn.click();
        const clr = await waitFor(() => $('.queue__clear'), 350);
        if (clr) {
          clr.click();
          await sleep(100);
        }
        if (!wasVis && $('.playControls.m-queueVisible')) qBtn.click();
      } finally {
        if (!wasVis) {
          await sleep(30);
          document.documentElement.classList.remove('cp-hide-queue');
        }
        suppressToasts = false;
        suppressToastsUntil = Date.now() + 800;
      }
    };

    let likesStarting = false;
    const playLikes = async (shuffle, group) => {
      if (likesStarting) return;
      const tracks = getLikesTracks();
      const first = tracks[0];
      if (!first) return;
      if (!shuffle) {
        likesStarting = true;
        try {
          await clearQueueQuietly();
          setShuffle(false);
          if (!first.playBtn.classList.contains('sc-button-pause')) first.playBtn.click();
        } finally {
          likesStarting = false;
        }
        return;
      }

      likesStarting = true;
      const btns = group ? [...group.querySelectorAll('button')] : [];
      for (const b of btns) { b.disabled = true; b.setAttribute('aria-busy', 'true'); }
      setSilentTransition(true);
      try {
        // 1. Clear any leftover Up Next / station queue so SoundCloud builds a clean Likes queue.
        await clearQueueQuietly();
        // 2. Start with shuffle OFF so SoundCloud populates the full Likes collection cleanly.
        setShuffle(false);
        await sleep(40);
        // If track #1 is already playing (possibly from another context), seed from track #2
        // so SoundCloud is forced to replace the queue with /you/likes.
        const seed = (first.playBtn.classList.contains('sc-button-pause') && tracks[1]) ? tracks[1] : first;
        const curBefore = normHref(hrefOf('.playbackSoundBadge__titleLink'));
        if (!seed.playBtn.classList.contains('sc-button-pause')) {
          seed.playBtn.click();
          if (seed.href && curBefore !== seed.href) {
            await waitFor(() => normHref(hrefOf('.playbackSoundBadge__titleLink')) === seed.href, 1500);
          } else {
            await sleep(150);
          }
        }
        // Let SoundCloud finish hydrating the Likes queue before enabling shuffle and skipping.
        await sleep(250);
        setShuffle(true);
        await sleep(100);
        const nxt = $('.playControls__next');
        if (nxt) {
          nxt.click();
          await waitFor(() => {
            const cur = normHref(hrefOf('.playbackSoundBadge__titleLink'));
            return cur && cur !== seed.href;
          }, 2500);
        }
      } finally {
        setSilentTransition(false);
        likesStarting = false;
        for (const b of btns) {
          if (b.isConnected) { b.disabled = false; b.removeAttribute('aria-busy'); }
        }
        syncLikesActions();
      }
    };

    const syncLikesActions = () => {
      const top = isLikesPage() ? document.querySelector('.collectionSection__top') : null;
      if (!top) {
        for (const g of document.querySelectorAll('.cp-likes-actions')) g.remove();
        return;
      }
      const existing = [...document.querySelectorAll('.cp-likes-actions')];
      let group = existing.find((g) => g.parentElement === top) || null;
      for (const g of existing) if (g !== group) g.remove();

      const hasTracks = !!getFirstLikesTrack();
      if (!hasTracks && !likesStarting) {
        if (group && !group.hidden) group.hidden = true;
        return;
      }
      if (!group) {
        group = document.createElement('div');
        group.className = 'cp-likes-actions';
        const playBtn = document.createElement('button');
        playBtn.type = 'button';
        playBtn.className = 'cp-likes-btn cp-likes-play';
        playBtn.innerHTML = '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2.5 1.4a.8.8 0 0 1 1.2-.69l7.1 4.1a.8.8 0 0 1 0 1.38l-7.1 4.1A.8.8 0 0 1 2.5 9.6V1.4z"/></svg><span>Play</span>';
        playBtn.addEventListener('click', (ev) => {
          ev.preventDefault(); ev.stopPropagation();
          playLikes(false, group);
        });
        const shufBtn = document.createElement('button');
        shufBtn.type = 'button';
        shufBtn.className = 'cp-likes-btn cp-likes-shuffle';
        shufBtn.innerHTML = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M1.5 4.5h2.6c1.2 0 2 .6 2.8 1.9l2.2 3.2c.8 1.3 1.6 1.9 2.8 1.9h2.6"/><path d="M12.2 9.2 14.5 11.5 12.2 13.8"/><path d="M1.5 11.5h2.6c1.2 0 2-.6 2.8-1.9l2.2-3.2c.8-1.3 1.6-1.9 2.8-1.9h2.6"/><path d="M12.2 2.2 14.5 4.5 12.2 6.8"/></svg><span>Shuffle</span>';
        shufBtn.addEventListener('click', (ev) => {
          ev.preventDefault(); ev.stopPropagation();
          playLikes(true, group);
        });
        group.appendChild(playBtn);
        group.appendChild(shufBtn);
      }
      const fill = top.querySelector(':scope > .collectionSection__flexFill');
      if (fill) {
        if (group.nextElementSibling !== fill) top.insertBefore(group, fill);
      } else if (group.parentElement !== top) {
        top.appendChild(group);
      }
      if (group.hidden) group.hidden = false;
    };

    // Hidden routes: /feed → Home, /settings/advertising → /settings.
    const leaveFeed = () => {
      if (/^\/feed(\/|$)/.test(location.pathname)) location.replace('/discover');
      else if (/^\/settings\/advertising(\/|$)/.test(location.pathname)) location.replace('/settings');
    };
    // Runs synchronously after each DOM change (before paint), so hidden sections never
    // render and their artwork is never requested.
    new MutationObserver((records) => {
      hideSections(); leaveFeed(); applyThemeClass(); profileView(); networkView(); settingsView(); syncViewToggles(); unclipSearchOptions(); heroActions(); setupTileGalleries(); syncSearchPlayAll(); syncLikesActions(); widenSystemPlaylist();
      for (const r of records) if (r.addedNodes.length) tagToasts(r.addedNodes);
    })
      .observe(document.documentElement, { childList: true, subtree: true });
    window.addEventListener('popstate', () => { leaveFeed(); profileView(); networkView(); settingsView(); syncSearchPlayAll(); syncLikesActions(); syncViewToggles(); });
    leaveFeed();

    // Artwork: SoundCloud asks for 500×500 almost everywhere. Once an artwork element has a
    // size, ask for the smallest variant that's still sharp at that size on this screen —
    // a decoded 500px image is ~1 MB, 400px ~0.64 MB, 300px ~0.35 MB, 120px ~0.06 MB.
    // Remember the original 500px URL so switching from compact → tiles/waveform upgrades it back.
    const artSizer = new ResizeObserver((entries) => {
      for (const e of entries) if (e.contentRect.width) { artSizer.unobserve(e.target); shrinkArt(e.target); }
    });
    const ART_STEPS = [[120, 't120x120'], [200, 't200x200'], [300, 't300x300'], [400, 'crop']];   // crop = 400×400
    const shrinkArt = (el) => {
      const bg = el.style && el.style.backgroundImage;
      if (!bg || bg.indexOf('i1.sndcdn.com') < 0) return;
      if (bg.indexOf('-t500x500.') >= 0) el.dataset.cpArt500 = bg;
      const base = el.dataset.cpArt500;
      if (!base) return;
      const w = el.getBoundingClientRect().width;
      if (!w) { artSizer.observe(el); return; }   // not laid out yet: retry once it has a size
      const need = w * (window.devicePixelRatio || 2);
      const step = ART_STEPS.find(([px]) => px >= need);
      const next = step ? base.replace('-t500x500.', '-' + step[1] + '.') : base;
      if (el.style.backgroundImage !== next) el.style.backgroundImage = next;
    };
    new MutationObserver((records) => {
      for (const r of records) {
        if (r.type === 'attributes') { shrinkArt(r.target); continue; }
        for (const n of r.addedNodes) {
          if (!(n instanceof Element)) continue;
          shrinkArt(n);
          if (n.firstElementChild) for (const e of n.querySelectorAll('[style*="t500x500"]')) shrinkArt(e);
        }
      }
    }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['style'] });

    // Native Liquid Glass hover play button over tiles (MainView floats a real NSGlassEffectView).
    let hoverTile = null;
    let hoverKey = '';
    const setHoverTile = (next) => {
      if (hoverTile === next) return;
      if (hoverTile) hoverTile.classList.remove('cp-tile-hover');
      hoverTile = next;
      if (hoverTile) hoverTile.classList.add('cp-tile-hover');
    };
    const postHoverPlay = (val) => {
      const k = val && typeof val === 'object' ? `${val.x},${val.y},${val.size},${val.playing}` : String(val);
      if (k === hoverKey) return;
      hoverKey = k;
      try { window.webkit.messageHandlers.cp.postMessage({ hoverPlay: val }); } catch (e) {}
    };
    const clearHoverPlay = () => {
      setHoverTile(null);
      postHoverPlay(null);
    };
    const syncHoverPlay = (tile) => {
      if (!tile || !tile.isConnected || tile.closest('.cp-view-compact')) { clearHoverPlay(); return; }
      const art = tile.querySelector('.playableTile__artwork, .sound__artwork');
      const btn = tile.querySelector('.playableTile__playButton .sc-button-play, .soundTitle__playButton .sc-button-play');
      if (!art || !btn) { clearHoverPlay(); return; }
      const r = art.getBoundingClientRect();
      if (r.width < 80 || r.bottom <= 0 || r.top >= window.innerHeight || r.right <= 0 || r.left >= window.innerWidth) {
        clearHoverPlay();
        return;
      }
      setHoverTile(tile);
      const size = Math.round(Math.min(78, Math.max(58, r.width * 0.44)));
      const x = Math.round((r.left + r.width / 2) * 2) / 2;
      const y = Math.round((r.top + r.height / 2) * 2) / 2;
      const playing = btn.classList.contains('sc-button-pause');
      postHoverPlay({ x, y, size, playing });
    };
    const onTilePointer = (e) => {
      const el = e.target instanceof Element ? e.target : null;
      const art = el && el.closest('.playableTile__artwork, .cp-view-tiles .sound__artwork');
      const tile = art && (art.closest('.playableTile') || art.closest('.sound'));
      if (tile && !tile.closest('.cp-view-compact')) syncHoverPlay(tile);
      else if (hoverTile) clearHoverPlay();
    };
    document.addEventListener('pointerover', onTilePointer, { passive: true });
    document.addEventListener('pointermove', onTilePointer, { passive: true });
    document.documentElement.addEventListener('pointerleave', () => {
      if (hoverTile) postHoverPlay('leave');
    }, { passive: true });
    window.addEventListener('scroll', clearHoverPlay, { capture: true, passive: true });
    window.addEventListener('resize', clearHoverPlay, { passive: true });
    window.addEventListener('blur', clearHoverPlay);
    window.addEventListener('popstate', clearHoverPlay);

    // Pre-fetch the Now Playing track page (and adjacent Up Next tracks if rendered) so
    // opening Now Playing or swiping Next/Previous renders immediately from warm cache.
    const prefetched = new Set();
    const PREFETCH_SKIP = /^\/(you|discover|search|feed|settings|stream|upload|charts|stations|pages|n)(\/|$)/;
    const prefetchTrackPage = (rawPath, art) => {
      const path = normHref(rawPath);
      if (!path || PREFETCH_SKIP.test(path) || path.split('/').filter(Boolean).length < 2) return;
      if (art) { const img = new Image(); img.src = bigArt(art); }
      if (prefetched.has(path)) return;
      if (prefetched.size >= 60) prefetched.delete(prefetched.values().next().value);
      prefetched.add(path);
      const url = '/n' + path + '?theme=' + (themeDark ? 'dark' : 'light');
      fetch(url, { credentials: 'include' }).catch(() => {});
    };
    let lastPrefetchedTrack = '';
    const prefetchForState = (s) => {
      const p = normHref(s && s.trackPath);
      if (!p || p === lastPrefetchedTrack) return;
      lastPrefetchedTrack = p;
      prefetchTrackPage(p, s.artwork);
      // Also pre-fetch the previous and next tracks if Up Next items are in the DOM.
      const items = [...document.querySelectorAll('.queue__itemWrapper')];
      if (!items.length) return;
      let idx = items.findIndex((el) => el.querySelector('.queueItemView.m-playing'));
      if (idx < 0) idx = items.findIndex((el) => normHref((el.querySelector('.queueItemView__title') || {}).getAttribute?.('href')) === p);
      if (idx < 0) return;
      for (const offset of [1, -1]) {
        const adj = items[idx + offset];
        if (!adj) continue;
        const a = adj.querySelector('.queueItemView__title');
        const art = bgURL(adj.querySelector('.image span, .sc-artwork span'));
        if (a) prefetchTrackPage(a.getAttribute('href'), art);
      }
    };

    // Track pending Next clicks so SoundCloud's intermediate reset to 0:00 on the outgoing
    // track isn't reported to the native player bar before the next track's metadata arrives.
    let pendingNextFrom = '', pendingNextUntil = 0, fastReportTimer = 0;
    const startFastReport = (ms = 1500) => {
      if (fastReportTimer) clearInterval(fastReportTimer);
      const end = Date.now() + ms;
      fastReportTimer = setInterval(() => {
        CP.report();
        if (Date.now() >= end) { clearInterval(fastReportTimer); fastReportTimer = 0; }
      }, 30);
    };

    const CP = window.CP = {
      media: null,
      debugErrors,
      volume: INITIAL_VOLUME,
      last: '',
      clickHoverPlay() {
        const btn = hoverTile && hoverTile.querySelector('.playableTile__playButton .sc-button-play, .soundTitle__playButton .sc-button-play');
        if (!btn) return;
        btn.click();
        setTimeout(() => { if (hoverTile) syncHoverPlay(hoverTile); }, 80);
        setTimeout(() => { if (hoverTile) syncHoverPlay(hoverTile); }, 250);
      },
      clearHoverTile() { clearHoverPlay(); },
      // The pointer left the native play button: if it is back on the same tile, post again
      // (postHoverPlay drops repeats, so a returning pointermove alone would send nothing).
      resyncHoverTile() {
        hoverKey = '';
        if (hoverTile && hoverTile.isConnected && hoverTile.matches(':hover')) syncHoverPlay(hoverTile);
        else clearHoverPlay();
      },

      setCustomCSS(css) { userStyle.textContent = css; mountStyles(); },
      setTheme(dark, css, frameCSS) {
        themeDark = dark; themeStyle.textContent = css; applyThemeClass();
        rethemeFrames();
        for (const f of document.querySelectorAll('iframe')) {
          try { f.contentWindow.CPFrame && f.contentWindow.CPFrame.setCSS(frameCSS); } catch (e) {}
        }
      },
      setVolume(v) { CP.volume = v; if (CP.media) CP.media.volume = v; },

      // In-app navigation without a page reload (a reload would stop playback):
      // SoundCloud's router handles clicks on same-site links.
      // replace: the navigation replaces the current history entry instead of adding one
      // (used when the Now Playing page follows playback, so Back returns to where it started).
      open(path, replace) {
        if (location.pathname + location.search === path) return;
        if (replace) { replaceNextPush = true; setTimeout(() => { replaceNextPush = false; }, 2000); }
        const a = document.createElement('a');
        a.href = path;
        a.style.display = 'none';
        (document.getElementById('content') || document.body).appendChild(a);
        a.click();
        a.remove();
      },

      state() {
        const meta = navigator.mediaSession && navigator.mediaSession.metadata;
        const m = CP.media;
        const title = titleOf('.playbackSoundBadge__titleLink') || (meta && meta.title) || '';
        const artist = titleOf('.playbackSoundBadge__lightLink') || (meta && meta.artist) || '';

        let art = bgURL($('.playbackSoundBadge .image span, .playbackSoundBadge .sc-artwork span'));
        if (!art && meta && meta.artwork && meta.artwork.length) art = meta.artwork[meta.artwork.length - 1].src;

        const domPos = toSeconds(textOf('.playbackTimeline__timePassed span[aria-hidden="true"]'));
        const domDur = toSeconds(textOf('.playbackTimeline__duration span[aria-hidden="true"]'));
        // Only trust the captured media element if its duration matches the visible track.
        const useMedia = m && isFinite(m.duration) && m.duration > 0 && (domDur === 0 || Math.abs(m.duration - domDur) < 5);

        const playBtn = $('.playControls__play');
        const likeBtn = $('.playbackSoundBadge__like');
        const shuffleBtn = $('button.shuffleControl');
        const repeatBtn = $('button.repeatControl');
        const repeatCls = repeatBtn ? repeatBtn.className + ' ' + (repeatBtn.parentElement || {}).className : '';
        return {
          hasTrack: !!title,
          title, artist,
          trackPath: hrefOf('.playbackSoundBadge__titleLink'),
          artistPath: hrefOf('.playbackSoundBadge__lightLink'),
          profilePath: hrefOf('.header__userNavUsernameButton'),
          artwork: art ? bigArt(art) : '',
          playing: playBtn ? playBtn.classList.contains('playing') : !!(m && !m.paused),
          position: round(useMedia ? m.currentTime : domPos),
          duration: round(useMedia ? m.duration : domDur),
          liked: !!(likeBtn && likeBtn.classList.contains('sc-button-selected')),
          shuffle: !!(shuffleBtn && /\b(m-shuffling|sc-button-selected|m-active)\b/.test(shuffleBtn.className)),
          repeat: /\bm-one\b/.test(repeatCls) ? 'one' : /\bm-all\b/.test(repeatCls) ? 'all' : 'none',
          queueVisible: !!$('.playControls.m-queueVisible'),
          albumPath: (() => {   // for "Go to Album" in the player's menu; looked up once per track
            const tp = normHref(hrefOf('.playbackSoundBadge__titleLink'));
            if (!tp) return '';
            if (!albumCache.has(tp)) { albumFor(tp).then(() => CP.report()); return ''; }
            const a = albumCache.get(tp);
            return a ? a.path : '';
          })(),
          volume: round((CP.volume != null ? CP.volume : (m ? m.volume : 1)) * 100) / 100,
        };
      },

      cmd(name, arg) {
        const click = (sel) => { const el = $(sel); if (el) el.click(); };
        switch (name) {
          case 'toggle':  click('.playControls__play'); break;
          case 'next':
            pendingNextFrom = normHref(hrefOf('.playbackSoundBadge__titleLink'));
            pendingNextUntil = Date.now() + 2000;
            click('.playControls__next');
            startFastReport(1800);
            break;
          case 'prev':
            pendingNextFrom = '';
            pendingNextUntil = 0;
            click('.playControls__prev');
            startFastReport(1500);
            break;
          case 'like':    click('.playbackSoundBadge__like'); break;
          case 'shuffle': click('button.shuffleControl'); break;
          case 'repeat':  click('button.repeatControl'); break;
          case 'queue':   click('.playbackSoundBadge__showQueue'); break;
          case 'seek':    CP.seek(arg); break;
          case 'volume':  CP.setVolume(arg); break;
        }
        setTimeout(CP.report, 60);
      },

      // Seek by "clicking" SoundCloud's own progress bar so its player logic stays in sync;
      // fall back to the raw media element.
      seek(f) {
        const bar = $('.playbackTimeline__progressWrapper');
        const r = bar && bar.getBoundingClientRect();
        if (r && r.width > 0) {
          const opts = { bubbles: true, cancelable: true, clientX: r.left + r.width * f, clientY: r.top + r.height / 2, button: 0 };
          for (const t of ['mousedown', 'mouseup', 'click']) bar.dispatchEvent(new MouseEvent(t, opts));
        } else if (CP.media && isFinite(CP.media.duration)) {
          CP.media.currentTime = CP.media.duration * f;
        }
      },

      albumFor,
      report() {
        if (silentTransition) return;
        try {
          const s = CP.state();
          const curPath = normHref(s.trackPath);
          if (pendingNextFrom) {
            if (curPath === pendingNextFrom && Date.now() < pendingNextUntil) return;
            pendingNextFrom = '';
            pendingNextUntil = 0;
          }
          prefetchForState(s);
          const key = JSON.stringify(s);
          if (key === CP.last) return;
          CP.last = key;
          window.webkit.messageHandlers.cp.postMessage(s);
        } catch (e) {}
      },
    };

    setInterval(CP.report, 500);
    for (const ev of ['play', 'pause', 'ended', 'seeked']) {
      document.addEventListener(ev, () => setTimeout(CP.report, 50), true);
    }
    """#

    static let customCSSTemplate = """
    /* CloudPlayer custom CSS: applied on top of SoundCloud and the built-in debloat.
       Save, then View → Reload Custom CSS (⇧⌘R) in CloudPlayer.
       Find selectors with right-click → Inspect Element in the main window. */

    /* Example: hide comments on track pages */
    /* .commentsList, .commentForm { display: none !important; } */

    /* Example: hide the whole right sidebar */
    /* .l-sidebar-right { display: none !important; } */
    """
}

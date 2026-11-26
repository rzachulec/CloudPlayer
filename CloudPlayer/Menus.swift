import AppKit
import SwiftUI
import WebKit

/// Native menus for the web content.
///
/// - Right-clicking a track, playlist, station or profile shows a native menu with that item's
///   actions (play, like, follow, everything from SoundCloud's own "More" menu, go to, copy, share).
/// - SoundCloud's own dropdowns ("More" on tiles and rows; filter dropdowns on Albums, Playlists
///   and Search; "More actions" and "Sort" on track pages) open as native menus instead of HTML ones.
/// - Anywhere else, WebKit's standard menu, minus the browser-only items (see `PageWebView`).
///
/// The page side (`js`) reads SoundCloud's menu by opening it invisibly, sends the entries as
/// `{menu: {id, items, at}}`, and gets the choice back through `CPMenu.run(id, key)`, which
/// opens SoundCloud's menu invisibly again and clicks the chosen entry.
enum Menus {
    /// Runs in the main page (from the bootstrap) and in the track-page iframes (from the frame script).
    static let js = #"""
    (() => {
    if (window.CPMenu) return;
    const WEBI = window !== window.top;   // SoundCloud's newer app (track pages), in an iframe
    const post = (m) => { try { window.webkit.messageHandlers.cp.postMessage(m); } catch (e) {} };
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const until = async (fn, ms = 800) => {
      for (const t0 = Date.now(); Date.now() - t0 < ms; await sleep(16)) { const v = fn(); if (v) return v; }
      return fn();
    };
    const shown = (el) => !!el && el.getClientRects().length > 0;
    const label = (el) => (el.getAttribute('aria-label') || el.getAttribute('title') || el.textContent || '').trim().replace(/\s+/g, ' ');

    // While SoundCloud's own menu is open just to be read (or to click one of its entries), hide it.
    const style = document.createElement('style');
    style.textContent = 'html.cp-quiet :is(.dropdownMenu, .MuiPopover-root, .MuiMenu-root, .MuiPopper-root, .MuiBackdrop-root) ' +
      '{ opacity: 0 !important; pointer-events: none !important; transition: none !important; animation: none !important; }';
    document.documentElement.appendChild(style);
    const quiet = (on) => document.documentElement.classList.toggle('cp-quiet', on);

    // Native titles and SF Symbols for SoundCloud's menu entries.
    const KINDS = {
      repost: ['Repost', 'arrow.2.squarepath'],
      queue: ['Add to Up Next', 'text.line.first.and.arrowtriangle.forward'],
      addtoset: ['Add to Playlist…', 'text.badge.plus'],
      startstation: ['Go to Station', 'dot.radiowaves.left.and.right'],
      download: ['Download', 'arrow.down.circle'],
      edit: ['Edit…', 'pencil'],
      delete: ['Delete…', 'trash'],
      share: ['Share…', 'square.and.arrow.up'],
      copylink: ['Copy Link', 'link'],
      report: null,   // dropped
    };
    const BY_LABEL = { 'add to next up': 'queue', 'go to station': 'startstation', 'station': 'startstation',
      'add to playlist': 'addtoset', 'repost': 'repost', 'unrepost': 'repost', 'copy link': 'copylink',
      'share': 'share', 'download': 'download', 'edit': 'edit', 'delete': 'delete', 'report': 'report' };
    const kindOf = (el) => {
      const m = String(el.className || '').match(/\bsc-button-(repost|share|copylink|queue|addtoset|startstation|download|edit|delete|report)\b/);
      return m ? m[1] : BY_LABEL[label(el).toLowerCase()] || null;
    };

    // ── Reading SoundCloud's menus ────────────────────────────────────────────────────────
    // A source opens one of SoundCloud's menus (resolving to its element), lists its entries, closes it.
    const classicSource = (btn) => ({
      // Classic dropdowns ("More" and .sc-button-dropdown selects) open and close synchronously on click.
      async open() {
        btn.click();
        const id = btn.getAttribute('aria-owns');
        return (id && document.getElementById(id)) || [...document.querySelectorAll('.dropdownMenu')].pop() || null;
      },
      entries: (c) => {
        const more = [...c.querySelectorAll('.moreActions__button')];
        if (more.length) return more;
        const links = [...c.querySelectorAll('.linkMenu__link, [role^="menuitem"]')];
        return links.length ? links : [...c.querySelectorAll('a, button')].filter(shown);
      },
      async close(c) {
        if (c && c.isConnected) btn.click();
        if (c && c.isConnected) document.body.click();
        if (btn && btn.blur) btn.blur();
      },
    });
    const searchFilterSource = (btn) => ({
      // Search filter options live directly inside .searchOptions__filterWrapper.
      async open() { return btn.closest('.searchOptions__filterWrapper'); },
      entries: (c) => [...c.querySelectorAll('.searchOptions__filter')],
      async close() { if (btn && btn.blur) btn.blur(); },
    });
    const muiSource = (btn) => ({
      // MUI menus render after a tick and close (with a short exit transition) on Escape.
      async open() {
        btn.click();
        return until(() => {
          const ms = [...document.querySelectorAll('[role="menu"]')];
          return (btn.id && ms.find((m) => m.getAttribute('aria-labelledby') === btn.id)) || ms.pop();
        });
      },
      entries: (c) => [...c.querySelectorAll('[role^="menuitem"]')],
      close: (c) => closeMenu(c, btn),
    });
    const closeMenu = async (c, btn) => {
      if (c && c.isConnected) {
        c.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true, cancelable: true }));
        await until(() => !c.isConnected, 600);
        if (c.isConnected) {
          const bd = c.closest('.MuiModal-root, .MuiPopover-root');
          const backdrop = bd && bd.querySelector('.MuiBackdrop-root');
          if (backdrop) { backdrop.click(); await until(() => !c.isConnected, 400); }
          else if (!WEBI) document.body.click();
        }
      }
      if (btn && btn.blur) btn.blur();
    };
    // A menu SoundCloud opened in response to one of its own entries (e.g. Repost → with caption).
    const openedSource = (c) => ({
      async open() { return c.isConnected ? c : null; },
      entries: (m) => [...m.querySelectorAll('[role^="menuitem"], .moreActions__button, button, a[href]')]
        .filter((e, i, all) => shown(e) && !all.some((o) => o !== e && o.contains(e))),
      close: (m) => closeMenu(m, null),
    });
    const sourceFor = (btn) => {
      if (btn.matches('.searchOptions__filterCategory')) return searchFilterSource(btn);
      if (btn.matches('.sc-button-more, .sc-button-dropdown')) return classicSource(btn);
      return muiSource(btn);
    };

    const toItem = (e, i) => {
      const isOption = e.matches('.linkMenu__link, .searchOptions__filter');
      const kind = isOption ? null : kindOf(e);
      if (kind && KINDS[kind] === null) return null;
      const def = kind && KINDS[kind];
      const text = (e.textContent || '').trim().replace(/\s+/g, ' ') || label(e);
      let t = def ? def[0] : text;
      if (kind === 'repost' && /^unrepost/i.test(label(e))) t = 'Unrepost';
      const on = !kind && (e.getAttribute('aria-checked') === 'true' || e.getAttribute('aria-selected') === 'true' ||
        e.classList.contains('Mui-selected') || e.classList.contains('sc-button-selected') ||
        e.classList.contains('active') || !!e.closest('.linkMenu__activeItem'));
      return { t, s: def ? def[1] : null, on, k: 'e' + i, kind, i, lbl: label(e) };
    };

    const read = async (src) => {
      quiet(true);
      try {
        const c = await src.open();
        if (!c) return null;   // not a menu after all: leave whatever opened visible
        const out = src.entries(c).map(toItem).filter(Boolean);
        await src.close(c);
        return out;
      } finally { quiet(false); }
    };

    // Opens SoundCloud's menu invisibly again and clicks the chosen entry.
    const choose = async (src, it, at) => {
      quiet(true);
      let done = true;
      try {
        const c = await src.open();
        if (!c) return;
        const es = src.entries(c);
        const e = (es[it.i] && label(es[it.i]) === it.lbl) ? es[it.i] : es.find((x) => label(x) === it.lbl);
        if (!e) { await src.close(c); return; }
        const before = new Set(document.querySelectorAll('.dropdownMenu, [role="menu"]'));
        e.click();
        await sleep(80);
        const sub = [...document.querySelectorAll('.dropdownMenu, [role="menu"]')].find((m) => !before.has(m) && shown(m));
        if (sub) {
          // A second-level menu: show that natively too; closing it closes both.
          done = false;
          const subSrc = openedSource(sub);
          const items = subSrc.entries(sub).map(toItem).filter(Boolean);
          const finish = async () => { await subSrc.close(sub); if (c.isConnected) await src.close(c); quiet(false); };
          const acts = {};
          for (const s of items) acts[s.k] = async () => {
            const es2 = subSrc.entries(sub);
            const e2 = es2.find((x) => label(x) === s.lbl);
            if (e2) e2.click();
            await sleep(80);
            await finish();
          };
          present(items, acts, at, finish);
          return;
        }
        if (c.isConnected) await src.close(c);
      } finally { if (done) quiet(false); }
    };

    // ── Presenting ────────────────────────────────────────────────────────────────────────
    let seq = 0, current = null;   // { id, acts: {key: fn}, dismiss: fn }
    // Where this frame sits in the web view (menus are positioned in its coordinates).
    const origin = () => {
      let x = 0, y = 0;
      for (let w = window; w !== w.top && w.frameElement; w = w.parent) {
        const r = w.frameElement.getBoundingClientRect(); x += r.left; y += r.top;
      }
      return { x, y };
    };
    const rectOf = (el) => {
      const r = el && el.getBoundingClientRect();
      if (!r || (!r.width && !r.height)) return null;
      const o = origin();
      return { x: o.x + r.left, y: o.y + r.top, w: r.width, h: r.height };
    };
    const below = (el) => {
      const r = rectOf(el);
      return r ? { x: r.x, y: r.y + r.h + 4 } : null;
    };
    const present = (items, acts, at, dismiss) => {
      if (current && current.dismiss) current.dismiss();
      current = { id: ++seq, acts, dismiss };
      post({ menu: { id: current.id, at: at || null,
        items: items.map((it) => it.sep ? { sep: 1 } : (({ fn, kind, i, lbl, ...rest }) => rest)(it)) } });
    };
    window.CPMenu = {
      run(id, key) {
        if (!current || current.id !== id) return;
        const c = current; current = null;
        const f = key && c.acts[key];
        if (f) f(); else if (c.dismiss) c.dismiss();
      },
    };

    // ── Links ─────────────────────────────────────────────────────────────────────────────
    const RESERVED = /^(you|discover|pages|search|tags|stream|upload|settings|n|charts|feed|messages|notifications|terms-of-use|imprint|popular|signin|logout|mobile|apps|jobs|press|creators|artists|premium|go|getstarted)$/;
    const SC_HOST = /^(www\.|m\.)?soundcloud\.com$/;
    const pathOf = (a) => {
      const h = a.getAttribute('href');
      if (!h || h === '#' || h.startsWith('javascript:')) return null;
      try {
        const u = new URL(h, location.href);
        if (!SC_HOST.test(u.host)) return null;
        return u.pathname.replace(/^\/n(?=\/)/, '').replace(/\/$/, '') || '/';
      } catch (e) { return null; }
    };
    const segs = (p) => p.split('/').filter(Boolean);
    const isObject = (p) => p && (/^\/discover\/sets\/./.test(p) || (segs(p).length >= 2 && !RESERVED.test(segs(p)[0])));
    const isProfile = (p) => p && segs(p).length === 1 && !RESERVED.test(segs(p)[0]);
    const here = () => location.pathname.replace(/^\/n(?=\/)/, '').replace(/\/$/, '');
    const objectName = (p) => /^\/discover\/sets\//.test(p) ? 'Station' : /\/sets\//.test(p) ? 'Playlist' : 'Track';
    // The item's own page (track / playlist / station) and its artist, from its links.
    const linksIn = (el) => {
      let obj = null, prof = null, profName = '';
      for (const a of el.querySelectorAll('a[href]')) {
        const p = pathOf(a);
        if (!obj && isObject(p)) obj = p;
        if (!prof && isProfile(p)) { prof = p; profName = (a.textContent || '').trim(); }
      }
      if (!obj && (el.closest(HERO) || el.matches(HERO))) obj = here();
      return { obj, prof, profName };
    };
    const shareItems = (url) => [{ sep: 1 }, { t: 'Copy Link', s: 'link', copy: url }, { share: url }];

    // ── Items ─────────────────────────────────────────────────────────────────────────────
    const MORE = WEBI ? 'button[aria-haspopup="true"][aria-label^="More actions"]' : '.sc-button-more';
    // The largest element around `t` that holds exactly one (visible) "More" button: the whole
    // tile / row / header, not just its button bar.
    const itemRoot = (t) => {
      let found = null;
      for (let e = t; e && e !== document.body && e !== document.documentElement; e = e.parentElement) {
        if (e.getBoundingClientRect().height > innerHeight * 0.8) break;   // that's the page, not an item
        const ms = [...e.querySelectorAll(MORE)].filter(shown);
        if (ms.length > 1) break;
        if (ms.length === 1) found = { el: e, more: ms[0] };
      }
      return found;
    };
    const HERO = '.l-listen-hero, .l-hero-banner, section[aria-label="Track header"]';
    const act = (t, s, fn) => ({ t, s, fn });
    const isCompactRow = (el) => !WEBI && !!el && !!el.closest('.cp-view-compact')
      && (el.matches('.soundList__item, .searchList__item, .historicalPlays__item, .badgeList__item, .tagsList__item')
        || !!el.closest('.soundList__item, .searchList__item, .historicalPlays__item, .badgeList__item, .tagsList__item'));

    // Playlist/set rows in SoundCloud's compact lists (e.g. Search) don't have a .sc-button-more
    // button — their actions (queue, repost, share, copy link, edit, delete) are inline buttons
    // that Theme.nativeCSS hides. Inject a synthetic ••• button so every row has Like + •••.
    const ensureRowMoreButtons = () => {
      if (WEBI) return;
      for (const group of document.querySelectorAll(':is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound .soundActions .sc-button-group')) {
        if (group.querySelector('.sc-button-more') || !group.querySelector('.sc-button')) continue;
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'sc-button-more sc-button-secondary sc-button sc-button-small sc-button-responsive sc-button-icon cp-more';
        btn.setAttribute('aria-label', 'More');
        btn.setAttribute('title', 'More');
        btn.innerHTML = '<div><svg viewBox="0 0 16 16" aria-hidden="true"></svg></div>';
        group.appendChild(btn);
      }
    };
    if (!WEBI) {
      let moreQueued = false;
      new MutationObserver(() => {
        if (moreQueued) return;
        moreQueued = true;
        requestAnimationFrame(() => { moreQueued = false; ensureRowMoreButtons(); });
      }).observe(document.documentElement, { childList: true, subtree: true });
      ensureRowMoreButtons();
    }

    // Collect row actions hidden by our compact-row CSS (Repost, Add to Up Next, Edit, etc.),
    // excluding Like (shown as its own button) and Share/Copy Link (handled natively).
    const hiddenRowActions = (el, seen) => {
      const out = [];
      if (WEBI || !el) return out;
      for (const b of el.querySelectorAll('.soundActions .sc-button')) {
        if (b.matches('.sc-button-like, .sc-button-more, .cp-more') || shown(b)) continue;
        const kind = kindOf(b);
        if (!kind || KINDS[kind] === null || kind === 'share' || kind === 'copylink' || seen.has(kind)) continue;
        seen.add(kind);
        const def = KINDS[kind];
        let t = def[0];
        if (kind === 'repost' && (b.classList.contains('sc-button-selected') || /^unrepost/i.test(label(b)))) t = 'Unrepost';
        out.push({ t, s: def[1], kind, fn: () => b.click() });
      }
      return out;
    };

    const contextMenu = async (root, link) => {
      // Groups, like Apple Music: play · library · go to · copy/share.
      const play = [], lib = [], go = [], acts = {};
      let obj = null, prof = null, profName = '';
      let ownLike = false;   // Like added from the item's heart button
      if (root) {
        const el = root.el;
        const pb = el.querySelector(WEBI ? 'button[aria-label="Play"], button[aria-label="Pause"]' : '.sc-button-play');
        if (pb) {
          const pause = /pause/i.test(label(pb)) || pb.classList.contains('sc-button-pause');
          play.push(act(pause ? 'Pause' : 'Play', pause ? 'pause.fill' : 'play.fill', () => pb.click()));
        }
        // Compact rows already have Like as a dedicated button on the row; omit it from the menu.
        if (!isCompactRow(el)) {
          const like = el.querySelector(WEBI ? 'button[aria-label="Like"], button[aria-label="Unlike"]' : '.sc-button-like');
          if (like) {
            const liked = WEBI ? label(like) === 'Unlike' : like.classList.contains('sc-button-selected');
            lib.push(act(liked ? 'Unlike' : 'Like', liked ? 'heart.slash' : 'heart', () => like.click()));
            ownLike = true;
          }
        }
        ({ obj, prof, profName } = linksIn(el));
        if (WEBI) {   // track pages have these as their own buttons, not in "More actions"
          const q = (sel) => [...el.querySelectorAll(sel)].find(shown);
          const rp = q('button[aria-label="Repost"], button[aria-label="Unrepost"]');
          if (rp) lib.push(act(label(rp), KINDS.repost[1], () => rp.click()));
          const ap = q('button[aria-label="Add to playlist"]');
          if (ap) lib.push(act(KINDS.addtoset[0], KINDS.addtoset[1], () => ap.click()));
        }
        const seen = new Set();
        if (!root.more.classList.contains('cp-more')) {
          const src = sourceFor(root.more);
          for (const it of (await read(src)) || []) {
            if (it.kind) seen.add(it.kind);
            // Some "More" menus (e.g. Next up rows) list Like too: keep only the one added above.
            if (ownLike && /^(un)?liked?$/i.test(it.t || '')) continue;
            if ((obj || prof) && (it.kind === 'share' || it.kind === 'copylink')) continue;   // native ones below
            it.fn = () => choose(src, it, null);
            (it.kind === 'queue' ? play : it.kind === 'startstation' ? go : lib).push(it);
          }
        }
        for (const it of hiddenRowActions(el, seen)) {
          (it.kind === 'queue' ? play : it.kind === 'startstation' ? go : lib).push(it);
        }
      } else if (link) {
        const p = pathOf(link);
        if (isObject(p)) obj = p;
        else if (isProfile(p)) { prof = p; profName = (link.textContent || '').trim(); }
        else if (p) go.push({ t: 'Open', s: 'arrow.right.circle', open: p }, ...shareItems('https://soundcloud.com' + p));
        else if (/^https?:/.test(link.href)) go.push({ t: 'Open in Browser', s: 'safari', browser: link.href }, ...shareItems(link.href));
      }
      // Follow / Unfollow: on the item, or on a profile card (which has no "More" menu).
      const card = root ? root.el : link && link.closest('li, .userBadge, .userBadgeListItem');
      const follow = !WEBI && card && card.querySelector('.sc-button-follow');
      if (follow) {
        const on = follow.classList.contains('sc-button-selected');
        lib.push(act(label(follow) || (on ? 'Unfollow' : 'Follow'), on ? 'person.badge.minus' : 'person.badge.plus', () => follow.click()));
      }
      if (obj && obj !== here()) go.push({ t: 'Go to ' + objectName(obj), s: 'arrow.right.circle', open: obj });
      // A track on an album: "Go to Album" (looked up via the main page, cached per track; if the
      // lookup takes longer than a moment the menu opens without it, and has it next time).
      const trackPath = obj && objectName(obj) === 'Track' ? obj : null;
      if (trackPath) {
        let lookup = null;
        try { lookup = window.top.CP && window.top.CP.albumFor ? window.top.CP.albumFor(trackPath) : null; } catch (e) {}
        const album = lookup ? await Promise.race([lookup, sleep(450).then(() => null)]) : null;
        if (album && album.path && album.path !== here()) {
          go.push({ t: 'Go to Album', s: 'square.stack', open: album.path });
        }
      }
      if (prof && prof !== here()) go.push({ t: profName && profName.length <= 40 ? 'Go to ' + profName : 'Go to Profile', s: 'person.crop.circle', open: prof });
      const p = obj || prof;
      const items = [...play, { sep: 1 }, ...lib, { sep: 1 }, ...go, ...(p ? shareItems('https://soundcloud.com' + p) : [])];
      items.forEach((it, n) => { if (it.fn) { it.k = 'a' + n; acts[it.k] = it.fn; } });
      present(items, acts, null, null);
    };

    // A click on one of SoundCloud's menu buttons opens the native menu instead.
    const dropdownMenu = async (btn) => {
      const at = below(btn);
      const synthetic = btn.classList.contains('cp-more');
      const isMore = btn.matches('.sc-button-more') || (WEBI && btn.matches('button[aria-label^="More actions"]'));
      const src = synthetic ? null : sourceFor(btn);
      const entries = synthetic ? [] : await read(src);
      if (!entries) return;
      const root = isMore ? itemRoot(btn) : null;
      const seen = new Set(entries.map((it) => it.kind).filter(Boolean));
      const extras = root ? hiddenRowActions(root.el, seen) : [];
      const l = root && linksIn(root.el);
      const p = l && (l.obj || l.prof);
      const base = p ? entries.filter((it) => it.kind !== 'share' && it.kind !== 'copylink') : entries;
      const acts = {};
      for (const it of entries) acts[it.k] = () => choose(src, it, at);
      extras.forEach((it, n) => { it.k = 'x' + n; acts[it.k] = it.fn; });
      const items = [...base, ...extras, ...(p ? shareItems('https://soundcloud.com' + p) : [])];
      if (!items.length) items.push({ t: 'No Actions', off: 1 });
      present(items, acts, at, null);
    };
    const SHARE_BUTTON = WEBI ? 'button[aria-label="Share"]' : '.sc-button-share';
    const sharePathFor = (btn) => {
      const cur = here();
      if (WEBI) return cur;
      if (btn.closest('.l-user-hero, .userInfoBar, .profileHeader')) {
        const s = segs(cur);
        return (s.length >= 1 && !RESERVED.test(s[0])) ? '/' + s[0] : cur;
      }
      if (btn.closest(HERO + ', .listenEngagement__actions, .systemPlaylistDetails__controls')) return cur;
      const root = itemRoot(btn);
      if (root) {
        const { obj, prof } = linksIn(root.el);
        if (obj || prof) return obj || prof;
      }
      return cur;
    };
    const MENU_BUTTON = WEBI ? 'button[aria-haspopup="true"]' : '.sc-button-more, .sc-button-dropdown, .searchOptions__filterCategory';
    window.addEventListener('click', (ev) => {
      if (!ev.isTrusted || !(ev.target instanceof Element)) return;   // our own clicks go through
      const shareBtn = ev.target.closest(SHARE_BUTTON);
      if (shareBtn) {
        const p = sharePathFor(shareBtn);
        if (p && p !== '/') {
          ev.preventDefault(); ev.stopImmediatePropagation();
          post({ share: { url: 'https://soundcloud.com' + p, rect: rectOf(shareBtn) } });
          if (shareBtn.blur) shareBtn.blur();
          return;
        }
      }
      const btn = ev.target.closest(MENU_BUTTON);
      if (!btn) return;
      ev.preventDefault(); ev.stopImmediatePropagation();
      dropdownMenu(btn);
    }, true);

    window.addEventListener('contextmenu', (ev) => {
      const t = ev.target instanceof Element ? ev.target : ev.target && ev.target.parentElement;
      if (!t || t.closest('input, textarea, [contenteditable]:not([contenteditable="false"])')) return;   // text menu
      const sel = window.getSelection();
      if (sel && !sel.isCollapsed && sel.toString().trim()) return;   // Copy / Look Up
      const root = itemRoot(t);
      const link = t.closest('a[href]');
      if (!root && !link) return;   // WebKit's page menu (Back, Reload, Inspect Element)
      ev.preventDefault(); ev.stopImmediatePropagation();
      contextMenu(root, link);
    }, true);

    // Debug: build the menus without a real click.
    window.CPMenu.debugContext = (el) => contextMenu(itemRoot(el), el.closest('a[href]'));
    window.CPMenu.debugDropdown = (btn) => dropdownMenu(btn);
    })();
    """#
}

// MARK: - Native side

extension WebPlayer {
    /// Shows a menu the page sent: `{id, at: {x, y} | null (mouse), items: [...]}`. Items:
    /// `{t, s, k, on}` (returned to the page), `{t, s, open: path}`, `{t, s, copy: url}`,
    /// `{t, s, browser: url}`, `{share: url}`, `{sep: 1}`.
    func presentMenu(_ spec: [String: Any], frame: WKFrameInfo) {
        guard let id = spec["id"] as? Int, let items = spec["items"] as? [[String: Any]] else { return }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "cpMenuDump") {
            if let data = try? JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: Self.debugDir.appendingPathComponent("debug-menu.json"))
            }
            finishMenu(id, key: nil, frame: frame)
            return
        }
        #endif
        let point: NSPoint
        if let at = spec["at"] as? [String: Any], let x = (at["x"] as? NSNumber)?.doubleValue,
           let y = (at["y"] as? NSNumber)?.doubleValue {
            let z = webView.pageZoom
            point = NSPoint(x: x * z, y: webView.isFlipped ? y * z : webView.bounds.height - y * z)
        } else if let window = webView.window {
            point = webView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        } else { return }
        let menu = PageMenu(player: self, items: items, anchor: point)
        // Pop up after the message handler returns (popUp runs its own event loop).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            menu.menu.popUp(positioning: nil, at: point, in: self.webView)
            self.finishMenu(id, key: menu.chosen, frame: frame)
        }
    }

    fileprivate func finishMenu(_ id: Int, key: String?, frame: WKFrameInfo) {
        let js = "window.CPMenu && CPMenu.run(\(id), \(key.map(Injected.js) ?? "null"))"
        webView.evaluateJavaScript(js, in: frame, in: .page, completionHandler: { _ in })
    }

    func copyLink(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        showToast("Link copied to clipboard", duration: 3)
    }

    /// Shows the native macOS Share sheet (`NSSharingServicePicker`) anchored to a Share button.
    func presentShare(_ spec: [String: Any]) {
        guard let raw = spec["url"] as? String, let url = URL(string: raw) else { return }
        let z = webView.pageZoom
        let rect: NSRect
        if let r = spec["rect"] as? [String: Any],
           let x = (r["x"] as? NSNumber)?.doubleValue,
           let y = (r["y"] as? NSNumber)?.doubleValue,
           let w = (r["w"] as? NSNumber)?.doubleValue,
           let h = (r["h"] as? NSNumber)?.doubleValue {
            let ry = webView.isFlipped ? y * z : webView.bounds.height - (y + h) * z
            rect = NSRect(x: x * z, y: ry, width: max(w * z, 1), height: max(h * z, 1))
        } else if let window = webView.window {
            let p = webView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            rect = NSRect(origin: p, size: NSSize(width: 1, height: 1))
        } else { return }
        let edge: NSRectEdge = webView.isFlipped ? .maxY : .minY
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSSharingServicePicker(items: [url]).show(relativeTo: rect, of: self.webView, preferredEdge: edge)
        }
    }

    /// Shows the native macOS Share sheet anchored at a point in `webView` coordinates.
    func presentShare(url: URL, at point: NSPoint) {
        let rect = NSRect(origin: point, size: NSSize(width: 1, height: 1))
        let edge: NSRectEdge = webView.isFlipped ? .maxY : .minY
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSSharingServicePicker(items: [url]).show(relativeTo: rect, of: self.webView, preferredEdge: edge)
        }
    }

    /// Shows the native macOS Share sheet anchored at the current mouse position (for native SwiftUI menus).
    func presentShareAtMouse(_ url: URL) {
        let screenPoint = NSEvent.mouseLocation
        let window = NSApp.windows.first { $0.isVisible && $0.frame.contains(screenPoint) } ?? webView.window
        guard let window, let view = window.contentView else { return }
        let winPoint = window.convertPoint(fromScreen: screenPoint)
        let pt = view.convert(winPoint, from: nil)
        let rect = NSRect(origin: pt, size: NSSize(width: 1, height: 1))
        let edge: NSRectEdge = view.isFlipped ? .maxY : .minY
        DispatchQueue.main.async {
            NSSharingServicePicker(items: [url]).show(relativeTo: rect, of: view, preferredEdge: edge)
        }
    }
}

/// Builds an NSMenu from the page's item list and remembers which page item was chosen.
@MainActor
private final class PageMenu: NSObject {
    let menu = NSMenu()
    private(set) var chosen: String?
    private weak var player: WebPlayer?
    private let anchor: NSPoint

    init(player: WebPlayer, items: [[String: Any]], anchor: NSPoint) {
        self.player = player
        self.anchor = anchor
        super.init()
        menu.autoenablesItems = false
        for spec in items {
            if spec["sep"] != nil {
                if let last = menu.items.last, !last.isSeparatorItem { menu.addItem(.separator()) }
                continue
            }
            if let share = spec["share"] as? String, URL(string: share) != nil {
                let item = NSMenuItem(title: "Share…", action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
                item.representedObject = ["share": share]
                menu.addItem(item)
                continue
            }
            guard let title = spec["t"] as? String, !title.isEmpty else { continue }
            let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = spec
            if let s = spec["s"] as? String { item.image = NSImage(systemSymbolName: s, accessibilityDescription: nil) }
            if spec["on"] as? Bool == true { item.state = .on }
            if spec["off"] != nil { item.isEnabled = false }
            menu.addItem(item)
        }
        while let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
        if menu.items.isEmpty { addPageItems() }
    }

    /// Nothing for this item (e.g. a comment whose only entry was Report): the page commands.
    private func addPageItems() {
        guard let player else { return }
        for (title, symbol, key, enabled) in [("Back", "chevron.left", "back", player.canGoBack),
                                               ("Forward", "chevron.right", "forward", player.canGoForward),
                                               ("Reload Page", "arrow.clockwise", "reload", true)] {
            let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.representedObject = ["page": key]
            item.isEnabled = enabled
            menu.addItem(item)
        }
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? [String: Any], let player else { return }
        if let key = spec["k"] as? String { chosen = key }
        else if let path = spec["open"] as? String { player.open(path) }
        else if let url = spec["copy"] as? String { player.copyLink(url) }
        else if let s = spec["share"] as? String, let url = URL(string: s) { player.presentShare(url: url, at: anchor) }
        else if let s = spec["browser"] as? String, let url = URL(string: s) { NSWorkspace.shared.open(url) }
        else if let page = spec["page"] as? String {
            switch page {
            case "back": player.goBack()
            case "forward": player.goForward()
            default: player.reload()
            }
        }
    }
}

/// The web view, with WebKit's standard context menu trimmed to what makes sense in an app:
/// no new windows, downloads, web search, speech or translation (Back, Reload, Copy, Look Up,
/// Inspect Element and the text-editing items stay).
final class PageWebView: WKWebView {
    private static let unwanted: Set<String> = [
        "WKMenuItemIdentifierOpenLinkInNewWindow", "WKMenuItemIdentifierDownloadLinkedFile",
        "WKMenuItemIdentifierOpenImageInNewWindow", "WKMenuItemIdentifierDownloadImage",
        "WKMenuItemIdentifierOpenFrameInNewWindow", "WKMenuItemIdentifierOpenMediaInNewWindow",
        "WKMenuItemIdentifierDownloadMedia", "WKMenuItemIdentifierCopyMediaLink",
        "WKMenuItemIdentifierSearchWeb", "WKMenuItemIdentifierSpeechMenu",
        "WKMenuItemIdentifierTranslate", "WKMenuItemIdentifierShowHideMediaControls",
        "WKMenuItemIdentifierToggleFullScreen", "WKMenuItemIdentifierToggleEnhancedFullScreen",
        "WKMenuItemIdentifierShareMenu", "WKMenuItemIdentifierAddHighlightToCurrentQuickNote",
        "WKMenuItemIdentifierAddHighlightToNewQuickNote", "WKMenuItemIdentifierCopySubject",
        "WKMenuItemIdentifierRevealImage", "WKMenuItemIdentifierLookUpImage",
    ]

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items where Self.unwanted.contains(item.identifier?.rawValue ?? "") {
            menu.removeItem(item)
        }
        // Tidy separators left behind.
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem && previousWasSeparator { menu.removeItem(item) } else { previousWasSeparator = item.isSeparatorItem }
        }
        while let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
    }
}

/// Context menu for the playing track (player bar and mini player).
struct NowPlayingMenu: View {
    @ObservedObject var player: WebPlayer
    /// Called after a "Go to" item, e.g. to bring the main window forward from the mini player.
    var onNavigate: () -> Void = {}

    var body: some View {
        let s = player.state
        let link = s.trackPath.isEmpty ? nil : URL(string: "https://soundcloud.com" + s.trackPath)
        Button { player.playPause() } label: {
            Label(s.isPlaying ? "Pause" : "Play", systemImage: s.isPlaying ? "pause.fill" : "play.fill")
        }
        Button { player.toggleLike() } label: {
            Label(s.isLiked ? "Unlike" : "Like", systemImage: s.isLiked ? "heart.slash" : "heart")
        }
        Divider()
        Button { player.open(s.trackPath); onNavigate() } label: { Label("Go to Track", systemImage: "arrow.right.circle") }
            .disabled(s.trackPath.isEmpty)
        if !s.albumPath.isEmpty {
            Button { player.open(s.albumPath); onNavigate() } label: { Label("Go to Album", systemImage: "square.stack") }
        }
        Button { player.open(s.artistPath); onNavigate() } label: {
            Label(s.artist.isEmpty ? "Go to Artist" : "Go to \(s.artist)", systemImage: "person.crop.circle")
        }
        .disabled(s.artistPath.isEmpty)
        Button { player.toggleQueue() } label: { Label(s.queueVisible ? "Hide Up Next" : "Show Up Next", systemImage: "list.bullet") }
        if let link {
            Divider()
            Button { player.copyLink(link.absoluteString) } label: { Label("Copy Link", systemImage: "link") }
            Button { player.presentShareAtMouse(link) } label: { Label("Share…", systemImage: "square.and.arrow.up") }
        }
    }
}

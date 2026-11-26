import AppKit

/// Native look for SoundCloud's content: follows the macOS appearance (light/dark) and accent
/// colour by filling ThemeVars' --cp-* tokens with real system colours.
enum Theme {
    struct Snapshot: Equatable {
        let isDark: Bool
        let tokens: String
    }

    /// Resolves the system colours for the app's current appearance.
    static func current() -> Snapshot {
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var tokens = ""
        appearance.performAsCurrentDrawingAppearance {
            let bg = NSColor.textBackgroundColor
            let colors: [(String, NSColor)] = [
                ("bg", bg),
                ("label", .labelColor),
                ("secondary", .secondaryLabelColor),
                ("fill", .quaternaryLabelColor),
                ("link", .linkColor),
                ("accent", .controlAccentColor),
            ]
            for (name, color) in colors {
                let (r, g, b) = flatten(color, over: bg)
                tokens += "--cp-\(name):rgb(\(r),\(g),\(b));--cp-\(name)-rgb:\(r),\(g),\(b);"
            }
        }
        return Snapshot(isDark: isDark, tokens: tokens)
    }

    /// The CSS for a snapshot: tokens + the generated variable remap + native-look rules.
    static func css(_ s: Snapshot) -> String {
        ":root{\(s.tokens)color-scheme:\(s.isDark ? "dark" : "light");}\n" + ThemeVars.css + "\n" + nativeCSS + "\n" + Icons.css
    }

    /// Composites a (possibly translucent) colour over the background → opaque sRGB.
    private static func flatten(_ color: NSColor, over bg: NSColor) -> (Int, Int, Int) {
        let c = color.usingColorSpace(.sRGB) ?? .gray
        let b = bg.usingColorSpace(.sRGB) ?? .white
        let a = c.alphaComponent
        func mix(_ x: CGFloat, _ y: CGFloat) -> Int { Int(((x * a + y * (1 - a)) * 255).rounded()) }
        return (mix(c.redComponent, b.redComponent), mix(c.greenComponent, b.greenComponent), mix(c.blueComponent, b.blueComponent))
    }

    /// CSS for SoundCloud's newer pages (tracks), which render in a same-origin iframe:
    /// tokens + rules that give the track header the same card look as playlist heroes.
    static func frameCSS(_ s: Snapshot) -> String {
        ":root{\(s.tokens)color-scheme:\(s.isDark ? "dark" : "light");}\n" + webiCSS + "\n" + Icons.css
    }

    static let webiCSS = """
    html body, html body * { font-family: -apple-system, BlinkMacSystemFont, system-ui !important; }
    html body { -webkit-font-smoothing: antialiased; }
    html, html body, #navigation-shell-right-side-container, #main, #main > div { background-color: var(--cp-bg) !important; }
    /* Room to scroll the end of the page past the floating player. */
    #navigation-shell-right-side-container::after { content: ""; display: block; flex: none; height: 76px; }

    /* Track header → rounded card on a blurred-artwork gradient (like the playlist hero). */
    section[aria-label="Track header"] {
      /* clip, not hidden: a hidden-overflow box can still be scrolled (e.g. by focusing the
         comment field), which shoved the header's contents up out of view. */
      position: relative !important; isolation: isolate; overflow: clip !important;
      margin: 12px 16px 0 !important; border-radius: 14px !important;
      background: #3a3a3c !important; border: 0 !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.08) !important;
    }
    section[aria-label="Track header"]::before {
      content: ""; position: absolute; inset: -80px; z-index: -2; pointer-events: none;
      background: var(--cp-art, none) center / cover no-repeat;
      filter: blur(70px) saturate(1.5) brightness(0.8);
    }
    section[aria-label="Track header"]::after {
      content: ""; position: absolute; inset: 0; z-index: -1; pointer-events: none;
      background: linear-gradient(to bottom, rgba(0, 0, 0, 0.05) 30%, rgba(0, 0, 0, 0.35) 100%);
    }
    section[aria-label="Track header"] > div, section[aria-label="Track header"] > div > div { background: transparent !important; }
    section[aria-label="Track header"] h1 {
      color: #fff !important; font-size: 30px !important; font-weight: 700 !important; line-height: 1.15 !important;
      letter-spacing: -0.02em !important; text-transform: none !important; text-shadow: 0 1px 12px rgba(0, 0, 0, 0.35);
    }
    section[aria-label="Track header"] [role="group"] .MuiTypography-caption {
      color: rgba(255, 255, 255, 0.82) !important; font-size: 15px !important; font-weight: 500 !important;
      text-shadow: 0 1px 8px rgba(0, 0, 0, 0.3);
    }
    /* Play: see-through Liquid Glass circle with a second refractive glass layer in the play/pause glyph itself. */
    html body section[aria-label="Track header"] button.MuiButton-outlined {
      position: relative !important; overflow: hidden !important;
      outline: none !important; border: 0 !important; color: #fff !important;
      background: rgba(255, 255, 255, 0.08) !important;
      -webkit-backdrop-filter: blur(12px) saturate(1.8) !important; backdrop-filter: blur(12px) saturate(1.8) !important;
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.45), inset 0 -0.5px 0 rgba(255, 255, 255, 0.14),
                  0 0 0 0.5px rgba(255, 255, 255, 0.24), 0 4px 14px rgba(0, 0, 0, 0.22) !important;
    }
    html body section[aria-label="Track header"] button.MuiButton-outlined:hover { background: rgba(255, 255, 255, 0.15) !important; }
    html body section[aria-label="Track header"] button.MuiButton-outlined:active { background: rgba(255, 255, 255, 0.22) !important; }
    html body section[aria-label="Track header"] button.MuiButton-outlined svg {
      background-color: transparent !important;
      background-image: linear-gradient(155deg, rgba(255, 255, 255, 0.48) 0%, rgba(255, 255, 255, 0.14) 55%, rgba(255, 255, 255, 0.28) 100%) !important;
      -webkit-backdrop-filter: blur(22px) saturate(2.5) brightness(1.42) contrast(1.12) !important;
      backdrop-filter: blur(22px) saturate(2.5) brightness(1.42) contrast(1.12) !important;
    }
    html body section[aria-label="Track header"] button.MuiButton-outlined:hover svg {
      -webkit-backdrop-filter: blur(22px) saturate(2.7) brightness(1.55) contrast(1.14) !important;
      backdrop-filter: blur(22px) saturate(2.7) brightness(1.55) contrast(1.14) !important;
    }
    /* Liquid Glass buttons (outlined rings → translucent glass pills). */
    html body :is(.MuiIconButton-root[variant="outlined"], .MuiButton-outlined) {
      border: 0 !important; outline: none !important; color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.07) !important;
      -webkit-backdrop-filter: blur(16px) saturate(1.8) !important; backdrop-filter: blur(16px) saturate(1.8) !important;
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.22), inset 0 -0.5px 0 rgba(255, 255, 255, 0.06),
                  0 0 0 0.5px rgba(var(--cp-label-rgb), 0.14), 0 2px 8px rgba(0, 0, 0, 0.16) !important;
    }
    html body :is(.MuiIconButton-root[variant="outlined"], .MuiButton-outlined):hover { background: rgba(var(--cp-label-rgb), 0.13) !important; }
    /* On the artwork-tinted header the glass is white-tinted; match playlist/album sizing
       (40px tall, 18px icons): icon-only buttons stay 40px circles (11+18+11=40), while
       buttons with counts (Like, Repost) expand into fitted 40px pills. */
    html body section[aria-label="Track header"] .MuiIconButton-root {
      border: 0 !important; outline: none !important; color: #fff !important; background: rgba(255, 255, 255, 0.14) !important;
      -webkit-backdrop-filter: blur(16px) saturate(1.8) !important; backdrop-filter: blur(16px) saturate(1.8) !important;
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35), inset 0 -0.5px 0 rgba(255, 255, 255, 0.1),
                  0 0 0 0.5px rgba(255, 255, 255, 0.18), 0 2px 10px rgba(0, 0, 0, 0.18) !important;
    }
    html body section[aria-label="Track header"] .MuiIconButton-root:not(.MuiOutlinedInput-root *) {
      width: auto !important; min-width: 40px !important; height: 40px !important;
      padding: 0 11px !important; border-radius: 999px !important;
      box-sizing: border-box !important; white-space: nowrap !important;
    }
    html body section[aria-label="Track header"] .MuiIconButton-root:not(.MuiOutlinedInput-root *):has(:is(p, .MuiTypography-root, span:not(.MuiTouchRipple-root):not(:has(svg)))) {
      padding: 0 14px !important;
    }
    html body section[aria-label="Track header"] .MuiIconButton-root svg {
      width: 18px !important; height: 18px !important; font-size: 18px !important; flex: none !important;
    }
    html body section[aria-label="Track header"] .MuiIconButton-root:hover { background: rgba(255, 255, 255, 0.24) !important; }
    section[aria-label="Track header"] .MuiOutlinedInput-root {
      outline: none !important; color: #fff !important; background: rgba(255, 255, 255, 0.14) !important;
      -webkit-backdrop-filter: blur(16px) saturate(1.8) !important; backdrop-filter: blur(16px) saturate(1.8) !important;
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35), inset 0 -0.5px 0 rgba(255, 255, 255, 0.1),
                  0 0 0 0.5px rgba(255, 255, 255, 0.18), 0 2px 10px rgba(0, 0, 0, 0.18) !important;
    }
    html body :is(.MuiIconButton-root, .MuiButton-root):focus-visible { outline: 2px solid var(--cp-accent) !important; outline-offset: 2px !important; }
    section[aria-label="Track header"] .MuiOutlinedInput-notchedOutline { border: 0 !important; }
    section[aria-label="Track header"] img.cp-art {
      border-radius: 10px !important; box-shadow: 0 8px 24px rgba(0, 0, 0, 0.35) !important;
    }
    section[aria-label="Track header"] :has(> img.cp-art) { border-radius: 10px !important; border: 0 !important; overflow: visible !important; }
    /* Calmer Apple typography & surfaces on track pages: no ALL-CAPS headings, soft cards, clean fade. */
    .MuiTypography-root, .MuiTypography-h5, .MuiTypography-overline,
    .MuiTypography-caption, .MuiTypography-micro, [class*="MuiTypography-"] {
      text-transform: none !important;
    }
    h2.MuiTypography-h5, aside h2.MuiTypography-h5 {
      font-size: 16px !important; font-weight: 600 !important;
      letter-spacing: -0.015em !important; color: var(--cp-label) !important;
    }
    #main *:not(section[aria-label="Track header"] *) {
      border-top-color: rgba(var(--cp-label-rgb), 0.08) !important;
      border-bottom-color: rgba(var(--cp-label-rgb), 0.08) !important;
    }
    aside .cp-rail-card {
      background: rgba(var(--cp-label-rgb), 0.045) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.07) !important;
      border-radius: 12px !important; box-shadow: none !important;
    }
    aside .cp-rail-card button, aside button { border-radius: 999px !important; }
    html body #main .cp-fade-mask::after, html body #main .cp-fade-mask::before,
    html body .cp-fade-mask::after, html body .cp-fade-mask::before {
      background: linear-gradient(to bottom, rgba(var(--cp-bg-rgb), 0), var(--cp-bg)) !important;
      background-image: linear-gradient(to bottom, rgba(var(--cp-bg-rgb), 0), var(--cp-bg)) !important;
    }
    .cp-toast, .MuiSnackbar-root { display: none !important; }
    """

    /// Rules that make the remaining page feel like a Mac app rather than a website.
    static let nativeCSS = """
    /* System font everywhere (SoundCloud uses Söhne via --font-main). */
    html body, html body [class*="theme-"] {
      --font-main: -apple-system, BlinkMacSystemFont, system-ui !important;
    }
    html body, html body input, html body button, html body textarea, html body select {
      font-family: -apple-system, BlinkMacSystemFont, system-ui !important;
      -webkit-font-smoothing: antialiased;
    }
    html body { background: var(--cp-bg) !important; padding-bottom: 80px !important; }   /* room for the floating player */

    /* SoundCloud's palette dims hovered button text/icons to 40% opacity; keep full contrast. */
    html body:is(.theme-dark, .theme-light),
    html body:is(.theme-dark, .theme-light) [class*="theme-"] {
      --button-primary-hover-font-color: var(--cp-bg) !important;
      --button-primary-selected-hover-font-color: var(--cp-label) !important;
      --button-secondary-hover-font-color: var(--cp-label) !important;
      --button-secondary-selected-hover-font-color: var(--cp-accent) !important;
      --button-tertiary-hover-font-color: var(--cp-label) !important;
      --button-tertiary-selected-hover-font-color: var(--cp-accent) !important;
    }

    /* SoundCloud's own chrome is replaced by native UI: header → toolbar/sidebar,
       player bar → native player bar. The player bar stays laid out (invisible) because
       the app drives it; its queue panel stays visible. */
    #app > header, .header, .dropbar { display: none !important; }
    #app, #content, .l-container.l-content { padding-top: 0 !important; margin-top: 0 !important; }
    .playControls, .playControls * { visibility: hidden !important; }
    .playControls__queue, .playControls__queue * { visibility: visible !important; }

    /* ── Up Next → full-height right sidebar (like Apple Music) ────────────────────────────
       SoundCloud's own queue (drag to reorder, Clear, Autoplay all keep working), moved into a
       fixed right column that slides in; the page narrows instead of being covered. */
    .playControls, .playControls__inner, .playControls__wrapper {
      transform: none !important; filter: none !important; contain: none !important;
    }
    .playControls__queue {
      position: fixed !important; top: 0 !important; bottom: 0 !important; right: 0 !important; left: auto !important;
      width: 340px !important; height: auto !important; max-height: none !important;
      opacity: 1 !important; transform: translateX(100%) !important; pointer-events: none !important;
      transition: transform 0.25s cubic-bezier(0.2, 0.8, 0.2, 1) !important; z-index: 50 !important;
    }
    .playControls.m-queueVisible .playControls__queue { transform: none !important; pointer-events: auto !important; }
    /* Push the page aside only if it keeps SoundCloud's 960px minimum (960 + 340 = 1300);
       on narrower windows the queue overlays the page instead, so layouts never squeeze. */
    @media (min-width: 1300px) {
      html body:has(.playControls.m-queueVisible) { padding-right: 340px !important; }
    }
    @media (max-width: 1299px) {
      .playControls.m-queueVisible .playControls__queue { box-shadow: -12px 0 32px rgba(0, 0, 0, 0.35) !important; }
    }
    html body { transition: padding-right 0.25s cubic-bezier(0.2, 0.8, 0.2, 1); }

    .playControls__queue .queue {
      height: 100% !important; display: flex !important; flex-direction: column !important;
      background: linear-gradient(rgba(var(--cp-label-rgb), 0.035), rgba(var(--cp-label-rgb), 0.035)), var(--cp-bg) !important;
      border: 0 !important; border-left: 0.5px solid rgba(var(--cp-label-rgb), 0.14) !important;
      border-radius: 0 !important; box-shadow: none !important;
    }
    .playControls__queue .queue__panel {
      display: flex !important; align-items: center !important; flex: none !important;
      padding: 14px 12px 8px 16px !important; background: transparent !important;
    }
    .playControls__queue .queue__title {
      flex: 1 !important; padding: 0 !important; font-size: 15px !important; font-weight: 600 !important;
      color: var(--cp-label) !important; letter-spacing: -0.01em !important;
    }
    .playControls__queue .queue__clear {
      height: 22px !important; padding: 0 10px !important; margin: 0 !important; border: 0 !important;
      border-radius: 11px !important; font-size: 12px !important; font-weight: 500 !important;
      color: var(--cp-accent) !important; background: transparent !important;
    }
    .playControls__queue .queue__clear:hover { background: rgba(var(--cp-accent-rgb), 0.12) !important; }
    .playControls__queue .queue__hide { display: none !important; }   /* toggled from the player bar */
    .playControls__queue .queue__scrollable {
      flex: 1 1 auto !important; min-height: 0 !important; height: auto !important;
    }
    .playControls__queue .queue__scrollableInner { height: 100% !important; }
    .playControls__queue .queue__itemsHeight { padding: 0 8px !important; background: none !important; }
    .playControls__queue .queue__itemsContainer, .playControls__queue .queue__itemsContainer * {
      font-family: inherit !important; letter-spacing: normal !important;
    }

    /* Newer pages (e.g. tracks) are a separate SoundCloud app in an iframe below the old one,
       laid out as body grid rows [old app | iframe]. The old app's row would hold only the
       (hidden) header, so collapse it and let the iframe fill the view; it also reserves room
       for SoundCloud's player bar, which is replaced by the native one. */
    html body:has(> .webiIframeV2Layout:not(.fullScreen):not(.sc-hidden)) {
      grid-template-rows: 0 minmax(0, 1fr) !important; padding: 0 !important;
    }
    /* Hide only the old page content: #app also holds the (driven) player bar and Up Next. */
    html body:has(> .webiIframeV2Layout:not(.fullScreen):not(.sc-hidden)) > #app { height: 0 !important; overflow: visible !important; }
    html body:has(> .webiIframeV2Layout:not(.fullScreen):not(.sc-hidden)) > #app #content { display: none !important; }
    /* Full height, so the page runs on under the floating player (the frame pads its own end). */
    html body > .webiIframeV2Layout.playerVisible:not(.fullScreen) { height: 100% !important; }

    /* Library pages: the Overview/Likes/Playlists/… tabs duplicate the native sidebar. */
    .l-collection > .l-nav { display: none !important; }

    /* Calmer type: no shouty uppercase headers or tight display tracking. */
    .sidebarHeader__actualTitle, .sidebarHeader__title, .sc-text-uppercase {
      text-transform: none !important; letter-spacing: normal !important;
    }
    h1, h2, h3, h4 { letter-spacing: -0.01em !important; }

    /* Mac-style rounding: artwork, buttons, inputs, menus. Avatars keep their circles. */
    .image:where(:not(.image__rounded):not(.userBadge *):not(.userBadgeListItem *):not(.userItem__coverArt *):not(.profileHeaderInfo__avatar *):not(.commentItem__avatar *):not(.conversationBadge *)),
    .image:where(:not(.image__rounded):not(.userBadge *):not(.userBadgeListItem *):not(.userItem__coverArt *):not(.profileHeaderInfo__avatar *):not(.commentItem__avatar *):not(.conversationBadge *)) > span,
    .sc-artwork:where(:not(.image__rounded):not(.image__rounded *):not(.userBadge *):not(.userBadgeListItem *):not(.userItem__coverArt *):not(.profileHeaderInfo__avatar *):not(.commentItem__avatar *):not(.conversationBadge *)) {
      border-radius: 6px !important;
    }
    html body :is(
      .image__rounded, .image__rounded > span, .image__rounded .sc-artwork,
      .userBadge__avatar, .userBadge__avatar .image, .userBadge__avatar .sc-artwork, .userBadge .image, .userBadge .sc-artwork,
      .userBadgeListItem .image, .userBadgeListItem .sc-artwork,
      .userItem__coverArt, .userItem__coverArt .image, .userItem__coverArt .sc-artwork,
      .profileHeaderInfo__avatar, .profileHeaderInfo__avatar .image, .profileHeaderInfo__avatar .sc-artwork,
      .commentItem__avatar, .commentItem__avatar .image, .commentItem__avatar .sc-artwork,
      .conversationBadge .image, .conversationBadge .sc-artwork
    ) {
      border-radius: 50% !important; overflow: hidden !important;
    }
    .sc-button:not(.sc-button-play) { border-radius: 999px !important; }   /* pills, as in macOS 26 */
    .sc-button-play { color: #fff; }
    /* Remove SoundCloud's clearfix pseudo-elements from list/grid containers (fixes empty cell #1),
       convert .badgeList floats to responsive CSS Grid, and hide empty filler boxes & shrinkwrap overlays. */
    :is(.soundList__list, .soundList, .badgeList__list, .searchList__list, .lazyLoadingList__list, .tagsList__list)::before,
    :is(.soundList__list, .soundList, .badgeList__list, .searchList__list, .lazyLoadingList__list, .tagsList__list)::after {
      display: none !important; content: none !important;
    }
    .badgeList__item:not(:has(a[href])) { display: none !important; }
    :is(.badgeList__list, .lazyLoadingList__list:has(> .badgeList__item)):not(.cp-view-compact *) {
      display: grid !important;
      grid-template-columns: repeat(auto-fill, minmax(168px, 1fr)) !important;
      gap: 24px 20px !important;
      padding: 8px 16px !important; margin: 0 !important;
    }
    :is(.badgeList__list, .lazyLoadingList__list:has(> .badgeList__item)):not(.cp-view-compact *) > .badgeList__item {
      float: none !important; width: auto !important; max-width: none !important;
      min-width: 0 !important; margin: 0 !important; padding: 0 !important;
    }
    :is(.playableTile, .audibleTile, .badgeList__item, .cp-view-compact .sound, .cp-view-tiles .sound) [class*="g-type-shrinkwrap"],
    :is(.playableTile, .audibleTile, .badgeList__item, .cp-view-compact .sound, .cp-view-tiles .sound) [class*="g-type-shrinkwrap"] * {
      background: transparent !important; box-shadow: none !important;
    }
    :is(.playableTile, .audibleTile, .badgeList__item, .cp-view-compact .sound, .cp-view-tiles .sound) :is([class*="g-type-shrinkwrap"], .soundTitle__title, .soundTitle__username)::before {
      display: none !important; content: none !important;
    }
    :is(.cp-view-compact, .cp-view-tiles) .sound :is(.visual, .sound__visual, .visual__image, .visuals, .visualSound__progress) {
      display: none !important;
    }
    /* Remove SoundCloud's washed-out hover overlay on album/playlist/track tiles. */
    .playableTile { --overlay-color: transparent !important; --overlay-default-color: transparent !important; }
    .playableTile :is(.playableTile__artwork, .playableTile__artworkLink, .playableTile__image, .playableTile__actions)::before,
    .playableTile :is(.playableTile__artwork, .playableTile__artworkLink, .playableTile__image, .playableTile__actions)::after,
    .playableTile .playableTile__actions {
      background: transparent !important; background-image: none !important;
    }
    .playableTile:hover .playableTile__artwork :is(.image, .sc-artwork, span) { opacity: 1 !important; filter: none !important; }

    /* Small action buttons (Like, Follow, •••) overlaid on tile artwork (Home, Likes, Albums, Playlists):
       high-contrast dark frosted pills/circles with dual light/dark rims so they stay legible on any cover. */
    .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions {
      overflow: visible !important; z-index: 4 !important;
    }
    .playableTile:where(:not(.cp-view-compact *)):is(:hover, .cp-tile-hover, .m-active, :focus-within) .playableTile__actions {
      display: block !important; opacity: 1 !important; visibility: visible !important;
    }
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button {
      box-sizing: border-box !important;
      display: inline-flex !important; align-items: center !important; justify-content: center !important;
      height: 30px !important; min-height: 30px !important; max-height: 30px !important;
      margin: 0 0 0 5px !important; vertical-align: middle !important;
      color: #fff !important;
      background: rgba(18, 18, 20, 0.78) !important;
      -webkit-backdrop-filter: blur(16px) saturate(1.6) !important;
      backdrop-filter: blur(16px) saturate(1.6) !important;
      border: 0 !important; border-radius: 999px !important;
      box-shadow: inset 0 0.5px 0 rgba(255, 255, 255, 0.32),
                  0 0 0 0.5px rgba(255, 255, 255, 0.24),
                  0 2px 8px rgba(0, 0, 0, 0.45) !important;
      font-size: 12px !important; font-weight: 600 !important; line-height: 1 !important;
      letter-spacing: -0.01em !important; white-space: nowrap !important;
      text-shadow: 0 1px 2px rgba(0, 0, 0, 0.35) !important;
      opacity: 1 !important;
      transition: background-color 0.14s ease, transform 0.12s ease, box-shadow 0.14s ease !important;
    }
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button:first-child {
      margin-left: 0 !important;
    }
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button:is(.sc-button-icon, .sc-button-like, .sc-button-more) {
      width: 30px !important; min-width: 30px !important; max-width: 30px !important;
      padding: 0 !important; border-radius: 50% !important;
    }
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button:not(.sc-button-icon):not(.sc-button-like):not(.sc-button-more) {
      width: auto !important; min-width: 0 !important; max-width: none !important;
      padding: 0 12px !important; gap: 5px !important;
    }
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button:hover {
      color: #fff !important;
      background: rgba(32, 32, 36, 0.92) !important;
      transform: scale(1.06) !important;
      box-shadow: inset 0 0.5px 0 rgba(255, 255, 255, 0.42),
                  0 0 0 0.5px rgba(255, 255, 255, 0.38),
                  0 4px 12px rgba(0, 0, 0, 0.55) !important;
    }
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button:active {
      color: #fff !important;
      background: rgba(12, 12, 14, 0.96) !important;
      transform: scale(0.96) !important;
    }
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button.sc-button-selected,
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button.sc-button-selected:hover {
      color: color-mix(in srgb, var(--cp-accent) 82%, #fff) !important;
    }
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button > div {
      display: inline-flex !important; align-items: center !important; justify-content: center !important; gap: 4px !important;
      width: auto !important; height: auto !important; margin: 0 !important; padding: 0 !important;
      background: transparent !important; border: 0 !important; box-shadow: none !important; color: inherit !important;
    }
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button::before,
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button::after {
      display: none !important;
    }
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button svg {
      width: 15px !important; height: 15px !important; margin: 0 !important; flex: none !important;
    }
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button:is(.sc-button-icon, .sc-button-like, .sc-button-more) :is(.sc-button-label, .sc-button-alt-labels):not(:has(svg)),
    html body .playableTile:where(:not(.cp-view-compact *)) .playableTile__actions .sc-button-like span:not(:has(svg)) {
      display: none !important;
    }

    /* Play buttons on tiles & cards (Likes, Albums, Playlists, Stations, Home): see-through Liquid Glass
       with the masked play/pause glyph itself acting as a second refractive glass layer.
       Keep the wrapper free of transform/will-change so it never traps WebKit's backdrop root. */
    .playableTile__playButton {
      position: absolute !important; inset: 0 !important; width: auto !important; height: auto !important;
      margin: 0 !important; padding: 0 !important; transform: none !important; pointer-events: none !important;
      display: flex !important; align-items: center !important; justify-content: center !important;
    }
    html body .playableTile__playButton .sc-button.sc-button-play {
      pointer-events: auto !important;
      width: 76px !important; height: 76px !important; min-width: 0 !important; padding: 0 !important; margin: 0 !important;
      display: flex !important; align-items: center !important; justify-content: center !important;
    }
    html body .playableTile__playButton .sc-button.sc-button-play svg {
      width: 34px !important; height: 34px !important; margin: 0 !important;
    }
    html body :is(.playableTile__playButton, .soundBadge__playButton, .collectionBadge__playButton) .sc-button.sc-button-play {
      position: relative !important; overflow: hidden !important;
      display: flex !important; align-items: center !important; justify-content: center !important;
      border: 0 !important; border-radius: 50% !important; color: #fff !important;
      background: rgba(255, 255, 255, 0.08) !important;
      -webkit-backdrop-filter: blur(12px) saturate(1.8) !important; backdrop-filter: blur(12px) saturate(1.8) !important;
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.45), inset 0 -0.5px 0 rgba(255, 255, 255, 0.14),
                  0 0 0 0.5px rgba(255, 255, 255, 0.24), 0 4px 14px rgba(0, 0, 0, 0.22) !important;
      transition: background-color 0.15s ease !important;
    }
    html body :is(.playableTile__playButton, .soundBadge__playButton, .collectionBadge__playButton) .sc-button.sc-button-play > div {
      display: flex !important; align-items: center !important; justify-content: center !important;
      width: 100% !important; height: 100% !important; margin: 0 !important; padding: 0 !important;
      background: transparent !important;
    }
    html body :is(.playableTile__playButton, .soundBadge__playButton, .collectionBadge__playButton) .sc-button.sc-button-play :is(.sc-button-label, .sc-button-alt-labels) {
      display: none !important;
    }
    html body :is(.playableTile__playButton, .soundBadge__playButton, .collectionBadge__playButton) .sc-button.sc-button-play svg {
      background-color: transparent !important;
      background-image: linear-gradient(155deg, rgba(255, 255, 255, 0.48) 0%, rgba(255, 255, 255, 0.14) 55%, rgba(255, 255, 255, 0.28) 100%) !important;
      -webkit-backdrop-filter: blur(22px) saturate(2.5) brightness(1.42) contrast(1.12) !important;
      backdrop-filter: blur(22px) saturate(2.5) brightness(1.42) contrast(1.12) !important;
    }
    html body :is(.playableTile__playButton, .soundBadge__playButton, .collectionBadge__playButton) .sc-button.sc-button-play:hover {
      background: rgba(255, 255, 255, 0.15) !important;
    }
    html body :is(.playableTile__playButton, .soundBadge__playButton, .collectionBadge__playButton) .sc-button.sc-button-play:hover svg {
      -webkit-backdrop-filter: blur(22px) saturate(2.7) brightness(1.55) contrast(1.14) !important;
      backdrop-filter: blur(22px) saturate(2.7) brightness(1.55) contrast(1.14) !important;
    }
    html body :is(.playableTile__playButton, .soundBadge__playButton, .collectionBadge__playButton) .sc-button.sc-button-play:active {
      background: rgba(255, 255, 255, 0.22) !important;
    }
    /* Secondary & small page buttons: crisp contrast in both light and dark modes. */
    .sc-button-secondary:where(:not(.listDisplayToggle__options .sc-button)) {
      color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.1) !important; border: 0 !important;
      -webkit-backdrop-filter: blur(16px) saturate(1.8) !important; backdrop-filter: blur(16px) saturate(1.8) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.2), 0 1px 2px rgba(0, 0, 0, 0.08) !important;
      transition: background-color 0.15s ease, box-shadow 0.15s ease, color 0.15s ease !important;
    }
    .sc-button-secondary:where(:not(.listDisplayToggle__options .sc-button)):hover {
      color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.16) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.28), 0 1px 3px rgba(0, 0, 0, 0.12) !important;
    }
    .sc-button-secondary:where(:not(.listDisplayToggle__options .sc-button)):active {
      color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.22) !important;
    }
    .sc-button-secondary.sc-button-selected:where(:not(.listDisplayToggle__options .sc-button)) {
      color: var(--cp-accent) !important;
      background: rgba(var(--cp-accent-rgb), 0.14) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-accent-rgb), 0.34) !important;
    }
    .sc-button-secondary.sc-button-selected:where(:not(.listDisplayToggle__options .sc-button)):hover {
      color: var(--cp-accent) !important;
      background: rgba(var(--cp-accent-rgb), 0.22) !important;
    }
    /* Follow / Following buttons on cards, creator sidebars, and user rows. */
    .sc-button-follow:where(:not(.playableTile__actions *):not(.cp-profile-actions *):not(.cp-hero-row *)) {
      display: inline-flex !important; align-items: center !important; justify-content: center !important; gap: 5px !important;
      height: 26px !important; min-height: 26px !important; padding: 0 12px !important;
      font-size: 12px !important; font-weight: 600 !important; line-height: 1 !important;
      color: var(--cp-label) !important; background: rgba(var(--cp-label-rgb), 0.12) !important;
      border: 0 !important; border-radius: 999px !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.24) !important;
    }
    .sc-button-follow.sc-button-icon:where(:not(.playableTile__actions *):not(.cp-profile-actions *):not(.cp-hero-row *)) {
      width: 26px !important; min-width: 26px !important; padding: 0 !important; border-radius: 50% !important;
    }
    .sc-button-follow:where(:not(.playableTile__actions *):not(.cp-profile-actions *):not(.cp-hero-row *)):hover {
      color: var(--cp-label) !important; background: rgba(var(--cp-label-rgb), 0.19) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.34) !important;
    }
    .sc-button-follow.sc-button-selected:where(:not(.playableTile__actions *):not(.cp-profile-actions *):not(.cp-hero-row *)) {
      color: var(--cp-accent) !important; background: rgba(var(--cp-accent-rgb), 0.15) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-accent-rgb), 0.36) !important;
    }
    .sc-button-follow.sc-button-selected:where(:not(.playableTile__actions *):not(.cp-profile-actions *):not(.cp-hero-row *)):hover {
      color: var(--cp-accent) !important; background: rgba(var(--cp-accent-rgb), 0.23) !important;
    }
    .sc-button-follow:where(:not(.playableTile__actions *):not(.cp-profile-actions *):not(.cp-hero-row *)) svg {
      width: 14px !important; height: 14px !important; margin: 0 !important; flex: none !important;
    }
    /* Small row buttons in album/playlist tracklists (.trackItem) and sidebar badges (.soundBadge). */
    :is(.trackItem__actions, .soundBadge__actions) .sc-button {
      box-sizing: border-box !important;
      display: inline-flex !important; align-items: center !important; justify-content: center !important;
      height: 26px !important; min-height: 26px !important; max-height: 26px !important;
      margin: 0 2px !important; padding: 0 10px !important;
      color: rgba(var(--cp-label-rgb), 0.85) !important;
      background: rgba(var(--cp-label-rgb), 0.09) !important;
      border: 0 !important; border-radius: 999px !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.18) !important;
      -webkit-backdrop-filter: none !important; backdrop-filter: none !important;
    }
    :is(.trackItem__actions, .soundBadge__actions) .sc-button:is(.sc-button-icon, .sc-button-like, .sc-button-more) {
      width: 26px !important; min-width: 26px !important; max-width: 26px !important;
      padding: 0 !important; border-radius: 50% !important;
    }
    :is(.trackItem__actions, .soundBadge__actions) .sc-button:hover {
      color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.17) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.28) !important;
    }
    :is(.trackItem__actions, .soundBadge__actions) .sc-button.sc-button-selected,
    :is(.trackItem__actions, .soundBadge__actions) .sc-button.sc-button-selected:hover {
      color: var(--cp-accent) !important;
      background: rgba(var(--cp-accent-rgb), 0.15) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-accent-rgb), 0.34) !important;
    }
    :is(.trackItem__actions, .soundBadge__actions) .sc-button > div {
      display: inline-flex !important; align-items: center !important; justify-content: center !important;
      width: auto !important; height: auto !important; margin: 0 !important; padding: 0 !important;
      background: transparent !important; border: 0 !important; box-shadow: none !important;
    }
    :is(.trackItem__actions, .soundBadge__actions) .sc-button svg {
      width: 14px !important; height: 14px !important; margin: 0 !important; flex: none !important;
    }
    .sc-input, input[type="search"], input[type="text"] { border-radius: 6px !important; }
    .dropdownMenu, .tooltip__content, .modal__modal { border-radius: 10px !important; }

    /* ── Compact track lists (.cp-view-compact on Likes, History, Profiles, Search, Tags, Messages…) ─
       One row per track: artwork (play on hover), title over artist, date, like, •••.
       No waveform, comment box, repost/share/copy-link buttons or stats.
       When .cp-view-waveform is active instead, SoundCloud's full waveform view renders. */
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) { margin: 0 !important; padding: 0 !important; border: 0 !important; }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound {
      position: relative !important; margin: 0 !important; padding: 4px 10px !important;
      border: 0 !important; border-radius: 6px !important; min-height: 0 !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item):nth-child(even) .sound { background: rgba(var(--cp-label-rgb), 0.035); }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound:hover { background: rgba(var(--cp-label-rgb), 0.08) !important; }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound__body {
      position: static !important; display: flex !important; align-items: center !important; gap: 10px;
      min-height: 0 !important; height: auto !important; padding: 0 !important; margin: 0 !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound__artwork {
      position: static !important; float: none !important; flex: none !important;
      width: 36px !important; height: 36px !important; margin: 0 !important; overflow: hidden !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound__coverArt,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound__artwork .image,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound__artwork .sc-artwork {
      display: block !important; width: 36px !important; height: 36px !important; border-radius: 4px !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) :is(.sound__content, .visualSound__wrapper) {
      position: static !important; flex: 1 1 auto !important; min-width: 0 !important;
      display: flex !important; flex-direction: row !important; align-items: center !important;
      justify-content: space-between !important; text-align: left !important; gap: 12px;
      margin: 0 !important; padding: 0 !important; height: auto !important; min-height: 0 !important;
      background: transparent !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound__header {
      position: static !important; display: flex !important; flex-direction: row !important; align-items: center !important;
      text-align: left !important;
      flex: 1 1 auto !important; min-width: 0 !important;
      height: auto !important; min-height: 0 !important;
      margin: 0 !important; padding: 0 !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__titleContainer {
      position: static !important; display: flex !important; flex-direction: row !important; align-items: center !important;
      flex: 1 1 auto !important; width: 100% !important; height: auto !important; min-height: 0 !important;
      min-width: 0 !important; margin: 0 !important; padding: 0 !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__titleContainer > * { flex: none; }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__usernameTitleContainer {
      display: flex !important; flex-direction: column-reverse !important; flex: 1 1 auto !important;
      min-width: 0 !important; margin: 0 !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__title,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__title span {
      font-size: 13px !important; font-weight: 500 !important; line-height: 17px !important; color: var(--cp-label) !important;
      white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis !important; display: block;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__secondary,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__username,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__usernameText {
      font-size: 12px !important; line-height: 16px !important; color: var(--cp-secondary) !important;
      white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__additionalContainer {
      position: static !important; top: auto !important; bottom: auto !important;
      align-self: center !important; display: flex !important; flex-direction: row !important;
      align-items: center !important; justify-content: center !important;
      height: auto !important; min-height: 0 !important; max-height: none !important;
      margin: 0 0 0 12px !important; padding: 0 !important; flex: none !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__additionalContainer > :not(.soundTitle__uploadTime) { display: none !important; }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__uploadTime {
      position: static !important; top: auto !important; bottom: auto !important;
      display: flex !important; align-items: center !important;
      height: auto !important; min-height: 0 !important;
      margin: 0 !important; padding: 0 !important; font-size: 11px !important; line-height: 1 !important;
      color: var(--cp-secondary) !important; white-space: nowrap !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__uploadTime :is(time, .relativeTime) {
      position: static !important; top: auto !important; bottom: auto !important;
      display: inline-flex !important; align-items: center !important;
      height: auto !important; min-height: 0 !important;
      margin: 0 !important; padding: 0 !important; line-height: 1 !important;
    }

    /* Play button: invisible over the artwork, shown on hover / while playing. */
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__playButton {
      position: absolute !important; left: 10px !important; top: 50% !important; transform: translateY(-50%) !important;
      width: 36px !important; height: 36px !important; margin: 0 !important; padding: 0 !important; z-index: 2;
      opacity: 0; transition: opacity 0.12s;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound:hover .soundTitle__playButton,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__playButton:has(.sc-button-pause) { opacity: 1; }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__playButton .sc-button-play {
      display: flex !important; align-items: center !important; justify-content: center !important;
      width: 36px !important; height: 36px !important; min-width: 0 !important; margin: 0 !important; padding: 0 !important;
      border: 0 !important; border-radius: 4px !important; background: rgba(0, 0, 0, 0.45) !important; color: #fff !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundTitle__playButton .sc-button-play svg { width: 16px !important; height: 16px !important; }

    /* Footer: keep only like + •••, inline on the right (all other actions live in the ••• menu). */
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound__waveform,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .commentForm,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound__footerRight,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .purchaseLink__container,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundActions .sc-button:not(.sc-button-like):not(.sc-button-more),
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .compactTrackList,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound__trackList,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound__tierIndicator
    { display: none !important; }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound__footer,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound__soundActions,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundActions {
      display: flex !important; align-items: center !important;
      flex: none !important; margin: 0 !important; padding: 0 !important; height: auto !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundActions .sc-button-group {
      display: flex !important; align-items: center !important; gap: 4px !important;
      float: none !important; margin: 0 !important; padding: 0 !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound .soundActions .sc-button {
      position: static !important; float: none !important; flex: none !important; box-sizing: border-box !important;
      display: inline-flex !important; align-items: center !important; justify-content: center !important;
      width: 28px !important; height: 28px !important; min-width: 28px !important; max-width: 28px !important;
      min-height: 28px !important; max-height: 28px !important; padding: 0 !important; margin: 0 !important;
      color: rgba(var(--cp-label-rgb), 0.82) !important;
      background: rgba(var(--cp-label-rgb), 0.06) !important;
      border: 0 !important; border-radius: 50% !important; overflow: hidden !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.14) !important;
      -webkit-backdrop-filter: none !important; backdrop-filter: none !important;
      opacity: 1 !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound:hover .soundActions .sc-button {
      color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.09) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.2) !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound .soundActions .sc-button:hover {
      color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.16) !important;
      border-radius: 50% !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.28) !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound .soundActions .sc-button:active {
      color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.22) !important;
      border-radius: 50% !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound .soundActions .sc-button-like.sc-button-selected {
      color: var(--cp-accent) !important;
      background: rgba(var(--cp-accent-rgb), 0.13) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-accent-rgb), 0.3) !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .sound .soundActions .sc-button-like.sc-button-selected:hover {
      color: var(--cp-accent) !important;
      background: rgba(var(--cp-accent-rgb), 0.22) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-accent-rgb), 0.42) !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundActions .sc-button > div,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundActions .sc-button:hover > div,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundActions .sc-button:active > div {
      display: flex !important; align-items: center !important; justify-content: center !important;
      width: auto !important; height: auto !important; margin: 0 !important; padding: 0 !important;
      background: transparent !important; border: 0 !important; box-shadow: none !important; color: inherit !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundActions .sc-button::before,
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundActions .sc-button::after { display: none !important; }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundActions .sc-button svg {
      width: 15px !important; height: 15px !important; margin: 0 !important;
    }
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundActions .sc-button :is(.sc-button-label, .sc-button-alt-labels):not(:has(svg)),
    .cp-view-compact :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item, .conversation) .soundActions .sc-button-like span:not(:has(svg)) { display: none !important; }

    /* ── Full waveform view (.cp-view-waveform) ───────────────────────────────────────────
       Restores SoundCloud's native full track view (160px artwork, interactive waveform,
       comments, full action bar, mini stats). Hide the synthetic compact-only ••• button. */
    .cp-view-waveform :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundActions .cp-more { display: none !important; }
    .cp-view-waveform :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) { margin-bottom: 24px !important; }

    /* ── Tiles grid for sound lists (.cp-view-tiles on History, Search, Profiles, Tags) ───
       Turns .soundList / .searchList into a responsive square-artwork tile grid matching
       SoundCloud's native .badgeList, with the native Liquid Glass hover play button. */
    .cp-view-tiles :is(.soundList__list, .soundList:has(> .soundList__item), .searchList__list, .tagsList__list, .lazyLoadingList__list:has(> :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item))) {
      display: grid !important;
      grid-template-columns: repeat(auto-fill, minmax(170px, 1fr)) !important;
      gap: 24px 20px !important;
      padding: 8px 16px !important; margin: 0 !important;
    }
    .l-user-main .cp-view-tiles :is(.soundList__list, .soundList:has(> .soundList__item), .lazyLoadingList__list:has(> .soundList__item)),
    .l-user-main.cp-view-tiles :is(.soundList__list, .soundList:has(> .soundList__item), .lazyLoadingList__list:has(> .soundList__item)) {
      grid-template-columns: repeat(auto-fill, minmax(168px, 1fr)) !important;
      gap: 22px 18px !important;
      padding: 8px 10px !important;
    }
    .cp-view-tiles :is(.soundList__item, .spotlight__item, .tagsList__item):not(:has(.sound)) { display: none !important; }
    .cp-view-tiles .searchResultGroupHeading,
    .cp-view-tiles:has(.sound) .searchList__item:not(:has(.sound)) { grid-column: 1 / -1 !important; }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item):has(.sound) {
      margin: 0 !important; padding: 0 !important; border: 0 !important; min-width: 0 !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound {
      position: relative !important; margin: 0 !important; padding: 0 !important; border: 0 !important;
      background: transparent !important; min-height: 0 !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound__body {
      position: relative !important; display: flex !important; flex-direction: column !important;
      margin: 0 !important; padding: 0 !important; min-height: 0 !important; height: auto !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound__artwork {
      position: relative !important; float: none !important; width: 100% !important;
      aspect-ratio: 1 / 1 !important; height: auto !important; margin: 0 0 8px 0 !important;
      border-radius: 6px !important; overflow: hidden !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound__coverArt,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound__artwork .image,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound__artwork .sc-artwork {
      display: block !important; width: 100% !important; height: 100% !important;
      border-radius: 6px !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) :is(.sound__content, .visualSound__wrapper) {
      position: static !important; display: block !important; text-align: left !important;
      margin: 0 !important; padding: 0 !important;
      min-width: 0 !important; width: 100% !important; height: auto !important; min-height: 0 !important;
      background: transparent !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound__header {
      position: static !important; margin: 0 !important; padding: 0 !important;
      height: auto !important; min-height: 0 !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundTitle,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundTitle__titleContainer {
      position: static !important; display: block !important; margin: 0 !important; padding: 0 !important;
      min-width: 0 !important; width: 100% !important; height: auto !important; min-height: 0 !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundTitle__usernameTitleContainer {
      display: flex !important; flex-direction: column-reverse !important; min-width: 0 !important; margin: 0 !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundTitle__title,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundTitle__title span {
      font-size: 13px !important; font-weight: 500 !important; line-height: 18px !important;
      white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis !important; display: block !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundTitle__secondary,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundTitle__username,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundTitle__usernameText {
      font-size: 12px !important; line-height: 16px !important; color: var(--cp-secondary) !important;
      white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis !important; display: block !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundTitle__playButton {
      opacity: 0 !important; pointer-events: none !important; position: absolute !important;
      width: 0 !important; height: 0 !important; overflow: hidden !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound__waveform,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .commentForm,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound__footerRight,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .purchaseLink__container,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundTitle__additionalContainer,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundActions .sc-button:not(.sc-button-like):not(.sc-button-more),
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .compactTrackList,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound__trackList,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound__tierIndicator
    { display: none !important; }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound__footer {
      position: absolute !important; right: 6px !important; bottom: 48px !important; z-index: 3 !important;
      margin: 0 !important; padding: 0 !important; height: auto !important;
      opacity: 0; transition: opacity 0.12s ease !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound:is(:hover, .cp-tile-hover, :focus-within) .sound__footer { opacity: 1; }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound__soundActions,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundActions,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundActions .sc-button-group {
      display: flex !important; align-items: center !important; gap: 5px !important;
      float: none !important; margin: 0 !important; padding: 0 !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound .soundActions .sc-button {
      position: static !important; float: none !important; flex: none !important; box-sizing: border-box !important;
      display: inline-flex !important; align-items: center !important; justify-content: center !important;
      width: 30px !important; height: 30px !important; min-width: 30px !important; max-width: 30px !important;
      min-height: 30px !important; max-height: 30px !important; padding: 0 !important; margin: 0 !important;
      color: #fff !important; background: rgba(18, 18, 20, 0.78) !important;
      -webkit-backdrop-filter: blur(16px) saturate(1.6) !important; backdrop-filter: blur(16px) saturate(1.6) !important;
      border: 0 !important; border-radius: 50% !important;
      box-shadow: inset 0 0.5px 0 rgba(255, 255, 255, 0.32),
                  0 0 0 0.5px rgba(255, 255, 255, 0.24),
                  0 2px 8px rgba(0, 0, 0, 0.45) !important;
      transition: background-color 0.14s ease, transform 0.12s ease, box-shadow 0.14s ease !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound .soundActions .sc-button:hover {
      color: #fff !important; background: rgba(32, 32, 36, 0.92) !important;
      transform: scale(1.06) !important;
      box-shadow: inset 0 0.5px 0 rgba(255, 255, 255, 0.42),
                  0 0 0 0.5px rgba(255, 255, 255, 0.38),
                  0 4px 12px rgba(0, 0, 0, 0.55) !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound .soundActions .sc-button:active {
      color: #fff !important; background: rgba(12, 12, 14, 0.96) !important;
      transform: scale(0.96) !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound .soundActions .sc-button-like.sc-button-selected,
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .sound .soundActions .sc-button-like.sc-button-selected:hover {
      color: color-mix(in srgb, var(--cp-accent) 82%, #fff) !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundActions .sc-button > div {
      display: flex !important; align-items: center !important; justify-content: center !important;
      width: auto !important; height: auto !important; margin: 0 !important; padding: 0 !important;
      background: transparent !important; border: 0 !important; box-shadow: none !important; color: inherit !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundActions .sc-button svg {
      width: 15px !important; height: 15px !important; margin: 0 !important;
    }
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundActions .sc-button :is(.sc-button-label, .sc-button-alt-labels):not(:has(svg)),
    .cp-view-tiles :is(.soundList__item, .searchList__item, .historicalPlays__item, .tagsList__item) .soundActions .sc-button-like span:not(:has(svg)) { display: none !important; }

    /* ── Compact list for tile collections (.cp-view-compact on Playlists, Albums, Stations, Following) ── */
    .cp-view-compact :is(.badgeList__list, .lazyLoadingList__list:has(> .badgeList__item)) {
      display: flex !important; flex-direction: column !important; gap: 0 !important;
      margin: 0 !important; padding: 0 8px !important;
    }
    .cp-view-compact .badgeList__item {
      float: none !important; width: 100% !important; max-width: none !important;
      margin: 0 !important; padding: 0 !important; display: block !important;
    }
    /* Hide SoundCloud's empty grid-filler placeholder tiles in compact list mode. */
    .cp-view-compact .badgeList__item:not(:has(a[href])) { display: none !important; }
    .cp-view-compact .badgeList__item > div { margin: 0 !important; padding: 0 !important; }
    .cp-view-compact .badgeList__item .playableTile {
      position: relative !important; display: flex !important; flex-direction: row !important;
      align-items: center !important; gap: 10px !important;
      width: 100% !important; margin: 0 !important; padding: 4px 10px !important;
      border-radius: 6px !important; box-sizing: border-box !important;
    }
    .cp-view-compact .badgeList__item:nth-child(even) .playableTile { background: rgba(var(--cp-label-rgb), 0.035); }
    .cp-view-compact .badgeList__item .playableTile:hover { background: rgba(var(--cp-label-rgb), 0.08) !important; }
    .cp-view-compact .badgeList__item .playableTile__artwork {
      position: static !important; overflow: visible !important; flex: none !important;
      width: 36px !important; height: 36px !important; min-width: 36px !important; min-height: 36px !important;
      margin: 0 !important; padding: 0 !important;
    }
    .cp-view-compact .badgeList__item .playableTile__artworkLink,
    .cp-view-compact .badgeList__item .playableTile__image,
    .cp-view-compact .badgeList__item .playableTile__image .image,
    .cp-view-compact .badgeList__item .playableTile__image .sc-artwork {
      display: block !important; width: 36px !important; height: 36px !important;
      padding: 0 !important; margin: 0 !important; border-radius: 4px !important; overflow: hidden !important;
    }
    .cp-view-compact .badgeList__item .playableTile__imageOverlay { display: none !important; }
    /* Play button overlaid on the 36x36 artwork on hover / while playing */
    .cp-view-compact .badgeList__item .playableTile__playButton {
      position: absolute !important; left: 10px !important; top: 50% !important; right: auto !important; bottom: auto !important;
      transform: translateY(-50%) !important; width: 36px !important; height: 36px !important;
      margin: 0 !important; padding: 0 !important; z-index: 2 !important;
      opacity: 0 !important; pointer-events: none !important; transition: opacity 0.12s !important;
    }
    .cp-view-compact .badgeList__item .playableTile:hover .playableTile__playButton,
    .cp-view-compact .badgeList__item .playableTile__playButton:has(.sc-button-pause) {
      opacity: 1 !important; pointer-events: auto !important;
    }
    html body .cp-view-compact .badgeList__item .playableTile__playButton .sc-button.sc-button-play {
      width: 36px !important; height: 36px !important; border-radius: 4px !important;
      background: rgba(0, 0, 0, 0.45) !important; box-shadow: none !important;
      -webkit-backdrop-filter: none !important; backdrop-filter: none !important;
    }
    html body .cp-view-compact .badgeList__item .playableTile__playButton .sc-button.sc-button-play svg {
      width: 16px !important; height: 16px !important;
      background-image: none !important; background-color: currentColor !important;
      -webkit-backdrop-filter: none !important; backdrop-filter: none !important;
    }
    .cp-view-compact .badgeList__item .playableTile__description {
      flex: 1 1 auto !important; min-width: 0 !important; margin: 0 !important; padding: 0 72px 0 0 !important;
      display: flex !important; flex-direction: column !important; justify-content: center !important;
    }
    .cp-view-compact .badgeList__item .playableTile__heading,
    .cp-view-compact .badgeList__item .playableTile__mainHeading {
      font-size: 13px !important; font-weight: 500 !important; line-height: 17px !important;
      margin: 0 !important; white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis !important;
      display: block !important;
    }
    .cp-view-compact .badgeList__item .playableTile__usernameHeadingContainer,
    .cp-view-compact .badgeList__item .playableTile__usernameHeading {
      font-size: 12px !important; line-height: 16px !important; color: var(--cp-secondary) !important;
      margin: 0 !important; white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis !important;
    }
    /* Inline Like + ••• actions on the right of the compact tile row */
    .cp-view-compact .badgeList__item .playableTile__actions {
      position: absolute !important; right: 10px !important; top: 50% !important; left: auto !important; bottom: auto !important;
      transform: translateY(-50%) !important; width: auto !important; height: auto !important;
      margin: 0 !important; padding: 0 !important; display: flex !important; align-items: center !important;
      opacity: 1 !important; visibility: visible !important; pointer-events: auto !important;
    }
    .cp-view-compact .badgeList__item .playableTile__actionWrapper {
      position: static !important; display: flex !important; align-items: center !important; gap: 4px !important;
      margin: 0 !important; padding: 0 !important;
    }
    .cp-view-compact .badgeList__item .playableTile__actions .sc-button:not(.sc-button-like):not(.sc-button-more) {
      display: none !important;
    }
    .cp-view-compact .badgeList__item .playableTile__actions .sc-button {
      position: static !important; float: none !important; flex: none !important; box-sizing: border-box !important;
      display: inline-flex !important; align-items: center !important; justify-content: center !important;
      width: 28px !important; height: 28px !important; min-width: 28px !important; max-width: 28px !important;
      min-height: 28px !important; max-height: 28px !important; padding: 0 !important; margin: 0 !important;
      color: rgba(var(--cp-label-rgb), 0.82) !important;
      background: rgba(var(--cp-label-rgb), 0.06) !important; border: 0 !important;
      border-radius: 50% !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.14) !important;
      -webkit-backdrop-filter: none !important; backdrop-filter: none !important;
      opacity: 1 !important;
    }
    .cp-view-compact .badgeList__item .playableTile:hover .playableTile__actions .sc-button {
      color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.09) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.2) !important;
    }
    .cp-view-compact .badgeList__item .playableTile__actions .sc-button:hover {
      color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.16) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.28) !important;
    }
    .cp-view-compact .badgeList__item .playableTile__actions .sc-button:active {
      color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.22) !important;
    }
    .cp-view-compact .badgeList__item .playableTile__actions .sc-button-like.sc-button-selected {
      color: var(--cp-accent) !important;
      background: rgba(var(--cp-accent-rgb), 0.13) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-accent-rgb), 0.3) !important;
    }
    .cp-view-compact .badgeList__item .playableTile__actions .sc-button-like.sc-button-selected:hover {
      color: var(--cp-accent) !important;
      background: rgba(var(--cp-accent-rgb), 0.22) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-accent-rgb), 0.42) !important;
    }
    .cp-view-compact .badgeList__item .playableTile__actions .sc-button > div {
      display: flex !important; align-items: center !important; justify-content: center !important;
      width: auto !important; height: auto !important; margin: 0 !important; padding: 0 !important;
      background: transparent !important; border: 0 !important; box-shadow: none !important; color: inherit !important;
    }
    .cp-view-compact .badgeList__item .playableTile__actions .sc-button svg {
      width: 15px !important; height: 15px !important; margin: 0 !important;
    }

    /* Compact list for user/profile badges (Following, Followers) */
    .cp-view-compact .badgeList__item .userBadge {
      display: flex !important; flex-direction: row !important; align-items: center !important; gap: 10px !important;
      width: 100% !important; margin: 0 !important; padding: 4px 10px !important;
      border-radius: 6px !important; box-sizing: border-box !important; text-align: left !important;
    }
    .cp-view-compact .badgeList__item:nth-child(even) .userBadge { background: rgba(var(--cp-label-rgb), 0.035); }
    .cp-view-compact .badgeList__item .userBadge:hover { background: rgba(var(--cp-label-rgb), 0.08) !important; }
    .cp-view-compact .badgeList__item .userBadge__avatar,
    .cp-view-compact .badgeList__item .userBadge__avatar .image,
    .cp-view-compact .badgeList__item .userBadge__avatar .sc-artwork {
      width: 36px !important; height: 36px !important; margin: 0 !important; flex: none !important;
    }
    .cp-view-compact .badgeList__item .userBadge__title {
      flex: 1 1 auto !important; min-width: 0 !important; margin: 0 !important; text-align: left !important;
      font-size: 13px !important; font-weight: 500 !important;
    }
    .cp-view-compact .badgeList__item .userBadge__stats { margin: 0 12px 0 0 !important; flex: none !important; }
    .cp-view-compact .badgeList__item .userBadge__actions { margin: 0 !important; flex: none !important; }

    /* ── Search results: categories as a pill row under the title, results full width ───── */
    .l-search { padding-top: 0 !important; }
    .l-search .l-fixed-top, .l-search .l-fixed-left {
      position: static !important; top: auto !important; left: auto !important;
      width: auto !important; height: auto !important; transform: none !important; float: none !important;
    }
    /* The filter bar's column must stack above the results so its option menus aren't covered. */
    .l-search .l-fixed-left { position: relative !important; z-index: 40 !important; }
    .l-search .l-fixed-left, .l-search .searchOptions, .l-search .searchOptions__scrollable,
    .l-search .searchOptions__scrollableInner, .l-search .searchOptions__container {
      width: auto !important; max-width: none !important;
    }
    .l-search .searchOptions__scrollable, .l-search .searchOptions__scrollableInner {
      position: static !important; height: auto !important; overflow: visible !important;
      transform: none !important; will-change: auto !important;   /* GPU layers can clip too */
    }
    .l-search .l-main {
      position: relative !important; z-index: 1 !important;
      margin: 0 !important; width: auto !important; max-width: none !important; float: none !important;
      padding: 0 8px !important; border: 0 !important;
    }
    .l-search .searchTitle { padding: 12px 0 8px !important; }
    .l-search .searchTitle__text { font-size: 22px !important; font-weight: 700 !important; letter-spacing: -0.01em !important; padding: 0 16px !important; }
    .l-search .searchOptions__footer { display: none !important; }
    /* One bar: [categories] (| [filter pills ▾] when present)   then a slim scrolling row of tags. */
    .l-search .searchOptions__container {
      display: flex !important; flex-wrap: wrap !important; align-items: center !important;
      gap: 6px !important; padding: 0 16px 12px !important;
    }
    .l-search .searchOptions__navigation {
      display: flex !important; flex-direction: row !important; flex-wrap: nowrap !important;
      gap: 6px !important; width: auto !important; margin: 0 !important; padding: 0 !important;
    }
    .l-search .searchOptions__container:has(.searchOptions__filterCategory) .searchOptions__navigation {
      padding-right: 10px !important; margin-right: 4px !important;
      border-right: 0.5px solid rgba(var(--cp-label-rgb), 0.16) !important;
    }
    .l-search .searchOptions__filtersTitle, .l-search .searchTags__title { display: none !important; }

    /* Filters: capsule pill button; clicking opens a native NSMenu (Menus.swift). */
    .l-search .searchOptions__filterWrapper { position: relative !important; margin: 0 !important; padding: 0 !important; }
    .l-search .searchOptions__filterCategory {
      display: inline-flex !important; align-items: center !important; gap: 6px; height: 26px !important;
      padding: 0 10px 0 12px !important; border-radius: 13px !important; box-sizing: border-box !important;
      font-size: 13px !important; font-weight: 500 !important; line-height: 1 !important;
      color: var(--cp-label) !important; text-decoration: none !important;
      background: rgba(var(--cp-label-rgb), 0.08) !important; border: 0.5px solid rgba(var(--cp-label-rgb), 0.12) !important;
    }
    .l-search .searchOptions__filterCategory:hover { background: rgba(var(--cp-label-rgb), 0.14) !important; }
    .l-search .searchOptions__filterCategory::after {
      content: ""; width: 9px; height: 6px; background: var(--cp-secondary);
      -webkit-mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 6'%3E%3Cpath d='M1 1l4 4 4-4' fill='none' stroke='black' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E") center / contain no-repeat;
    }
    .l-search .searchOptions__filterList { display: none !important; }

    /* Tags: one slim row of chips that scrolls sideways. */
    .l-search .searchTags {
      flex-basis: 100% !important; min-width: 0 !important; margin: 4px 0 0 !important; padding: 0 !important; border: 0 !important;
    }
    .l-search .searchTags .sc-tag-group {
      display: flex !important; flex-wrap: nowrap !important; gap: 6px !important; overflow-x: auto !important; scrollbar-width: none;
    }
    .l-search .searchTags .sc-tag-group::-webkit-scrollbar { display: none; }
    .l-search .searchTags__tag {
      flex: none !important; display: inline-flex !important; align-items: center !important;
      height: 22px !important; padding: 0 9px !important; margin: 0 !important; border-radius: 11px !important;
      font-size: 12px !important; color: var(--cp-secondary) !important; border: 0 !important;
      background: rgba(var(--cp-label-rgb), 0.06) !important;
    }
    .l-search .searchTags__tag:hover { color: var(--cp-label) !important; background: rgba(var(--cp-label-rgb), 0.11) !important; }
    .l-search .searchOptions__navigationItem {
      margin: 0 !important; padding: 0 !important; background: none !important; border: 0 !important;
      width: auto !important; flex: none !important; display: block !important;
    }
    .l-search .searchOptions__navigationLink {
      display: flex !important; align-items: center !important; height: 26px !important; padding: 0 12px !important;
      border-radius: 13px !important; font-size: 13px !important; font-weight: 500 !important;
      color: var(--cp-label) !important; text-decoration: none !important;
      background: rgba(var(--cp-label-rgb), 0.06) !important; border: 0.5px solid rgba(var(--cp-label-rgb), 0.1) !important;
    }
    .l-search .searchOptions__navigationLink:hover { background: rgba(var(--cp-label-rgb), 0.11) !important; }
    .l-search .searchOptions__navigationItem.active .searchOptions__navigationLink {
      background: rgba(var(--cp-label-rgb), 0.2) !important; font-weight: 600 !important;
    }
    .l-search .searchResultGroupHeading { margin: 0 8px 6px !important; }
    .l-search .resultCounts { display: none !important; }

    /* /search/people city filter row: single scrolling row of 22px chips (matching .searchTags). */
    .l-search .searchOptions__container > :has(a[href*="filter.place="]) {
      order: 10 !important; flex-basis: 100% !important; min-width: 0 !important; width: 100% !important;
      margin: 4px 0 0 !important; padding: 0 !important; border: 0 !important;
      column-count: unset !important; columns: auto !important;
    }
    .l-search :is(div, section, nav):has(> ul a[href*="filter.place="]):not(.l-search, .l-main, .searchOptions, .searchOptions__scrollable, .searchOptions__scrollableInner, .searchOptions__container) {
      flex-basis: 100% !important; min-width: 0 !important; width: 100% !important;
      margin: 2px 0 6px !important; padding: 0 !important; border: 0 !important;
      column-count: unset !important; columns: auto !important;
    }
    .l-search ul:has(a[href*="filter.place="]),
    .l-search div:has(> a[href*="filter.place="]) {
      display: flex !important; flex-direction: row !important; flex-wrap: nowrap !important;
      align-items: center !important; gap: 6px !important;
      overflow-x: auto !important; overflow-y: hidden !important; scrollbar-width: none !important;
      margin: 2px 0 8px !important; padding: 0 10px !important;
      width: auto !important; max-width: none !important; list-style: none !important;
      column-count: unset !important; columns: auto !important;
    }
    .l-search .searchOptions__container ul:has(a[href*="filter.place="]),
    .l-search .searchOptions__container div:has(> a[href*="filter.place="]) {
      padding: 0 !important; margin: 2px 0 0 !important; flex-basis: 100% !important;
    }
    .l-search ul:has(a[href*="filter.place="])::-webkit-scrollbar,
    .l-search div:has(> a[href*="filter.place="])::-webkit-scrollbar { display: none !important; }
    .l-search li:has(> a[href*="filter.place="]) {
      flex: none !important; width: auto !important; min-width: 0 !important; max-width: none !important;
      float: none !important; margin: 0 !important; padding: 0 !important; list-style: none !important;
    }
    .l-search a[href*="filter.place="] {
      flex: none !important; display: inline-flex !important; align-items: center !important;
      width: auto !important; min-width: 0 !important; max-width: none !important;
      height: 22px !important; padding: 0 10px !important; margin: 0 !important;
      border-radius: 11px !important; font-size: 12px !important; font-weight: 500 !important;
      color: var(--cp-secondary) !important; text-decoration: none !important;
      background: rgba(var(--cp-label-rgb), 0.06) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.08) !important;
      white-space: nowrap !important; text-transform: capitalize !important;
    }
    .l-search a[href*="filter.place="]:hover {
      color: var(--cp-label) !important; background: rgba(var(--cp-label-rgb), 0.12) !important;
    }

    /* Compact Apple Music artist rows for .userItem on Search (/search & /search/people) */
    .searchList__item:has(.userItem) { margin: 0 !important; padding: 0 !important; border: 0 !important; }
    .l-search:not(.cp-view-tiles) .searchList__item:has(.userItem):nth-child(even) .userItem,
    .l-search.cp-view-tiles:has(.sound) .searchList__item:has(.userItem) .userItem {
      background: rgba(var(--cp-label-rgb), 0.035);
    }
    .l-search:not(.cp-view-tiles) .userItem,
    .l-search.cp-view-tiles:has(.sound) .userItem {
      display: flex !important; flex-direction: row !important; align-items: center !important;
      gap: 12px !important; padding: 6px 10px !important; margin: 0 0 2px !important;
      border-radius: 8px !important; min-height: 0 !important; border: 0 !important;
    }
    .l-search:not(.cp-view-tiles) .userItem:hover,
    .l-search.cp-view-tiles:has(.sound) .userItem:hover {
      background: rgba(var(--cp-label-rgb), 0.08) !important;
    }
    .l-search:not(.cp-view-tiles) :is(.userItem__coverArt, .userItem__coverArt .image, .userItem__coverArt .sc-artwork),
    .l-search.cp-view-tiles:has(.sound) :is(.userItem__coverArt, .userItem__coverArt .image, .userItem__coverArt .sc-artwork) {
      width: 52px !important; height: 52px !important; min-width: 52px !important; min-height: 52px !important;
      flex: none !important; margin: 0 !important; float: none !important;
      border-radius: 50% !important; overflow: hidden !important;
    }
    .l-search:not(.cp-view-tiles) .userItem__content,
    .l-search.cp-view-tiles:has(.sound) .userItem__content {
      flex: 1 1 auto !important; min-width: 0 !important; min-height: 0 !important;
      display: flex !important; align-items: center !important; justify-content: space-between !important;
      gap: 12px !important; margin: 0 !important; padding: 0 !important;
    }
    .l-search:not(.cp-view-tiles) .userItem__title,
    .l-search.cp-view-tiles:has(.sound) .userItem__title {
      font-size: 14px !important; font-weight: 600 !important; line-height: 18px !important; margin: 0 !important;
    }
    .l-search:not(.cp-view-tiles) .userItem__details,
    .l-search.cp-view-tiles:has(.sound) .userItem__details {
      font-size: 12px !important; line-height: 16px !important; color: var(--cp-secondary) !important;
      margin: 1px 0 0 !important; white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis !important;
    }
    /* Names filled in from the URL slug (the real one is only invisible characters). */
    .cp-untitled { font-style: italic !important; }
    :is(.l-search:not(.cp-view-tiles), .l-search.cp-view-tiles:has(.sound)) .userItem__details > * { display: inline !important; }
    :is(.l-search:not(.cp-view-tiles), .l-search.cp-view-tiles:has(.sound)) .userItem__details > :not(:empty) ~ :not(:empty)::before {
      content: " · "; color: var(--cp-secondary);
    }
    .l-search:not(.cp-view-tiles) .userItem__details:empty,
    .l-search.cp-view-tiles:has(.sound) .userItem__details:empty { display: none !important; }
    .l-search:not(.cp-view-tiles) .userItem .sc-ministats-group,
    .l-search.cp-view-tiles:has(.sound) .userItem .sc-ministats-group { margin-top: 2px !important; }
    /* Tiles mode on /search/people: circular artist grid */
    .l-search.cp-view-tiles:not(:has(.sound)) .userItem {
      display: flex !important; flex-direction: column !important; align-items: center !important;
      text-align: center !important; gap: 8px !important; padding: 8px !important; margin: 0 !important;
    }
    .l-search.cp-view-tiles:not(:has(.sound)) .userItem__coverArt {
      width: 136px !important; height: 136px !important; margin: 0 auto !important; float: none !important;
    }
    .l-search.cp-view-tiles:not(:has(.sound)) :is(.userItem__coverArt .image, .userItem__coverArt .sc-artwork) {
      width: 100% !important; height: 100% !important;
    }
    .l-search.cp-view-tiles:not(:has(.sound)) .userItem__content {
      display: flex !important; flex-direction: column !important; align-items: center !important;
      gap: 4px !important; margin: 0 !important; padding: 0 !important; width: 100% !important; min-height: 0 !important;
    }
    .l-search.cp-view-tiles:not(:has(.sound)) .userItem__title { font-size: 13.5px !important; font-weight: 600 !important; margin: 0 !important; }
    .l-search.cp-view-tiles:not(:has(.sound)) .userItem__details { display: none !important; }

    /* ── Playlist / album hero: rounded gradient card, no black label boxes ──────────────── */
    .l-listen-hero, .l-hero-banner { padding: 12px 16px 0 !important; }
    :is(.l-listen-hero, .l-hero-banner) .fullHero {
      margin: 0 !important; width: auto !important; border-radius: 14px !important;
      overflow: hidden !important; position: relative !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.08) !important;
    }
    :is(.l-listen-hero, .l-hero-banner) .backgroundGradient, :is(.l-listen-hero, .l-hero-banner) .backgroundGradient__buffer {
      position: absolute !important; inset: 0 !important; border-radius: inherit !important;
    }
    :is(.l-listen-hero, .l-hero-banner) .backgroundGradient__imageOverlay {
      position: absolute !important; inset: 0 !important;
      background: linear-gradient(to bottom, rgba(0, 0, 0, 0) 45%, rgba(0, 0, 0, 0.28) 100%) !important;
    }
    /* Text sits directly on the gradient: drop SoundCloud's black "shrinkwrap" label boxes. */
    :is(.l-listen-hero, .l-hero-banner) [class*="g-type-shrinkwrap"], :is(.l-listen-hero, .l-hero-banner) [class*="g-type-shrinkwrap"] * {
      background: transparent !important; box-shadow: none !important; padding: 0 !important;
    }
    :is(.l-listen-hero, .l-hero-banner) [class*="g-type-shrinkwrap"]::before,
    :is(.l-listen-hero, .l-hero-banner) .soundTitle__title::before, :is(.l-listen-hero, .l-hero-banner) .soundTitle__username::before {
      display: none !important; content: none !important;   /* the label box is drawn here */
    }
    :is(.l-listen-hero, .l-hero-banner) :is(.soundTitle__title, .soundTitle__title span, .fullHero__titleTextLineBig, .fullHero__titleTextLineBig *:not(.sc-label, .sc-label *)) {
      color: #fff !important; font-size: 30px !important; font-weight: 700 !important; line-height: 1.15 !important;
      letter-spacing: -0.02em !important; text-shadow: 0 1px 12px rgba(0, 0, 0, 0.35);
    }
    :is(.l-listen-hero, .l-hero-banner) .soundTitle__username, :is(.l-listen-hero, .l-hero-banner) .soundTitle__username a,
    :is(.l-listen-hero, .l-hero-banner) .fullHero__uploadTime, :is(.l-listen-hero, .l-hero-banner) .fullHero__uploadTime * {
      color: rgba(255, 255, 255, 0.82) !important; font-size: 15px !important; font-weight: 500 !important;
      text-shadow: 0 1px 8px rgba(0, 0, 0, 0.3);
    }
    :is(.l-listen-hero, .l-hero-banner) .fullHero__uploadTime, :is(.l-listen-hero, .l-hero-banner) .fullHero__uploadTime * { font-size: 12px !important; font-weight: 400 !important; }
    :is(.l-listen-hero, .l-hero-banner) .soundTitle__usernameHeroContainer { margin-top: 6px !important; }
    /* Playlist / album / station / discover-set hero = track header: blurred-artwork backdrop
       (--cp-art, set by Injected heroLook) instead of flat grey or two-colour gradients. */
    :is(.l-listen-hero, .l-hero-banner) .fullHero { isolation: isolate; background: #3a3a3c !important; }
    :is(.l-listen-hero, .l-hero-banner) .fullHero::before {
      content: ""; position: absolute; inset: -80px; z-index: -2; pointer-events: none;
      background: var(--cp-art, none) center / cover no-repeat;
      filter: blur(70px) saturate(1.5) brightness(0.8);
    }
    :is(.l-listen-hero, .l-hero-banner) .fullHero::after {
      content: ""; position: absolute; inset: 0; z-index: -1; pointer-events: none;
      background: linear-gradient(to bottom, rgba(0, 0, 0, 0.05) 30%, rgba(0, 0, 0, 0.35) 100%);
    }
    :is(.l-listen-hero, .l-hero-banner) .fullHero .backgroundGradient { display: none !important; }
    /* "Updated 7 years ago" + tag (top right) → "artist · 7 years ago" under the title, as on tracks. */
    .l-listen-hero .fullHero__info { display: none !important; }
    .l-listen-hero .soundTitle__usernameHeroContainer { display: flex !important; align-items: baseline !important; gap: 6px !important; }
    .l-listen-hero .soundTitle__usernameHeroContainer > .soundTitle__username {
      flex: 0 1 auto !important; min-width: 0 !important; white-space: nowrap !important;
      overflow: hidden !important; text-overflow: ellipsis !important;
    }
    .l-listen-hero .cp-hero-meta {
      flex: none; white-space: nowrap; color: rgba(255, 255, 255, 0.82) !important;
      font-size: 15px !important; font-weight: 500 !important; text-shadow: 0 1px 8px rgba(0, 0, 0, 0.3);
    }
    /* While the playlist plays, SoundCloud shows the playing track's waveform at the bottom:
       lift it above the action row (40px + 12px gap) and draw it white like the track header's
       (Injected heroWaveFilters: played bars solid, unplayed ~45%, plain white time labels). */
    .l-listen-hero .fullHero:has(.cp-hero-row) .fullHero__waveform { margin-bottom: 52px !important; }
    .l-listen-hero .fullHero__waveform .waveform__scene canvas:first-child {
      filter: url(#cp-wave-bars);
      -webkit-mask-image: linear-gradient(to bottom, #000 70%, rgba(0, 0, 0, 0.5) 70%);
      mask-image: linear-gradient(to bottom, #000 70%, rgba(0, 0, 0, 0.5) 70%);
    }
    .l-listen-hero .fullHero__waveform .waveform__scene canvas:not(:first-child) {
      filter: url(#cp-wave-time) drop-shadow(0 1px 2px rgba(0, 0, 0, 0.35));
    }
    :is(.l-listen-hero, .l-hero-banner) .fullHero__artwork .image, :is(.l-listen-hero, .l-hero-banner) .fullHero__artwork .sc-artwork {
      border-radius: 10px !important; box-shadow: 0 8px 24px rgba(0, 0, 0, 0.35) !important;
    }
    :is(.l-listen-hero, .l-hero-banner) .genericTrackCount {
      background: rgba(0, 0, 0, 0.28) !important; color: #fff !important;
      -webkit-backdrop-filter: blur(20px) !important; backdrop-filter: blur(20px) !important;
      border: 0.5px solid rgba(255, 255, 255, 0.15) !important;
    }
    :is(.l-listen-hero, .l-hero-banner) .genericTrackCount * { color: #fff !important; }
    :is(.l-listen-hero, .l-hero-banner) .genericTrackCount__duration { color: rgba(255, 255, 255, 0.7) !important; }

    /* Station / system-playlist heroes: secondary line ("Track station", "Made for …"). */
    .l-hero-banner .fullHero__titleTextLineSmall, .l-hero-banner .fullHero__titleTextLineSmall * {
      color: rgba(255, 255, 255, 0.82) !important; font-size: 15px !important; font-weight: 500 !important;
      text-shadow: 0 1px 8px rgba(0, 0, 0, 0.3);
    }
    .l-hero-banner .fullHero__titleTextLineSmall { margin-top: 6px !important; }
    .l-hero-banner .fullHero__playerArea { display: none !important; }
    /* Header play button: see-through Liquid Glass with a second refractive glass layer in the play/pause glyph. */
    html body :is(.l-listen-hero, .l-hero-banner) :is(.fullHero__titleButton, .soundTitle__playButtonHero) .sc-button.sc-button-play {
      position: relative !important; overflow: hidden !important;
      border: 0 !important; color: #fff !important;
      background: rgba(255, 255, 255, 0.08) !important;
      -webkit-backdrop-filter: blur(12px) saturate(1.8) !important; backdrop-filter: blur(12px) saturate(1.8) !important;
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.45), inset 0 -0.5px 0 rgba(255, 255, 255, 0.14),
                  0 0 0 0.5px rgba(255, 255, 255, 0.24), 0 4px 14px rgba(0, 0, 0, 0.22) !important;
      transition: background-color 0.15s ease !important;
    }
    html body :is(.l-listen-hero, .l-hero-banner) :is(.fullHero__titleButton, .soundTitle__playButtonHero) .sc-button.sc-button-play svg {
      background-color: transparent !important;
      background-image: linear-gradient(155deg, rgba(255, 255, 255, 0.48) 0%, rgba(255, 255, 255, 0.14) 55%, rgba(255, 255, 255, 0.28) 100%) !important;
      -webkit-backdrop-filter: blur(22px) saturate(2.5) brightness(1.42) contrast(1.12) !important;
      backdrop-filter: blur(22px) saturate(2.5) brightness(1.42) contrast(1.12) !important;
    }
    html body :is(.l-listen-hero, .l-hero-banner) :is(.fullHero__titleButton, .soundTitle__playButtonHero) .sc-button.sc-button-play:hover {
      background: rgba(255, 255, 255, 0.15) !important;
    }
    html body :is(.l-listen-hero, .l-hero-banner) :is(.fullHero__titleButton, .soundTitle__playButtonHero) .sc-button.sc-button-play:hover svg {
      -webkit-backdrop-filter: blur(22px) saturate(2.7) brightness(1.55) contrast(1.14) !important;
      backdrop-filter: blur(22px) saturate(2.7) brightness(1.55) contrast(1.14) !important;
    }
    html body :is(.l-listen-hero, .l-hero-banner) :is(.fullHero__titleButton, .soundTitle__playButtonHero) .sc-button.sc-button-play:active {
      background: rgba(255, 255, 255, 0.22) !important;
    }
    .l-hero-banner .fullHero__titleText .sc-label {   /* "Private" badge: small pill, not title-sized */
      display: inline-flex !important; align-items: center; gap: 4px; vertical-align: middle;
      font-size: 11px !important; font-weight: 600 !important; letter-spacing: 0.04em !important; line-height: 1 !important;
      color: rgba(255, 255, 255, 0.85) !important; background: rgba(0, 0, 0, 0.28) !important;
      padding: 4px 7px !important; border-radius: 5px !important; text-shadow: none !important; bottom: 0 !important;
    }
    .l-hero-banner .fullHero__titleText .sc-label * { font-size: 11px !important; color: inherit !important; text-shadow: none !important; }
    /* Playlist / album / station action rows: round glass icon buttons, same size as the
       track header's (40px circles, 18px icons). Stations use labelled buttons: drop the text. */
    .systemPlaylistDetails__button .sc-button :is(.sc-button-label, .sc-button-alt-labels) { display: none !important; }
    :is(.listenEngagement__actions, .systemPlaylistDetails__button) .sc-button:not(.sc-button-play) {
      display: inline-flex !important; align-items: center !important; justify-content: center !important;
      width: 40px !important; height: 40px !important; min-width: 0 !important; padding: 0 !important;
      border-radius: 50% !important; line-height: 1 !important; vertical-align: middle !important;
    }
    .listenEngagement__actions .sc-button:not(.sc-button-play) { margin: 0 8px 0 0 !important; }
    :is(.listenEngagement__actions, .systemPlaylistDetails__button) .sc-button > div { margin: 0 !important; }
    :is(.listenEngagement__actions, .systemPlaylistDetails__button) .sc-button svg {
      width: 18px !important; height: 18px !important; margin: 0 !important;
    }
    .listenEngagement__actions .sc-button-label:has(> svg) { display: flex !important; margin: 0 !important; }
    /* The "Buy" cart link is a borderless tertiary button: give it the same glass. */
    .listenEngagement__actions .soundActions__purchaseLink {
      background: rgba(var(--cp-label-rgb), 0.07) !important; border: 0 !important; color: var(--cp-label) !important;
      -webkit-backdrop-filter: blur(16px) saturate(1.8) !important; backdrop-filter: blur(16px) saturate(1.8) !important;
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.22), inset 0 -0.5px 0 rgba(255, 255, 255, 0.06),
                  0 0 0 0.5px rgba(var(--cp-label-rgb), 0.14), 0 2px 8px rgba(0, 0, 0, 0.16) !important;
    }
    .listenEngagement__actions .soundActions__purchaseLink:hover { background: rgba(var(--cp-label-rgb), 0.13) !important; }
    .systemPlaylistDetails__button { margin-right: 8px !important; }

    /* Hero action row (Injected heroActions moves the buttons here): track-count pill + white
       glass buttons on the artwork tint, like the track header's comment field and buttons. */
    /* z-index: .fullHero__playerArea (the waveform, a later sibling) spans the bottom of the
       hero and would otherwise sit on top of the row and swallow every click on its buttons. */
    html body .fullHero__tracksSummary.cp-hero-row {
      display: flex !important; align-items: center !important; gap: 8px !important;
      left: 32px !important; bottom: 32px !important; right: auto !important;
      position: absolute !important; z-index: 2 !important;
    }
    html body .cp-hero-row :is(.cp-moved, .cp-moved .soundActions, .cp-moved .sc-button-group, .cp-moved .purchaseLink__container) {
      display: flex !important; align-items: center !important; gap: 8px !important; float: none !important;
      margin: 0 !important; padding: 0 !important; border: 0 !important; background: none !important;
    }
    html body .cp-hero-row :is(.systemPlaylistDetails__button, .cp-moved .sc-button-group > *) { margin: 0 !important; float: none !important; }
    html body .cp-hero-row :is(.sc-button:not(.sc-button-play), .genericTrackCount) {
      margin: 0 !important; border: 0 !important; outline: none !important;
      color: #fff !important; background: rgba(255, 255, 255, 0.14) !important;
      -webkit-backdrop-filter: blur(16px) saturate(1.8) !important; backdrop-filter: blur(16px) saturate(1.8) !important;
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35), inset 0 -0.5px 0 rgba(255, 255, 255, 0.1),
                  0 0 0 0.5px rgba(255, 255, 255, 0.18), 0 2px 10px rgba(0, 0, 0, 0.18) !important;
    }
    html body .cp-hero-row .sc-button:not(.sc-button-play):hover { background: rgba(255, 255, 255, 0.24) !important; }
    html body .cp-hero-row .sc-button:not(.sc-button-play):active { background: rgba(255, 255, 255, 0.3) !important; }
    /* Track count: "14 tracks · 40:12" in a text pill instead of the round badge. */
    html body .cp-hero-row .genericTrackCount {
      width: auto !important; height: 40px !important; padding: 0 16px !important; border-radius: 999px !important;
      box-sizing: border-box !important; display: flex !important; align-items: center !important; gap: 5px !important;
      text-transform: none !important; white-space: nowrap !important;
    }
    html body .cp-hero-row .genericTrackCount > * {
      color: #fff !important; font-size: 14px !important; font-weight: 500 !important; line-height: 1 !important;
      letter-spacing: 0 !important; margin: 0 !important; padding: 0 !important; text-transform: lowercase !important;
    }
    html body .cp-hero-row .genericTrackCount__title { font-weight: 600 !important; }
    html body .cp-hero-row .genericTrackCount__duration { color: rgba(255, 255, 255, 0.72) !important; }
    html body .cp-hero-row .genericTrackCount__duration::before { content: "·"; margin-right: 5px; }
    html body .cp-hero-row :is(.sc-ministats, .sc-ministats-group, .systemPlaylistDetails__likesCount) { display: none !important; }

    /* ── Album / Playlist / Station body: single-column full-width Apple Music tracklist ─── */
    .listenEngagement__footer { display: none !important; }
    .listenEngagement { border: 0 !important; box-shadow: none !important; margin: 0 !important; padding: 0 !important; }
    .l-listen-wrapper .l-about-left,
    .listenDetails__user,
    .trackList__footer,
    .listenDetails__end,
    .sc-classic-CloudIcon,
    .l-listen-wrapper .paging-eof,
    .systemPlaylistTrackList .paging-eof,
    .paging-eof { display: none !important; }
    #content:has(.l-listen-wrapper, .systemPlaylistTrackList, .listenDetails, .l-hero-banner) .l-main,
    .l-listen--main > .l-main,
    .l-listen-wrapper,
    .l-listen-wrapper .l-about-rows,
    .l-listen-wrapper .l-about-right,
    .l-listen-wrapper .l-about-main,
    .l-listen-wrapper .l-about-top,
    .listenDetails,
    .systemPlaylistTrackList {
      width: auto !important; max-width: none !important; min-width: 0 !important;
      float: none !important; margin: 0 !important; border: 0 !important;
    }
    #content:has(.l-listen-wrapper, .systemPlaylistTrackList, .listenDetails, .l-hero-banner) .l-main,
    .l-listen--main > .l-main {
      padding: 14px 16px 24px !important;
    }
    .l-listen-wrapper, .l-listen-wrapper .l-about-rows, .l-listen-wrapper .l-about-right, .l-listen-wrapper .l-about-main { padding: 0 !important; }
    .truncatedAudioInfo__wrapper::after,
    .truncatedAudioInfo__wrapper.m-overflow::after,
    .truncatedUserDescription__wrapper::after,
    .truncatedUserDescription.m-overflow .truncatedUserDescription__wrapper::after {
      background: linear-gradient(to bottom, rgba(var(--cp-bg-rgb), 0), var(--cp-bg)) !important;
    }
    :is(.trackList__list, .systemPlaylistTrackList__list) { margin: 0 !important; padding: 0 !important; border: 0 !important; }
    :is(.trackList__item, .systemPlaylistTrackList__item) { border: 0 !important; margin: 0 !important; padding: 0 !important; }
    .trackItem {
      display: flex !important; align-items: center !important; min-height: 42px !important;
      padding: 4px 10px !important; margin: 0 !important; border-radius: 6px !important;
      border: 0 !important; background: transparent !important;
    }
    :is(.trackList__item, .systemPlaylistTrackList__item):nth-child(even) .trackItem {
      background: rgba(var(--cp-label-rgb), 0.035) !important;
    }
    .trackItem:is(:hover, .active, .m-playing) {
      background: rgba(var(--cp-label-rgb), 0.08) !important;
    }
    .trackItem__image, .trackItem__image .image, .trackItem__image .sc-artwork {
      width: 34px !important; height: 34px !important; border-radius: 4px !important; flex: none !important;
    }
    .trackItem__number, .trackItem__numberWrapper {
      font-variant-numeric: tabular-nums !important; color: var(--cp-secondary) !important; font-size: 12.5px !important;
    }
    .trackItem__trackTitle { font-size: 13px !important; font-weight: 500 !important; color: var(--cp-label) !important; }
    .trackItem__username { font-size: 13px !important; color: var(--cp-secondary) !important; }
    .trackItem__additional {
      background: transparent !important; background-image: none !important; box-shadow: none !important;
    }

    /* ── Profile hero: same rounded card treatment as playlists ─────────────────────────── */
    .l-user-hero { padding: 12px 16px 0 !important; }
    .l-user-hero .profileHeader {
      background: #2c2c2e !important;
      border-radius: 14px !important; overflow: hidden !important; position: relative !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.08) !important;
    }
    .l-user-hero .profileHeaderBackground, .l-user-hero .profileHeaderBackground__visual { border-radius: inherit !important; }
    .l-user-hero .profileHeaderBackground::after {   /* strong scrim so name & location stay crisp on bright banners */
      content: ""; position: absolute; inset: 0; pointer-events: none;
      background: linear-gradient(to right, rgba(0, 0, 0, 0.56) 0%, rgba(0, 0, 0, 0.26) 50%, rgba(0, 0, 0, 0.08) 80%),
                  linear-gradient(to top, rgba(0, 0, 0, 0.48) 0%, rgba(0, 0, 0, 0) 55%) !important;
    }
    .l-user-hero [class*="g-type-shrinkwrap"], .l-user-hero [class*="g-type-shrinkwrap"] * {
      background: transparent !important; box-shadow: none !important; padding: 0 !important;
    }
    .l-user-hero [class*="g-type-shrinkwrap"]::before { display: none !important; content: none !important; }
    .l-user-hero .profileHeaderInfo__userName {
      color: #fff !important; font-size: 30px !important; font-weight: 700 !important;
      letter-spacing: -0.02em !important; text-shadow: 0 1px 12px rgba(0, 0, 0, 0.5);
    }
    .l-user-hero .profileHeaderInfo__additional {
      color: rgba(255, 255, 255, 0.88) !important; font-size: 14px !important; font-weight: 500 !important;
      line-height: 1.35 !important; margin-top: 2px !important;
      text-shadow: 0 1px 8px rgba(0, 0, 0, 0.55) !important;
    }
    .l-user-hero .cp-profile-meta-links {
      display: flex !important; flex-wrap: wrap !important; align-items: center !important;
      gap: 6px !important; margin-top: 10px !important; position: relative !important; z-index: 3 !important;
    }
    .l-user-hero .cp-profile-meta-link {
      display: inline-flex !important; align-items: center !important; height: 24px !important;
      padding: 0 10px !important; border-radius: 999px !important;
      font-size: 12px !important; font-weight: 500 !important; line-height: 1 !important;
      color: rgba(255, 255, 255, 0.92) !important; text-decoration: none !important;
      background: rgba(0, 0, 0, 0.32) !important;
      -webkit-backdrop-filter: blur(14px) saturate(1.5) !important; backdrop-filter: blur(14px) saturate(1.5) !important;
      border: 0.5px solid rgba(255, 255, 255, 0.18) !important;
      text-shadow: 0 1px 4px rgba(0, 0, 0, 0.35) !important; cursor: pointer !important;
    }
    .l-user-hero .cp-profile-meta-link:hover {
      background: rgba(255, 255, 255, 0.22) !important; color: #fff !important;
    }
    .l-user-hero .profileHeaderInfo__avatar .image { box-shadow: 0 8px 24px rgba(0, 0, 0, 0.35) !important; }
    .cp-profile-actions :is(.sc-button-insights, a[href*="/insights"], button[aria-label*="Insights" i], button[title*="Insights" i], button[aria-label="Send a message"], button[title="Send a message"], .sc-button-message),
    .l-user-main .spotlight:not(:has(.sound, .playableTile)) { display: none !important; }

    /* ── Profile: Apple Music style (no underline tabs; actions in hero; sections + See All) ─ */
    .l-vertical-bar:has(.userInfoBar), .userInfoBar { display: none !important; }
    .l-user-hero .profileHeader .cp-profile-actions {
      position: absolute !important; right: 24px !important; bottom: 20px !important; z-index: 4 !important;
      display: flex !important; align-items: center !important; gap: 8px !important;
      margin: 0 !important; padding: 0 !important;
    }
    .l-user-hero .profileHeader .cp-profile-actions .sc-button-group {
      display: flex !important; align-items: center !important; gap: 8px !important;
      margin: 0 !important; padding: 0 !important; float: none !important;
    }
    .l-user-hero .profileHeader .cp-profile-actions .sc-button {
      margin: 0 !important; height: 34px !important; min-height: 34px !important;
      padding: 0 14px !important; border: 0 !important; border-radius: 999px !important;
      display: inline-flex !important; align-items: center !important; justify-content: center !important; gap: 6px !important;
      font-size: 13px !important; font-weight: 500 !important; line-height: 1 !important;
      box-sizing: border-box !important; outline: none !important;
    }
    .l-user-hero .profileHeader .cp-profile-actions .sc-button-icon {
      width: 34px !important; min-width: 34px !important; padding: 0 !important;
    }
    .l-user-hero .profileHeader .cp-profile-actions .sc-button-secondary {
      color: #fff !important; background: rgba(255, 255, 255, 0.14) !important;
      -webkit-backdrop-filter: blur(16px) saturate(1.8) !important; backdrop-filter: blur(16px) saturate(1.8) !important;
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35), inset 0 -0.5px 0 rgba(255, 255, 255, 0.1),
                  0 0 0 0.5px rgba(255, 255, 255, 0.18), 0 2px 10px rgba(0, 0, 0, 0.22) !important;
    }
    .l-user-hero .profileHeader .cp-profile-actions .sc-button-secondary:hover {
      background: rgba(255, 255, 255, 0.24) !important;
    }
    .l-user-hero .profileHeader .cp-profile-actions .sc-button-secondary:active {
      background: rgba(255, 255, 255, 0.3) !important;
    }
    .l-user-hero .profileHeader .cp-profile-actions .sc-button-primary,
    .l-user-hero .profileHeader .cp-profile-actions .sc-button-cta {
      background: #fff !important; color: #111 !important; font-weight: 600 !important;
      box-shadow: 0 2px 10px rgba(0, 0, 0, 0.22) !important;
    }
    .l-user-hero .profileHeader .cp-profile-actions .sc-button-primary:hover,
    .l-user-hero .profileHeader .cp-profile-actions .sc-button-cta:hover {
      background: rgba(255, 255, 255, 0.9) !important;
    }
    .l-user-hero .profileHeader .cp-profile-actions .sc-button.sc-button-selected {
      background: rgba(255, 255, 255, 0.22) !important; color: #fff !important;
      -webkit-backdrop-filter: blur(16px) saturate(1.8) !important; backdrop-filter: blur(16px) saturate(1.8) !important;
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35), 0 0 0 0.5px rgba(255, 255, 255, 0.22), 0 2px 10px rgba(0, 0, 0, 0.22) !important;
    }
    .l-user-hero .profileHeader .cp-profile-actions .sc-button svg {
      width: 15px !important; height: 15px !important; margin: 0 !important;
    }
    .l-user-hero .profileHeader .cp-profile-actions .sc-button > div {
      display: flex !important; align-items: center !important; margin: 0 !important;
    }

    /* Profile main area spacing now that the tab bar & right sidebar are gone */
    .l-fluid-fixed:has(.l-user-main) { padding-top: 14px !important; }
    .l-fluid-fixed:has(.l-user-main) > .l-main { padding-left: 16px !important; padding-right: 16px !important; }
    .l-user-main .spotlightTitle,
    .l-user-main .userstream__header {
      font-size: 20px !important; font-weight: 700 !important; letter-spacing: -0.02em !important;
      color: var(--cp-label) !important; margin: 20px 0 8px !important; padding: 0 10px !important;
    }
    .l-user-main .spotlight:first-child .spotlightTitle { margin-top: 4px !important; }
    .l-user-main .userstream__header.cp-section-heading {
      display: flex !important; align-items: center !important; justify-content: space-between !important;
    }

    /* Apple Music-style overview sections (Popular Tracks, Albums, Playlists, Reposts) */
    .l-user-main .spotlight > .g-box-full { pointer-events: none !important; }
    .cp-profile-sections {
      position: relative !important; z-index: 2 !important;
      display: flex !important; flex-direction: column !important; gap: 22px !important;
      margin: 18px 0 16px !important; padding: 0 !important;
    }
    .cp-profile-sections:empty { display: none !important; }
    /* Trim "Recent" on the artist overview page to 10 rows */
    .cp-profile-overview :is(.userStream, .userStream__list, .soundList, .lazyLoadingList, .soundList__list, .lazyLoadingList__list):not(.spotlight *) {
      min-height: 0 !important; margin-bottom: 0 !important; padding-bottom: 0 !important;
    }
    html body .cp-profile-overview:not([data-cp-trimmed]) .soundList__item:not(.spotlight *):nth-child(n+11),
    html body .cp-profile-overview .soundList__item.cp-trimmed-extra,
    html body .cp-profile-overview .soundList__item:not(.spotlight *):not(:has(.sound)),
    html body .cp-profile-overview :is(.loading, .paging-eof):not(.spotlight *) {
      display: none !important;
    }
    .cp-section { display: flex !important; flex-direction: column !important; gap: 8px !important; }
    .cp-section__header {
      display: flex !important; align-items: center !important; justify-content: space-between !important;
      padding: 0 10px !important; margin: 0 !important;
    }
    .cp-section__title {
      display: inline-flex !important; align-items: center !important; gap: 4px !important;
      font-size: 20px !important; font-weight: 700 !important; letter-spacing: -0.02em !important;
      color: var(--cp-label) !important; text-decoration: none !important; cursor: pointer !important;
      line-height: 1.2 !important;
    }
    .cp-section__title:hover { color: var(--cp-label) !important; opacity: 0.85; }
    .cp-section__chevron {
      width: 14px !important; height: 14px !important; color: var(--cp-secondary) !important;
      transition: transform 0.14s ease, color 0.14s ease !important;
    }
    .cp-section__title:hover .cp-section__chevron {
      color: var(--cp-label) !important; transform: translateX(2px) !important;
    }
    .cp-section__seeAll {
      font-size: 13px !important; font-weight: 500 !important; color: var(--cp-accent) !important;
      text-decoration: none !important; padding: 3px 8px !important; border-radius: 999px !important;
      cursor: pointer !important; line-height: 1.2 !important;
    }
    .cp-section__seeAll:hover { background: rgba(var(--cp-accent-rgb), 0.12) !important; }

    /* Compact track rows inside profile overview sections (matches CloudPlayer's .sound rows) */
    .cp-track-list {
      display: flex !important; flex-direction: column !important; margin: 0 !important; padding: 0 !important;
      list-style: none !important;
    }
    .cp-track-row {
      display: flex !important; align-items: center !important; gap: 10px !important;
      padding: 5px 10px !important; border-radius: 6px !important;
      text-decoration: none !important; color: inherit !important; cursor: pointer !important;
    }
    .cp-track-row:nth-child(even) { background: rgba(var(--cp-label-rgb), 0.035) !important; }
    .cp-track-row:hover { background: rgba(var(--cp-label-rgb), 0.08) !important; }
    .cp-track-row__art {
      width: 36px !important; height: 36px !important; border-radius: 4px !important; flex: none !important;
      background-color: rgba(var(--cp-label-rgb), 0.08) !important;
      background-size: cover !important; background-position: center !important;
    }
    .cp-track-row__meta {
      flex: 1 1 auto !important; min-width: 0 !important;
      display: flex !important; flex-direction: column !important;
    }
    .cp-track-row__title {
      font-size: 13px !important; font-weight: 500 !important; line-height: 17px !important;
      color: var(--cp-label) !important; white-space: nowrap !important;
      overflow: hidden !important; text-overflow: ellipsis !important;
    }
    .cp-track-row__sub {
      font-size: 12px !important; line-height: 16px !important; color: var(--cp-secondary) !important;
      white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis !important;
    }
    .cp-track-row__right {
      flex: none !important; font-size: 11px !important; color: var(--cp-secondary) !important;
      white-space: nowrap !important; font-variant-numeric: tabular-nums !important;
    }

    /* Horizontal artwork shelf for Albums & Playlists (Apple Music style) */
    .cp-shelf {
      display: flex !important; flex-direction: row !important; gap: 14px !important;
      overflow-x: auto !important; overflow-y: hidden !important;
      padding: 2px 10px 6px !important; margin: 0 !important;
      scrollbar-width: none !important; overscroll-behavior-x: contain !important;
    }
    .cp-shelf::-webkit-scrollbar { display: none !important; }
    .cp-card {
      flex: none !important; width: 148px !important; display: flex !important; flex-direction: column !important;
      gap: 6px !important; text-decoration: none !important; color: inherit !important; cursor: pointer !important;
    }
    .cp-card__art {
      width: 148px !important; height: 148px !important; border-radius: 8px !important;
      background-color: rgba(var(--cp-label-rgb), 0.08) !important;
      background-size: cover !important; background-position: center !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.1), 0 4px 12px rgba(0, 0, 0, 0.14) !important;
      transition: transform 0.15s ease, box-shadow 0.15s ease !important;
    }
    .cp-card:hover .cp-card__art {
      transform: translateY(-2px) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.16), 0 8px 18px rgba(0, 0, 0, 0.22) !important;
    }
    .cp-card__title {
      font-size: 13px !important; font-weight: 500 !important; line-height: 17px !important;
      color: var(--cp-label) !important; white-space: nowrap !important;
      overflow: hidden !important; text-overflow: ellipsis !important;
    }
    .cp-card__sub {
      font-size: 12px !important; line-height: 15px !important; color: var(--cp-secondary) !important;
      white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis !important;
    }

    /* Fallback browse row if API data is unavailable */
    .cp-browse-row {
      display: flex !important; flex-wrap: wrap !important; gap: 6px !important; padding: 0 10px !important;
    }
    .cp-browse-pill {
      display: inline-flex !important; align-items: center !important; gap: 4px !important;
      height: 28px !important; padding: 0 12px !important; border-radius: 999px !important;
      font-size: 13px !important; font-weight: 500 !important; color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.06) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.1) !important; text-decoration: none !important;
    }
    .cp-browse-pill:hover { background: rgba(var(--cp-label-rgb), 0.12) !important; }

    /* Similar Artists circular shelf & About footer on Artist Overview */
    .cp-section__headingText {
      font-size: 20px !important; font-weight: 700 !important; letter-spacing: -0.02em !important;
      color: var(--cp-label) !important; margin: 0 !important; line-height: 1.2 !important;
    }
    .cp-artist-shelf {
      display: flex !important; flex-direction: row !important; gap: 18px !important;
      overflow-x: auto !important; overflow-y: hidden !important;
      padding: 4px 10px 8px !important; margin: 0 !important;
      scrollbar-width: none !important; overscroll-behavior-x: contain !important;
    }
    .cp-artist-shelf::-webkit-scrollbar { display: none !important; }
    .cp-artist-card {
      flex: none !important; width: 120px !important; display: flex !important; flex-direction: column !important;
      align-items: center !important; gap: 8px !important; text-decoration: none !important;
      color: inherit !important; cursor: pointer !important; text-align: center !important;
    }
    .cp-artist-card__avatar {
      width: 120px !important; height: 120px !important; border-radius: 50% !important;
      background-color: rgba(var(--cp-label-rgb), 0.08) !important;
      background-size: cover !important; background-position: center !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.12), 0 4px 12px rgba(0, 0, 0, 0.16) !important;
      transition: transform 0.15s ease, box-shadow 0.15s ease !important;
    }
    .cp-artist-card:hover .cp-artist-card__avatar {
      transform: translateY(-2px) !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.2), 0 8px 18px rgba(0, 0, 0, 0.24) !important;
    }
    .cp-artist-card__name {
      font-size: 13px !important; font-weight: 500 !important; line-height: 17px !important;
      color: var(--cp-label) !important; width: 100% !important;
      white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis !important;
    }
    .cp-profile-about {
      display: flex !important; flex-direction: column !important; gap: 10px !important;
      margin: 22px 0 16px !important; padding: 0 10px !important;
    }
    .cp-profile-about:has(+ .cp-profile-related) { margin-bottom: 0 !important; }
    .cp-profile-related { margin: 22px 0 16px !important; }
    .cp-profile-about__card {
      display: flex !important; flex-direction: column !important; gap: 12px !important;
      padding: 16px 18px !important; border-radius: 12px !important;
      background: rgba(var(--cp-label-rgb), 0.035) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.08) !important;
    }
    .cp-profile-about__bio {
      margin: 0 !important; font-size: 13px !important; line-height: 1.5 !important;
      color: var(--cp-secondary) !important; white-space: pre-line !important;
      display: -webkit-box !important; -webkit-line-clamp: 6 !important; -webkit-box-orient: vertical !important;
      overflow: hidden !important;
    }
    .cp-profile-about__links {
      display: flex !important; flex-wrap: wrap !important; gap: 6px !important;
    }
    .cp-profile-about__link {
      display: inline-flex !important; align-items: center !important; height: 26px !important;
      padding: 0 12px !important; border-radius: 999px !important;
      font-size: 12.5px !important; font-weight: 500 !important; color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.07) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.12) !important;
      text-decoration: none !important;
    }
    .cp-profile-about__link:hover { background: rgba(var(--cp-label-rgb), 0.14) !important; }

    /* Sub-page drill-down header (Profile, User Network & Track/Playlist Engagement sub-pages) */
    .cp-profile-subhead {
      display: flex !important; align-items: center !important; justify-content: space-between !important;
      gap: 12px !important; padding: 4px 10px 12px !important; margin: 0 0 10px !important;
      border-bottom: 0.5px solid rgba(var(--cp-label-rgb), 0.1) !important;
    }
    .cp-profile-subhead__left {
      display: flex !important; align-items: center !important; gap: 10px !important; min-width: 0 !important;
    }
    .cp-profile-subhead__art {
      width: 32px !important; height: 32px !important; border-radius: 6px !important; flex: none !important;
      background-color: rgba(var(--cp-label-rgb), 0.08) !important;
      background-size: cover !important; background-position: center !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.12) !important;
    }
    .cp-profile-subhead__avatar {
      width: 28px !important; height: 28px !important; border-radius: 50% !important; flex: none !important;
      background-color: rgba(var(--cp-label-rgb), 0.08) !important;
      background-size: cover !important; background-position: center !important;
      box-shadow: 0 0 0 0.5px rgba(var(--cp-label-rgb), 0.12) !important;
    }
    .cp-profile-subhead__back {
      display: inline-flex !important; align-items: center !important; gap: 3px !important;
      height: 26px !important; max-width: 300px !important; padding: 0 10px 0 7px !important; border-radius: 999px !important;
      font-size: 13px !important; font-weight: 500 !important; color: var(--cp-accent) !important;
      background: rgba(var(--cp-accent-rgb), 0.1) !important; text-decoration: none !important;
      cursor: pointer !important; flex: 0 1 auto !important; min-width: 0 !important;
    }
    .cp-profile-subhead__backText {
      white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis !important;
    }
    .cp-profile-subhead__back:hover { background: rgba(var(--cp-accent-rgb), 0.18) !important; }
    .cp-profile-subhead__title {
      font-size: 20px !important; font-weight: 700 !important; letter-spacing: -0.02em !important;
      color: var(--cp-label) !important; margin: 0 !important; line-height: 1.2 !important;
      white-space: nowrap !important;
    }
    .cp-profile-subhead > .cp-view-toggle-wrap { flex: none !important; margin-left: auto !important; }

    /* ── User & Track/Set Network Engagement sub-pages (.userNetwork, .listenNetwork) ───── */
    .l-fixed-top-one-column:has(.userNetwork, .listenNetwork, .userNetworkTop, .listenNetworkInfo, .userNetworkTabs, .listenNetworkTabs),
    .l-fixed-top-one-column:has(.userNetwork, .listenNetwork, .userNetworkTop, .listenNetworkInfo, .userNetworkTabs, .listenNetworkTabs) > .l-top,
    .l-fixed-top-one-column:has(.userNetwork, .listenNetwork, .userNetworkTop, .listenNetworkInfo, .userNetworkTabs, .listenNetworkTabs) > .l-main,
    .userNetwork, .listenNetwork,
    .userNetwork__header, .listenNetwork__header {
      position: static !important; top: auto !important; left: auto !important; right: auto !important;
      width: auto !important; max-width: none !important; height: auto !important;
      margin: 0 !important; transform: none !important; float: none !important; border: 0 !important;
    }
    .l-fixed-top-one-column:has(.userNetwork, .listenNetwork, .userNetworkTop, .listenNetworkInfo, .userNetworkTabs, .listenNetworkTabs) {
      padding: 14px 16px 24px !important;
    }
    .l-fixed-top-one-column:has(.userNetwork, .listenNetwork, .userNetworkTop, .listenNetworkInfo, .userNetworkTabs, .listenNetworkTabs) > .l-main {
      padding: 0 !important;
    }
    /* Visually hide .l-top while keeping .userNetworkTop / .listenNetworkInfo laid out 1x1 so
       SoundCloud still hydrates their artwork thumbnail & title for .cp-profile-subhead! */
    .l-fixed-top-one-column:has(.userNetwork, .listenNetwork, .userNetworkTop, .listenNetworkInfo, .userNetworkTabs, .listenNetworkTabs) > .l-top {
      position: absolute !important; width: 1px !important; height: 1px !important;
      overflow: hidden !important; opacity: 0 !important; pointer-events: none !important;
    }
    .userNetworkTabs, .userNetwork__header, .userNetwork__subHeader, .userNetwork__subheadline,
    .listenNetworkTabs, .listenNetwork__header,
    .userNetwork :is(.userNetwork__controls, .sc-button-share:not(.playableTile *):not(.sound *)) {
      display: none !important;
    }
    /* Profile Comments sub-page (/<user>/comments) clean cards */
    .userNetwork :is(.commentsList__item, .badgeList__item:has(.commentItem), li:has(> .commentItem), li:has(> .commentBadge)) {
      display: block !important; width: auto !important; float: none !important;
      padding: 12px 14px !important; margin: 0 10px 8px !important; border-radius: 10px !important;
      background: rgba(var(--cp-label-rgb), 0.035) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.07) !important;
    }
    .userNetwork :is(.commentItem, .commentBadge) {
      border: 0 !important; margin: 0 !important; padding: 0 !important; background: transparent !important;
    }

    /* ── Tag / Genre Pages (/tags/<tag>, /popular-tracks, /playlists) ───────────────────── */
    .l-fluid-fixed:has(.tagsMain) > .l-main { padding: 12px 16px 24px !important; }
    .tagsMain { padding: 0 !important; margin: 0 !important; }
    .tagsMain__title {
      font-size: 24px !important; font-weight: 700 !important; letter-spacing: -0.02em !important;
      padding: 4px 10px 10px !important; margin: 0 !important;
    }
    .tagsMain .g-tabs {
      display: flex !important; flex-wrap: wrap !important; align-items: center !important;
      gap: 6px !important; border: 0 !important; padding: 0 10px 14px !important; margin: 0 !important;
      height: auto !important;
    }
    .tagsMain .g-tabs > li { margin: 0 !important; padding: 0 !important; float: none !important; list-style: none !important; }
    .tagsMain .g-tabs .g-tabs-link {
      display: inline-flex !important; align-items: center !important; height: 26px !important;
      padding: 0 12px !important; margin: 0 !important; border-radius: 13px !important;
      font-size: 13px !important; font-weight: 500 !important; line-height: 1 !important;
      color: var(--cp-label) !important; text-decoration: none !important;
      background: rgba(var(--cp-label-rgb), 0.06) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.1) !important;
    }
    .tagsMain .g-tabs .g-tabs-link:hover { background: rgba(var(--cp-label-rgb), 0.12) !important; }
    .tagsMain .g-tabs .g-tabs-link.active {
      background: rgba(var(--cp-label-rgb), 0.2) !important; font-weight: 600 !important;
      border-color: rgba(var(--cp-label-rgb), 0.16) !important;
    }
    .tagsMain .g-tabs .g-tabs-link::before,
    .tagsMain .g-tabs .g-tabs-link::after { display: none !important; content: none !important; }
    .tagsMain .g-tabs > .cp-view-toggle-wrap { margin-left: auto !important; flex: none !important; }
    .tagsList__empty {
      font-size: 15px !important; font-weight: 500 !important; color: var(--cp-secondary) !important;
      padding: 28px 12px !important; margin: 0 !important;
    }

    /* ── Settings (/settings, /content, /notifications, /privacy, /two-factor) ──────────── */
    .l-settings-layout, .l-settings-layout .l-one-column, .l-settings-layout .l-main {
      width: auto !important; max-width: 880px !important; float: none !important;
      margin: 0 !important; padding: 0 !important; border: 0 !important;
    }
    .settingsMain { padding: 20px 32px 100px !important; margin: 0 !important; }
    .settingsMain__title {
      font-size: 26px !important; font-weight: 700 !important; letter-spacing: -0.02em !important;
      margin: 0 0 14px !important; padding: 0 !important;
    }
    .settingsMain__tabs.g-tabs {
      display: flex !important; flex-wrap: wrap !important; align-items: center !important;
      gap: 6px !important; border: 0 !important; padding: 0 !important; margin: 0 0 22px !important;
      height: auto !important;
    }
    .settingsMain__tabs .g-tabs-item { margin: 0 !important; padding: 0 !important; float: none !important; }
    .settingsMain__tabs li:has(> a[href="/settings/advertising"]) { display: none !important; }
    .settingsMain__tabs .g-tabs-link {
      display: inline-flex !important; align-items: center !important; height: 28px !important;
      padding: 0 14px !important; margin: 0 !important; border-radius: 14px !important;
      font-size: 13px !important; font-weight: 500 !important; line-height: 1 !important;
      color: var(--cp-label) !important; text-decoration: none !important;
      background: rgba(var(--cp-label-rgb), 0.06) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.1) !important;
    }
    .settingsMain__tabs .g-tabs-link:hover { background: rgba(var(--cp-label-rgb), 0.12) !important; }
    .settingsMain__tabs .g-tabs-link.active {
      background: rgba(var(--cp-label-rgb), 0.2) !important; font-weight: 600 !important;
      border-color: rgba(var(--cp-label-rgb), 0.16) !important;
    }
    .settingsMain__tabs .g-tabs-link::before,
    .settingsMain__tabs .g-tabs-link::after { display: none !important; content: none !important; }
    .settingsMain__tabContent { margin-top: 0 !important; }
    .settingsMain .g-form-section:has([data-radio-value="automatic"]),
    .settingsMain .g-form-section:has(input[value="light"][type="radio"]),
    .settingsMain .g-form-section:has(.cookie-setting-link, #ot-sdk-btn, .ot-sdk-show-settings),
    .settingsMain .g-form-section:has(> .m-sectionHidden) {
      display: none !important;
    }
    .settingsMain__tabContent > div > .g-form-section {
      padding: 16px 20px !important; margin: 0 0 12px !important; border-radius: 12px !important;
      background: rgba(var(--cp-label-rgb), 0.035) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.08) !important;
    }
    .settingsMain .g-form-section .g-form-section {
      padding: 0 !important; margin: 0 !important; background: transparent !important; border: 0 !important;
    }
    .settingsMain .g-form-section-head { padding: 0 0 8px !important; }
    .settingsMain .g-form-section-head h3 { font-size: 15px !important; font-weight: 600 !important; margin: 0 !important; }
    .accountSocialItem {
      display: flex !important; align-items: center !important; justify-content: space-between !important;
      padding: 8px 0 !important; border-color: rgba(var(--cp-label-rgb), 0.08) !important;
    }
    .accountSocialItem__nameWrapper {
      display: inline-flex !important; align-items: center !important; gap: 10px !important;
    }
    .accountSocialItem .socialLogo {
      width: 18px !important; height: 18px !important; margin: 0 !important;
      display: inline-flex !important; align-items: center !important; justify-content: center !important;
      color: var(--cp-label) !important;
    }
    .accountSocialItem .socialLogo svg { width: 18px !important; height: 18px !important; }
    .accountSocialConnect__buttons {
      display: flex !important; flex-wrap: wrap !important; gap: 8px !important; margin-top: 8px !important;
    }
    .accountSocialConnect__buttons .sc-button {
      margin: 0 !important; height: 30px !important; padding: 0 14px !important;
      display: inline-flex !important; align-items: center !important; gap: 7px !important;
      font-size: 13px !important; font-weight: 500 !important;
      color: var(--cp-label) !important; background: rgba(var(--cp-label-rgb), 0.08) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.14) !important; box-shadow: none !important;
    }
    .accountSocialConnect__buttons .sc-button:hover { background: rgba(var(--cp-label-rgb), 0.14) !important; }
    .accountSocialConnect__buttons .sc-button > div {
      display: inline-flex !important; align-items: center !important; margin: 0 !important;
    }
    .accountSocialConnect__buttons .sc-button svg { width: 15px !important; height: 15px !important; }

    /* ── Messages (/messages) fallback polish ───────────────────────────────────────────── */
    .inbox, .conversation { padding-bottom: 96px !important; }
    .conversation__actions, .inbox__header { top: 0 !important; }
    .conversation :is(.blockButton, .reportForm, a[href*="/pages/report-content"]) { display: none !important; }
    .conversationBadge { border-radius: 8px !important; }
    .conversation .sound {
      margin: 6px 0 !important; padding: 6px 10px !important;
      max-width: 580px !important; box-sizing: border-box !important;
      background: rgba(var(--cp-label-rgb), 0.045) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.08) !important; border-radius: 8px !important;
    }
    .composeMessage textarea {
      border-radius: 10px !important; background: rgba(var(--cp-label-rgb), 0.06) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.12) !important; padding: 10px 12px !important;
    }

    /* ── Library header row: "View [tiles][list]" + Filter ──────────────────────────────── */
    .collectionSection__top {
      display: flex !important; align-items: center !important; gap: 10px !important; padding: 8px 16px !important;
    }
    .collectionSection__subHeading {
      font-size: 17px !important; font-weight: 600 !important; letter-spacing: -0.01em !important;
      flex: 0 1 auto !important; min-width: 0 !important;
    }
    .collectionSection__flexFill { flex: 1 1 auto !important; min-width: 8px !important; }
    .collectionSection__action, .collectionSection__filters { margin: 0 !important; }
    .collectionSection__top .cp-view-toggle-wrap {
      flex: none !important; width: auto !important; position: relative !important; z-index: 1 !important;
    }

    /* Tiles/list → macOS segmented control */
    .listDisplayToggle__title { display: none !important; }
    .listDisplayToggle__options {
      display: inline-flex !important; gap: 0 !important; padding: 2px !important; margin: 0 !important;
      background: rgba(var(--cp-label-rgb), 0.08) !important; border-radius: 13px !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.12) !important; box-sizing: border-box !important;
      height: 26px !important; align-items: center !important;
    }
    .listDisplayToggle__options li {
      margin: 0 !important; padding: 0 !important; height: 21px !important;
      display: flex !important; align-items: center !important; background: none !important;
    }
    .listDisplayToggle__options .sc-button > div { height: auto !important; background: none !important; display: flex !important; }
    .listDisplayToggle__options .sc-button {
      width: 34px !important; height: 21px !important; min-height: 0 !important; max-height: 21px !important;
      line-height: 21px !important; box-sizing: border-box !important; outline: none !important;
      min-width: 0 !important; padding: 0 !important; margin: 0 !important;
      display: flex !important; align-items: center !important; justify-content: center !important;
      background: transparent !important; border: 0 !important; border-radius: 11px !important;
      color: var(--cp-secondary) !important; box-shadow: none !important;
    }
    .listDisplayToggle__options .sc-button:hover { color: var(--cp-label) !important; }
    .listDisplayToggle__options .sc-button.sc-button-selected {
      background: rgba(var(--cp-label-rgb), 0.16) !important; color: var(--cp-label) !important;
      box-shadow: 0 0.5px 1px rgba(0, 0, 0, 0.25), inset 0 0.5px 0 rgba(255, 255, 255, 0.06) !important;
    }
    /* When CloudPlayer manages the active segment (2 or 3 options), drive selection from data-cp-mode
       so SoundCloud's own sc-button-selected on the List button doesn't double-highlight in Waveform mode. */
    .listDisplayToggle__options[data-cp-mode] .sc-button.sc-button-selected {
      background: transparent !important; color: var(--cp-secondary) !important; box-shadow: none !important;
    }
    html body .listDisplayToggle__options[data-cp-mode="tiles"] .sc-button:is(.listDisplayToggle__badgeToggle, .cp-view-btn-tiles),
    html body .listDisplayToggle__options[data-cp-mode="compact"] .sc-button:is(.listDisplayToggle__listToggle, .cp-view-btn-compact),
    html body .listDisplayToggle__options[data-cp-mode="waveform"] .sc-button.cp-view-btn-waveform {
      background: rgba(var(--cp-label-rgb), 0.16) !important; color: var(--cp-label) !important;
      box-shadow: 0 0.5px 1px rgba(0, 0, 0, 0.25), inset 0 0.5px 0 rgba(255, 255, 255, 0.06) !important;
    }
    .listDisplayToggle__options svg { width: 14px !important; height: 14px !important; }
    .cp-profile-view-bar {
      display: flex !important; justify-content: flex-end !important; align-items: center !important;
      padding: 0 0 10px !important; margin: 0 !important;
    }

    /* Filter row: other filters (e.g. the All/Created/Liked dropdown on Albums and Playlists)
       sit to the LEFT of the search field, as matching 26px capsules. */
    .collectionSection__filters {
      display: flex !important; align-items: center !important; gap: 8px !important;
      flex: none !important; width: auto !important; max-width: none !important; min-width: 0 !important;
      position: static !important; margin: 0 !important; padding: 0 !important;
    }
    .collectionSection__filters > * {
      position: relative !important; left: auto !important; right: auto !important; top: auto !important; bottom: auto !important;
      float: none !important; flex: none !important; width: auto !important; margin: 0 !important;
    }
    .collectionSection__filters > .collectionSection__filterText { order: 2 !important; }
    .collectionSection__filters > :not(.collectionSection__filterText) { order: 1 !important; }
    .collectionSection__filters > :not(.collectionSection__filterText) :is(button, .sc-button, [role="button"], select) {
      height: 26px !important; min-height: 0 !important; box-sizing: border-box !important;
      padding: 0 10px 0 12px !important; margin: 0 !important; border-radius: 13px !important;
      display: inline-flex !important; align-items: center !important; gap: 6px;
      font-size: 13px !important; font-weight: 500 !important; line-height: 1 !important; color: var(--cp-label) !important;
      background-color: rgba(var(--cp-label-rgb), 0.08) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.12) !important; box-shadow: none !important;
      -webkit-backdrop-filter: none !important; backdrop-filter: none !important;
    }
    .collectionSection__filters > :not(.collectionSection__filterText) :is(button, .sc-button, [role="button"]):hover {
      background-color: rgba(var(--cp-label-rgb), 0.14) !important;
    }
    .collectionSection__filters > :not(.collectionSection__filterText) select {
      -webkit-appearance: none !important; appearance: none !important; padding-right: 26px !important;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 6'%3E%3Cpath d='M1 1l4 4 4-4' fill='none' stroke='%23999' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E") !important;
      background-repeat: no-repeat !important; background-position: right 10px center !important; background-size: 9px 6px !important;
    }
    .collectionSection__filters > :not(.collectionSection__filterText) .sc-button-dropdown > div {
      display: inline-flex !important; align-items: center !important; margin: 0 !important; color: var(--cp-secondary) !important;
    }
    .collectionSection__filters > :not(.collectionSection__filterText) svg { width: 10px !important; height: 10px !important; }

    /* Filter → capsule search field */
    .collectionSection__filterText .textfield__inputWrapper { position: relative !important; }
    .collectionSection__filterText .textfield__inputWrapper::before {
      content: ""; position: absolute; left: 9px; top: 50%; width: 13px; height: 13px; transform: translateY(-50%);
      background: var(--cp-secondary); pointer-events: none; z-index: 1;
      -webkit-mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Ccircle cx='6.75' cy='6.75' r='5' fill='none' stroke='black' stroke-width='1.6'/%3E%3Cpath d='M10.4 10.4 14.5 14.5' stroke='black' stroke-width='1.6' stroke-linecap='round'/%3E%3C/svg%3E") center / contain no-repeat;
    }
    .collectionSection__filterText .textfield__input {
      width: 220px !important; height: 26px !important; padding: 0 26px 0 28px !important;
      font-size: 13px !important; color: var(--cp-label) !important;
      background: rgba(var(--cp-label-rgb), 0.08) !important;
      border: 0.5px solid rgba(var(--cp-label-rgb), 0.12) !important; border-radius: 13px !important;
      box-shadow: none !important; outline: none !important; transition: box-shadow 0.15s;
    }
    .collectionSection__filterText .textfield__input::placeholder { color: var(--cp-secondary) !important; }
    .collectionSection__filterText .textfield__input:focus {
      border-color: rgba(var(--cp-accent-rgb), 0.8) !important;
      box-shadow: 0 0 0 3px rgba(var(--cp-accent-rgb), 0.35) !important;
    }
    .collectionSection__filterText .textfield__clearContainer {
      right: 6px !important; top: 50% !important; transform: translateY(-50%) !important; color: var(--cp-secondary) !important;
    }

    /* Toasts ("… was saved to your Library"), tagged .cp-toast by the injected script, are
       shown natively at the bottom of the sidebar instead. */
    .cp-toast, #gritter-notice-wrapper { display: none !important; }

    /* ── Horizontal tile streams (Home, etc.): native horizontal scroll + pronounced, centred buttons ── */
    .tileGallery { position: relative !important; }
    .tileGallery__slider {
      overflow-x: auto !important; overflow-y: hidden !important;
      scrollbar-width: none !important; overscroll-behavior-x: contain !important;
      -webkit-overflow-scrolling: touch;
    }
    .tileGallery__slider::-webkit-scrollbar { display: none !important; }
    /* SoundCloud caps the panel at artwork + one text line (e.g. max-height: 208px); with the
       slider's overflow-y: hidden above, that clipped the artist line under every tile. */
    .tileGallery__sliderPanel {
      transform: none !important; transition: none !important;
      height: auto !important; max-height: none !important;
    }
    /* The tiles' own bottom margin (sc-mb-6x) used to be clipped away too; drop it so rows stay tight. */
    .tileGallery .playableTile { margin-bottom: 0 !important; }
    .tileGallery__sliderPeekContainer { animation: none !important; }

    /* Prev / next button containers: sit above the tiles and only intercept clicks on the button itself. */
    .tileGallery__sliderPeek {
      position: absolute !important; top: 0 !important; bottom: 0 !important;
      width: 0 !important; margin: 0 !important; padding: 0 !important;
      z-index: 30 !important; pointer-events: none !important; display: none !important;
    }
    .tileGallery__sliderPeekBackward { left: 0 !important; right: auto !important; }
    .tileGallery__sliderPeekForward { right: 0 !important; left: auto !important; }
    .tileGallery.cp-can-back > .tileGallery__sliderPeekBackward,
    .tileGallery.cp-can-forward > .tileGallery__sliderPeekForward { display: block !important; }

    /* Pronounced circular glass buttons, vertically centred on the tile artwork (--cp-btn-top). */
    html body .tileGallery .tileGallery__sliderPeek .tileGallery__sliderButton {
      position: absolute !important;
      top: var(--cp-btn-top, 42%) !important; bottom: auto !important;
      transform: translateY(-50%) !important;
      width: 44px !important; height: 44px !important; min-width: 44px !important; min-height: 44px !important;
      margin: 0 !important; padding: 0 !important; border: 0 !important; border-radius: 50% !important;
      display: flex !important; align-items: center !important; justify-content: center !important;
      pointer-events: auto !important; cursor: pointer !important; opacity: 1 !important;
      color: var(--cp-label) !important;
      background: rgba(var(--cp-bg-rgb), 0.92) !important;
      -webkit-backdrop-filter: blur(20px) saturate(1.8) !important; backdrop-filter: blur(20px) saturate(1.8) !important;
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.45),
                  0 0 0 1px rgba(var(--cp-label-rgb), 0.14),
                  0 4px 16px rgba(0, 0, 0, 0.28),
                  0 1px 4px rgba(0, 0, 0, 0.16) !important;
      transition: transform 0.15s ease, background-color 0.15s ease, box-shadow 0.15s ease !important;
    }
    html body .tileGallery .tileGallery__sliderPeek .tileGallery__slideBackwardButton { left: 24px !important; right: auto !important; }
    html body .tileGallery .tileGallery__sliderPeek .tileGallery__slideForwardButton { right: 14px !important; left: auto !important; }
    html body .tileGallery .tileGallery__sliderPeek .tileGallery__sliderButton:hover {
      background: var(--cp-bg) !important;
      transform: translateY(-50%) scale(1.07) !important;
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.55),
                  0 0 0 1px rgba(var(--cp-label-rgb), 0.22),
                  0 6px 22px rgba(0, 0, 0, 0.34),
                  0 2px 6px rgba(0, 0, 0, 0.18) !important;
    }
    html body .tileGallery .tileGallery__sliderPeek .tileGallery__sliderButton:active {
      transform: translateY(-50%) scale(0.96) !important;
    }
    html body .tileGallery .tileGallery__sliderPeek .tileGallery__sliderButton > div {
      display: flex !important; align-items: center !important; justify-content: center !important;
      width: 100% !important; height: 100% !important; margin: 0 !important; padding: 0 !important;
    }
    html body .tileGallery .tileGallery__sliderPeek .tileGallery__sliderButton svg {
      display: block !important; width: 18px !important; height: 18px !important; margin: 0 !important;
    }

    /* Selection uses the accent colour. */
    ::selection { background: rgba(var(--cp-accent-rgb), 0.35); }
    """
}

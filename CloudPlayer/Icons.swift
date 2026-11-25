import AppKit

/// Replaces SoundCloud's icons with SF Symbols. Each symbol is rendered natively to a PNG and
/// used as a CSS mask over the original <svg> (whose own paths are hidden), filled with
/// `currentColor`, so icons keep following the button's text / accent colour and the theme.
enum Icons {
    /// Classic app: icons are `<svg>`s inside `.sc-button-<kind>` / `.sc-ministats-<kind>`.
    /// Track pages (newer app, in an iframe): buttons are identified by their aria-label.
    private static let map: [(selector: String, symbol: String)] = [
        // Classic buttons
        (".sc-button-play", "play.fill"),
        (".sc-button-play.sc-button-pause", "pause.fill"),
        (".sc-button-like", "heart"),
        (".sc-button-like.sc-button-selected", "heart.fill"),
        (".sc-button-repost", "arrow.2.squarepath"),
        (".sc-button-share", "square.and.arrow.up"),
        (".sc-button-copylink", "link"),
        (".sc-button-queue", "text.line.first.and.arrowtriangle.forward"),
        (".sc-button-addtoset", "text.badge.plus"),
        (".sc-button-more", "ellipsis"),
        (".sc-button-download", "arrow.down.circle"),
        (".sc-button-edit", "pencil"),
        (".sc-button-delete", "trash"),
        (".soundActions__purchaseLink", "cart"),
        (".sc-button-dropdown", "chevron.down"),
        (".tileGallery__slideBackwardButton", "chevron.left"),
        (".tileGallery__slideForwardButton", "chevron.right"),
        (".listDisplayToggle__badgeToggle", "square.grid.2x2"),
        (".cp-view-btn-tiles", "square.grid.2x2"),
        (".listDisplayToggle__listToggle", "list.bullet"),
        (".cp-view-btn-compact", "list.bullet"),
        (".cp-view-btn-waveform", "waveform"),
        // Classic mini stats (counts next to tracks, profiles, playlists)
        (".sc-ministats-likes", "heart.fill"),
        (".sc-ministats-reposts", "arrow.2.squarepath"),
        (".sc-ministats-plays", "play.fill"),
        (".sc-ministats-comments", "text.bubble.fill"),
        (".sc-ministats-followers", "person.fill"),
        (".sc-ministats-following", "person.2.fill"),
        (".sc-ministats-sounds", "waveform"),
        (".sc-ministats-tracks", "waveform"),
        (".sc-ministats-playlists", "music.note.list"),
        // Track pages
        ("button[aria-label=\"Play\"]", "play.fill"),
        ("button[aria-label=\"Pause\"]", "pause.fill"),
        ("button[aria-label=\"Like\"]", "heart"),
        ("button[aria-label=\"Unlike\"]", "heart.fill"),
        ("button[aria-label=\"Repost\"]", "arrow.2.squarepath"),
        ("button[aria-label=\"Unrepost\"]", "arrow.2.squarepath"),
        ("button[aria-label=\"Share\"]", "square.and.arrow.up"),
        ("button[aria-label=\"Copy link\"]", "link"),
        ("button[aria-label=\"Add to playlist\"]", "text.badge.plus"),
        ("button[aria-label=\"Download\"]", "arrow.down.circle"),
        ("button[aria-label^=\"More actions\"]", "ellipsis"),
        ("button[aria-label=\"Post comment\"]", "paperplane"),
        ("button[aria-label^=\"Sort comments\"]", "line.3.horizontal.decrease"),
        ("button[aria-label^=\"More info\"]", "info.circle"),
    ]

    /// CSS for both the main page and the track-page iframe (selectors that don't match are inert).
    static let css: String = {
        var bySymbol: [(String, [String])] = []
        for (sel, sym) in map {
            if let i = bySymbol.firstIndex(where: { $0.0 == sym }) { bySymbol[i].1.append(sel) } else { bySymbol.append((sym, [sel])) }
        }
        var out = "/* SF Symbols in place of SoundCloud's icons. */\n"
        for (sym, sels) in bySymbol {
            guard let url = dataURL(sym) else { continue }
            let list = sels.joined(separator: ", ")
            out += """
            html body :is(\(list)) svg {
              -webkit-mask: url(\(url)) center / contain no-repeat !important;
              mask: url(\(url)) center / contain no-repeat !important;
              background-color: currentColor !important; fill: none !important; stroke: none !important;
            }

            """
        }
        // Hide the original artwork of every replaced icon.
        let all = map.map(\.selector).joined(separator: ", ")
        out += "html body :is(\(all)) svg > * { display: none !important; }\n"
        return out
    }()

    /// A black-on-transparent PNG of the symbol, centred in a square canvas, as a data URL.
    private static func dataURL(_ name: String) -> String? {
        let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let glyph = image.size
        let side = ceil(max(glyph.width, glyph.height) * 1.08)
        let px = Int(side * 2)   // @2x
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: (side - glyph.width) / 2, y: (side - glyph.height) / 2,
                              width: glyph.width, height: glyph.height))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return "\"data:image/png;base64,\(png.base64EncodedString())\""
    }
}

import WebKit

/// Network requests blocked outright (WebKit content blocker), for things the CSS hides anyway.
/// Each entry is a regex matched against the full request URL.
/// Home page sections can't be blocked this way: they all come from one /mixed-selections call.
enum Blocklist {
    static let patterns: [String] = [
        // Right sidebar "Artist Studio / Artist tools / Unlock…" embed — only the sidebar
        // module variant: the same credit-tracker app powers "Behind this track".
        #"^https?://soundcloud\.com/n/embeds/credit-tracker\?.*embedded=module"#,
        // "Events near you" embed
        #"^https?://artist-events\.soundcloud\.com/"#,
        // "Artists you should follow"
        #"^https?://api-v2\.soundcloud\.com/me/suggested/users/who_to_follow"#,
        // "New tracks" sidebar
        #"^https?://api-v2\.soundcloud\.com/me/artist-shortcuts"#,
        // Nudge banners, announcements, promoted accounts.
        // (Not /payments/quotations: track pages crash without it. Upsells are hidden by CSS.)
        #"^https?://api-v2\.soundcloud\.com/smartnudges/"#,
        #"^https?://api-v2\.soundcloud\.com/announcements"#,
        #"^https?://api-v2\.soundcloud\.com/promoted/"#,
        // Unread-message and notification badges (they lived in the hidden header)
        #"^https?://api-v2\.soundcloud\.com/users/[0-9]+/conversations/unread"#,
        #"^https?://api-v2\.soundcloud\.com/activities\?.*limit=1&"#,

        // Tracking / marketing (not visible content)
        // (Not cdn.cookielaw.org: /settings requires OneTrust SDK to mount; its UI is hidden in debloatCSS.)
        #"^https?://dwt\.soundcloud\.com/"#,                // SoundCloud analytics tags
        #"^https?://prodregistryv2\.org/v1/rgstr"#,         // Statsig event logging (feature flags still load)
        #"^https?://invite\.soundcloud\.com/"#,             // in-app marketing zones
        #"^https?://[^/]*doubleclick\.net/"#,
        #"^https?://[^/]*googlesyndication\.com/"#,
        #"^https?://[^/]*googletagmanager\.com/"#,
        #"^https?://[^/]*google-analytics\.com/"#,
        #"^https?://[^/]*scorecardresearch\.com/"#,
        #"^https?://[^/]*quantserve\.com/"#,
    ]

    static var json: String {
        var active = patterns
        #if DEBUG
        // Debug: -cpBlockSkip "cookielaw,dwt" leaves out rules whose pattern contains any of these.
        if let skip = UserDefaults.standard.string(forKey: "cpBlockSkip") {
            let words = skip.split(separator: ",").map { String($0) }
            active = active.filter { p in !words.contains { p.contains($0) } }
        }
        // Debug: -cpBlockExtra "regex1,regex2" adds block rules (for measuring what a resource costs).
        if let extra = UserDefaults.standard.string(forKey: "cpBlockExtra") {
            active += extra.split(separator: ",").map { String($0) }
        }
        #endif
        let rules = active.map { ["trigger": ["url-filter": $0], "action": ["type": "block"]] }
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Compiles the rules and installs them on the given controller.
    @MainActor
    static func install(on controller: WKUserContentController) async {
        do {
            if let list = try await WKContentRuleListStore.default()
                .compileContentRuleList(forIdentifier: "CloudPlayerBlocklist", encodedContentRuleList: json) {
                controller.add(list)
            }
        } catch {
            NSLog("CloudPlayer: blocklist failed to compile: \(error)")
        }
    }
}

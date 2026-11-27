import Foundation
import OSLog

enum SoundCloudAPIError: LocalizedError, Equatable {
    case unauthenticated
    case clientIDDiscoveryFailed
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String?)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            "Your SoundCloud session expired. Please sign in again."
        case .clientIDDiscoveryFailed:
            "Could not discover a SoundCloud client_id."
        case .invalidURL:
            "Invalid SoundCloud API URL."
        case .invalidResponse:
            "Unexpected response from SoundCloud."
        case .httpStatus(let code, let snippet):
            if let snippet, !snippet.isEmpty {
                "SoundCloud API error \(code): \(snippet)"
            } else {
                "SoundCloud API error \(code)."
            }
        case .decodingFailed(let message):
            "Failed to decode SoundCloud response: \(message)"
        }
    }
}

/// Pure-Swift SoundCloud `api-v2` HTTP client. Zero WebKit dependency.
actor SoundCloudAPI {
    static let baseURL = URL(string: "https://api-v2.soundcloud.com")!
    static let webOrigin = URL(string: "https://soundcloud.com")!
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private let session: URLSession
    private let logger = Logger(subsystem: "local.cloudplayer", category: "SoundCloudAPI")
    private var oauthToken: String?
    private var clientID: String?
    private var onClientIDUpdated: (@Sendable (String) -> Void)?

    init(
        session: URLSession = SoundCloudAPI.makeDefaultSession(),
        onClientIDUpdated: (@Sendable (String) -> Void)? = nil
    ) {
        self.session = session
        self.onClientIDUpdated = onClientIDUpdated
    }

    static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept-Language": "en-US,en;q=0.9",
        ]
        return URLSession(configuration: config)
    }

    func configure(session scSession: SoundCloudSession?) {
        self.oauthToken = scSession?.oauthToken
        if let cid = scSession?.clientID, !cid.isEmpty {
            self.clientID = cid
        } else if scSession == nil {
            self.clientID = nil
        }
    }

    func setOnClientIDUpdated(_ handler: (@Sendable (String) -> Void)?) {
        self.onClientIDUpdated = handler
    }

    func currentClientID() -> String? {
        clientID
    }

    // MARK: - Endpoints

    func fetchCurrentUser() async throws -> SCUser {
        try await get(path: "/me")
    }

    func fetchTrackLikes(userID: Int, limit: Int = 50, nextHref: String? = nil) async throws -> SCCollectionPage<SCLikeItem> {
        if let nextHref, !nextHref.isEmpty {
            return try await get(path: nextHref)
        }
        return try await get(
            path: "/users/\(userID)/track_likes",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "linked_partitioning", value: "1"),
            ]
        )
    }

    func fetchRelatedTracks(trackID: Int, limit: Int = 15) async throws -> [SCTrack] {
        let page: SCCollectionPage<SCTrack> = try await get(
            path: "/tracks/\(trackID)/related",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return page.collection
    }

    func likeTrack(userID: Int, trackID: Int) async throws {
        _ = try await sendData(path: "/users/\(userID)/track_likes/\(trackID)", method: "PUT")
    }

    func unlikeTrack(userID: Int, trackID: Int) async throws {
        _ = try await sendData(path: "/users/\(userID)/track_likes/\(trackID)", method: "DELETE")
    }

    func fetchMixedSelections(limit: Int = 12) async throws -> [SCMixedSelection] {
        let page: SCCollectionPage<SCMixedSelection> = try await get(
            path: "/mixed-selections",
            query: [
                URLQueryItem(name: "variant_ids", value: ""),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        return page.collection
    }

    func fetchPlayHistory(limit: Int = 50, nextHref: String? = nil) async throws -> SCCollectionPage<SCHistoryItem> {
        if let nextHref, !nextHref.isEmpty {
            return try await get(path: nextHref)
        }
        return try await get(
            path: "/me/play-history/tracks",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "linked_partitioning", value: "1"),
            ]
        )
    }

    func fetchPlaylist(id: Int) async throws -> SCPlaylist {
        try await get(path: "/playlists/\(id)")
    }

    func fetchTracks(ids: [Int]) async throws -> [SCTrack] {
        guard !ids.isEmpty else { return [] }
        var all: [SCTrack] = []
        var offset = 0
        while offset < ids.count {
            let chunk = Array(ids[offset..<min(offset + 50, ids.count)])
            let joined = chunk.map(String.init).joined(separator: ",")
            let batch: [SCTrack] = try await get(
                path: "/tracks",
                query: [URLQueryItem(name: "ids", value: joined)]
            )
            all.append(contentsOf: batch)
            offset += 50
        }
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    /// Resolves all tracks for a playlist/album/system-playlist (hydrating any ID-only stubs).
    func resolveTracks(for playlist: SCPlaylist) async throws -> [SCTrack] {
        let source: SCPlaylist
        if (playlist.tracks ?? []).isEmpty, let id = playlist.id {
            source = try await fetchPlaylist(id: id)
        } else {
            source = playlist
        }
        guard let entries = source.tracks, !entries.isEmpty else { return [] }
        let missing = source.missingTrackIDs
        let hydratedByID: [Int: SCTrack]
        if !missing.isEmpty {
            let fetched = try await fetchTracks(ids: missing)
            hydratedByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        } else {
            hydratedByID = [:]
        }
        return entries.compactMap { $0.fullTrack ?? hydratedByID[$0.id] }
    }

    // MARK: - Search & Library Endpoints

    func searchTracks(
        query: String,
        genreOrTag: String? = nil,
        createdAt: String? = nil,
        duration: String? = nil,
        license: String? = nil,
        limit: Int = 30,
        nextHref: String? = nil
    ) async throws -> SCSearchTrackPage {
        if let nextHref, !nextHref.isEmpty { return try await get(path: nextHref) }
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "linked_partitioning", value: "1"),
            URLQueryItem(name: "facet", value: "genre"),
        ]
        if let genreOrTag, !genreOrTag.isEmpty {
            items.append(URLQueryItem(name: "filter.genre_or_tag", value: genreOrTag))
        }
        if let createdAt, !createdAt.isEmpty {
            items.append(URLQueryItem(name: "filter.created_at", value: createdAt))
        }
        if let duration, !duration.isEmpty {
            items.append(URLQueryItem(name: "filter.duration", value: duration))
        }
        if let license, !license.isEmpty {
            items.append(URLQueryItem(name: "filter.license", value: license))
        }
        return try await get(path: "/search/tracks", query: items)
    }

    func fetchUserOwnPlaylists(userID: Int, limit: Int = 50) async throws -> [SCPlaylist] {
        let page: SCCollectionPage<SCPlaylist> = try await get(
            path: "/users/\(userID)/playlists_without_albums",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "linked_partitioning", value: "1"),
            ]
        )
        return page.collection
    }

    func searchPlaylists(query: String, limit: Int = 30, nextHref: String? = nil) async throws -> SCCollectionPage<SCPlaylist> {
        if let nextHref, !nextHref.isEmpty { return try await get(path: nextHref) }
        return try await get(
            path: "/search/playlists_without_albums",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "linked_partitioning", value: "1"),
            ]
        )
    }

    func searchAlbums(query: String, limit: Int = 30, nextHref: String? = nil) async throws -> SCCollectionPage<SCPlaylist> {
        if let nextHref, !nextHref.isEmpty { return try await get(path: nextHref) }
        return try await get(
            path: "/search/albums",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "linked_partitioning", value: "1"),
            ]
        )
    }

    func searchUsers(query: String, limit: Int = 30, nextHref: String? = nil) async throws -> SCCollectionPage<SCUser> {
        if let nextHref, !nextHref.isEmpty { return try await get(path: nextHref) }
        return try await get(
            path: "/search/users",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "linked_partitioning", value: "1"),
            ]
        )
    }

    func fetchLibraryCollections(limit: Int = 50, nextHref: String? = nil) async throws -> SCCollectionPage<SCLibraryItem> {
        if let nextHref, !nextHref.isEmpty { return try await get(path: nextHref) }
        return try await get(
            path: "/me/library/all",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "linked_partitioning", value: "1"),
            ]
        )
    }

    func fetchUserFollowings(userID: Int, limit: Int = 50, nextHref: String? = nil) async throws -> SCCollectionPage<SCUser> {
        if let nextHref, !nextHref.isEmpty { return try await get(path: nextHref) }
        return try await get(
            path: "/users/\(userID)/followings",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "linked_partitioning", value: "1"),
            ]
        )
    }

    // MARK: - Track Detail & Profile Endpoints

    func fetchTrackComments(trackID: Int, limit: Int = 40, nextHref: String? = nil) async throws -> SCCollectionPage<SCComment> {
        if let nextHref, !nextHref.isEmpty { return try await get(path: nextHref) }
        return try await get(
            path: "/tracks/\(trackID)/comments",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "threaded", value: "0"),
                URLQueryItem(name: "filter_replies", value: "0"),
                URLQueryItem(name: "linked_partitioning", value: "1"),
            ]
        )
    }

    func fetchUser(id: Int) async throws -> SCUser {
        try await get(path: "/users/\(id)")
    }

    func fetchUserTopTracks(userID: Int, limit: Int = 30) async throws -> [SCTrack] {
        let page: SCCollectionPage<SCTrack> = try await get(
            path: "/users/\(userID)/toptracks",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "linked_partitioning", value: "1"),
            ]
        )
        return page.collection
    }

    func fetchUserTracks(userID: Int, limit: Int = 40, nextHref: String? = nil) async throws -> SCCollectionPage<SCTrack> {
        if let nextHref, !nextHref.isEmpty { return try await get(path: nextHref) }
        return try await get(
            path: "/users/\(userID)/tracks",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "linked_partitioning", value: "1"),
            ]
        )
    }

    func fetchUserAlbums(userID: Int, limit: Int = 40, nextHref: String? = nil) async throws -> SCCollectionPage<SCPlaylist> {
        if let nextHref, !nextHref.isEmpty { return try await get(path: nextHref) }
        return try await get(
            path: "/users/\(userID)/albums",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "linked_partitioning", value: "1"),
            ]
        )
    }

    func followUser(userID: Int) async throws {
        _ = try await sendData(path: "/me/followings/\(userID)", method: "PUT")
    }

    func unfollowUser(userID: Int) async throws {
        _ = try await sendData(path: "/me/followings/\(userID)", method: "DELETE")
    }

    /// Fetches all of the user's saved/liked stations (`system-playlist-like`) by paginating `/me/library/all`.
    func fetchSavedStations(maxPages: Int = 12) async throws -> [SCPlaylist] {
        var stations: [SCPlaylist] = []
        var seen = Set<String>()
        var nextHref: String? = nil

        for pageIndex in 0..<maxPages {
            let page = try await fetchLibraryCollections(limit: 50, nextHref: pageIndex == 0 ? nil : nextHref)
            for item in page.collection where (item.type ?? "").contains("system-playlist") {
                if let pl = item.resolvedPlaylist, seen.insert(pl.stableID).inserted {
                    stations.append(pl)
                }
            }
            guard let next = page.nextHref, !next.isEmpty else { break }
            nextHref = next
        }
        return stations
    }

    // MARK: - Core Request Pipeline

    func get<T: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await sendData(path: path, query: query, method: "GET", body: nil, allowClientIDRefresh: true)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("Decode failed for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw SoundCloudAPIError.decodingFailed(error.localizedDescription)
        }
    }

    func sendData(
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        allowClientIDRefresh: Bool = true
    ) async throws -> Data {
        guard let token = oauthToken, !token.isEmpty else {
            throw SoundCloudAPIError.unauthenticated
        }

        let cid: String
        if let existing = clientID, !existing.isEmpty {
            cid = existing
        } else {
            cid = try await discoverClientID()
        }

        let request = try buildRequest(path: path, query: query, method: method, body: body, token: token, clientID: cid)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SoundCloudAPIError.invalidResponse
        }

        if (200...299).contains(http.statusCode) {
            return data
        }

        // If client_id rotated, refresh it once from soundcloud.com JS bundles and retry.
        if (http.statusCode == 401 || http.statusCode == 403), allowClientIDRefresh {
            logger.notice("HTTP \(http.statusCode) on \(path, privacy: .public) — attempting client_id refresh")
            if let refreshed = try? await discoverClientID(), refreshed != cid {
                return try await sendData(
                    path: path,
                    query: query,
                    method: method,
                    body: body,
                    allowClientIDRefresh: false
                )
            }
            if http.statusCode == 401 {
                throw SoundCloudAPIError.unauthenticated
            }
        }

        let snippet = String(data: data.prefix(200), encoding: .utf8)
        throw SoundCloudAPIError.httpStatus(http.statusCode, snippet)
    }

    private func buildRequest(
        path: String,
        query: [URLQueryItem],
        method: String,
        body: Data?,
        token: String,
        clientID: String
    ) throws -> URLRequest {
        let url: URL
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            guard var comps = URLComponents(string: path) else { throw SoundCloudAPIError.invalidURL }
            var items = comps.queryItems ?? []
            if !items.contains(where: { $0.name == "client_id" }) {
                items.append(URLQueryItem(name: "client_id", value: clientID))
            }
            items.append(contentsOf: query)
            comps.queryItems = items
            guard let built = comps.url else { throw SoundCloudAPIError.invalidURL }
            url = built
        } else {
            let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
            guard var comps = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false) else {
                throw SoundCloudAPIError.invalidURL
            }
            comps.path = normalizedPath
            var items = query
            items.append(URLQueryItem(name: "client_id", value: clientID))
            items.append(URLQueryItem(name: "app_locale", value: "en"))
            comps.queryItems = items
            guard let built = comps.url else { throw SoundCloudAPIError.invalidURL }
            url = built
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        req.setValue("https://soundcloud.com", forHTTPHeaderField: "Origin")
        req.setValue("https://soundcloud.com/", forHTTPHeaderField: "Referer")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    // MARK: - Self-Healing client_id Discovery

    /// Scrapes SoundCloud's public web bundles for the active `client_id` without WebKit.
    func discoverClientID() async throws -> String {
        let (htmlData, htmlResp) = try await session.data(from: Self.webOrigin)
        guard let http = htmlResp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let html = String(data: htmlData, encoding: .utf8) else {
            throw SoundCloudAPIError.clientIDDiscoveryFailed
        }

        let scriptURLs = Self.extractAssetScriptURLs(from: html)
        // App bundles containing client_id are typically at the end of the script list.
        for scriptURL in scriptURLs.reversed() {
            guard let (jsData, jsResp) = try? await session.data(from: scriptURL),
                  let jsHTTP = jsResp as? HTTPURLResponse, (200...299).contains(jsHTTP.statusCode),
                  let js = String(data: jsData, encoding: .utf8) else {
                continue
            }
            if let found = Self.extractClientID(fromJS: js) {
                self.clientID = found
                self.onClientIDUpdated?(found)
                logger.info("Discovered SoundCloud client_id (\(found.prefix(6), privacy: .public)…)")
                return found
            }
        }
        throw SoundCloudAPIError.clientIDDiscoveryFailed
    }

    nonisolated static func extractAssetScriptURLs(from html: String) -> [URL] {
        let pattern = #"https://a-v2\.sndcdn\.com/assets/[A-Za-z0-9._-]+\.js"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seen = Set<String>()
        var urls: [URL] = []
        for match in regex.matches(in: html, range: range) {
            guard let r = Range(match.range, in: html) else { continue }
            let s = String(html[r])
            if seen.insert(s).inserted, let url = URL(string: s) {
                urls.append(url)
            }
        }
        return urls
    }

    nonisolated static func extractClientID(fromJS js: String) -> String? {
        let patterns = [
            #"client_id\s*:\s*["']([A-Za-z0-9]{20,40})["']"#,
            #"client_id=([A-Za-z0-9]{20,40})"#,
        ]
        let range = NSRange(js.startIndex..<js.endIndex, in: js)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: js, range: range),
                  match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: js) else {
                continue
            }
            return String(js[r])
        }
        return nil
    }
}

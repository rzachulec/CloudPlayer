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

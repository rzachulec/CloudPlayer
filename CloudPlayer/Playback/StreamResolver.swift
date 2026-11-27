import Foundation
import OSLog

enum StreamResolverError: LocalizedError, Equatable {
    case noPlayableTranscoding
    case trackBlocked
    case invalidStreamURL

    var errorDescription: String? {
        switch self {
        case .noPlayableTranscoding:
            "No AVPlayer-compatible audio stream found for this track."
        case .trackBlocked:
            "This track is not available for streaming in your region."
        case .invalidStreamURL:
            "SoundCloud returned an invalid stream URL."
        }
    }
}

/// Resolves SoundCloud transcoding endpoints into playable CDN URLs (preferring native HLS MP3/AAC
/// over Opus since macOS `AVPlayer` natively hardware-decodes MP3 & AAC HLS).
actor StreamResolver {
    private struct CacheEntry {
        let url: URL
        let expiresAt: Date
    }

    private struct StreamResponse: Decodable {
        let url: URL
    }

    private let api: SoundCloudAPI
    private let logger = Logger(subsystem: "local.cloudplayer", category: "StreamResolver")
    private var cache: [Int: CacheEntry] = [:]
    private var inFlight: [Int: Task<URL, Error>] = [:]
    private let cacheTTL: TimeInterval

    init(api: SoundCloudAPI, cacheTTL: TimeInterval = 240) {
        self.api = api
        self.cacheTTL = cacheTTL
    }

    /// Picks the best AVPlayer-compatible transcoding:
    /// 1. Full HLS MP3 / AAC
    /// 2. Full Progressive MP3
    /// 3. Preview/Snipped HLS MP3 / AAC
    /// 4. Preview/Snipped Progressive MP3
    static func selectBestTranscoding(from transcodings: [SCTranscoding]) -> SCTranscoding? {
        let compatible = transcodings.filter { isAVPlayerCompatible($0.format.mimeType) }
        guard !compatible.isEmpty else { return nil }

        let full = compatible.filter { $0.snipped != true }
        let candidates = full.isEmpty ? compatible : full

        if let hlsAAC = candidates.first(where: {
            $0.format.protocolType == "hls" && $0.format.mimeType.lowercased().contains("mp4a")
        }) {
            return hlsAAC
        }
        if let hlsMP3 = candidates.first(where: {
            $0.format.protocolType == "hls" && $0.format.mimeType.lowercased().contains("mpeg")
        }) {
            return hlsMP3
        }
        if let progressiveMP3 = candidates.first(where: {
            $0.format.protocolType == "progressive" && $0.format.mimeType.lowercased().contains("mpeg")
        }) {
            return progressiveMP3
        }
        return candidates.first
    }

    static func isAVPlayerCompatible(_ mimeType: String) -> Bool {
        let lower = mimeType.lowercased()
        if lower.contains("ogg") || lower.contains("opus") { return false }
        return lower.contains("mpeg") || lower.contains("mp4") || lower.contains("aac")
    }

    func resolveStreamURL(for track: SCTrack, forceRefresh: Bool = false) async throws -> URL {
        if track.isBlocked {
            throw StreamResolverError.trackBlocked
        }

        if !forceRefresh, let cached = cache[track.id], cached.expiresAt > Date() {
            return cached.url
        }

        if !forceRefresh, let existingTask = inFlight[track.id] {
            return try await existingTask.value
        }

        let task = Task<URL, Error> {
            let transcodings = track.media?.transcodings ?? []
            guard let chosen = Self.selectBestTranscoding(from: transcodings) else {
                throw StreamResolverError.noPlayableTranscoding
            }

            var query: [URLQueryItem] = []
            if let auth = track.trackAuthorization, !auth.isEmpty {
                query.append(URLQueryItem(name: "track_authorization", value: auth))
            }

            let data = try await api.sendData(path: chosen.url.absoluteString, query: query)
            let decoded = try JSONDecoder().decode(StreamResponse.self, from: data)
            logger.debug("Resolved \(chosen.format.protocolType, privacy: .public) (\(chosen.format.mimeType, privacy: .public)) for track \(track.id)")
            return decoded.url
        }

        inFlight[track.id] = task
        defer { inFlight[track.id] = nil }

        let resolved = try await task.value
        cache[track.id] = CacheEntry(url: resolved, expiresAt: Date().addingTimeInterval(cacheTTL))
        return resolved
    }

    func preResolve(track: SCTrack) {
        Task {
            _ = try? await resolveStreamURL(for: track)
        }
    }

    func invalidate(trackID: Int) {
        cache[trackID] = nil
    }
}

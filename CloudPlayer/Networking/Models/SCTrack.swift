import Foundation

/// Tolerant SoundCloud track model returned by `/users/{id}/track_likes`, `/tracks/{id}`,
/// `/search/tracks`, `/tracks/{id}/related`, playlists, etc.
struct SCTrack: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let permalinkURL: URL?
    let artworkURL: URL?
    let duration: Int
    let fullDuration: Int?
    let genre: String?
    let waveformURL: URL?
    let trackAuthorization: String?
    let policy: String?
    let playbackCount: Int?
    let likesCount: Int?
    let repostsCount: Int?
    let commentCount: Int?
    let createdAt: String?
    let description: String?
    let user: SCUser?
    let media: SCMedia?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case permalinkURL = "permalink_url"
        case artworkURL = "artwork_url"
        case duration
        case fullDuration = "full_duration"
        case genre
        case waveformURL = "waveform_url"
        case trackAuthorization = "track_authorization"
        case policy
        case playbackCount = "playback_count"
        case likesCount = "likes_count"
        case repostsCount = "reposts_count"
        case commentCount = "comment_count"
        case createdAt = "created_at"
        case description
        case user
        case media
    }

    init(
        id: Int,
        title: String,
        permalinkURL: URL? = nil,
        artworkURL: URL? = nil,
        duration: Int = 0,
        fullDuration: Int? = nil,
        genre: String? = nil,
        waveformURL: URL? = nil,
        trackAuthorization: String? = nil,
        policy: String? = nil,
        playbackCount: Int? = nil,
        likesCount: Int? = nil,
        repostsCount: Int? = nil,
        commentCount: Int? = nil,
        createdAt: String? = nil,
        description: String? = nil,
        user: SCUser? = nil,
        media: SCMedia? = nil
    ) {
        self.id = id
        self.title = title
        self.permalinkURL = permalinkURL
        self.artworkURL = artworkURL
        self.duration = duration
        self.fullDuration = fullDuration
        self.genre = genre
        self.waveformURL = waveformURL
        self.trackAuthorization = trackAuthorization
        self.policy = policy
        self.playbackCount = playbackCount
        self.likesCount = likesCount
        self.repostsCount = repostsCount
        self.commentCount = commentCount
        self.createdAt = createdAt
        self.description = description
        self.user = user
        self.media = media
    }

    var durationSeconds: Double {
        Double(duration) / 1000.0
    }

    var artistName: String {
        user?.displayName ?? "Unknown Artist"
    }

    var isPreviewOnly: Bool {
        policy?.uppercased() == "SNIP"
    }

    var isBlocked: Bool {
        policy?.uppercased() == "BLOCK"
    }

    func resolvedArtworkURL(size: SCImageSize = .large) -> URL? {
        (artworkURL ?? user?.avatarURL)?.scImageVariant(size)
    }
}

struct SCMedia: Codable, Hashable, Sendable {
    let transcodings: [SCTranscoding]
}

struct SCTranscoding: Codable, Hashable, Sendable {
    let url: URL
    let preset: String?
    let duration: Int?
    let snipped: Bool?
    let format: SCTranscodingFormat
    let quality: String?
}

struct SCTranscodingFormat: Codable, Hashable, Sendable {
    let protocolType: String
    let mimeType: String

    enum CodingKeys: String, CodingKey {
        case protocolType = "protocol"
        case mimeType = "mime_type"
    }
}

/// Wrapper for `/users/{id}/track_likes` entries.
struct SCLikeItem: Codable, Sendable {
    let createdAt: String?
    let track: SCTrack?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case track
    }
}

/// Decodes SoundCloud paginated `{ "collection": [...], "next_href": "..." }` responses
/// while skipping individual malformed or deleted items instead of failing the whole page.
struct SCCollectionPage<Element: Decodable & Sendable>: Decodable, Sendable {
    let collection: [Element]
    let nextHref: String?

    enum CodingKeys: String, CodingKey {
        case collection
        case nextHref = "next_href"
    }

    init(collection: [Element], nextHref: String?) {
        self.collection = collection
        self.nextHref = nextHref
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.nextHref = try container.decodeIfPresent(String.self, forKey: .nextHref)

        var unkeyed = try container.nestedUnkeyedContainer(forKey: .collection)
        var items: [Element] = []
        while !unkeyed.isAtEnd {
            if let item = try? unkeyed.decode(Element.self) {
                items.append(item)
            } else {
                _ = try? unkeyed.decode(AnyDecodableSkip.self)
            }
        }
        self.collection = items
    }
}

private struct AnyDecodableSkip: Decodable {}

/// Search facet chip returned by `/search/tracks?facet=genre`.
struct SCSearchFacet: Codable, Hashable, Identifiable, Sendable {
    let value: String
    let count: Int?
    let filter: String?

    var id: String { value }
}

struct SCSearchFacetGroup: Codable, Sendable {
    let name: String
    let facets: [SCSearchFacet]
}

struct SCSearchTrackPage: Decodable, Sendable {
    let collection: [SCTrack]
    let nextHref: String?
    let facets: [SCSearchFacetGroup]?

    enum CodingKeys: String, CodingKey {
        case collection
        case nextHref = "next_href"
        case facets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.nextHref = try container.decodeIfPresent(String.self, forKey: .nextHref)
        self.facets = try container.decodeIfPresent([SCSearchFacetGroup].self, forKey: .facets)

        var unkeyed = try container.nestedUnkeyedContainer(forKey: .collection)
        var items: [SCTrack] = []
        while !unkeyed.isAtEnd {
            if let item = try? unkeyed.decode(SCTrack.self) {
                items.append(item)
            } else {
                _ = try? unkeyed.decode(AnyDecodableSkip.self)
            }
        }
        self.collection = items
    }

    var genreTags: [SCSearchFacet] {
        facets?.first(where: { $0.name == "genre" })?.facets ?? []
    }
}

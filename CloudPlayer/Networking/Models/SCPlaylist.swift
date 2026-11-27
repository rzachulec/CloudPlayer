import Foundation

/// SoundCloud playlist / album / system-playlist item.
/// Handles both numeric `id` (regular playlists) and String URN `id` (`system-playlist`),
/// plus SoundCloud's partial track arrays (first ~5 full tracks + ID-only stubs).
struct SCPlaylist: Codable, Identifiable, Hashable, Sendable {
    let id: Int?
    let urn: String?
    let title: String
    let permalinkURL: URL?
    let artworkURL: URL?
    let calculatedArtworkURL: URL?
    let description: String?
    let isAlbum: Bool?
    let trackCount: Int?
    let duration: Int?
    let likesCount: Int?
    let genre: String?
    let user: SCUser?
    let tracks: [SCTrackOrStub]?

    enum CodingKeys: String, CodingKey {
        case id
        case urn
        case title
        case permalinkURL = "permalink_url"
        case artworkURL = "artwork_url"
        case calculatedArtworkURL = "calculated_artwork_url"
        case description
        case isAlbum = "is_album"
        case trackCount = "track_count"
        case duration
        case likesCount = "likes_count"
        case genre
        case user
        case tracks
    }

    init(
        id: Int? = nil,
        urn: String? = nil,
        title: String,
        permalinkURL: URL? = nil,
        artworkURL: URL? = nil,
        calculatedArtworkURL: URL? = nil,
        description: String? = nil,
        isAlbum: Bool? = nil,
        trackCount: Int? = nil,
        duration: Int? = nil,
        likesCount: Int? = nil,
        genre: String? = nil,
        user: SCUser? = nil,
        tracks: [SCTrackOrStub]? = nil
    ) {
        self.id = id
        self.urn = urn
        self.title = title
        self.permalinkURL = permalinkURL
        self.artworkURL = artworkURL
        self.calculatedArtworkURL = calculatedArtworkURL
        self.description = description
        self.isAlbum = isAlbum
        self.trackCount = trackCount
        self.duration = duration
        self.likesCount = likesCount
        self.genre = genre
        self.user = user
        self.tracks = tracks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var parsedID: Int?
        var parsedURN = try c.decodeIfPresent(String.self, forKey: .urn)
        if let intID = try? c.decodeIfPresent(Int.self, forKey: .id) {
            parsedID = intID
        } else if let strID = try? c.decodeIfPresent(String.self, forKey: .id) {
            parsedURN = parsedURN ?? strID
        }
        self.id = parsedID
        self.urn = parsedURN
        self.title = try c.decode(String.self, forKey: .title)
        self.permalinkURL = try c.decodeIfPresent(URL.self, forKey: .permalinkURL)
        self.artworkURL = try c.decodeIfPresent(URL.self, forKey: .artworkURL)
        self.calculatedArtworkURL = try c.decodeIfPresent(URL.self, forKey: .calculatedArtworkURL)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.isAlbum = try c.decodeIfPresent(Bool.self, forKey: .isAlbum)
        self.trackCount = try c.decodeIfPresent(Int.self, forKey: .trackCount)
        self.duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        self.likesCount = try c.decodeIfPresent(Int.self, forKey: .likesCount)
        self.genre = try c.decodeIfPresent(String.self, forKey: .genre)
        self.user = try c.decodeIfPresent(SCUser.self, forKey: .user)
        self.tracks = try c.decodeIfPresent([SCTrackOrStub].self, forKey: .tracks)
    }

    var stableID: String {
        if let id { return "pl:\(id)" }
        if let urn { return urn }
        return "pl:\(title)"
    }

    var subtitle: String {
        if let user { return user.displayName }
        if let count = trackCount, count > 0 { return "\(count) tracks" }
        if let desc = description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty { return desc }
        return isAlbum == true ? "Album" : "Playlist"
    }

    func resolvedArtworkURL(size: SCImageSize = .large) -> URL? {
        if let url = artworkURL ?? calculatedArtworkURL {
            return url.scImageVariant(size)
        }
        if let firstTrackArt = tracks?.compactMap({ $0.fullTrack?.resolvedArtworkURL(size: size) }).first {
            return firstTrackArt
        }
        return user?.avatarURL(size: size)
    }

    var hydratedTracks: [SCTrack] {
        tracks?.compactMap(\.fullTrack) ?? []
    }

    var missingTrackIDs: [Int] {
        tracks?.compactMap { $0.fullTrack == nil ? $0.id : nil } ?? []
    }

    func mergingTracks(from detailed: SCPlaylist) -> SCPlaylist {
        SCPlaylist(
            id: id ?? detailed.id,
            urn: urn ?? detailed.urn,
            title: title,
            permalinkURL: permalinkURL ?? detailed.permalinkURL,
            artworkURL: artworkURL ?? detailed.artworkURL,
            calculatedArtworkURL: calculatedArtworkURL ?? detailed.calculatedArtworkURL,
            description: description ?? detailed.description,
            isAlbum: isAlbum ?? detailed.isAlbum,
            trackCount: trackCount ?? detailed.trackCount,
            duration: duration ?? detailed.duration,
            likesCount: likesCount ?? detailed.likesCount,
            genre: genre ?? detailed.genre,
            user: user ?? detailed.user,
            tracks: (tracks?.isEmpty == false) ? tracks : detailed.tracks
        )
    }
}

/// Decodes either a full `SCTrack` or an ID-only `{ "id": 12345 }` stub inside a playlist's `tracks` array.
struct SCTrackOrStub: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let fullTrack: SCTrack?

    enum CodingKeys: String, CodingKey {
        case id
        case title
    }

    init(id: Int, fullTrack: SCTrack? = nil) {
        self.id = id
        self.fullTrack = fullTrack
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        if container.contains(.title), let track = try? SCTrack(from: decoder) {
            self.fullTrack = track
        } else {
            self.fullTrack = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        if let fullTrack {
            try fullTrack.encode(to: encoder)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
        }
    }
}

/// Mixed item inside `/mixed-selections` shelves (playlists, system-playlists, or users).
enum SCSelectionEntry: Codable, Identifiable, Hashable, Sendable {
    case playlist(SCPlaylist)
    case user(SCUser)

    var id: String {
        switch self {
        case .playlist(let pl): pl.stableID
        case .user(let u): "user:\(u.id)"
        }
    }

    private enum KindKey: String, CodingKey { case kind }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: KindKey.self)
        let kind = try c.decodeIfPresent(String.self, forKey: .kind)
        if kind == "user" {
            self = .user(try SCUser(from: decoder))
        } else {
            self = .playlist(try SCPlaylist(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .playlist(let pl): try pl.encode(to: encoder)
        case .user(let u): try u.encode(to: encoder)
        }
    }
}

/// Home / Discover shelf returned by `/mixed-selections`.
struct SCMixedSelection: Codable, Identifiable, Sendable {
    let urn: String
    let title: String
    let description: String?
    let items: SCSelectionItems?

    var id: String { urn }
}

struct SCSelectionItems: Codable, Sendable {
    let collection: [SCSelectionEntry]

    enum CodingKeys: String, CodingKey {
        case collection
    }

    init(collection: [SCSelectionEntry]) {
        self.collection = collection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var unkeyed = try container.nestedUnkeyedContainer(forKey: .collection)
        var seen = Set<String>()
        var out: [SCSelectionEntry] = []
        while !unkeyed.isAtEnd {
            if let entry = try? unkeyed.decode(SCSelectionEntry.self) {
                if seen.insert(entry.id).inserted {
                    out.append(entry)
                }
            } else {
                _ = try? unkeyed.decode(SkipSelectionItem.self)
            }
        }
        self.collection = out
    }
}

private struct SkipSelectionItem: Decodable {}

/// Wrapper for `/me/play-history/tracks` entries.
struct SCHistoryItem: Codable, Sendable {
    let playedAt: Int?
    let track: SCTrack?

    enum CodingKeys: String, CodingKey {
        case playedAt = "played_at"
        case track
    }
}

/// Wrapper for `/stream/users/{id}/reposts` entries.
struct SCRepostItem: Codable, Sendable {
    let type: String?
    let createdAt: String?
    let track: SCTrack?
    let playlist: SCPlaylist?

    enum CodingKeys: String, CodingKey {
        case type
        case createdAt = "created_at"
        case track
        case playlist
    }
}

/// Wrapper for `/me/library/all` entries (playlists, albums, system playlists).
struct SCLibraryItem: Codable, Sendable {
    let type: String?
    let playlist: SCPlaylist?
    let systemPlaylist: SCPlaylist?

    enum CodingKeys: String, CodingKey {
        case type
        case playlist
        case systemPlaylist = "system_playlist"
    }

    var resolvedPlaylist: SCPlaylist? {
        playlist ?? systemPlaylist
    }
}

/// Wrapper for `/me/personalized-stations` entries.
struct SCStationItem: Codable, Sendable {
    let playlist: SCPlaylist?
    let systemPlaylist: SCPlaylist?

    enum CodingKeys: String, CodingKey {
        case playlist
        case systemPlaylist = "system_playlist"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pl = try? container.decodeIfPresent(SCPlaylist.self, forKey: .playlist)
        let sys = try? container.decodeIfPresent(SCPlaylist.self, forKey: .systemPlaylist)
        if let direct = pl ?? sys {
            self.playlist = direct
            self.systemPlaylist = nil
        } else if let directPl = try? SCPlaylist(from: decoder) {
            self.playlist = directPl
            self.systemPlaylist = nil
        } else {
            self.playlist = nil
            self.systemPlaylist = nil
        }
    }
}

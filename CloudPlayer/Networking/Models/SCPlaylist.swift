import Foundation

/// SoundCloud playlist / album / system-playlist item.
/// Handles SoundCloud's partial track arrays (first ~5 tracks are full objects, remaining are `{ "id": ... }` stubs).
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

    var stableID: String {
        if let id { return "pl:\(id)" }
        if let urn { return urn }
        return "pl:\(title)"
    }

    var subtitle: String {
        if let user { return user.displayName }
        if let count = trackCount, count > 0 { return "\(count) tracks" }
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

/// Home / Discover shelf returned by `/mixed-selections`.
struct SCMixedSelection: Codable, Identifiable, Sendable {
    let urn: String
    let title: String
    let description: String?
    let items: SCSelectionItems?

    var id: String { urn }
}

struct SCSelectionItems: Codable, Sendable {
    let collection: [SCPlaylist]

    enum CodingKeys: String, CodingKey {
        case collection
    }

    init(collection: [SCPlaylist]) {
        self.collection = collection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var unkeyed = try container.nestedUnkeyedContainer(forKey: .collection)
        var out: [SCPlaylist] = []
        while !unkeyed.isAtEnd {
            if let item = try? unkeyed.decode(SCPlaylist.self) {
                out.append(item)
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

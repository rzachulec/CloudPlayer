import Foundation

/// SoundCloud user model returned by `/me`, `/users/{id}`, and embedded inside tracks/playlists.
/// Designed with tolerant optional decoding so schema drift never breaks feed loading.
struct SCUser: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let username: String
    let fullName: String?
    let permalink: String?
    let permalinkURL: URL?
    let avatarURL: URL?
    let followersCount: Int?
    let followingsCount: Int?
    let trackCount: Int?
    let likesCount: Int?
    let playlistCount: Int?
    let description: String?
    let city: String?
    let countryCode: String?
    let verified: Bool?
    let visuals: SCUserVisuals?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case fullName = "full_name"
        case permalink
        case permalinkURL = "permalink_url"
        case avatarURL = "avatar_url"
        case followersCount = "followers_count"
        case followingsCount = "followings_count"
        case trackCount = "track_count"
        case likesCount = "likes_count"
        case playlistCount = "playlist_count"
        case description
        case city
        case countryCode = "country_code"
        case verified
        case visuals
    }

    var displayName: String {
        if let full = fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !full.isEmpty {
            return full
        }
        return username
    }

    var bannerURL: URL? {
        guard visuals?.enabled != false else { return nil }
        return visuals?.visuals?.first?.visualURL
    }

    func avatarURL(size: SCImageSize) -> URL? {
        avatarURL?.scImageVariant(size)
    }
}

struct SCUserVisuals: Codable, Hashable, Sendable {
    let enabled: Bool?
    let visuals: [SCVisualItem]?
}

struct SCVisualItem: Codable, Hashable, Sendable {
    let visualURL: URL?

    enum CodingKeys: String, CodingKey {
        case visualURL = "visual_url"
    }
}

enum SCImageSize: String, Sendable {
    case small = "t120x120"
    case medium = "t200x200"
    case large = "t500x500"
    case original = "original"
}

extension URL {
    /// SoundCloud artwork & avatar URLs encode dimensions in the filename suffix (e.g. `-large.jpg`).
    func scImageVariant(_ size: SCImageSize) -> URL {
        let raw = absoluteString
        let replaced = raw.replacingOccurrences(
            of: #"-(t\d+x\d+|large|small|badge|tiny|crop)\."#,
            with: "-\(size.rawValue).",
            options: .regularExpression
        )
        return URL(string: replaced) ?? self
    }
}

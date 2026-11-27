import Foundation

/// SoundCloud timed track comment returned by `/tracks/{id}/comments`.
struct SCComment: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let body: String
    let timestamp: Int?
    let createdAt: String?
    let user: SCUser?

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case timestamp
        case createdAt = "created_at"
        case user
    }

    var timestampSeconds: Double? {
        timestamp.map { Double($0) / 1000.0 }
    }
}

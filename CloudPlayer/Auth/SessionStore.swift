import Foundation
import Observation
import Security

/// Persisted SoundCloud credentials captured from the disposable sign-in flow.
struct SoundCloudSession: Codable, Equatable, Sendable {
    var oauthToken: String
    var refreshToken: String?
    var clientID: String
    var userID: Int?
    var username: String?
    var avatarURL: URL?
    var updatedAt: Date

    init(
        oauthToken: String,
        refreshToken: String? = nil,
        clientID: String = "",
        userID: Int? = nil,
        username: String? = nil,
        avatarURL: URL? = nil,
        updatedAt: Date = Date()
    ) {
        self.oauthToken = oauthToken
        self.refreshToken = refreshToken
        self.clientID = clientID
        self.userID = userID
        self.username = username
        self.avatarURL = avatarURL
        self.updatedAt = updatedAt
    }
}

protocol SessionPersistence: Sendable {
    func load() -> SoundCloudSession?
    func save(_ session: SoundCloudSession) throws
    func clear() throws
}

/// File-backed persistence (`0600`) used in Debug builds so ad-hoc code signing never triggers
/// repeated macOS Keychain prompts across rebuilds.
struct FileSessionPersistence: SessionPersistence {
    let url: URL

    static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudPlayer/session.json")
    }

    init(url: URL = Self.defaultURL) {
        self.url = url
    }

    func load() -> SoundCloudSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SoundCloudSession.self, from: data)
    }

    func save(_ session: SoundCloudSession) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(session)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

/// Keychain-backed persistence for Release builds.
struct KeychainSessionPersistence: SessionPersistence {
    let service: String
    let account: String

    init(service: String = "local.cloudplayer.session", account: String = "soundcloud") {
        self.service = service
        self.account = account
    }

    func load() -> SoundCloudSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SoundCloudSession.self, from: data)
    }

    func save(_ session: SoundCloudSession) throws {
        let data = try JSONEncoder().encode(session)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

/// Owns the user's native SoundCloud session without any WebKit dependency.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn
    }

    private(set) var state: State = .unknown
    private(set) var session: SoundCloudSession?
    private let persistence: any SessionPersistence

    init(persistence: (any SessionPersistence)? = nil) {
        if let persistence {
            self.persistence = persistence
        } else {
            #if DEBUG
            self.persistence = FileSessionPersistence()
            #else
            self.persistence = KeychainSessionPersistence()
            #endif
        }
    }

    func bootstrap() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "cpEphemeral") {
            session = nil
            state = .signedOut
            return
        }
        #endif
        if let loaded = persistence.load(), !loaded.oauthToken.isEmpty {
            session = loaded
            state = .signedIn
        } else {
            session = nil
            state = .signedOut
        }
    }

    func save(_ newSession: SoundCloudSession) {
        var normalized = newSession
        normalized.updatedAt = Date()
        session = normalized
        state = .signedIn
        try? persistence.save(normalized)
    }

    func updateClientID(_ clientID: String) {
        guard var current = session, !clientID.isEmpty, current.clientID != clientID else { return }
        current.clientID = clientID
        current.updatedAt = Date()
        session = current
        try? persistence.save(current)
    }

    func updateUser(_ user: SCUser) {
        guard var current = session else { return }
        current.userID = user.id
        current.username = user.username
        current.avatarURL = user.avatarURL
        current.updatedAt = Date()
        session = current
        try? persistence.save(current)
    }

    func signOut() {
        session = nil
        state = .signedOut
        try? persistence.clear()
    }
}

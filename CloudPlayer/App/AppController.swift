import Foundation
import Observation
import OSLog

struct NativeToast: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let artworkURL: URL?
}

/// Central native application controller. Zero WebKit dependency.
@MainActor
@Observable
final class AppController {
    let sessionStore: SessionStore
    let api: SoundCloudAPI
    let cache: APICache
    let audio: AudioEngine
    let library: LibraryStore
    let router: AppRouter

    private(set) var currentUser: SCUser?
    private(set) var isValidatingSession = false
    private(set) var lastError: String?
    var toast: NativeToast?

    private let logger = Logger(subsystem: "local.cloudplayer", category: "AppController")

    init(
        sessionStore: SessionStore? = nil,
        api: SoundCloudAPI? = nil,
        cache: APICache? = nil
    ) {
        let store = sessionStore ?? SessionStore()
        let client = api ?? SoundCloudAPI()
        self.sessionStore = store
        self.api = client
        self.cache = cache ?? APICache()
        self.audio = AudioEngine(api: client)
        self.library = LibraryStore(api: client)
        self.router = AppRouter(initial: .likes)
    }

    func start() {
        sessionStore.bootstrap()
        let store = sessionStore
        Task {
            await api.setOnClientIDUpdated { newID in
                Task { @MainActor in
                    store.updateClientID(newID)
                }
            }
            await api.configure(session: store.session)
            if store.state == .signedIn {
                await validateSession()
            }
        }
    }

    func handleAuthenticated(_ session: SoundCloudSession) {
        lastError = nil
        sessionStore.save(session)
        Task {
            await api.configure(session: session)
            await validateSession()
        }
    }

    func validateSession() async {
        guard sessionStore.state == .signedIn else { return }
        isValidatingSession = true
        lastError = nil
        defer { isValidatingSession = false }

        do {
            let user = try await api.fetchCurrentUser()
            currentUser = user
            sessionStore.updateUser(user)
            logger.info("Authenticated as \(user.username, privacy: .public) (id: \(user.id))")
        } catch let err as SoundCloudAPIError where err == .unauthenticated {
            logger.warning("Stored SoundCloud session rejected (401); signing out")
            lastError = err.localizedDescription
            signOut()
        } catch {
            logger.error("Session validation failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    func toggleLikeCurrentTrack() {
        guard let track = audio.currentTrack else { return }
        library.toggleLike(trackID: track.id, userID: currentUser?.id ?? sessionStore.session?.userID)
    }

    func isCurrentTrackLiked() -> Bool {
        guard let track = audio.currentTrack else { return false }
        return library.isLiked(track.id)
    }

    func showToast(_ text: String, artworkURL: URL? = nil, duration: TimeInterval = 3.5) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let t = NativeToast(text: trimmed, artworkURL: artworkURL)
        toast = t
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            if self?.toast?.id == t.id {
                self?.toast = nil
            }
        }
    }

    func signOut() {
        audio.shutdown()
        library.reset()
        router.reset(to: .likes)
        currentUser = nil
        lastError = nil
        toast = nil
        sessionStore.signOut()
        Task {
            await api.configure(session: nil)
            await cache.clearAll()
        }
    }

    func shutdown() {
        audio.shutdown()
    }
}

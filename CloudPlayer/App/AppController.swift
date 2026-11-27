import Foundation
import Nuke
import Observation
import OSLog

struct NativeToast: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let artworkURL: URL?
}

struct TrackDetailPayload: Sendable {
    let comments: [SCComment]
    let related: [SCTrack]
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

    /// In-memory pre-fetched comments & related tracks keyed by track ID for zero-latency swipe transitions.
    private var trackDetailsCache: [Int: TrackDetailPayload] = [:]
    private var trackDetailsInFlight: Set<Int> = []
    private let imagePrefetcher = ImagePrefetcher()

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

    func toggleLike(_ track: SCTrack) {
        let willLike = !library.isLiked(track.id)
        library.toggleLike(trackID: track.id, userID: currentUser?.id ?? sessionStore.session?.userID)
        showToast(
            willLike ? "Saved “\(track.title)” to Likes" : "Removed “\(track.title)” from Likes",
            artworkURL: track.resolvedArtworkURL(size: .small)
        )
    }

    func toggleLikeCurrentTrack() {
        guard let track = audio.currentTrack else { return }
        toggleLike(track)
    }

    func isCurrentTrackLiked() -> Bool {
        guard let track = audio.currentTrack else { return false }
        return library.isLiked(track.id)
    }

    func showToast(_ text: String, artworkURL: URL? = nil, duration: TimeInterval = 3.2) {
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

    func cachedTrackDetails(for trackID: Int) -> TrackDetailPayload? {
        trackDetailsCache[trackID]
    }

    func loadTrackDetails(for track: SCTrack) async -> TrackDetailPayload {
        if let existing = trackDetailsCache[track.id] {
            return existing
        }
        async let relatedTask = api.fetchRelatedTracks(trackID: track.id, limit: 15)
        async let commentsTask = api.fetchTrackComments(trackID: track.id, limit: 80)

        let related = (try? await relatedTask) ?? []
        let comments = (try? await commentsTask)?.collection ?? []
        let payload = TrackDetailPayload(comments: comments, related: related)
        storeTrackDetails(payload, for: track.id)
        return payload
    }

    /// Pre-fetches artwork (Nuke), waveform JSON, comments, and related tracks for the next and
    /// previous tracks in the queue so Now Playing swipe transitions render with zero blank frames.
    func prefetchAdjacentTracks() {
        let candidates = [audio.queue.nextUpPreview, audio.queue.history.last].compactMap { $0 }
        guard !candidates.isEmpty else { return }

        let artURLs = candidates.compactMap { $0.resolvedArtworkURL(size: .large) }
        if !artURLs.isEmpty {
            imagePrefetcher.startPrefetching(with: artURLs)
        }

        for track in candidates {
            if let wfURL = track.waveformURL {
                Task { _ = await WaveformCache.shared.waveform(for: wfURL) }
            }
            if trackDetailsCache[track.id] == nil && !trackDetailsInFlight.contains(track.id) {
                trackDetailsInFlight.insert(track.id)
                Task { [weak self] in
                    guard let self else { return }
                    _ = await self.loadTrackDetails(for: track)
                    self.trackDetailsInFlight.remove(track.id)
                }
            }
        }
    }

    private func storeTrackDetails(_ payload: TrackDetailPayload, for trackID: Int) {
        if trackDetailsCache.count > 40 {
            trackDetailsCache.removeAll(keepingCapacity: true)
        }
        trackDetailsCache[trackID] = payload
    }

    func signOut() {
        audio.shutdown()
        library.reset()
        router.reset(to: .likes)
        trackDetailsCache.removeAll()
        trackDetailsInFlight.removeAll()
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

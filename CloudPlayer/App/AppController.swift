import Foundation
import Nuke
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
    private(set) var sessionHistory: [SCTrack] = []
    var focusTrack: SCTrack?
    var isFocusVisible = false
    var focusZoomAnimation = false
    var onFocusOverlayChanged: ((Bool) -> Void)?
    private var focusExitTask: Task<Void, Never>?

    var isFocusMode: Bool { isFocusVisible }

    func enterFocusMode(track: SCTrack? = nil, zoomFromCover: Bool = false) {
        guard let target = track ?? audio.currentTrack else { return }
        focusExitTask?.cancel()
        focusTrack = target
        focusZoomAnimation = zoomFromCover
        isFocusVisible = true
        onFocusOverlayChanged?(true)
    }

    func exitFocusMode() {
        guard isFocusVisible else { return }
        isFocusVisible = false
        focusExitTask?.cancel()
        focusExitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled, let self, !self.isFocusVisible else { return }
            self.focusTrack = nil
            self.focusZoomAnimation = false
            self.onFocusOverlayChanged?(false)
        }
    }

    /// Tight sliding-window cache for timed comments (only keeps [previous, current, next, viewing]).
    private var trackCommentsCache: [Int: [SCComment]] = [:]
    private var trackCommentsInFlight: Set<Int> = []
    private var prefetchedArtURLs: Set<URL> = []
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
        self.audio.onTrackStarted = { [weak self] track in
            self?.recordTrackPlayed(track)
        }
    }

    func recordTrackPlayed(_ track: SCTrack) {
        sessionHistory.removeAll { $0.id == track.id }
        sessionHistory.insert(track, at: 0)
        if sessionHistory.count > 100 {
            sessionHistory.removeLast(sessionHistory.count - 100)
        }
        let trackID = track.id
        Task {
            try? await api.recordPlayHistory(trackID: trackID)
        }
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
        if UserDefaults.standard.object(forKey: "cp.showToasts") as? Bool == false {
            return
        }
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

    func clearAllCaches() async {
        await cache.clearAll()
        trackCommentsCache.removeAll()
        ImagePipeline.shared.cache.removeAll()
        URLCache.shared.removeAllCachedResponses()
        showToast("Cleared cached data")
    }

    func cachedComments(for trackID: Int) -> [SCComment]? {
        trackCommentsCache[trackID]
    }

    func loadComments(for track: SCTrack) async -> [SCComment] {
        if let existing = trackCommentsCache[track.id] {
            return existing
        }
        let comments = (try? await api.fetchTrackComments(trackID: track.id, limit: 80))?.collection ?? []
        trackCommentsCache[track.id] = comments
        pruneTrackCache()
        let avatarURLs = comments.prefix(34).compactMap { $0.user?.avatarURL(size: .small) }
        if !avatarURLs.isEmpty {
            imagePrefetcher.startPrefetching(with: avatarURLs)
        }
        return comments
    }

    /// Pre-fetches only above-the-fold data (artwork, waveform, timed comments) for [previous, next]
    /// and flushes any older cached tracks outside the active window to keep memory minimal.
    func prefetchAdjacentTracks() {
        let neighbors = [audio.queue.nextUpPreview, audio.queue.history.last].compactMap { $0 }
        pruneTrackCache()

        let nextArtURLs = Set(neighbors.compactMap { $0.resolvedArtworkURL(size: .large) })
        let staleURLs = Array(prefetchedArtURLs.subtracting(nextArtURLs))
        if !staleURLs.isEmpty {
            imagePrefetcher.stopPrefetching(with: staleURLs)
        }
        let newURLs = Array(nextArtURLs.subtracting(prefetchedArtURLs))
        if !newURLs.isEmpty {
            imagePrefetcher.startPrefetching(with: newURLs)
        }
        prefetchedArtURLs = nextArtURLs

        for track in neighbors {
            if let wfURL = track.waveformURL {
                Task { _ = await WaveformCache.shared.waveform(for: wfURL) }
            }
            if trackCommentsCache[track.id] == nil && !trackCommentsInFlight.contains(track.id) {
                trackCommentsInFlight.insert(track.id)
                Task { [weak self] in
                    guard let self else { return }
                    _ = await self.loadComments(for: track)
                    self.trackCommentsInFlight.remove(track.id)
                }
            }
        }
    }

    private func pruneTrackCache() {
        var keep = Set<Int>()
        if let cur = audio.currentTrack?.id { keep.insert(cur) }
        if let next = audio.queue.nextUpPreview?.id { keep.insert(next) }
        if let prev = audio.queue.history.last?.id { keep.insert(prev) }
        if case .track(let viewing) = router.current { keep.insert(viewing.id) }
        trackCommentsCache = trackCommentsCache.filter { keep.contains($0.key) }
    }

    func signOut() {
        audio.shutdown()
        library.reset()
        router.reset(to: .likes)
        trackCommentsCache.removeAll()
        trackCommentsInFlight.removeAll()
        if !prefetchedArtURLs.isEmpty {
            imagePrefetcher.stopPrefetching(with: Array(prefetchedArtURLs))
            prefetchedArtURLs.removeAll()
        }
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

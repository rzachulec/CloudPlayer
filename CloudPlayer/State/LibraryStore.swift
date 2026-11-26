import Foundation
import Observation
import OSLog

/// Holds optimistic local library state (liked tracks, followed users, etc.) so UI toggles
/// respond in 0ms across every screen and roll back cleanly only if the API call fails.
@MainActor
@Observable
final class LibraryStore {
    private(set) var likedTrackIDs: Set<Int> = []
    private let api: SoundCloudAPI
    private let logger = Logger(subsystem: "local.cloudplayer", category: "LibraryStore")

    init(api: SoundCloudAPI) {
        self.api = api
    }

    func isLiked(_ trackID: Int) -> Bool {
        likedTrackIDs.contains(trackID)
    }

    func registerLikedTracks(_ tracks: [SCTrack]) {
        for t in tracks {
            likedTrackIDs.insert(t.id)
        }
    }

    func toggleLike(trackID: Int, userID: Int?) {
        guard let userID else { return }
        let wasLiked = likedTrackIDs.contains(trackID)
        if wasLiked {
            likedTrackIDs.remove(trackID)
        } else {
            likedTrackIDs.insert(trackID)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                if wasLiked {
                    try await self.api.unlikeTrack(userID: userID, trackID: trackID)
                } else {
                    try await self.api.likeTrack(userID: userID, trackID: trackID)
                }
            } catch {
                self.logger.error("Like toggle failed for track \(trackID): \(error.localizedDescription, privacy: .public)")
                // Roll back optimistic change
                if wasLiked {
                    self.likedTrackIDs.insert(trackID)
                } else {
                    self.likedTrackIDs.remove(trackID)
                }
            }
        }
    }

    func reset() {
        likedTrackIDs.removeAll()
    }
}

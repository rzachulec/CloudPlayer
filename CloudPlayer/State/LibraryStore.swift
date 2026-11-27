import Foundation
import Observation
import OSLog

/// Holds optimistic local library state (liked tracks, followed users) so UI toggles
/// respond in 0ms across every screen and roll back cleanly only if the API call fails.
@MainActor
@Observable
final class LibraryStore {
    private(set) var likedTrackIDs: Set<Int> = []
    private(set) var followedUserIDs: Set<Int> = []
    private let api: SoundCloudAPI
    private let logger = Logger(subsystem: "local.cloudplayer", category: "LibraryStore")

    init(api: SoundCloudAPI) {
        self.api = api
    }

    func isLiked(_ trackID: Int) -> Bool {
        likedTrackIDs.contains(trackID)
    }

    func isFollowing(_ userID: Int) -> Bool {
        followedUserIDs.contains(userID)
    }

    func registerLikedTracks(_ tracks: [SCTrack]) {
        for t in tracks {
            likedTrackIDs.insert(t.id)
        }
    }

    func registerFollowedUsers(_ users: [SCUser]) {
        for u in users {
            followedUserIDs.insert(u.id)
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
                if wasLiked {
                    self.likedTrackIDs.insert(trackID)
                } else {
                    self.likedTrackIDs.remove(trackID)
                }
            }
        }
    }

    func toggleFollow(userID: Int) {
        let wasFollowing = followedUserIDs.contains(userID)
        if wasFollowing {
            followedUserIDs.remove(userID)
        } else {
            followedUserIDs.insert(userID)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                if wasFollowing {
                    try await self.api.unfollowUser(userID: userID)
                } else {
                    try await self.api.followUser(userID: userID)
                }
            } catch {
                self.logger.error("Follow toggle failed for user \(userID): \(error.localizedDescription, privacy: .public)")
                if wasFollowing {
                    self.followedUserIDs.insert(userID)
                } else {
                    self.followedUserIDs.remove(userID)
                }
            }
        }
    }

    func reset() {
        likedTrackIDs.removeAll()
        followedUserIDs.removeAll()
    }
}

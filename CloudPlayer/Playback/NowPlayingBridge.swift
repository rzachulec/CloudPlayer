import AppKit
import Foundation
import MediaPlayer
import Nuke

/// Bridges `AudioEngine` to macOS Control Center, Lock Screen, Touch Bar, and hardware media keys.
@MainActor
final class NowPlayingBridge {
    private var artworkTask: Task<Void, Never>?
    private var currentArtworkTrackID: Int?
    private var currentArtwork: MPMediaItemArtwork?

    func registerCommands(
        onPlay: @escaping @MainActor () -> Void,
        onPause: @escaping @MainActor () -> Void,
        onToggle: @escaping @MainActor () -> Void,
        onNext: @escaping @MainActor () -> Void,
        onPrevious: @escaping @MainActor () -> Void,
        onSeek: @escaping @MainActor (Double) -> Void
    ) {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { _ in
            Task { @MainActor in onPlay() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in onPause() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in onToggle() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in onNext() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in onPrevious() }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let target = posEvent.positionTime
            Task { @MainActor in onSeek(target) }
            return .success
        }
    }

    func update(track: SCTrack?, isPlaying: Bool, position: Double, duration: Double) {
        let center = MPNowPlayingInfoCenter.default()
        guard let track else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            currentArtworkTrackID = nil
            currentArtwork = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistName,
            MPMediaItemPropertyPlaybackDuration: max(duration, track.durationSeconds),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if currentArtworkTrackID == track.id, let art = currentArtwork {
            info[MPMediaItemPropertyArtwork] = art
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused

        if currentArtworkTrackID != track.id {
            currentArtworkTrackID = track.id
            currentArtwork = nil
            fetchArtwork(for: track)
        }
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        currentArtworkTrackID = nil
        currentArtwork = nil
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }

    private func fetchArtwork(for track: SCTrack) {
        artworkTask?.cancel()
        guard let url = track.resolvedArtworkURL(size: .large) else { return }
        let trackID = track.id
        artworkTask = Task { [weak self] in
            guard let image = try? await ImagePipeline.shared.image(for: url) else { return }
            guard !Task.isCancelled, let self, self.currentArtworkTrackID == trackID else { return }
            let size = image.size
            let art = MPMediaItemArtwork(boundsSize: size) { _ in image }
            self.currentArtwork = art
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = art
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}

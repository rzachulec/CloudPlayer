import AppKit
import Combine
import MediaPlayer

/// Media keys, AirPods controls and the Control Center "Now Playing" widget.
@MainActor
final class NowPlaying {
    private let player: WebPlayer
    private var sub: AnyCancellable?
    private var lastKey = ""
    private var anchor: (position: Double, at: Date, rate: Double) = (0, .distantPast, 0)
    private var artwork: (url: URL, art: MPMediaItemArtwork)?
    private var artworkTask: Task<Void, Never>?
    private var pendingArtworkURL: URL?

    init(player: WebPlayer) {
        self.player = player
        let cc = MPRemoteCommandCenter.shared()
        on(cc.togglePlayPauseCommand) { [weak player] _ in player?.playPause(); return true }
        on(cc.playCommand) { [weak player] _ in player?.play(); return true }
        on(cc.pauseCommand) { [weak player] _ in player?.pause(); return true }
        on(cc.nextTrackCommand) { [weak player] _ in player?.next(); return true }
        on(cc.previousTrackCommand) { [weak player] _ in player?.previous(); return true }
        on(cc.changePlaybackPositionCommand) { [weak player] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return false }
            player?.seek(seconds: e.positionTime)
            return true
        }
        sub = player.$state.sink { [weak self] in self?.update($0) }
    }

    private func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor (MPRemoteCommandEvent) -> Bool) {
        command.isEnabled = true
        command.addTarget { event in
            MainActor.assumeIsolated { action(event) } ? .success : .commandFailed
        }
    }

    private func update(_ s: TrackState) {
        let center = MPNowPlayingInfoCenter.default()
        guard s.hasTrack else {
            if !lastKey.isEmpty {
                center.nowPlayingInfo = nil
                center.playbackState = .stopped
                lastKey = ""
            }
            return
        }

        // Only push when something meaningful changed or the position jumped (seek);
        // the system extrapolates elapsed time from the playback rate.
        let key = "\(s.title)|\(s.artist)|\(s.isPlaying)|\(Int(s.duration))|\(s.artworkURL?.absoluteString ?? "")|\(artwork?.url.absoluteString ?? "")"
        let expected = anchor.position + Date().timeIntervalSince(anchor.at) * anchor.rate
        guard key != lastKey || abs(expected - s.position) > 2 else { return }
        lastKey = key
        anchor = (s.position, Date(), s.isPlaying ? 1 : 0)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: s.title,
            MPMediaItemPropertyArtist: s.artist,
            MPMediaItemPropertyPlaybackDuration: s.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: s.position,
            MPNowPlayingInfoPropertyPlaybackRate: s.isPlaying ? 1.0 : 0.0,
        ]
        if let a = artwork, a.url == s.artworkURL {
            info[MPMediaItemPropertyArtwork] = a.art
        } else {
            loadArtwork(s.artworkURL)
        }
        center.nowPlayingInfo = info
        center.playbackState = s.isPlaying ? .playing : .paused
    }

    private func loadArtwork(_ url: URL?) {
        guard let url, url != pendingArtworkURL else { return }
        pendingArtworkURL = url
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data), !Task.isCancelled, let self else { return }
            self.artwork = (url, MPMediaItemArtwork(boundsSize: image.size) { _ in image })
            self.update(self.player.state)
        }
    }
}

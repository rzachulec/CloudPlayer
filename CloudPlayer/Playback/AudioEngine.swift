import AVFoundation
import Foundation
import Observation
import OSLog

enum TrackTransitionDirection: Equatable, Sendable {
    case next
    case previous
}

/// Native macOS audio playback engine backed by `AVPlayer` + `PlaybackQueue` + `NowPlayingBridge`.
@MainActor
@Observable
final class AudioEngine {
    private(set) var queue = PlaybackQueue()
    private(set) var currentTrack: SCTrack?
    private(set) var lastTransitionDirection: TrackTransitionDirection = .next
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var errorMessage: String?
    var queueVisible = false
    var volume: Double {
        didSet {
            let clamped = min(max(volume, 0), 1)
            if clamped != volume { volume = clamped; return }
            player.volume = Float(clamped)
            UserDefaults.standard.set(clamped, forKey: "volume")
        }
    }

    var hasTrack: Bool { currentTrack != nil }

    private let api: SoundCloudAPI
    private let resolver: StreamResolver
    private let nowPlaying = NowPlayingBridge()
    private let player = AVPlayer()
    private let logger = Logger(subsystem: "local.cloudplayer", category: "AudioEngine")

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var loadTask: Task<Void, Never>?
    private var relatedTask: Task<Void, Never>?
    private var preloadedTrackID: Int?
    private var isScrubbing = false

    init(api: SoundCloudAPI) {
        self.api = api
        self.resolver = StreamResolver(api: api)
        let savedVol = UserDefaults.standard.object(forKey: "volume") as? Double ?? 1.0
        self.volume = min(max(savedVol, 0), 1)
        if let savedAutoplay = UserDefaults.standard.object(forKey: "cp.autoplayEnabled") as? Bool {
            self.queue.autoplayEnabled = savedAutoplay
        }
        self.player.volume = Float(self.volume)
        self.player.automaticallyWaitsToMinimizeStalling = true

        setupObservers()
        nowPlaying.registerCommands(
            onPlay: { [weak self] in self?.play() },
            onPause: { [weak self] in self?.pause() },
            onToggle: { [weak self] in self?.togglePlayPause() },
            onNext: { [weak self] in self?.next() },
            onPrevious: { [weak self] in self?.previous() },
            onSeek: { [weak self] seconds in self?.seek(seconds: seconds) }
        )
    }

    private func setupObservers() {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                let secs = time.seconds
                if secs.isFinite, secs >= 0 {
                    self.position = secs
                }
                if let itemDur = self.player.currentItem?.duration.seconds, itemDur.isFinite, itemDur > 0 {
                    self.duration = itemDur
                }
                self.maybePreloadNext()
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch p.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering = true
                case .paused:
                    self.isPlaying = false
                    self.isBuffering = false
                @unknown default:
                    break
                }
                self.syncNowPlaying()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.next(manual: false)
            }
        }
    }

    // MARK: - Playback Commands

    func play(track: SCTrack, inContext context: [SCTrack] = [], contextTitle: String? = nil) {
        if currentTrack?.id == track.id, player.currentItem != nil {
            togglePlayPause()
            return
        }
        queue.play(track: track, inContext: context, contextTitle: contextTitle)
        startTrack(track)
    }

    func playShuffled(tracks: [SCTrack], contextTitle: String? = nil) {
        queue.playShuffled(tracks: tracks, contextTitle: contextTitle)
        if let track = queue.current {
            startTrack(track)
        }
    }

    func togglePlayPause() {
        guard currentTrack != nil else { return }
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard currentTrack != nil else { return }
        isPlaying = true
        player.play()
        syncNowPlaying()
    }

    func pause() {
        isPlaying = false
        player.pause()
        syncNowPlaying()
    }

    func next(manual: Bool = true) {
        if let nextTrack = queue.advance(manual: manual) {
            if nextTrack.id == currentTrack?.id && !manual {
                seek(seconds: 0)
                play()
            } else {
                lastTransitionDirection = .next
                startTrack(nextTrack)
            }
        } else {
            pause()
            seek(seconds: 0)
        }
    }

    func previous() {
        switch queue.previous(currentPosition: position) {
        case .none:
            break
        case .restartCurrent:
            seek(seconds: 0)
        case .switchTo(let prev):
            lastTransitionDirection = .previous
            startTrack(prev)
        }
    }

    func seek(fraction: Double) {
        guard duration > 0 else { return }
        seek(seconds: min(max(fraction, 0), 1) * duration)
    }

    func seek(seconds: Double) {
        guard duration > 0 else { return }
        let clamped = min(max(seconds, 0), duration)
        isScrubbing = true
        position = clamped
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.isScrubbing = false
                self?.syncNowPlaying()
            }
        }
    }

    func toggleShuffle() {
        queue.toggleShuffle()
    }

    func cycleRepeat() {
        queue.cycleRepeat()
    }

    func enqueueNext(_ track: SCTrack) {
        queue.enqueueNext(track)
    }

    func enqueueLater(_ track: SCTrack) {
        queue.enqueueLater(track)
    }

    func moveUserUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.moveUserUpNext(fromOffsets: source, toOffset: destination)
    }

    func removeUserUpNext(at offsets: IndexSet) {
        queue.removeUserUpNext(at: offsets)
    }

    func removeFromContext(at offsets: IndexSet) {
        queue.removeFromContext(at: offsets)
    }

    func clearUpcoming() {
        queue.clearUpcoming()
    }

    func setAutoplayEnabled(_ enabled: Bool) {
        queue.autoplayEnabled = enabled
    }

    func shutdown() {
        loadTask?.cancel()
        relatedTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        nowPlaying.clear()
    }

    // MARK: - Internal Stream Loading & Preloading

    private func startTrack(_ track: SCTrack) {
        loadTask?.cancel()
        errorMessage = nil
        preloadedTrackID = nil

        // Optimistic immediate UI update for instant perceived response
        currentTrack = track
        position = 0
        duration = track.durationSeconds
        isPlaying = true
        isBuffering = true
        syncNowPlaying()

        let trackID = track.id
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await self.resolver.resolveStreamURL(for: track)
                guard !Task.isCancelled, self.currentTrack?.id == trackID else { return }

                let item = AVPlayerItem(url: url)
                self.statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
                    MainActor.assumeIsolated {
                        guard let self, observed === self.player.currentItem else { return }
                        if observed.status == .failed {
                            let msg = observed.error?.localizedDescription ?? "Playback failed."
                            self.logger.error("AVPlayerItem failed for track \(trackID): \(msg, privacy: .public)")
                            self.errorMessage = msg
                            self.isBuffering = false
                            self.isPlaying = false
                        }
                    }
                }
                self.player.replaceCurrentItem(with: item)
                self.player.volume = Float(self.volume)
                self.player.play()
                self.syncNowPlaying()
                self.ensureAutoplayPopulatedIfNeeded(for: track)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.currentTrack?.id == trackID else { return }
                self.logger.error("Stream resolve failed for track \(trackID): \(error.localizedDescription, privacy: .public)")
                self.errorMessage = error.localizedDescription
                self.isBuffering = false
                self.isPlaying = false
                self.syncNowPlaying()
            }
        }
    }

    private func maybePreloadNext() {
        guard duration > 20, (duration - position) < 15,
              let next = queue.nextUpPreview,
              preloadedTrackID != next.id else { return }
        preloadedTrackID = next.id
        Task {
            await resolver.preResolve(track: next)
        }
    }

    private func ensureAutoplayPopulatedIfNeeded(for track: SCTrack) {
        guard queue.autoplayEnabled,
              queue.userUpNext.isEmpty,
              queue.contextQueue.isEmpty,
              queue.autoplayQueue.isEmpty else { return }
        relatedTask?.cancel()
        relatedTask = Task { [weak self] in
            guard let self else { return }
            if let related = try? await self.api.fetchRelatedTracks(trackID: track.id, limit: 15),
               !Task.isCancelled {
                self.queue.setAutoplayTracks(related)
            }
        }
    }

    private func syncNowPlaying() {
        nowPlaying.update(track: currentTrack, isPlaying: isPlaying, position: position, duration: duration)
    }
}

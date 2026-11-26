import NukeUI
import SwiftUI

/// Nuke-backed cached artwork thumbnail with zero flicker on scroll/recycling.
struct CachedArtwork: View {
    let url: URL?
    let size: CGFloat
    var cornerRadius: CGFloat = 5

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: max(10, size * 0.34)))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}

/// Apple Music–style floating Liquid Glass capsule player backed by native `AudioEngine`.
struct NativePlayerBar: View {
    @Bindable var app: AppController
    var onMini: () -> Void

    static let height: CGFloat = 46

    var body: some View {
        let audio = app.audio
        let track = audio.currentTrack
        HStack(spacing: 14) {
            transport(audio)
            nowPlaying(audio: audio, track: track)
                .frame(minWidth: 220, maxWidth: .infinity)
            trailing(audio: audio, track: track)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: Self.height)
        .frame(maxWidth: 760)
        .modifier(NativeCapsuleGlass())
    }

    private func transport(_ audio: AudioEngine) -> some View {
        HStack(spacing: 14) {
            IconButton(
                symbol: "shuffle",
                size: 11,
                active: audio.queue.shuffle,
                help: "Shuffle"
            ) { audio.toggleShuffle() }
                .opacity(audio.queue.shuffle ? 1 : 0.5)

            IconButton(symbol: "backward.fill", size: 14, help: "Previous") { audio.previous() }

            ZStack {
                IconButton(
                    symbol: audio.isPlaying ? "pause.fill" : "play.fill",
                    size: 18,
                    help: audio.isPlaying ? "Pause" : "Play"
                ) { audio.togglePlayPause() }
                    .opacity(audio.isBuffering ? 0.35 : 1)
                if audio.isBuffering {
                    ProgressView().controlSize(.mini)
                }
            }

            IconButton(symbol: "forward.fill", size: 14, help: "Next") { audio.next() }

            IconButton(
                symbol: audio.queue.repeatMode == .one ? "repeat.1" : "repeat",
                size: 11,
                active: audio.queue.repeatMode != .none,
                help: "Repeat: \(audio.queue.repeatMode.rawValue)"
            ) { audio.cycleRepeat() }
                .opacity(audio.queue.repeatMode != .none ? 1 : 0.5)
        }
        .disabled(!audio.hasTrack)
        .fixedSize()
    }

    private func nowPlaying(audio: AudioEngine, track: SCTrack?) -> some View {
        HStack(spacing: 9) {
            CachedArtwork(url: track?.resolvedArtworkURL(size: .small), size: 32, cornerRadius: 4)
            VStack(alignment: .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(track?.title ?? "Not Playing")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(track?.artistName ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                NativeThinScrubber(audio: audio)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }

    private func trailing(audio: AudioEngine, track: SCTrack?) -> some View {
        let liked = track.map { app.library.isLiked($0.id) } ?? false
        return HStack(spacing: 12) {
            IconButton(
                symbol: liked ? "heart.fill" : "heart",
                size: 13,
                active: liked,
                help: liked ? "Unlike" : "Like"
            ) { app.toggleLikeCurrentTrack() }
                .disabled(!audio.hasTrack)

            IconButton(
                symbol: "list.bullet",
                size: 13,
                active: audio.queueVisible,
                help: "Up Next"
            ) { audio.queueVisible.toggle() }
                .disabled(!audio.hasTrack)

            IconButton(symbol: "pip.enter", size: 13, help: "Mini Player (⇧⌘M)", action: onMini)

            NativeVolumeButton(audio: audio)
        }
        .fixedSize()
    }
}

private struct NativeThinScrubber: View {
    @Bindable var audio: AudioEngine
    @State private var scrub: Double?
    @State private var hovering = false

    var body: some View {
        let enabled = audio.hasTrack && audio.duration > 0
        let fraction = min(max(scrub ?? (audio.duration > 0 ? audio.position / audio.duration : 0), 0), 1)
        let active = enabled && (hovering || scrub != nil)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.15))
                Capsule().fill(.primary.opacity(active ? 0.8 : 0.55))
                    .frame(width: geo.size.width * fraction)
            }
            .frame(height: active ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard enabled else { return }
                        scrub = min(max(v.location.x / geo.size.width, 0), 1)
                    }
                    .onEnded { v in
                        guard enabled else { return }
                        let f = min(max(v.location.x / geo.size.width, 0), 1)
                        audio.seek(fraction: f)
                        scrub = nil
                    }
            )
            .animation(.easeOut(duration: 0.12), value: active)
        }
        .frame(height: 8)
        .help(enabled ? "\(formatTime(fraction * audio.duration)) / \(formatTime(audio.duration))" : "")
    }
}

private struct NativeVolumeButton: View {
    @Bindable var audio: AudioEngine
    @State private var open = false

    var body: some View {
        IconButton(symbol: symbol, size: 13, help: "Volume") { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .top) {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                    Slider(value: $audio.volume, in: 0...1)
                        .controlSize(.small)
                        .frame(width: 140)
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(12)
            }
    }

    private var symbol: String {
        switch audio.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

private struct NativeCapsuleGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        }
    }
}

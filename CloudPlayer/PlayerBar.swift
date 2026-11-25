import SwiftUI

/// Apple Music–style floating capsule player, hovering over the bottom of the page.
/// [shuffle ◀◀ ▶ ▶▶ repeat] [artwork · title / artist · thin scrubber] [♥ queue mini volume]
struct PlayerBar: View {
    @ObservedObject var player: WebPlayer
    var onMini: () -> Void

    static let height: CGFloat = 46

    var body: some View {
        let s = player.state
        HStack(spacing: 14) {
            transport(s)
            nowPlaying(s)
                .frame(minWidth: 220, maxWidth: .infinity)
            trailing(s)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: Self.height)
        .frame(maxWidth: 760)
        .modifier(CapsuleGlass())
    }

    // MARK: Sections

    private func transport(_ s: TrackState) -> some View {
        HStack(spacing: 14) {
            IconButton(symbol: "shuffle", size: 11, active: s.shuffle, help: "Shuffle") { player.toggleShuffle() }
                .opacity(s.shuffle ? 1 : 0.5)
            IconButton(symbol: "backward.fill", size: 14, help: "Previous") { player.previous() }
            IconButton(symbol: s.isPlaying ? "pause.fill" : "play.fill", size: 18,
                       help: s.isPlaying ? "Pause" : "Play") { player.playPause() }
            IconButton(symbol: "forward.fill", size: 14, help: "Next") { player.next() }
            IconButton(symbol: s.repeatMode == .one ? "repeat.1" : "repeat", size: 11, active: s.repeatMode != .none,
                       help: "Repeat: \(s.repeatMode.rawValue)") { player.cycleRepeat() }
                .opacity(s.repeatMode != .none ? 1 : 0.5)
        }
        .disabled(!s.hasTrack)
        .fixedSize()
    }

    private func nowPlaying(_ s: TrackState) -> some View {
        HStack(spacing: 9) {
            Button { player.open(s.trackPath) } label: {
                Artwork(url: s.artworkURL, size: 32, cornerRadius: 4)
            }
            .buttonStyle(.plain)
            .disabled(s.trackPath.isEmpty)
            .help("Go to Track")
            VStack(alignment: .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 0) {
                    Button { player.open(s.trackPath) } label: {
                        Text(s.hasTrack ? s.title : "Not Playing")
                            .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(s.trackPath.isEmpty)
                    Button { player.open(s.artistPath) } label: {
                        Text(s.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(s.artistPath.isEmpty)
                }
                ThinScrubber(player: player)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu { if s.hasTrack { NowPlayingMenu(player: player) } }
    }

    private func trailing(_ s: TrackState) -> some View {
        HStack(spacing: 12) {
            IconButton(symbol: s.isLiked ? "heart.fill" : "heart", size: 13, active: s.isLiked,
                       help: s.isLiked ? "Unlike" : "Like") { player.toggleLike() }
                .disabled(!s.hasTrack)
            IconButton(symbol: "list.bullet", size: 13, active: s.queueVisible, help: "Up Next") { player.toggleQueue() }
                .disabled(!s.hasTrack)
            IconButton(symbol: "pip.enter", size: 13, help: "Mini Player (⇧⌘M)", action: onMini)
            VolumeButton(player: player)
        }
        .fixedSize()
    }
}

/// Thin progress line under the title (Apple Music style); thickens on hover, drag to seek.
private struct ThinScrubber: View {
    @ObservedObject var player: WebPlayer
    @State private var scrub: Double?
    @State private var hovering = false

    var body: some View {
        let s = player.state
        let enabled = s.hasTrack && s.duration > 0
        let fraction = min(max(scrub ?? (s.duration > 0 ? s.position / s.duration : 0), 0), 1)
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
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in if enabled { scrub = min(max(v.location.x / geo.size.width, 0), 1) } }
                .onEnded { v in
                    guard enabled else { return }
                    player.seek(fraction: min(max(v.location.x / geo.size.width, 0), 1))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { scrub = nil }
                })
            .animation(.easeOut(duration: 0.12), value: active)
        }
        .frame(height: 8)
        .help(enabled ? "\(formatTime(fraction * s.duration)) / \(formatTime(s.duration))" : "")
    }
}

/// Speaker button with a volume slider in a popover (as in Apple Music).
private struct VolumeButton: View {
    @ObservedObject var player: WebPlayer
    @State private var open = false

    var body: some View {
        IconButton(symbol: symbol, size: 13, help: "Volume") { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .top) {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0...1)
                        .controlSize(.small)
                        .frame(width: 140)
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(12)
            }
    }

    private var symbol: String {
        switch player.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

/// Liquid Glass capsule on macOS 26+, frosted material before that.
private struct CapsuleGlass: ViewModifier {
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

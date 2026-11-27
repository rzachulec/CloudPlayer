import AppKit
import SwiftUI

enum TrackListDisplayMode: String, CaseIterable, Identifiable {
    case tiles
    case compact
    case waveform

    var id: Self { self }

    var symbol: String {
        switch self {
        case .tiles: "square.grid.2x2"
        case .compact: "list.bullet"
        case .waveform: "waveform"
        }
    }

    var label: String {
        switch self {
        case .tiles: "Tiles"
        case .compact: "Compact List"
        case .waveform: "Waveform"
        }
    }
}

/// Reusable native track row supporting Compact and Waveform modes, hover play button,
/// optimistic like toggle, and full native context menu.
struct NativeTrackRow: View {
    let track: SCTrack
    @Bindable var app: AppController
    var mode: TrackListDisplayMode = .compact
    var onPlay: () -> Void
    var onArtistTap: ((SCUser) -> Void)?

    @State private var isHovered = false

    private var isCurrent: Bool { app.audio.currentTrack?.id == track.id }
    private var isPlayingThis: Bool { isCurrent && app.audio.isPlaying }
    private var isLiked: Bool { app.library.isLiked(track.id) }

    var body: some View {
        HStack(alignment: mode == .waveform ? .top : .center, spacing: 12) {
            artworkControl
            VStack(alignment: .leading, spacing: mode == .waveform ? 5 : 2) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    if track.isPreviewOnly {
                        Text("Go+")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.16), in: Capsule())
                    }
                    Spacer(minLength: 8)
                    if mode == .waveform {
                        trailingMeta
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        if let user = track.user { onArtistTap?(user) }
                    } label: {
                        Text(track.artistName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    if let genre = track.genre, !genre.isEmpty, mode == .waveform {
                        Text("#\(genre)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary.opacity(0.7), in: Capsule())
                            .lineLimit(1)
                    }
                }

                if mode == .waveform {
                    let progress = isCurrent && app.audio.duration > 0 ? app.audio.position / app.audio.duration : 0
                    WaveformView(
                        url: track.waveformURL,
                        progress: progress,
                        isActive: isCurrent,
                        height: 30
                    ) { fraction in
                        if isCurrent {
                            app.audio.seek(fraction: fraction)
                        } else {
                            onPlay()
                        }
                    }
                    .padding(.top, 2)
                }
            }
            if mode != .waveform {
                Spacer(minLength: 8)
                trailingMeta
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, mode == .waveform ? 9 : 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.10) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onPlay)
        .contextMenu {
            TrackContextMenu(track: track, app: app, onPlay: onPlay)
        }
    }

    private var artworkControl: some View {
        let side: CGFloat = mode == .waveform ? 64 : 44
        return ZStack {
            CachedArtwork(url: track.resolvedArtworkURL(size: mode == .waveform ? .medium : .small), size: side, cornerRadius: 6)
            if isHovered || isCurrent {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.black.opacity(isHovered ? 0.42 : 0.34))
                    .frame(width: side, height: side)
                Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                    .font(.system(size: mode == .waveform ? 20 : 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: isPlayingThis ? 0 : 1)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var trailingMeta: some View {
        HStack(spacing: 10) {
            if let plays = track.playbackCount, plays > 0, mode == .waveform {
                Label(formatCompactCount(plays), systemImage: "play.fill")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(formatTime(track.durationSeconds))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            IconButton(
                symbol: isLiked ? "heart.fill" : "heart",
                size: 12,
                active: isLiked,
                help: isLiked ? "Unlike" : "Like"
            ) {
                app.toggleLike(track)
            }
            .opacity(isLiked || isHovered ? 1 : 0.45)
        }
        .fixedSize()
    }
}

/// Adaptive square tile card with native macOS 26 Liquid Glass hover play button.
struct NativeMediaTile: View {
    let track: SCTrack
    @Bindable var app: AppController
    var onPlay: () -> Void

    @State private var isHovered = false

    private var isCurrent: Bool { app.audio.currentTrack?.id == track.id }
    private var isPlayingThis: Bool { isCurrent && app.audio.isPlaying }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                let side = geo.size.width
                ZStack {
                    CachedArtwork(url: track.resolvedArtworkURL(size: .large), size: side, cornerRadius: 10)

                    if isHovered || isCurrent {
                        Button(action: onPlay) {
                            Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: isPlayingThis ? 0 : 2)
                                .frame(width: 62, height: 62)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .modifier(TilePlayGlass())
                        .scaleEffect(isHovered ? 1.06 : 0.96)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(duration: 0.22, bounce: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            app.router.navigate(to: .track(track))
        }
        .contextMenu {
            TrackContextMenu(track: track, app: app, onPlay: onPlay)
        }
    }
}

struct TrackContextMenu: View {
    let track: SCTrack
    @Bindable var app: AppController
    var onPlay: () -> Void

    var body: some View {
        let liked = app.library.isLiked(track.id)
        Button("Play", systemImage: "play.fill", action: onPlay)
        Button("Play Next", systemImage: "text.insert") {
            app.audio.enqueueNext(track)
            app.showToast("Playing next: \(track.title)", artworkURL: track.resolvedArtworkURL(size: .small))
        }
        Button("Add to Up Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            app.audio.enqueueLater(track)
            app.showToast("Added to Up Next", artworkURL: track.resolvedArtworkURL(size: .small))
        }
        Divider()
        Button("Go to Track", systemImage: "waveform") {
            app.router.navigate(to: .track(track))
        }
        if let user = track.user {
            Button("Go to Artist", systemImage: "person.crop.circle") {
                app.router.navigate(to: .user(user))
            }
        }
        Button(liked ? "Unlike" : "Like", systemImage: liked ? "heart.slash" : "heart") {
            app.toggleLike(track)
        }
        if let url = track.permalinkURL {
            Divider()
            ContextShareSubmenu(url: url) {
                app.showToast("Copied link")
            }
            Button("Open on SoundCloud", systemImage: "safari") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

private struct TilePlayGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        }
    }
}

func formatCompactCount(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}

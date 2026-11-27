import AppKit
import NukeUI
import SwiftUI

/// Native Track Detail screen with blurred artwork hero backdrop, large interactive Canvas waveform,
/// timed comments (click timestamp to seek), and related tracks.
struct TrackDetailView: View {
    let track: SCTrack
    @Bindable var app: AppController

    @State private var comments: [SCComment] = []
    @State private var related: [SCTrack] = []
    @State private var isLoadingDetails = false

    private var isCurrent: Bool { app.audio.currentTrack?.id == track.id }
    private var isPlayingThis: Bool { isCurrent && app.audio.isPlaying }
    private var isLiked: Bool { app.library.isLiked(track.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroCard
                if let desc = track.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("About")
                            .font(.system(size: 14, weight: .semibold))
                        Text(desc)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if !related.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Related Tracks")
                            .font(.system(size: 16, weight: .bold))
                        LazyVStack(spacing: 2) {
                            ForEach(related) { rel in
                                NativeTrackRow(
                                    track: rel,
                                    app: app,
                                    mode: .compact,
                                    onPlay: {
                                        app.audio.play(track: rel, inContext: related, contextTitle: "Related to \(track.title)")
                                    },
                                    onArtistTap: { user in
                                        app.router.navigate(to: .user(user))
                                    }
                                )
                            }
                        }
                    }
                }

                if !comments.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Comments (\(track.commentCount ?? comments.count))")
                            .font(.system(size: 16, weight: .bold))
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(comments) { comment in
                                commentRow(comment)
                            }
                        }
                    }
                } else if isLoadingDetails {
                    LazyVStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { _ in TrackRowSkeleton() }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 96)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: track.id) {
            await loadDetails()
        }
    }

    private var heroCard: some View {
        ZStack {
            // Blurred artwork backdrop
            LazyImage(url: track.resolvedArtworkURL(size: .large)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.accentColor.opacity(0.25)
                }
            }
            .blur(radius: 44)
            .scaleEffect(1.2)
            .overlay(Color.black.opacity(0.42))

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 20) {
                    CachedArtwork(url: track.resolvedArtworkURL(size: .large), size: 164, cornerRadius: 12)
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            if let genre = track.genre, !genre.isEmpty {
                                Text("#\(genre)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(.white.opacity(0.16), in: Capsule())
                            }
                            if track.isPreviewOnly {
                                Text("Go+ Preview")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(.orange.opacity(0.45), in: Capsule())
                            }
                        }

                        Text(track.title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Button {
                            if let user = track.user {
                                app.router.navigate(to: .user(user))
                            }
                        } label: {
                            Text(track.artistName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 14) {
                            if let plays = track.playbackCount {
                                Label(formatCompactCount(plays), systemImage: "play.fill")
                            }
                            if let likes = track.likesCount {
                                Label(formatCompactCount(likes), systemImage: "heart.fill")
                            }
                            if let reposts = track.repostsCount {
                                Label(formatCompactCount(reposts), systemImage: "arrow.2.squarepath")
                            }
                            Label(formatTime(track.durationSeconds), systemImage: "clock")
                        }
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))

                        HStack(spacing: 10) {
                            Button {
                                app.audio.play(track: track, inContext: [track] + related, contextTitle: track.title)
                            } label: {
                                Label(isPlayingThis ? "Pause" : "Play", systemImage: isPlayingThis ? "pause.fill" : "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                app.toggleLike(track)
                            } label: {
                                Label(isLiked ? "Liked" : "Like", systemImage: isLiked ? "heart.fill" : "heart")
                            }
                            .buttonStyle(.bordered)
                            .tint(isLiked ? .accentColor : .white)

                            Button {
                                app.audio.enqueueLater(track)
                                app.showToast("Added to Up Next", artworkURL: track.resolvedArtworkURL(size: .small))
                            } label: {
                                Label("Up Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)

                            if let url = track.permalinkURL {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                    app.showToast("Copied link")
                                } label: {
                                    Image(systemName: "link")
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)
                                .help("Copy Link")
                            }
                        }
                        .padding(.top, 4)
                    }
                    Spacer()
                }

                // Large interactive waveform scrubber
                let progress = isCurrent && app.audio.duration > 0 ? app.audio.position / app.audio.duration : 0
                WaveformView(
                    url: track.waveformURL,
                    progress: progress,
                    isActive: isCurrent,
                    height: 62
                ) { fraction in
                    if isCurrent {
                        app.audio.seek(fraction: fraction)
                    } else {
                        app.audio.play(track: track, inContext: [track] + related, contextTitle: track.title)
                    }
                }
                .environment(\.colorScheme, .dark)
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func commentRow(_ comment: SCComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            LazyImage(url: comment.user?.avatarURL(size: .small)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Circle().fill(.quaternary)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.user?.displayName ?? "Listener")
                        .font(.system(size: 12, weight: .semibold))
                    if let secs = comment.timestampSeconds {
                        Button("at \(formatTime(secs))") {
                            if !isCurrent {
                                app.audio.play(track: track, inContext: [track] + related, contextTitle: track.title)
                            }
                            app.audio.seek(seconds: secs)
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11).monospacedDigit())
                    }
                }
                Text(comment.body)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary.opacity(0.9))
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func loadDetails() async {
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        async let relatedTask = app.api.fetchRelatedTracks(trackID: track.id, limit: 15)
        async let commentsTask = app.api.fetchTrackComments(trackID: track.id, limit: 40)

        if let r = try? await relatedTask {
            related = r
        }
        if let c = try? await commentsTask {
            comments = c.collection
        }
    }
}

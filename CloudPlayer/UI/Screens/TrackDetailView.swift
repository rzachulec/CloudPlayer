import AppKit
import NukeUI
import SwiftUI

private enum TrackDetailPane: String, CaseIterable, Identifiable {
    case comments = "Comments"
    case related = "Related Tracks"
    var id: Self { self }
}

private enum CommentSort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case trackTime = "Track Time"
    var id: Self { self }
}

/// Native Track Detail screen with compact blurred artwork hero, large interactive Canvas waveform,
/// and an adaptive two-column layout keeping Comments and Related Tracks both immediately accessible.
struct TrackDetailView: View {
    let track: SCTrack
    @Bindable var app: AppController

    @State private var comments: [SCComment] = []
    @State private var related: [SCTrack] = []
    @State private var isLoadingDetails = false
    @State private var narrowPane: TrackDetailPane = .comments
    @State private var commentSort: CommentSort = .newest
    @State private var descriptionExpanded = false

    private var isCurrent: Bool { app.audio.currentTrack?.id == track.id }
    private var isPlayingThis: Bool { isCurrent && app.audio.isPlaying }
    private var isLiked: Bool { app.library.isLiked(track.id) }

    private var sortedComments: [SCComment] {
        switch commentSort {
        case .newest:
            comments
        case .trackTime:
            comments.sorted { ($0.timestamp ?? Int.max) < ($1.timestamp ?? Int.max) }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width >= 780
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroCard

                    if isWide {
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 18) {
                                aboutSection
                                commentsSection
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            relatedSection
                                .frame(width: min(max(geo.size.width * 0.38, 300), 420), alignment: .leading)
                        }
                    } else {
                        aboutSection
                        Picker("Section", selection: $narrowPane) {
                            ForEach(TrackDetailPane.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 280)

                        switch narrowPane {
                        case .comments: commentsSection
                        case .related: relatedSection
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 96)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: track.id) {
            await loadDetails()
        }
    }

    // MARK: - Compact Blurred Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                CachedArtwork(url: track.resolvedArtworkURL(size: .large), size: 136, cornerRadius: 11)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 5)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let genre = track.genre, !genre.isEmpty {
                            Text("#\(genre)")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(.white.opacity(0.16), in: Capsule())
                        }
                        if track.isPreviewOnly {
                            Text("Go+ Preview")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(.orange.opacity(0.45), in: Capsule())
                        }
                    }

                    Text(track.title)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Button {
                        if let user = track.user {
                            app.router.navigate(to: .user(user))
                        }
                    } label: {
                        Text(track.artistName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.84))
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

                    HStack(spacing: 8) {
                        Button {
                            app.audio.play(track: track, inContext: [track] + related, contextTitle: track.title)
                        } label: {
                            Label(isPlayingThis ? "Pause" : "Play", systemImage: isPlayingThis ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)

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
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            let progress = isCurrent && app.audio.duration > 0 ? app.audio.position / app.audio.duration : 0
            WaveformView(
                url: track.waveformURL,
                progress: progress,
                isActive: isCurrent,
                height: 54
            ) { fraction in
                if isCurrent {
                    app.audio.seek(fraction: fraction)
                } else {
                    app.audio.play(track: track, inContext: [track] + related, contextTitle: track.title)
                }
            }
            .environment(\.colorScheme, .dark)
        }
        .padding(20)
        .background {
            LazyImage(url: track.resolvedArtworkURL(size: .large)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.accentColor.opacity(0.28)
                }
            }
            .blur(radius: 42)
            .scaleEffect(1.25)
            .overlay(
                LinearGradient(
                    colors: [.black.opacity(0.35), .black.opacity(0.58)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: - Sections

    @ViewBuilder
    private var aboutSection: some View {
        if let desc = track.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("About")
                    .font(.system(size: 14, weight: .semibold))
                Text(desc)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(descriptionExpanded ? nil : 3)
                    .textSelection(.enabled)
                if desc.count > 160 {
                    Button(descriptionExpanded ? "Show less" : "Show more") {
                        withAnimation(.easeOut(duration: 0.16)) { descriptionExpanded.toggle() }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                }
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Comments")
                    .font(.system(size: 16, weight: .bold))
                if let count = track.commentCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.7), in: Capsule())
                }
                Spacer()
                if comments.count > 1 {
                    Picker("Sort", selection: $commentSort) {
                        ForEach(CommentSort.allCases) { s in Text(s.rawValue).tag(s) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 156)
                }
            }

            if isLoadingDetails && comments.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in TrackRowSkeleton() }
                }
            } else if comments.isEmpty {
                Text("No comments yet.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(sortedComments) { comment in
                        commentRow(comment)
                    }
                }
            }
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Related Tracks")
                .font(.system(size: 16, weight: .bold))
            if isLoadingDetails && related.isEmpty {
                LazyVStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { _ in TrackRowSkeleton() }
                }
            } else if related.isEmpty {
                Text("No related tracks found.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
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
    }

    private func commentRow(_ comment: SCComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                if let u = comment.user { app.router.navigate(to: .user(u)) }
            } label: {
                LazyImage(url: comment.user?.avatarURL(size: .small)) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Circle().fill(.quaternary)
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Button {
                        if let u = comment.user { app.router.navigate(to: .user(u)) }
                    } label: {
                        Text(comment.user?.displayName ?? "Listener")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)

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
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func loadDetails() async {
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        async let relatedTask = app.api.fetchRelatedTracks(trackID: track.id, limit: 15)
        async let commentsTask = app.api.fetchTrackComments(trackID: track.id, limit: 50)

        if let r = try? await relatedTask {
            related = r
        }
        if let c = try? await commentsTask {
            comments = c.collection
        }
    }
}

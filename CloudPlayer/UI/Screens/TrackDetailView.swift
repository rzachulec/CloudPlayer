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

/// Native Track Detail screen:
/// - Full-viewport blurred artwork hero with large interactive Canvas waveform and timed waveform comments
/// - Smoothly scrolls down into About, Comments (with Newest / Track Time sort), and Related Tracks.
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
            let heroHeight = max(geo.size.height - 86, 440)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    heroCard(minHeight: heroHeight)

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

    // MARK: - Full-Viewport Blurred Hero + Waveform Comments

    private func heroCard(minHeight: CGFloat) -> some View {
        let progress = isCurrent && app.audio.duration > 0 ? app.audio.position / app.audio.duration : 0
        let duration = isCurrent && app.audio.duration > 0 ? app.audio.duration : track.durationSeconds

        return VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 8)

            HStack(alignment: .center, spacing: 24) {
                CachedArtwork(url: track.resolvedArtworkURL(size: .large), size: 196, cornerRadius: 14)
                    .shadow(color: .black.opacity(0.40), radius: 20, y: 8)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        if let genre = track.genre, !genre.isEmpty {
                            Text("#\(genre)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.16), in: Capsule())
                        }
                        if track.isPreviewOnly {
                            Text("Go+ Preview")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(.orange.opacity(0.45), in: Capsule())
                        }
                    }

                    Text(track.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Button {
                        if let user = track.user {
                            app.router.navigate(to: .user(user))
                        }
                    } label: {
                        Text(track.artistName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.84))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 16) {
                        if let plays = track.playbackCount {
                            Label(formatCompactCount(plays), systemImage: "play.fill")
                        }
                        if let likes = track.likesCount {
                            Label(formatCompactCount(likes), systemImage: "heart.fill")
                        }
                        if let reposts = track.repostsCount {
                            Label(formatCompactCount(reposts), systemImage: "arrow.2.squarepath")
                        }
                        Label(formatTime(duration), systemImage: "clock")
                    }
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.76))

                    HStack(spacing: 10) {
                        Button {
                            app.audio.play(track: track, inContext: [track] + related, contextTitle: track.title)
                        } label: {
                            Label(isPlayingThis ? "Pause" : "Play", systemImage: isPlayingThis ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            app.toggleLike(track)
                        } label: {
                            Label(isLiked ? "Liked" : "Like", systemImage: isLiked ? "heart.fill" : "heart")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(isLiked ? .accentColor : .white)

                        if let url = track.permalinkURL {
                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .tint(.white)
                        }
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 12)

            // Large interactive waveform + timed avatar comment pins
            VStack(alignment: .leading, spacing: 0) {
                WaveformView(
                    url: track.waveformURL,
                    progress: progress,
                    isActive: isCurrent,
                    height: 82
                ) { fraction in
                    if isCurrent {
                        app.audio.seek(fraction: fraction)
                    } else {
                        app.audio.play(track: track, inContext: [track] + related, contextTitle: track.title)
                    }
                }
                .environment(\.colorScheme, .dark)

                WaveformCommentsStrip(
                    comments: comments,
                    duration: duration,
                    currentTime: isCurrent ? app.audio.position : nil,
                    isPlaying: isPlayingThis,
                    onSelectTimestamp: { secs in
                        if !isCurrent {
                            app.audio.play(track: track, inContext: [track] + related, contextTitle: track.title)
                        }
                        app.audio.seek(seconds: secs)
                    },
                    onSelectUser: { user in
                        app.router.navigate(to: .user(user))
                    }
                )
            }

            HStack {
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Scroll for comments & related tracks")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.55))
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .frame(minHeight: minHeight)
        .background {
            LazyImage(url: track.resolvedArtworkURL(size: .large)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.accentColor.opacity(0.28)
                }
            }
            .blur(radius: 48)
            .scaleEffect(1.25)
            .overlay(
                LinearGradient(
                    colors: [.black.opacity(0.32), .black.opacity(0.62)],
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

    // MARK: - Below-the-Fold Sections

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
        async let commentsTask = app.api.fetchTrackComments(trackID: track.id, limit: 80)

        if let r = try? await relatedTask {
            related = r
        }
        if let c = try? await commentsTask {
            comments = c.collection
        }
    }
}

// MARK: - Timed Waveform Comments Strip

/// Renders SoundCloud's signature timed comment avatars pinned along the waveform,
/// plus a live pop-up comment bubble on hover or as playback crosses a comment's timestamp.
private struct WaveformCommentsStrip: View {
    let comments: [SCComment]
    let duration: Double
    let currentTime: Double?
    let isPlaying: Bool
    var onSelectTimestamp: (Double) -> Void
    var onSelectUser: (SCUser) -> Void

    @State private var hoveredCommentID: Int?

    private struct PinnedComment: Identifiable {
        let comment: SCComment
        let fraction: Double
        var id: Int { comment.id }
    }

    /// Buckets timed comments into evenly spaced slots so avatars never pile on top of each other.
    private var pinnedComments: [PinnedComment] {
        guard duration > 0 else { return [] }
        let slots = 34
        var buckets: [Int: PinnedComment] = [:]
        for c in comments {
            guard let secs = c.timestampSeconds, secs >= 0, secs <= duration else { continue }
            let frac = min(max(secs / duration, 0), 1)
            let slot = min(Int(frac * Double(slots)), slots - 1)
            if buckets[slot] == nil {
                buckets[slot] = PinnedComment(comment: c, fraction: frac)
            }
        }
        return buckets.values.sorted { $0.fraction < $1.fraction }
    }

    private var activeComment: PinnedComment? {
        if let hoveredID = hoveredCommentID,
           let match = pinnedComments.first(where: { $0.id == hoveredID }) {
            return match
        }
        guard isPlaying, let t = currentTime else { return nil }
        return pinnedComments.min(by: {
            abs(($0.comment.timestampSeconds ?? -999) - t) < abs(($1.comment.timestampSeconds ?? -999) - t)
        }).flatMap { nearest in
            guard let ts = nearest.comment.timestampSeconds, abs(ts - t) <= 2.5 else { return nil }
            return nearest
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let w = max(geo.size.width - 20, 1)
                ZStack(alignment: .leading) {
                    ForEach(pinnedComments) { pin in
                        let isHighlighted = activeComment?.id == pin.id
                        Button {
                            if let secs = pin.comment.timestampSeconds {
                                onSelectTimestamp(secs)
                            }
                        } label: {
                            LazyImage(url: pin.comment.user?.avatarURL(size: .small)) { state in
                                if let image = state.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Circle().fill(.white.opacity(0.25))
                                }
                            }
                            .frame(width: isHighlighted ? 22 : 18, height: isHighlighted ? 22 : 18)
                            .clipShape(Circle())
                            .overlay(
                                Circle().strokeBorder(
                                    isHighlighted ? Color.accentColor : Color.white.opacity(0.55),
                                    lineWidth: isHighlighted ? 1.5 : 0.8
                                )
                            )
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .offset(x: pin.fraction * w)
                        .zIndex(isHighlighted ? 5 : 1)
                        .onHover { over in
                            withAnimation(.easeOut(duration: 0.14)) {
                                if over {
                                    hoveredCommentID = pin.id
                                } else if hoveredCommentID == pin.id {
                                    hoveredCommentID = nil
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 24)
            .padding(.top, 5)

            // Live comment bubble (fixed height so hero layout never jumps)
            ZStack(alignment: .leading) {
                if let active = activeComment {
                    HStack(spacing: 8) {
                        Button {
                            if let u = active.comment.user { onSelectUser(u) }
                        } label: {
                            Text(active.comment.user?.displayName ?? "Listener")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Text(active.comment.body)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)

                        if let secs = active.comment.timestampSeconds {
                            Text(formatTime(secs))
                                .font(.system(size: 10.5).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.38), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .leading)))
                }
            }
            .frame(height: 28, alignment: .leading)
            .animation(.easeOut(duration: 0.18), value: activeComment?.id)
        }
    }
}

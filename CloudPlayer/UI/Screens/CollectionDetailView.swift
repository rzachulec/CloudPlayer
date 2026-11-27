import NukeUI
import SwiftUI

/// Native Playlist / Album / Station detail screen with blurred artwork hero banner,
/// clickable creator, total runtime, native ShareLink, and numbered tracklist.
struct CollectionDetailView: View {
    let playlist: SCPlaylist
    @Bindable var app: AppController

    @State private var tracks: [SCTrack] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var descriptionExpanded = false

    private var totalDurationSeconds: Double {
        if !tracks.isEmpty {
            return tracks.reduce(0) { $0 + $1.durationSeconds }
        }
        return Double(playlist.duration ?? 0) / 1000.0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroCard
                trackList
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 96)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: playlist.stableID) {
            await loadTracks()
        }
    }

    private var heroCard: some View {
        HStack(alignment: .bottom, spacing: 22) {
            CachedArtwork(url: playlist.resolvedArtworkURL(size: .large), size: 186, cornerRadius: 13)
                .shadow(color: .black.opacity(0.40), radius: 18, y: 7)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(playlist.isAlbum == true ? "ALBUM" : "PLAYLIST")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(.white.opacity(0.16), in: Capsule())

                    if let genre = playlist.genre, !genre.isEmpty {
                        Text("#\(genre)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                }

                Text(playlist.title)
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let user = playlist.user {
                        Button {
                            app.router.navigate(to: .user(user))
                        } label: {
                            Text(user.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        .buttonStyle(.plain)
                        Text("·").foregroundStyle(.white.opacity(0.5))
                    }

                    let count = tracks.isEmpty ? (playlist.trackCount ?? 0) : tracks.count
                    if count > 0 {
                        Text("\(count) tracks")
                    }
                    if totalDurationSeconds > 0 {
                        Text("· \(formatTotalRuntime(totalDurationSeconds))")
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.76))

                if let desc = playlist.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(descriptionExpanded ? nil : 2)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.15)) { descriptionExpanded.toggle() }
                        }
                }

                HStack(spacing: 10) {
                    Button {
                        if let first = tracks.first {
                            app.audio.play(track: first, inContext: tracks, contextTitle: playlist.title)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(tracks.isEmpty)

                    Button {
                        app.audio.playShuffled(tracks: tracks, contextTitle: playlist.title)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white)
                    .disabled(tracks.isEmpty)

                    if let url = playlist.permalinkURL {
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
        .padding(22)
        .background {
            LazyImage(url: playlist.resolvedArtworkURL(size: .large)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.accentColor.opacity(0.28)
                }
            }
            .blur(radius: 44)
            .scaleEffect(1.25)
            .overlay(
                LinearGradient(
                    colors: [.black.opacity(0.32), .black.opacity(0.68)],
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

    @ViewBuilder
    private var trackList: some View {
        if isLoading && tracks.isEmpty {
            LazyVStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { _ in TrackRowSkeleton() }
            }
        } else if let errorMessage, tracks.isEmpty {
            VStack(spacing: 10) {
                Text(errorMessage).font(.system(size: 13)).foregroundStyle(.secondary)
                Button("Retry") { Task { await loadTracks() } }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVStack(spacing: 2) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .trailing)

                        NativeTrackRow(
                            track: track,
                            app: app,
                            mode: .compact,
                            onPlay: {
                                app.audio.play(track: track, inContext: tracks, contextTitle: playlist.title)
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

    private func loadTracks() async {
        let initial = playlist.hydratedTracks
        if !initial.isEmpty {
            tracks = initial
        }
        guard playlist.missingTrackIDs.isEmpty == false || initial.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resolved = try await app.api.resolveTracks(for: playlist)
            tracks = resolved
        } catch {
            if tracks.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func formatTotalRuntime(_ seconds: Double) -> String {
        let mins = Int(seconds / 60)
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m > 0 ? "\(h) hr \(m) min" : "\(h) hr"
        }
        return "\(max(mins, 1)) min"
    }
}

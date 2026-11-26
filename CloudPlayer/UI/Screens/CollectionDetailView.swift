import SwiftUI

/// Native Playlist / Album / Mix detail screen.
/// Opens immediately with available playlist metadata and hydrates any missing track IDs in the background.
struct CollectionDetailView: View {
    let playlist: SCPlaylist
    @Bindable var app: AppController

    @State private var tracks: [SCTrack] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                trackList
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 92)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: playlist.stableID) {
            await loadTracks()
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 20) {
            CachedArtwork(url: playlist.resolvedArtworkURL(size: .large), size: 170, cornerRadius: 12)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)

            VStack(alignment: .leading, spacing: 8) {
                Text(playlist.isAlbum == true ? "ALBUM" : "PLAYLIST")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(playlist.title)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(2)
                Text(playlist.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                if let desc = playlist.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
                    .disabled(tracks.isEmpty)

                    Button {
                        app.audio.playShuffled(tracks: tracks, contextTitle: playlist.title)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(tracks.isEmpty)
                }
                .padding(.top, 4)
            }
            Spacer()
        }
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
                ForEach(tracks) { track in
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

    private func loadTracks() async {
        // Show already-hydrated tracks on frame 1
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
}

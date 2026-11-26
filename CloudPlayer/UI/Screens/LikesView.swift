import SwiftUI

/// Native Likes screen with stale-while-revalidate caching, shimmering skeletons,
/// Tiles / Compact / Waveform view modes, instant local filtering, and infinite scroll.
struct LikesView: View {
    @Bindable var app: AppController

    @AppStorage("cp.viewMode.likes") private var viewModeRaw: String = TrackListDisplayMode.compact.rawValue
    @State private var tracks: [SCTrack] = []
    @State private var nextHref: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var filterText = ""

    private var viewMode: TrackListDisplayMode {
        TrackListDisplayMode(rawValue: viewModeRaw) ?? .compact
    }

    private var filteredTracks: [SCTrack] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.lowercased().contains(q)
                || $0.artistName.lowercased().contains(q)
                || ($0.genre?.lowercased().contains(q) ?? false)
        }
    }

    private let tileColumns = [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 92)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: app.currentUser?.id) {
            await loadStaleWhileRevalidate()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Likes")
                    .font(.system(size: 24, weight: .bold))
                let count = app.currentUser?.likesCount ?? tracks.count
                Text(count > 0 ? "\(count) tracks" : "Your liked tracks")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            // Instant local filter
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Filter", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 130)
                if !filterText.isEmpty {
                    Button { filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: Capsule())

            // View mode segmented picker (Tiles / Compact / Waveform)
            HStack(spacing: 2) {
                ForEach(TrackListDisplayMode.allCases) { mode in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            viewModeRaw = mode.rawValue
                        }
                    } label: {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 26, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(viewMode == mode ? Color.accentColor.opacity(0.18) : Color.clear)
                            )
                            .foregroundStyle(viewMode == mode ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                    .help(mode.label)
                }
            }
            .padding(2)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if !filteredTracks.isEmpty {
                Button {
                    if let first = filteredTracks.first {
                        app.audio.play(track: first, inContext: filteredTracks, contextTitle: "Likes")
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    app.audio.playShuffled(tracks: filteredTracks, contextTitle: "Likes")
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && tracks.isEmpty {
            if viewMode == .tiles {
                TileGridSkeleton()
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(0..<14, id: \.self) { _ in
                        TrackRowSkeleton(waveformMode: viewMode == .waveform)
                    }
                }
            }
        } else if let errorMessage, tracks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await refreshFromNetwork() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else if filteredTracks.isEmpty {
            Text(filterText.isEmpty ? "No liked tracks yet." : "No likes match \"\(filterText)\".")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            switch viewMode {
            case .tiles:
                LazyVGrid(columns: tileColumns, spacing: 20) {
                    ForEach(filteredTracks) { track in
                        NativeMediaTile(track: track, app: app) {
                            app.audio.play(track: track, inContext: filteredTracks, contextTitle: "Likes")
                        }
                        .onAppear {
                            maybeLoadMore(currentTrack: track)
                        }
                    }
                }
            case .compact, .waveform:
                LazyVStack(spacing: viewMode == .waveform ? 4 : 2) {
                    ForEach(filteredTracks) { track in
                        NativeTrackRow(
                            track: track,
                            app: app,
                            mode: viewMode,
                            onPlay: {
                                app.audio.play(track: track, inContext: filteredTracks, contextTitle: "Likes")
                            },
                            onArtistTap: { user in
                                app.router.navigate(to: .user(user))
                            }
                        )
                        .onAppear {
                            maybeLoadMore(currentTrack: track)
                        }
                    }
                }
            }

            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Stale-While-Revalidate Data Loading

    private var cacheKey: String? {
        guard let uid = app.currentUser?.id else { return nil }
        return "likes:\(uid):v1"
    }

    private func loadStaleWhileRevalidate() async {
        guard let key = cacheKey else { return }
        if tracks.isEmpty, let cached = await app.cache.load([SCTrack].self, key: key), !cached.isEmpty {
            tracks = cached
            app.library.registerLikedTracks(cached)
        }
        await refreshFromNetwork()
    }

    private func refreshFromNetwork() async {
        guard let uid = app.currentUser?.id else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await app.api.fetchTrackLikes(userID: uid, limit: 50)
            let fetched = page.collection.compactMap(\.track)
            tracks = fetched
            nextHref = page.nextHref
            app.library.registerLikedTracks(fetched)
            if let key = cacheKey {
                await app.cache.save(fetched, key: key)
            }
        } catch {
            if tracks.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func maybeLoadMore(currentTrack: SCTrack) {
        guard filterText.isEmpty,
              let nextHref,
              !isLoadingMore,
              let idx = tracks.firstIndex(where: { $0.id == currentTrack.id }),
              idx >= tracks.count - 8 else { return }

        Task {
            guard let uid = app.currentUser?.id else { return }
            isLoadingMore = true
            defer { isLoadingMore = false }
            do {
                let page = try await app.api.fetchTrackLikes(userID: uid, nextHref: nextHref)
                let fetched = page.collection.compactMap(\.track)
                let existing = Set(tracks.map(\.id))
                let unique = fetched.filter { !existing.contains($0.id) }
                tracks.append(contentsOf: unique)
                self.nextHref = page.nextHref
                app.library.registerLikedTracks(unique)
            } catch {
                // Keep existing list on pagination error
            }
        }
    }
}

import SwiftUI

private enum LikesSort: String, CaseIterable, Identifiable {
    case recentlyLiked = "Recently Liked"
    case oldestLiked = "Oldest Liked"
    case uploadNewest = "Upload Date (Newest)"
    case uploadOldest = "Upload Date (Oldest)"
    case titleAZ = "Title (A–Z)"
    case artistAZ = "Artist (A–Z)"
    case mostPlayed = "Most Played"
    case mostLiked = "Most Liked"
    case durationLongest = "Longest"
    case durationShortest = "Shortest"

    var id: Self { self }

    var shortLabel: String {
        switch self {
        case .recentlyLiked: "Sort"
        case .oldestLiked: "Oldest Liked"
        case .uploadNewest: "Newest"
        case .uploadOldest: "Oldest"
        case .titleAZ: "Title"
        case .artistAZ: "Artist"
        case .mostPlayed: "Most Played"
        case .mostLiked: "Most Liked"
        case .durationLongest: "Longest"
        case .durationShortest: "Shortest"
        }
    }
}

/// Native Likes screen with stale-while-revalidate caching, shimmering skeletons,
/// Tiles / Compact / Waveform view modes, instant local filtering, metadata sorting, and infinite scroll.
struct LikesView: View {
    @Bindable var app: AppController

    @AppStorage("cp.viewMode.likes") private var viewModeRaw: String = TrackListDisplayMode.compact.rawValue
    @AppStorage("cp.sort.likes") private var sortRaw: String = LikesSort.recentlyLiked.rawValue
    @State private var tracks: [SCTrack] = []
    @State private var nextHref: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var filterText = ""

    private var viewMode: TrackListDisplayMode {
        TrackListDisplayMode(rawValue: viewModeRaw) ?? .compact
    }

    private var sortOrder: LikesSort {
        LikesSort(rawValue: sortRaw) ?? .recentlyLiked
    }

    private var filteredTracks: [SCTrack] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [SCTrack] = q.isEmpty ? tracks : tracks.filter {
            $0.title.lowercased().contains(q)
                || $0.artistName.lowercased().contains(q)
                || ($0.genre?.lowercased().contains(q) ?? false)
        }
        switch sortOrder {
        case .recentlyLiked:
            return base
        case .oldestLiked:
            return base.reversed()
        case .uploadNewest:
            return base.sorted { ($0.uploadedDate ?? .distantPast) > ($1.uploadedDate ?? .distantPast) }
        case .uploadOldest:
            return base.sorted { ($0.uploadedDate ?? .distantFuture) < ($1.uploadedDate ?? .distantFuture) }
        case .titleAZ:
            return base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artistAZ:
            return base.sorted {
                let cmp = $0.artistName.localizedCaseInsensitiveCompare($1.artistName)
                return cmp == .orderedSame
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : cmp == .orderedAscending
            }
        case .mostPlayed:
            return base.sorted { ($0.playbackCount ?? -1) > ($1.playbackCount ?? -1) }
        case .mostLiked:
            return base.sorted { ($0.likesCount ?? -1) > ($1.likesCount ?? -1) }
        case .durationLongest:
            return base.sorted { $0.duration > $1.duration }
        case .durationShortest:
            return base.sorted { $0.duration < $1.duration }
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
            LiquidFilterField(text: $filterText, width: 130)

            // Metadata sort menu
            Menu {
                ForEach(LikesSort.allCases) { option in
                    Button {
                        sortRaw = option.rawValue
                    } label: {
                        if sortOrder == option {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                Label(sortOrder.shortLabel, systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .liquidGlassButton(prominent: sortOrder != .recentlyLiked)
            .fixedSize()
            .help("Sort Likes: \(sortOrder.rawValue)")

            // View mode segmented picker (Tiles / Compact / Waveform)
            LiquidIconPicker(
                options: TrackListDisplayMode.allCases,
                selection: Binding(
                    get: { viewMode },
                    set: { viewModeRaw = $0.rawValue }
                ),
                symbol: \.symbol,
                label: \.label
            )

            if !filteredTracks.isEmpty {
                Button {
                    if let first = filteredTracks.first {
                        app.audio.play(track: first, inContext: filteredTracks, contextTitle: "Likes")
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .liquidGlassButton(prominent: true)

                Button {
                    app.audio.playShuffled(tracks: filteredTracks, contextTitle: "Likes")
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .liquidGlassButton()
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
                .liquidGlassButton(prominent: true)
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
            let page = try await app.api.fetchTrackLikes(userID: uid, limit: 200)
            let fetched = page.collection.compactMap(\.track)
            if tracks.count <= fetched.count {
                tracks = fetched
            } else {
                // Keep any deeper already-cached likes while updating the top slice in place
                let topIDs = Set(fetched.map(\.id))
                let remainder = tracks.filter { !topIDs.contains($0.id) }
                tracks = fetched + remainder
            }
            nextHref = page.nextHref
            app.library.registerLikedTracks(fetched)
            if let key = cacheKey {
                await app.cache.save(tracks, key: key)
            }
            // Background-index all remaining pages so local filtering searches 100% of Likes
            if let next = page.nextHref {
                await fetchAllRemainingPages(userID: uid, startingAt: next)
            }
        } catch {
            if tracks.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func fetchAllRemainingPages(userID: Int, startingAt firstNext: String) async {
        var cursor: String? = firstNext
        var all = tracks
        var seen = Set(all.map(\.id))
        var pagesFetched = 0

        while let next = cursor, !next.isEmpty, pagesFetched < 25, !Task.isCancelled {
            pagesFetched += 1
            guard let page = try? await app.api.fetchTrackLikes(userID: userID, nextHref: next) else { break }
            let batch = page.collection.compactMap(\.track).filter { seen.insert($0.id).inserted }
            if !batch.isEmpty {
                all.append(contentsOf: batch)
                tracks = all
                app.library.registerLikedTracks(batch)
            }
            cursor = page.nextHref
        }
        nextHref = cursor
        if let key = cacheKey {
            await app.cache.save(all, key: key)
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

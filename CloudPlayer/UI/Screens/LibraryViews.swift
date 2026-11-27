import SwiftUI

private enum CollectionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case created = "Created"
    case liked = "Saved"
    var id: Self { self }
}

private enum CollectionSort: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case title = "Title"
    case trackCount = "Most Tracks"
    var id: Self { self }
}

private enum CollectionDisplayMode: String, CaseIterable, Identifiable {
    case tiles
    case list

    var id: Self { self }
    var symbol: String { self == .tiles ? "square.grid.2x2" : "list.bullet" }
    var label: String { self == .tiles ? "Tiles" : "List" }
}

/// Native Playlists / Albums library screen backed by `/me/library/all` + `/users/{id}/playlists_without_albums`
/// with ownership filters, sorting, instant search, Tiles/List view modes, and cover hydration.
struct LibraryCollectionsView: View {
    enum Kind {
        case playlists
        case albums

        var title: String { self == .playlists ? "Playlists" : "Albums" }
        var subtitle: String { self == .playlists ? "Your playlists and saved sets" : "Your saved albums" }
        var cacheKeySuffix: String { self == .playlists ? "playlists" : "albums" }
    }

    let kind: Kind
    @Bindable var app: AppController

    @AppStorage("cp.viewMode.collections") private var viewModeRaw: String = CollectionDisplayMode.tiles.rawValue
    @State private var items: [SCPlaylist] = []
    @State private var nextHref: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var ownershipFilter: CollectionFilter = .all
    @State private var sortOrder: CollectionSort = .recent
    @State private var filterText = ""

    private let gridColumns = [GridItem(.adaptive(minimum: 168, maximum: 225), spacing: 18)]

    private var viewMode: CollectionDisplayMode {
        CollectionDisplayMode(rawValue: viewModeRaw) ?? .tiles
    }

    private var displayedItems: [SCPlaylist] {
        let uid = app.currentUser?.id
        var result = items

        if kind == .playlists, let uid {
            switch ownershipFilter {
            case .all: break
            case .created: result = result.filter { $0.user?.id == uid }
            case .liked: result = result.filter { $0.user?.id != uid }
            }
        }

        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(q)
                    || ($0.user?.displayName.lowercased().contains(q) ?? false)
                    || ($0.genre?.lowercased().contains(q) ?? false)
            }
        }

        switch sortOrder {
        case .recent: break
        case .title:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .trackCount:
            result.sort { ($0.trackCount ?? 0) > ($1.trackCount ?? 0) }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if isLoading && items.isEmpty {
                    TileGridSkeleton()
                } else if let errorMessage, items.isEmpty {
                    VStack(spacing: 10) {
                        Text(errorMessage).font(.system(size: 13)).foregroundStyle(.secondary)
                        Button("Retry") { Task { await refresh() } }.liquidGlassButton(prominent: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else if displayedItems.isEmpty {
                    Text(filterText.isEmpty ? "No \(kind.title.lowercased()) in your library yet." : "No \(kind.title.lowercased()) match “\(filterText)”.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    if viewMode == .tiles {
                        LazyVGrid(columns: gridColumns, spacing: 20) {
                            ForEach(displayedItems, id: \.stableID) { playlist in
                                PlaylistCard(playlist: playlist, app: app)
                                    .onAppear {
                                        if playlist.stableID == items.last?.stableID { loadMore() }
                                    }
                            }
                        }
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(displayedItems, id: \.stableID) { playlist in
                                CollectionListRow(playlist: playlist, app: app)
                                    .onAppear {
                                        if playlist.stableID == items.last?.stableID { loadMore() }
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
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 92)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: "\(kind.cacheKeySuffix)|\(app.currentUser?.id ?? 0)") {
            await loadStaleWhileRevalidate()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.system(size: 24, weight: .bold))
                    Text(items.isEmpty ? kind.subtitle : "\(displayedItems.count) \(kind.title.lowercased())")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                // Instant filter
                LiquidFilterField(text: $filterText)

                // Sort menu
                Menu {
                    ForEach(CollectionSort.allCases) { option in
                        Button {
                            sortOrder = option
                        } label: {
                            if sortOrder == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 10.5))
                        Text(sortOrder.rawValue).font(.system(size: 11.5, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .liquidGlassCapsule(interactive: true)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Tiles / List toggle
                LiquidIconPicker(
                    options: CollectionDisplayMode.allCases,
                    selection: Binding(
                        get: { viewMode },
                        set: { viewModeRaw = $0.rawValue }
                    ),
                    symbol: \.symbol,
                    label: \.label
                )
            }

            if kind == .playlists {
                HStack(spacing: 6) {
                    ForEach(CollectionFilter.allCases) { f in
                        let selected = ownershipFilter == f
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { ownershipFilter = f }
                        } label: {
                            Text(f.rawValue)
                                .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var cacheKey: String {
        "library:\(kind.cacheKeySuffix):\(app.currentUser?.id ?? 0):v2"
    }

    private func matchesKind(_ entry: SCLibraryItem) -> Bool {
        // System playlists (stations) belong in StationsView
        if (entry.type ?? "").contains("system-playlist") { return false }
        guard let pl = entry.resolvedPlaylist else { return false }
        let isAlbum = pl.isAlbum == true
        return kind == .albums ? isAlbum : !isAlbum
    }

    private func loadStaleWhileRevalidate() async {
        if items.isEmpty, let cached = await app.cache.load([SCPlaylist].self, key: cacheKey), !cached.isEmpty {
            items = cached
        }
        await refresh()
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let libTask = app.api.fetchLibraryCollections(limit: 50)
            async let ownTask: [SCPlaylist] = {
                guard kind == .playlists, let uid = app.currentUser?.id else { return [] }
                return (try? await app.api.fetchUserOwnPlaylists(userID: uid, limit: 50)) ?? []
            }()

            let page = try await libTask
            let ownPlaylists = await ownTask
            let ownByID = Dictionary(uniqueKeysWithValues: ownPlaylists.compactMap { pl in pl.id.map { ($0, pl) } })
            let priorByID = Dictionary(uniqueKeysWithValues: items.compactMap { pl in pl.id.map { ($0, pl) } })

            var merged: [SCPlaylist] = page.collection
                .filter(matchesKind)
                .compactMap(\.resolvedPlaylist)
                .map { pl in
                    guard let id = pl.id else { return pl }
                    if let detailed = ownByID[id] {
                        return pl.mergingTracks(from: detailed)
                    }
                    if let prior = priorByID[id] {
                        return pl.mergingTracks(from: prior)
                    }
                    return pl
                }

            // Also include any owned playlists not present on the first page of /me/library/all
            let existingIDs = Set(merged.compactMap(\.id))
            for own in ownPlaylists where own.id.map({ !existingIDs.contains($0) }) ?? false {
                merged.append(own)
            }

            // Hydrate any remaining coverless liked playlists concurrently before committing
            merged = await hydrateMissingCovers(in: merged)
            items = merged
            nextHref = page.nextHref
            await app.cache.save(merged, key: cacheKey)
        } catch {
            if items.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func hydrateMissingCovers(in playlists: [SCPlaylist]) async -> [SCPlaylist] {
        let missingIDs = playlists.compactMap { pl -> Int? in
            guard pl.artworkURL == nil,
                  pl.calculatedArtworkURL == nil,
                  pl.hydratedTracks.isEmpty,
                  let id = pl.id else { return nil }
            return id
        }.prefix(12)
        guard !missingIDs.isEmpty else { return playlists }

        let api = app.api
        let detailedByID: [Int: SCPlaylist] = await withTaskGroup(of: (Int, SCPlaylist?).self) { group in
            for id in missingIDs {
                group.addTask { (id, try? await api.fetchPlaylist(id: id)) }
            }
            var out: [Int: SCPlaylist] = [:]
            for await (id, pl) in group {
                if let pl { out[id] = pl }
            }
            return out
        }

        return playlists.map { pl in
            if let id = pl.id, let detailed = detailedByID[id] {
                return pl.mergingTracks(from: detailed)
            }
            return pl
        }
    }

    private func loadMore() {
        guard let next = nextHref, !isLoadingMore else { return }
        Task {
            isLoadingMore = true
            defer { isLoadingMore = false }
            if let page = try? await app.api.fetchLibraryCollections(nextHref: next) {
                let seen = Set(items.map(\.stableID))
                let more = page.collection
                    .filter(matchesKind)
                    .compactMap(\.resolvedPlaylist)
                    .filter { !seen.contains($0.stableID) }
                items.append(contentsOf: more)
                nextHref = page.nextHref
            }
        }
    }
}

/// Compact list row for Playlists & Albums view mode.
private struct CollectionListRow: View {
    let playlist: SCPlaylist
    @Bindable var app: AppController
    @State private var isHovered = false
    @State private var isStarting = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                CachedArtwork(url: playlist.resolvedArtworkURL(size: .medium), size: 50, cornerRadius: 7)
                if isHovered || isStarting {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.black.opacity(0.42))
                        .frame(width: 50, height: 50)
                    Button(action: playNow) {
                        if isStarting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let user = playlist.user {
                        Text(user.displayName)
                    }
                    if let count = playlist.trackCount, count > 0 {
                        Text("· \(count) tracks")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let dur = playlist.duration, dur > 0 {
                Text(formatTime(Double(dur) / 1000.0))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            app.router.navigate(to: .playlist(playlist))
        }
    }

    private func playNow() {
        guard !isStarting else { return }
        let ready = playlist.hydratedTracks
        if let first = ready.first, playlist.missingTrackIDs.isEmpty {
            app.audio.play(track: first, inContext: ready, contextTitle: playlist.title)
            return
        }
        isStarting = true
        Task {
            defer { isStarting = false }
            if let resolved = try? await app.api.resolveTracks(for: playlist), let first = resolved.first {
                app.audio.play(track: first, inContext: resolved, contextTitle: playlist.title)
            }
        }
    }
}

/// Native Stations view showing the user's saved/liked stations from `/me/library/all`.
struct StationsView: View {
    @Bindable var app: AppController

    @State private var stations: [SCPlaylist] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let gridColumns = [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stations").font(.system(size: 24, weight: .bold))
                    Text("Your saved stations")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if isLoading && stations.isEmpty {
                    TileGridSkeleton()
                } else if let errorMessage, stations.isEmpty {
                    VStack(spacing: 10) {
                        Text(errorMessage).font(.system(size: 13)).foregroundStyle(.secondary)
                        Button("Retry") { Task { await refresh() } }.liquidGlassButton(prominent: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else if stations.isEmpty {
                    Text("No saved stations in your library yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(stations, id: \.stableID) { station in
                            PlaylistCard(playlist: station, app: app)
                        }
                    }
                }
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

    private var cacheKey: String { "stations:\(app.currentUser?.id ?? 0):v3" }

    private func loadStaleWhileRevalidate() async {
        if stations.isEmpty,
           let cached = await app.cache.load([SCPlaylist].self, key: cacheKey),
           !cached.isEmpty {
            stations = cached
        }
        await refresh()
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await app.api.fetchSavedStations()
            stations = fetched
            await app.cache.save(fetched, key: cacheKey)
        } catch {
            if stations.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Native Following artists screen backed by `/users/{id}/followings`.
struct FollowingView: View {
    @Bindable var app: AppController

    @State private var users: [SCUser] = []
    @State private var nextHref: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    private let gridColumns = [GridItem(.adaptive(minimum: 155, maximum: 205), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Following").font(.system(size: 24, weight: .bold))
                    let count = app.currentUser?.followingsCount ?? users.count
                    Text(count > 0 ? "\(count) artists" : "Artists you follow")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if isLoading && users.isEmpty {
                    TileGridSkeleton()
                } else if let errorMessage, users.isEmpty {
                    VStack(spacing: 10) {
                        Text(errorMessage).font(.system(size: 13)).foregroundStyle(.secondary)
                        Button("Retry") { Task { await refresh() } }.liquidGlassButton(prominent: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else if users.isEmpty {
                    Text("You aren't following anyone yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 18) {
                        ForEach(users) { user in
                            UserCard(user: user) {
                                app.router.navigate(to: .user(user))
                            }
                            .onAppear {
                                if user.id == users.last?.id { loadMore() }
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
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 92)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: app.currentUser?.id) {
            await loadStaleWhileRevalidate()
        }
    }

    private var cacheKey: String { "following:\(app.currentUser?.id ?? 0):v1" }

    private func loadStaleWhileRevalidate() async {
        if users.isEmpty, let cached = await app.cache.load([SCUser].self, key: cacheKey), !cached.isEmpty {
            users = cached
        }
        await refresh()
    }

    private func refresh() async {
        guard let uid = app.currentUser?.id else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await app.api.fetchUserFollowings(userID: uid, limit: 50)
            users = page.collection
            nextHref = page.nextHref
            app.library.registerFollowedUsers(page.collection)
            await app.cache.save(page.collection, key: cacheKey)
        } catch {
            if users.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func loadMore() {
        guard let uid = app.currentUser?.id, let next = nextHref, !isLoadingMore else { return }
        Task {
            isLoadingMore = true
            defer { isLoadingMore = false }
            if let page = try? await app.api.fetchUserFollowings(userID: uid, nextHref: next) {
                let seen = Set(users.map(\.id))
                users.append(contentsOf: page.collection.filter { !seen.contains($0.id) })
                nextHref = page.nextHref
            }
        }
    }
}

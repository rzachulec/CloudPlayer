import SwiftUI

/// Native Playlists / Albums library screen backed by `/me/library/all` + `/users/{id}/playlists_without_albums`
/// so user-created playlists without a custom cover automatically display their first track's artwork.
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

    @State private var items: [SCPlaylist] = []
    @State private var nextHref: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    private let gridColumns = [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.system(size: 24, weight: .bold))
                    Text(kind.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }

                if isLoading && items.isEmpty {
                    TileGridSkeleton()
                } else if let errorMessage, items.isEmpty {
                    VStack(spacing: 10) {
                        Text(errorMessage).font(.system(size: 13)).foregroundStyle(.secondary)
                        Button("Retry") { Task { await refresh() } }.buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else if items.isEmpty {
                    Text("No \(kind.title.lowercased()) in your library yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(items, id: \.stableID) { playlist in
                            PlaylistCard(playlist: playlist, app: app)
                                .onAppear {
                                    if playlist.stableID == items.last?.stableID { loadMore() }
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

            var merged: [SCPlaylist] = page.collection
                .filter(matchesKind)
                .compactMap(\.resolvedPlaylist)
                .map { pl in
                    if let id = pl.id, let detailed = ownByID[id] {
                        return pl.mergingTracks(from: detailed)
                    }
                    return pl
                }

            // Also include any owned playlists not present on the first page of /me/library/all
            let existingIDs = Set(merged.compactMap(\.id))
            for own in ownPlaylists where own.id.map({ !existingIDs.contains($0) }) ?? false {
                merged.append(own)
            }

            items = merged
            nextHref = page.nextHref
            await app.cache.save(merged, key: cacheKey)

            // Hydrate coverless liked playlists in the background so they also show first-track artwork
            await hydrateMissingCovers(in: merged)
        } catch {
            if items.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func hydrateMissingCovers(in playlists: [SCPlaylist]) async {
        let missing = playlists.filter {
            $0.artworkURL == nil && $0.calculatedArtworkURL == nil && $0.hydratedTracks.isEmpty && $0.id != nil
        }.prefix(12)
        guard !missing.isEmpty else { return }

        var updated = items
        var changed = false
        for pl in missing {
            guard let id = pl.id, let detailed = try? await app.api.fetchPlaylist(id: id) else { continue }
            if let idx = updated.firstIndex(where: { $0.id == id }) {
                updated[idx] = updated[idx].mergingTracks(from: detailed)
                changed = true
            }
        }
        if changed {
            items = updated
            await app.cache.save(updated, key: cacheKey)
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

/// Native Stations / Radio view combining liked stations (`system-playlist-like`) and
/// SoundCloud's curated station shelves from `/mixed-selections`.
struct StationsView: View {
    @Bindable var app: AppController

    @State private var likedStations: [SCPlaylist] = []
    @State private var discoverShelves: [SCMixedSelection] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let gridColumns = [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stations").font(.system(size: 24, weight: .bold))
                    Text("Your saved stations and personalized radio")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if isLoading && likedStations.isEmpty && discoverShelves.isEmpty {
                    TileGridSkeleton()
                } else if let errorMessage, likedStations.isEmpty && discoverShelves.isEmpty {
                    VStack(spacing: 10) {
                        Text(errorMessage).font(.system(size: 13)).foregroundStyle(.secondary)
                        Button("Retry") { Task { await refresh() } }.buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else if likedStations.isEmpty && discoverShelves.isEmpty {
                    Text("No stations available yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    if !likedStations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Stations")
                                .font(.system(size: 17, weight: .bold))
                            LazyVGrid(columns: gridColumns, spacing: 20) {
                                ForEach(likedStations, id: \.stableID) { station in
                                    PlaylistCard(playlist: station, app: app)
                                }
                            }
                        }
                    }

                    ForEach(discoverShelves) { shelf in
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shelf.title).font(.system(size: 17, weight: .bold))
                                if let desc = shelf.description, !desc.isEmpty {
                                    Text(desc).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(shelf.items?.collection ?? [], id: \.stableID) { station in
                                        PlaylistCard(playlist: station, app: app)
                                            .frame(width: 174)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
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

    private struct CachedStations: Codable {
        let liked: [SCPlaylist]
        let discover: [SCMixedSelection]
    }

    private var cacheKey: String { "stations:\(app.currentUser?.id ?? 0):v2" }

    private func loadStaleWhileRevalidate() async {
        if likedStations.isEmpty && discoverShelves.isEmpty,
           let cached = await app.cache.load(CachedStations.self, key: cacheKey) {
            likedStations = cached.liked
            discoverShelves = cached.discover
        }
        await refresh()
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await app.api.fetchStations()
            likedStations = result.liked
            discoverShelves = result.discover
            await app.cache.save(CachedStations(liked: result.liked, discover: result.discover), key: cacheKey)
        } catch {
            if likedStations.isEmpty && discoverShelves.isEmpty {
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
                        Button("Retry") { Task { await refresh() } }.buttonStyle(.borderedProminent)
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

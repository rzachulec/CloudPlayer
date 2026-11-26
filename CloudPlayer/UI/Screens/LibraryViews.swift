import SwiftUI

/// Native Playlists / Albums library screen backed by `/me/library/all`.
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
        "library:\(kind.cacheKeySuffix):\(app.currentUser?.id ?? 0):v1"
    }

    private func matchesKind(_ playlist: SCPlaylist) -> Bool {
        let isAlbum = playlist.isAlbum == true
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
            let page = try await app.api.fetchLibraryCollections(limit: 50)
            let filtered = page.collection.compactMap(\.resolvedPlaylist).filter(matchesKind)
            items = filtered
            nextHref = page.nextHref
            await app.cache.save(filtered, key: cacheKey)
        } catch {
            if items.isEmpty { errorMessage = error.localizedDescription }
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
                    .compactMap(\.resolvedPlaylist)
                    .filter { matchesKind($0) && !seen.contains($0.stableID) }
                items.append(contentsOf: more)
                nextHref = page.nextHref
            }
        }
    }
}

/// Native Stations view backed by `/me/personalized-stations`.
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
                    Text("Personalized radio stations").font(.system(size: 12)).foregroundStyle(.secondary)
                }

                if isLoading && stations.isEmpty {
                    TileGridSkeleton()
                } else if let errorMessage, stations.isEmpty {
                    VStack(spacing: 10) {
                        Text(errorMessage).font(.system(size: 13)).foregroundStyle(.secondary)
                        Button("Retry") { Task { await refresh() } }.buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else if stations.isEmpty {
                    Text("No personalized stations available.")
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

    private var cacheKey: String { "stations:\(app.currentUser?.id ?? 0):v1" }

    private func loadStaleWhileRevalidate() async {
        if stations.isEmpty, let cached = await app.cache.load([SCPlaylist].self, key: cacheKey), !cached.isEmpty {
            stations = cached
        }
        await refresh()
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await app.api.fetchPersonalizedStations(limit: 30)
            stations = fetched
            await app.cache.save(fetched, key: cacheKey)
        } catch {
            if stations.isEmpty { errorMessage = error.localizedDescription }
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

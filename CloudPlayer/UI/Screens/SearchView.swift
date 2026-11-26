import NukeUI
import SwiftUI

enum SearchScope: String, CaseIterable, Identifiable {
    case tracks = "Tracks"
    case playlists = "Playlists"
    case albums = "Albums"
    case people = "People"

    var id: Self { self }
}

/// Native Search screen with 4 scopes (Tracks, Playlists, Albums, People),
/// instant scope switching, Play All, shimmering skeletons, and infinite scroll.
struct SearchView: View {
    let query: String
    @Bindable var app: AppController

    @State private var scope: SearchScope = .tracks
    @State private var tracks: [SCTrack] = []
    @State private var playlists: [SCPlaylist] = []
    @State private var albums: [SCPlaylist] = []
    @State private var users: [SCUser] = []

    @State private var tracksNext: String?
    @State private var playlistsNext: String?
    @State private var albumsNext: String?
    @State private var usersNext: String?

    @State private var loadedScopes: Set<SearchScope> = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    private let gridColumns = [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 92)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: "\(query)|\(scope.rawValue)") {
            await loadScopeIfNeeded()
        }
        .onChange(of: query) { _, _ in
            resetResults()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search")
                        .font(.system(size: 24, weight: .bold))
                    Text("Results for “\(query)”")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if scope == .tracks && !tracks.isEmpty {
                    Button {
                        if let first = tracks.first {
                            app.audio.play(track: first, inContext: tracks, contextTitle: "Search: \(query)")
                        }
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Picker("Scope", selection: $scope) {
                ForEach(SearchScope.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && !loadedScopes.contains(scope) {
            if scope == .tracks {
                LazyVStack(spacing: 4) {
                    ForEach(0..<12, id: \.self) { _ in TrackRowSkeleton() }
                }
            } else {
                TileGridSkeleton()
            }
        } else if let errorMessage, currentIsEmpty {
            VStack(spacing: 10) {
                Text(errorMessage).font(.system(size: 13)).foregroundStyle(.secondary)
                Button("Retry") {
                    loadedScopes.remove(scope)
                    Task { await loadScopeIfNeeded() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        } else if currentIsEmpty {
            Text("No \(scope.rawValue.lowercased()) found for “\(query)”.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            switch scope {
            case .tracks:
                LazyVStack(spacing: 2) {
                    ForEach(tracks) { track in
                        NativeTrackRow(
                            track: track,
                            app: app,
                            mode: .compact,
                            onPlay: {
                                app.audio.play(track: track, inContext: tracks, contextTitle: "Search: \(query)")
                            },
                            onArtistTap: { user in
                                app.router.navigate(to: .user(user))
                            }
                        )
                        .onAppear {
                            if track.id == tracks.last?.id { loadMoreTracks() }
                        }
                    }
                }
            case .playlists:
                LazyVGrid(columns: gridColumns, spacing: 20) {
                    ForEach(playlists, id: \.stableID) { pl in
                        PlaylistCard(playlist: pl, app: app)
                            .onAppear {
                                if pl.stableID == playlists.last?.stableID { loadMorePlaylists() }
                            }
                    }
                }
            case .albums:
                LazyVGrid(columns: gridColumns, spacing: 20) {
                    ForEach(albums, id: \.stableID) { album in
                        PlaylistCard(playlist: album, app: app)
                            .onAppear {
                                if album.stableID == albums.last?.stableID { loadMoreAlbums() }
                            }
                    }
                }
            case .people:
                LazyVGrid(columns: gridColumns, spacing: 20) {
                    ForEach(users) { user in
                        UserCard(user: user) {
                            app.router.navigate(to: .user(user))
                        }
                        .onAppear {
                            if user.id == users.last?.id { loadMoreUsers() }
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

    private var currentIsEmpty: Bool {
        switch scope {
        case .tracks: tracks.isEmpty
        case .playlists: playlists.isEmpty
        case .albums: albums.isEmpty
        case .people: users.isEmpty
        }
    }

    private func resetResults() {
        tracks = []
        playlists = []
        albums = []
        users = []
        tracksNext = nil
        playlistsNext = nil
        albumsNext = nil
        usersNext = nil
        loadedScopes = []
        errorMessage = nil
    }

    private func loadScopeIfNeeded() async {
        guard !loadedScopes.contains(scope) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch scope {
            case .tracks:
                let page = try await app.api.searchTracks(query: query)
                tracks = page.collection
                tracksNext = page.nextHref
            case .playlists:
                let page = try await app.api.searchPlaylists(query: query)
                playlists = page.collection
                playlistsNext = page.nextHref
            case .albums:
                let page = try await app.api.searchAlbums(query: query)
                albums = page.collection
                albumsNext = page.nextHref
            case .people:
                let page = try await app.api.searchUsers(query: query)
                users = page.collection
                usersNext = page.nextHref
            }
            loadedScopes.insert(scope)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMoreTracks() {
        guard let next = tracksNext, !isLoadingMore else { return }
        Task {
            isLoadingMore = true
            defer { isLoadingMore = false }
            if let page = try? await app.api.searchTracks(query: query, nextHref: next) {
                let seen = Set(tracks.map(\.id))
                tracks.append(contentsOf: page.collection.filter { !seen.contains($0.id) })
                tracksNext = page.nextHref
            }
        }
    }

    private func loadMorePlaylists() {
        guard let next = playlistsNext, !isLoadingMore else { return }
        Task {
            isLoadingMore = true
            defer { isLoadingMore = false }
            if let page = try? await app.api.searchPlaylists(query: query, nextHref: next) {
                let seen = Set(playlists.map(\.stableID))
                playlists.append(contentsOf: page.collection.filter { !seen.contains($0.stableID) })
                playlistsNext = page.nextHref
            }
        }
    }

    private func loadMoreAlbums() {
        guard let next = albumsNext, !isLoadingMore else { return }
        Task {
            isLoadingMore = true
            defer { isLoadingMore = false }
            if let page = try? await app.api.searchAlbums(query: query, nextHref: next) {
                let seen = Set(albums.map(\.stableID))
                albums.append(contentsOf: page.collection.filter { !seen.contains($0.stableID) })
                albumsNext = page.nextHref
            }
        }
    }

    private func loadMoreUsers() {
        guard let next = usersNext, !isLoadingMore else { return }
        Task {
            isLoadingMore = true
            defer { isLoadingMore = false }
            if let page = try? await app.api.searchUsers(query: query, nextHref: next) {
                let seen = Set(users.map(\.id))
                users.append(contentsOf: page.collection.filter { !seen.contains($0.id) })
                usersNext = page.nextHref
            }
        }
    }
}

/// Reusable circular avatar card for artists/users in Search & Following.
struct UserCard: View {
    let user: SCUser
    var onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            LazyImage(url: user.avatarURL(size: .large)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Circle().fill(.quaternary)
                        .overlay(Image(systemName: "person.fill").font(.title).foregroundStyle(.secondary))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
            .scaleEffect(isHovered ? 1.03 : 1.0)

            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if user.verified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tint)
                    }
                }
                if let followers = user.followersCount {
                    Text("\(formatCompactCount(followers)) followers")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovered = hovering }
        }
        .onTapGesture(perform: onTap)
    }
}

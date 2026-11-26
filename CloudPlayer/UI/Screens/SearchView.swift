import NukeUI
import SwiftUI

enum SearchScope: String, CaseIterable, Identifiable {
    case tracks = "Tracks"
    case playlists = "Playlists"
    case albums = "Albums"
    case people = "People"

    var id: Self { self }
}

enum SearchCreatedFilter: String, CaseIterable, Identifiable {
    case any = ""
    case lastHour = "last_hour"
    case lastDay = "last_day"
    case lastWeek = "last_week"
    case lastMonth = "last_month"
    case lastYear = "last_year"

    var id: Self { self }
    var label: String {
        switch self {
        case .any: "Any time"
        case .lastHour: "Past hour"
        case .lastDay: "Past day"
        case .lastWeek: "Past week"
        case .lastMonth: "Past month"
        case .lastYear: "Past year"
        }
    }
}

enum SearchDurationFilter: String, CaseIterable, Identifiable {
    case any = ""
    case short = "short"
    case medium = "medium"
    case long = "long"
    case epic = "epic"

    var id: Self { self }
    var label: String {
        switch self {
        case .any: "Any length"
        case .short: "< 2 min"
        case .medium: "2–10 min"
        case .long: "10–30 min"
        case .epic: "> 30 min"
        }
    }
}

enum SearchLicenseFilter: String, CaseIterable, Identifiable {
    case any = ""
    case toListen = "to_listen"
    case toShare = "to_share"
    case toUseCommercially = "to_use_commercially"
    case toModifyCommercially = "to_modify_commercially"

    var id: Self { self }
    var label: String {
        switch self {
        case .any: "Any license"
        case .toListen: "To listen to"
        case .toShare: "To share"
        case .toUseCommercially: "Commercial use"
        case .toModifyCommercially: "Modify commercially"
        }
    }
}

/// Native Search screen with 4 scopes (Tracks, Playlists, Albums, People),
/// live tag/genre facet chips, track-specific filters (Added, Length, License),
/// Play All, shimmering skeletons, and infinite scroll.
struct SearchView: View {
    let query: String
    @Bindable var app: AppController

    @State private var scope: SearchScope = .tracks
    @State private var selectedTag: String?
    @State private var createdFilter: SearchCreatedFilter = .any
    @State private var durationFilter: SearchDurationFilter = .any
    @State private var licenseFilter: SearchLicenseFilter = .any
    @State private var tagFacets: [SCSearchFacet] = []

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

    private var trackFilterKey: String {
        "\(selectedTag ?? "")|\(createdFilter.rawValue)|\(durationFilter.rawValue)|\(licenseFilter.rawValue)"
    }

    private var hasActiveTrackFilters: Bool {
        selectedTag != nil || createdFilter != .any || durationFilter != .any || licenseFilter != .any
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if scope == .tracks {
                    trackFiltersBar
                }
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 92)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: "\(query)|\(scope.rawValue)|\(scope == .tracks ? trackFilterKey : "")") {
            await loadCurrentScope()
        }
        .onChange(of: query) { _, _ in
            resetAll()
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

    private var trackFiltersBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(SearchCreatedFilter.allCases) { option in
                        Button {
                            createdFilter = option
                        } label: {
                            if createdFilter == option {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    filterPillLabel(
                        icon: "calendar",
                        title: createdFilter == .any ? "Added" : createdFilter.label,
                        active: createdFilter != .any
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    ForEach(SearchDurationFilter.allCases) { option in
                        Button {
                            durationFilter = option
                        } label: {
                            if durationFilter == option {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    filterPillLabel(
                        icon: "clock",
                        title: durationFilter == .any ? "Length" : durationFilter.label,
                        active: durationFilter != .any
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    ForEach(SearchLicenseFilter.allCases) { option in
                        Button {
                            licenseFilter = option
                        } label: {
                            if licenseFilter == option {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    filterPillLabel(
                        icon: "doc.text",
                        title: licenseFilter == .any ? "License" : licenseFilter.label,
                        active: licenseFilter != .any
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if hasActiveTrackFilters {
                    Button("Clear filters") {
                        selectedTag = nil
                        createdFilter = .any
                        durationFilter = .any
                        licenseFilter = .any
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                }
                Spacer()
            }

            if !tagFacets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tagFacets.prefix(16)) { facet in
                            let isSelected = selectedTag == facet.value
                            Button {
                                selectedTag = isSelected ? nil : facet.value
                            } label: {
                                Text("#\(facet.value)")
                                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private func filterPillLabel(icon: String, title: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10.5))
            Text(title).font(.system(size: 11.5, weight: active ? .semibold : .medium))
            Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .semibold))
        }
        .foregroundStyle(active ? Color.accentColor : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(active ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.07))
        )
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && (scope == .tracks || !loadedScopes.contains(scope)) && currentIsEmpty {
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
                    Task { await loadCurrentScope(force: true) }
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

    private func resetAll() {
        tracks = []
        playlists = []
        albums = []
        users = []
        tracksNext = nil
        playlistsNext = nil
        albumsNext = nil
        usersNext = nil
        selectedTag = nil
        createdFilter = .any
        durationFilter = .any
        licenseFilter = .any
        tagFacets = []
        loadedScopes = []
        errorMessage = nil
    }

    private func loadCurrentScope(force: Bool = false) async {
        if scope != .tracks, !force, loadedScopes.contains(scope) { return }
        isLoading = true
        errorMessage = nil
        if scope == .tracks { tracks = [] }
        defer { isLoading = false }

        do {
            switch scope {
            case .tracks:
                let page = try await app.api.searchTracks(
                    query: query,
                    genreOrTag: selectedTag,
                    createdAt: createdFilter == .any ? nil : createdFilter.rawValue,
                    duration: durationFilter == .any ? nil : durationFilter.rawValue,
                    license: licenseFilter == .any ? nil : licenseFilter.rawValue
                )
                tracks = page.collection
                tracksNext = page.nextHref
                if tagFacets.isEmpty || selectedTag == nil {
                    let facets = page.genreTags
                    if !facets.isEmpty { tagFacets = facets }
                }
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

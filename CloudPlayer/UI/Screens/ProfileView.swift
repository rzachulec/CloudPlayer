import NukeUI
import SwiftUI

enum ProfileTab: String, CaseIterable, Identifiable {
    case popular = "Popular"
    case tracks = "Tracks"
    case albums = "Albums"
    case playlists = "Playlists"
    case likes = "Likes"

    var id: Self { self }
}

/// Native Artist / User Profile screen with instant stub rendering, optimistic Follow button,
/// and cached tabs (Popular, Tracks, Albums, Playlists, Likes).
struct ProfileView: View {
    let initialUser: SCUser
    @Bindable var app: AppController

    @State private var user: SCUser
    @State private var tab: ProfileTab = .popular
    @State private var popularTracks: [SCTrack] = []
    @State private var allTracks: [SCTrack] = []
    @State private var albums: [SCPlaylist] = []
    @State private var playlists: [SCPlaylist] = []
    @State private var likedTracks: [SCTrack] = []

    @State private var loadedTabs: Set<ProfileTab> = []
    @State private var isLoadingTab = false

    private let gridColumns = [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 18)]

    init(user: SCUser, app: AppController) {
        self.initialUser = user
        self.app = app
        self._user = State(initialValue: user)
    }

    private var isSelf: Bool { app.currentUser?.id == user.id }
    private var isFollowing: Bool { app.library.isFollowing(user.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Picker("Section", selection: $tab) {
                    ForEach(ProfileTab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)

                tabContent
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 96)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: initialUser.id) {
            user = initialUser
            loadedTabs = []
            if let full = try? await app.api.fetchUser(id: initialUser.id) {
                user = full
            }
        }
        .task(id: "\(initialUser.id)|\(tab.rawValue)") {
            await loadTabIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            LazyImage(url: user.avatarURL(size: .large)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Circle().fill(.quaternary)
                        .overlay(Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(.secondary))
                }
            }
            .frame(width: 112, height: 112)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(user.displayName)
                        .font(.system(size: 26, weight: .bold))
                    if user.verified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.tint)
                    }
                }

                let loc = [user.city, user.countryCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                if !loc.isEmpty {
                    Text(loc)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    if let f = user.followersCount {
                        Text("\(formatCompactCount(f)) followers")
                    }
                    if let fg = user.followingsCount {
                        Text("\(formatCompactCount(fg)) following")
                    }
                    if let t = user.trackCount {
                        Text("\(t) tracks")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                if let bio = user.description?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }

                HStack(spacing: 10) {
                    if !isSelf {
                        Button {
                            let willFollow = !isFollowing
                            app.library.toggleFollow(userID: user.id)
                            app.showToast(
                                willFollow ? "Following \(user.displayName)" : "Unfollowed \(user.displayName)",
                                artworkURL: user.avatarURL(size: .small)
                            )
                        } label: {
                            Label(isFollowing ? "Following" : "Follow", systemImage: isFollowing ? "person.fill.checkmark" : "person.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isFollowing ? .secondary : .accentColor)
                    }

                    if let tracks = activeTrackList, !tracks.isEmpty {
                        Button {
                            app.audio.play(track: tracks[0], inContext: tracks, contextTitle: user.displayName)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let url = user.permalinkURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .buttonStyle(.bordered)
                        .help("Open on SoundCloud")
                    }
                }
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    private var activeTrackList: [SCTrack]? {
        switch tab {
        case .popular: popularTracks
        case .tracks: allTracks
        case .likes: likedTracks
        case .albums, .playlists: nil
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if isLoadingTab && !loadedTabs.contains(tab) {
            if tab == .albums || tab == .playlists {
                TileGridSkeleton()
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(0..<10, id: \.self) { _ in TrackRowSkeleton() }
                }
            }
        } else {
            switch tab {
            case .popular:
                trackListView(popularTracks, empty: "No popular tracks yet.")
            case .tracks:
                trackListView(allTracks, empty: "No uploaded tracks yet.")
            case .likes:
                trackListView(likedTracks, empty: "No liked tracks visible.")
            case .albums:
                collectionGrid(albums, empty: "No albums.")
            case .playlists:
                collectionGrid(playlists, empty: "No playlists.")
            }
        }
    }

    @ViewBuilder
    private func trackListView(_ list: [SCTrack], empty: String) -> some View {
        if list.isEmpty {
            Text(empty)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVStack(spacing: 2) {
                ForEach(list) { track in
                    NativeTrackRow(
                        track: track,
                        app: app,
                        mode: .compact,
                        onPlay: {
                            app.audio.play(track: track, inContext: list, contextTitle: user.displayName)
                        },
                        onArtistTap: { artist in
                            if artist.id != user.id {
                                app.router.navigate(to: .user(artist))
                            }
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func collectionGrid(_ list: [SCPlaylist], empty: String) -> some View {
        if list.isEmpty {
            Text(empty)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(list, id: \.stableID) { pl in
                    PlaylistCard(playlist: pl, app: app)
                }
            }
        }
    }

    private func loadTabIfNeeded() async {
        guard !loadedTabs.contains(tab) else { return }
        isLoadingTab = true
        defer { isLoadingTab = false }

        switch tab {
        case .popular:
            popularTracks = (try? await app.api.fetchUserTopTracks(userID: user.id)) ?? []
        case .tracks:
            allTracks = (try? await app.api.fetchUserTracks(userID: user.id).collection) ?? []
        case .albums:
            albums = (try? await app.api.fetchUserAlbums(userID: user.id).collection) ?? []
        case .playlists:
            playlists = (try? await app.api.fetchUserOwnPlaylists(userID: user.id)) ?? []
        case .likes:
            let page = try? await app.api.fetchTrackLikes(userID: user.id, limit: 50)
            likedTracks = page?.collection.compactMap(\.track) ?? []
        }
        loadedTabs.insert(tab)
    }
}

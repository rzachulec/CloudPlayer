import AppKit
import NukeUI
import SwiftUI

enum ProfileDrilldownSection: String, Identifiable {
    case popular = "Popular Tracks"
    case tracks = "Tracks"
    case albums = "Albums"
    case playlists = "Playlists"
    case likes = "Likes"

    var id: Self { self }
}

/// Apple Music–style native Artist / User Profile:
/// - Full-width banner hero card (artist's SoundCloud banner visual or blurred avatar fallback)
/// - Overview with curated vertical shelves and `"Title ›"` drill-downs (no underline tab bar)
/// - Drill-down sub-pages with `"‹ Artist · Section"` back header.
struct ProfileView: View {
    let initialUser: SCUser
    @Bindable var app: AppController

    @State private var user: SCUser
    @State private var drilldown: ProfileDrilldownSection?
    @State private var popularTracks: [SCTrack] = []
    @State private var allTracks: [SCTrack] = []
    @State private var albums: [SCPlaylist] = []
    @State private var playlists: [SCPlaylist] = []
    @State private var likedTracks: [SCTrack] = []
    @State private var isLoading = false

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
            VStack(alignment: .leading, spacing: 24) {
                if let section = drilldown {
                    drilldownView(section)
                } else {
                    bannerHero
                    overviewShelves
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 96)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: initialUser.id) {
            user = initialUser
            drilldown = nil
            await loadOverview()
        }
    }

    // MARK: - Banner Hero

    private var bannerHero: some View {
        HStack(alignment: .bottom, spacing: 20) {
            LazyImage(url: user.avatarURL(size: .large)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Circle().fill(.quaternary)
                        .overlay(Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(.secondary))
                }
            }
            .frame(width: 118, height: 118)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(user.displayName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if user.verified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                }

                let loc = [user.city, user.countryCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                HStack(spacing: 12) {
                    if !loc.isEmpty { Text(loc) }
                    if let f = user.followersCount { Text("\(formatCompactCount(f)) followers") }
                    if let fg = user.followingsCount { Text("\(formatCompactCount(fg)) following") }
                    if let t = user.trackCount { Text("\(t) tracks") }
                }
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.82))

                if let bio = user.description?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                        .padding(.top, 1)
                }

                HStack(spacing: 8) {
                    let playList = popularTracks.isEmpty ? allTracks : popularTracks
                    if !playList.isEmpty {
                        Button {
                            app.audio.play(track: playList[0], inContext: playList, contextTitle: user.displayName)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if !isSelf {
                        Button {
                            let willFollow = !isFollowing
                            app.library.toggleFollow(userID: user.id)
                            app.showToast(
                                willFollow ? "Following \(user.displayName)" : "Unfollowed \(user.displayName)",
                                artworkURL: user.avatarURL(size: .small)
                            )
                        } label: {
                            Label(
                                isFollowing ? "Following" : "Follow",
                                systemImage: isFollowing ? "person.fill.checkmark" : "person.badge.plus"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }

                    if let url = user.permalinkURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .help("Open on SoundCloud")
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(minHeight: 205, alignment: .bottomLeading)
        .background {
            if let banner = user.bannerURL {
                LazyImage(url: banner) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        blurredAvatarBackdrop
                    }
                }
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.18), .black.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            } else {
                blurredAvatarBackdrop
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private var blurredAvatarBackdrop: some View {
        LazyImage(url: user.avatarURL(size: .large)) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.accentColor.opacity(0.3)
            }
        }
        .blur(radius: 44)
        .scaleEffect(1.3)
        .overlay(
            LinearGradient(
                colors: [.black.opacity(0.28), .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Curated Overview Shelves

    @ViewBuilder
    private var overviewShelves: some View {
        if isLoading && popularTracks.isEmpty && allTracks.isEmpty && albums.isEmpty && playlists.isEmpty {
            LazyVStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { _ in TrackRowSkeleton() }
            }
        } else {
            if !popularTracks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(.popular, count: popularTracks.count)
                    LazyVStack(spacing: 2) {
                        ForEach(popularTracks.prefix(5)) { track in
                            trackRow(track, context: popularTracks)
                        }
                    }
                }
            }

            if !albums.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(.albums, count: albums.count)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(albums.prefix(12), id: \.stableID) { album in
                                PlaylistCard(playlist: album, app: app, fixedSize: 168)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !allTracks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(.tracks, count: allTracks.count)
                    LazyVStack(spacing: 2) {
                        ForEach(allTracks.prefix(5)) { track in
                            trackRow(track, context: allTracks)
                        }
                    }
                }
            }

            if !playlists.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(.playlists, count: playlists.count)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(playlists.prefix(12), id: \.stableID) { pl in
                                PlaylistCard(playlist: pl, app: app, fixedSize: 168)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !likedTracks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(.likes, count: likedTracks.count)
                    LazyVStack(spacing: 2) {
                        ForEach(likedTracks.prefix(5)) { track in
                            trackRow(track, context: likedTracks)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ section: ProfileDrilldownSection, count: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { drilldown = section }
        } label: {
            HStack(spacing: 5) {
                Text(section.rawValue)
                    .font(.system(size: 18, weight: .bold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if count > 5 {
                    Text("See All")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drill-Down Sub-Page

    @ViewBuilder
    private func drilldownView(_ section: ProfileDrilldownSection) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { drilldown = nil }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(user.displayName)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Text("·").foregroundStyle(.tertiary)

            Text(section.rawValue)
                .font(.system(size: 20, weight: .bold))

            Spacer()

            if let list = tracksFor(section), !list.isEmpty {
                Button {
                    app.audio.play(track: list[0], inContext: list, contextTitle: "\(user.displayName) — \(section.rawValue)")
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    app.audio.playShuffled(tracks: list, contextTitle: "\(user.displayName) — \(section.rawValue)")
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }

        switch section {
        case .popular:
            LazyVStack(spacing: 2) {
                ForEach(popularTracks) { trackRow($0, context: popularTracks) }
            }
        case .tracks:
            LazyVStack(spacing: 2) {
                ForEach(allTracks) { trackRow($0, context: allTracks) }
            }
        case .likes:
            LazyVStack(spacing: 2) {
                ForEach(likedTracks) { trackRow($0, context: likedTracks) }
            }
        case .albums:
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(albums, id: \.stableID) { PlaylistCard(playlist: $0, app: app) }
            }
        case .playlists:
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(playlists, id: \.stableID) { PlaylistCard(playlist: $0, app: app) }
            }
        }
    }

    private func tracksFor(_ section: ProfileDrilldownSection) -> [SCTrack]? {
        switch section {
        case .popular: popularTracks
        case .tracks: allTracks
        case .likes: likedTracks
        case .albums, .playlists: nil
        }
    }

    private func trackRow(_ track: SCTrack, context: [SCTrack]) -> some View {
        NativeTrackRow(
            track: track,
            app: app,
            mode: .compact,
            onPlay: {
                app.audio.play(track: track, inContext: context, contextTitle: user.displayName)
            },
            onArtistTap: { artist in
                if artist.id != user.id {
                    app.router.navigate(to: .user(artist))
                }
            }
        )
    }

    // MARK: - Parallel Overview Loading

    private func loadOverview() async {
        isLoading = true
        defer { isLoading = false }

        let uid = initialUser.id
        async let userTask = app.api.fetchUser(id: uid)
        async let popularTask = app.api.fetchUserTopTracks(userID: uid, limit: 30)
        async let tracksTask = app.api.fetchUserTracks(userID: uid, limit: 40)
        async let albumsTask = app.api.fetchUserAlbums(userID: uid, limit: 30)
        async let playlistsTask = app.api.fetchUserOwnPlaylists(userID: uid, limit: 30)
        async let likesTask = app.api.fetchTrackLikes(userID: uid, limit: 30)

        if let full = try? await userTask { user = full }
        if let pop = try? await popularTask { popularTracks = pop }
        if let tr = try? await tracksTask { allTracks = tr.collection }
        if let alb = try? await albumsTask { albums = alb.collection }
        if let pls = try? await playlistsTask { playlists = pls }
        if let lk = try? await likesTask { likedTracks = lk.collection.compactMap(\.track) }
    }
}

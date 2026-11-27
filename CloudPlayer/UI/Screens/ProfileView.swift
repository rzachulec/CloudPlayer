import AppKit
import NukeUI
import SwiftUI

enum ProfileDrilldownSection: String, Identifiable {
    case popular = "Popular Tracks"
    case tracks = "Tracks"
    case albums = "Albums"
    case playlists = "Playlists"
    case reposts = "Reposts"
    case likes = "Likes"
    case following = "Following"
    case followers = "Followers"

    var id: Self { self }
}

/// Apple Music–style native Artist / User Profile:
/// - Full-width banner hero card with clickable stat pills (Followers, Following, Likes, Tracks, Playlists)
/// - Curated vertical overview shelves (`Popular Tracks ›`, `Albums ›`, `Tracks ›`, `Playlists ›`,
///   `Reposts ›`, `Likes ›`, `Following ›`, `Followers ›`)
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
    @State private var repostTracks: [SCTrack] = []
    @State private var likedTracks: [SCTrack] = []
    @State private var followingUsers: [SCUser] = []
    @State private var followerUsers: [SCUser] = []
    @State private var isLoading = false

    private let gridColumns = [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 18)]
    private let userGridColumns = [GridItem(.adaptive(minimum: 155, maximum: 205), spacing: 16)]

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

            VStack(alignment: .leading, spacing: 6) {
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
                if !loc.isEmpty {
                    Text(loc)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                }

                if let bio = user.description?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                }

                // Clickable stat pills (Followers, Following, Likes, Tracks, Playlists)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        if let f = user.followersCount {
                            statPill(icon: "person.fill", label: "\(formatCompactCount(f)) Followers", section: .followers)
                        }
                        if let fg = user.followingsCount {
                            statPill(icon: "person.2.fill", label: "\(formatCompactCount(fg)) Following", section: .following)
                        }
                        if let lk = user.likesCount, lk > 0 {
                            statPill(icon: "heart.fill", label: "\(formatCompactCount(lk)) Likes", section: .likes)
                        }
                        if let t = user.trackCount, t > 0 {
                            statPill(icon: "waveform", label: "\(t) Tracks", section: .tracks)
                        }
                        if let pl = user.playlistCount, pl > 0 {
                            statPill(icon: "music.note.list", label: "\(pl) Playlists", section: .playlists)
                        }
                        if !repostTracks.isEmpty {
                            statPill(icon: "arrow.2.squarepath", label: "\(repostTracks.count) Reposts", section: .reposts)
                        }
                    }
                }
                .padding(.top, 2)

                HStack(spacing: 8) {
                    let playList = popularTracks.isEmpty ? (allTracks.isEmpty ? likedTracks : allTracks) : popularTracks
                    if !playList.isEmpty {
                        Button {
                            app.audio.play(track: playList[0], inContext: playList, contextTitle: user.displayName)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .liquidGlassButton(prominent: true)
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
                        .liquidGlassButton()
                        .tint(.white)
                    }

                    if let url = user.permalinkURL {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .liquidGlassButton()
                        .tint(.white)

                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .liquidGlassButton()
                        .tint(.white)
                        .help("Open on SoundCloud")
                    }
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(minHeight: 215, alignment: .bottomLeading)
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
                        colors: [.black.opacity(0.18), .black.opacity(0.75)],
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

    private func statPill(icon: String, label: String, section: ProfileDrilldownSection) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { drilldown = section }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.white.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
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
                colors: [.black.opacity(0.28), .black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Curated Overview Shelves

    @ViewBuilder
    private var overviewShelves: some View {
        if isLoading && popularTracks.isEmpty && allTracks.isEmpty && albums.isEmpty && playlists.isEmpty && likedTracks.isEmpty {
            LazyVStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { _ in TrackRowSkeleton() }
            }
        } else {
            if !popularTracks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(.popular, count: popularTracks.count)
                    LazyVStack(spacing: 2) {
                        ForEach(popularTracks.prefix(5)) { trackRow($0, context: popularTracks) }
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
                        ForEach(allTracks.prefix(5)) { trackRow($0, context: allTracks) }
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

            if !repostTracks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(.reposts, count: repostTracks.count)
                    LazyVStack(spacing: 2) {
                        ForEach(repostTracks.prefix(5)) { trackRow($0, context: repostTracks) }
                    }
                }
            }

            if !likedTracks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(.likes, count: user.likesCount ?? likedTracks.count)
                    LazyVStack(spacing: 2) {
                        ForEach(likedTracks.prefix(5)) { trackRow($0, context: likedTracks) }
                    }
                }
            }

            if !followingUsers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(.following, count: user.followingsCount ?? followingUsers.count)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(followingUsers.prefix(12)) { artist in
                                UserCard(user: artist) {
                                    app.router.navigate(to: .user(artist))
                                }
                                .frame(width: 152)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !followerUsers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(.followers, count: user.followersCount ?? followerUsers.count)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(followerUsers.prefix(12)) { follower in
                                UserCard(user: follower) {
                                    app.router.navigate(to: .user(follower))
                                }
                                .frame(width: 152)
                            }
                        }
                        .padding(.vertical, 2)
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
                .liquidGlassButton(prominent: true)

                Button {
                    app.audio.playShuffled(tracks: list, contextTitle: "\(user.displayName) — \(section.rawValue)")
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .liquidGlassButton()
            }
        }

        switch section {
        case .popular:
            LazyVStack(spacing: 2) { ForEach(popularTracks) { trackRow($0, context: popularTracks) } }
        case .tracks:
            LazyVStack(spacing: 2) { ForEach(allTracks) { trackRow($0, context: allTracks) } }
        case .reposts:
            LazyVStack(spacing: 2) { ForEach(repostTracks) { trackRow($0, context: repostTracks) } }
        case .likes:
            LazyVStack(spacing: 2) { ForEach(likedTracks) { trackRow($0, context: likedTracks) } }
        case .albums:
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(albums, id: \.stableID) { PlaylistCard(playlist: $0, app: app) }
            }
        case .playlists:
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(playlists, id: \.stableID) { PlaylistCard(playlist: $0, app: app) }
            }
        case .following:
            LazyVGrid(columns: userGridColumns, spacing: 18) {
                ForEach(followingUsers) { artist in
                    UserCard(user: artist) { app.router.navigate(to: .user(artist)) }
                }
            }
        case .followers:
            LazyVGrid(columns: userGridColumns, spacing: 18) {
                ForEach(followerUsers) { follower in
                    UserCard(user: follower) { app.router.navigate(to: .user(follower)) }
                }
            }
        }
    }

    private func tracksFor(_ section: ProfileDrilldownSection) -> [SCTrack]? {
        switch section {
        case .popular: popularTracks
        case .tracks: allTracks
        case .reposts: repostTracks
        case .likes: likedTracks
        case .albums, .playlists, .following, .followers: nil
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
        async let repostsTask = app.api.fetchUserReposts(userID: uid, limit: 30)
        async let likesTask = app.api.fetchTrackLikes(userID: uid, limit: 40)
        async let followingTask = app.api.fetchUserFollowings(userID: uid, limit: 40)
        async let followersTask = app.api.fetchUserFollowers(userID: uid, limit: 40)

        if let full = try? await userTask { user = full }
        if let pop = try? await popularTask { popularTracks = pop }
        if let tr = try? await tracksTask { allTracks = tr.collection }
        if let alb = try? await albumsTask { albums = alb.collection }
        if let pls = try? await playlistsTask { playlists = pls }
        if let rep = try? await repostsTask { repostTracks = rep.collection.compactMap(\.track) }
        if let lk = try? await likesTask { likedTracks = lk.collection.compactMap(\.track) }
        if let fg = try? await followingTask { followingUsers = fg.collection }
        if let fl = try? await followersTask { followerUsers = fl.collection }
    }
}

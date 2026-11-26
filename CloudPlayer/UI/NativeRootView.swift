import NukeUI
import SwiftUI

/// Native root view:
/// - Signed out → DisposableSignInView (the only place WebKit ever exists).
/// - Signed in → 100% pure SwiftUI native shell (WebKit is torn down and deallocated).
struct NativeRootView: View {
    @Bindable var app: AppController
    var onMini: () -> Void
    var onSignOut: () -> Void

    var body: some View {
        switch app.sessionStore.state {
        case .unknown:
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()
                .frame(minWidth: DisposableSignInView.minWidth, minHeight: DisposableSignInView.minHeight)
        case .signedOut:
            DisposableSignInView { session in
                app.handleAuthenticated(session)
            }
        case .signedIn:
            Milestone2PlayerShell(app: app, onMini: onMini, onSignOut: onSignOut)
        }
    }
}

/// Milestone 2 shell: real Likes feed fetched via pure-Swift `SoundCloudAPI`,
/// playable through `AudioEngine` (`AVPlayer`), with floating Liquid Glass `NativePlayerBar`.
private struct Milestone2PlayerShell: View {
    @Bindable var app: AppController
    var onMini: () -> Void
    var onSignOut: () -> Void

    @State private var tracks: [SCTrack] = []
    @State private var nextHref: String?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    header
                    Divider()
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if app.audio.queueVisible {
                    Divider()
                    quickQueueSidebar
                        .frame(width: 320)
                        .transition(.move(edge: .trailing))
                }
            }

            VStack(spacing: 8) {
                if let err = app.audio.errorMessage {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.red.opacity(0.85), in: Capsule())
                }
                NativePlayerBar(app: app, onMini: onMini)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
            .padding(.trailing, app.audio.queueVisible ? 320 : 0)
            .animation(.easeOut(duration: 0.22), value: app.audio.queueVisible)
        }
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
        .task(id: app.currentUser?.id) {
            await loadInitialLikes()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Likes")
                    .font(.system(size: 22, weight: .bold))
                if let user = app.currentUser {
                    Text("\(user.displayName) · \(user.likesCount ?? tracks.count) liked tracks · Zero WebKit")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !tracks.isEmpty {
                Button {
                    if let first = tracks.first {
                        app.audio.play(track: first, inContext: tracks, contextTitle: "Likes")
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    app.audio.playShuffled(tracks: tracks, contextTitle: "Likes")
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Menu {
                Button("Refresh") { Task { await loadInitialLikes(force: true) } }
                Divider()
                Button("Sign Out…", role: .destructive, action: onSignOut)
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 16))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && tracks.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading your liked tracks…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, tracks.isEmpty {
            VStack(spacing: 10) {
                Text(loadError)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button("Retry") { Task { await loadInitialLikes(force: true) } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(tracks) { track in
                        let isCurrent = app.audio.currentTrack?.id == track.id
                        trackRow(track, isCurrent: isCurrent)
                            .onAppear {
                                if track.id == tracks.last?.id, nextHref != nil {
                                    Task { await loadMoreLikes() }
                                }
                            }
                    }
                    if isLoading && !tracks.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 84)
            }
        }
    }

    private func trackRow(_ track: SCTrack, isCurrent: Bool) -> some View {
        let liked = app.library.isLiked(track.id)
        return HStack(spacing: 12) {
            ZStack {
                CachedArtwork(url: track.resolvedArtworkURL(size: .small), size: 42, cornerRadius: 5)
                if isCurrent {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.black.opacity(0.45))
                        .frame(width: 42, height: 42)
                    Image(systemName: app.audio.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    if track.isPreviewOnly {
                        Text("Go+")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.2), in: Capsule())
                    }
                }
                Text(track.artistName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(formatTime(track.durationSeconds))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            IconButton(symbol: liked ? "heart.fill" : "heart", size: 12, active: liked, help: liked ? "Unlike" : "Like") {
                app.library.toggleLike(trackID: track.id, userID: app.currentUser?.id)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            app.audio.play(track: track, inContext: tracks, contextTitle: "Likes")
        }
        .contextMenu {
            Button("Play") { app.audio.play(track: track, inContext: tracks, contextTitle: "Likes") }
            Button("Play Next") { app.audio.enqueueNext(track) }
            Button("Add to Up Next") { app.audio.enqueueLater(track) }
            Divider()
            Button(liked ? "Unlike" : "Like") {
                app.library.toggleLike(trackID: track.id, userID: app.currentUser?.id)
            }
        }
    }

    private var quickQueueSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if app.audio.queue.upcomingCount > 0 {
                    Button("Clear") { app.audio.clearUpcoming() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
            .padding(14)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if !app.audio.queue.userUpNext.isEmpty {
                        Text("Queued")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                        ForEach(app.audio.queue.userUpNext) { t in
                            queueRow(t)
                        }
                    }
                    if !app.audio.queue.contextQueue.isEmpty {
                        Text("From \(app.audio.queue.contextTitle ?? "Queue")")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                        ForEach(app.audio.queue.contextQueue.prefix(40)) { t in
                            queueRow(t)
                        }
                    }
                    if app.audio.queue.userUpNext.isEmpty && app.audio.queue.contextQueue.isEmpty {
                        Text("Nothing queued up.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .background(.background)
    }

    private func queueRow(_ track: SCTrack) -> some View {
        HStack(spacing: 8) {
            CachedArtwork(url: track.resolvedArtworkURL(size: .small), size: 32, cornerRadius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(track.artistName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            app.audio.play(track: track, inContext: tracks, contextTitle: app.audio.queue.contextTitle)
        }
    }

    private func loadInitialLikes(force: Bool = false) async {
        guard let uid = app.currentUser?.id else { return }
        if !force && !tracks.isEmpty { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let page = try await app.api.fetchTrackLikes(userID: uid, limit: 50)
            let fetched = page.collection.compactMap(\.track)
            tracks = fetched
            nextHref = page.nextHref
            app.library.registerLikedTracks(fetched)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadMoreLikes() async {
        guard let uid = app.currentUser?.id, let next = nextHref, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await app.api.fetchTrackLikes(userID: uid, nextHref: next)
            let fetched = page.collection.compactMap(\.track)
            let existing = Set(tracks.map(\.id))
            let unique = fetched.filter { !existing.contains($0.id) }
            tracks.append(contentsOf: unique)
            nextHref = page.nextHref
            app.library.registerLikedTracks(unique)
        } catch {
            // Keep existing list on pagination error
        }
    }
}

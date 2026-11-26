import SwiftUI

/// Native Home / Discover screen backed by `/mixed-selections` with stale-while-revalidate caching,
/// shimmering carousel skeletons, and instant click-to-play playlist cards.
struct HomeView: View {
    @Bindable var app: AppController

    @State private var selections: [SCMixedSelection] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private static let hiddenPrefixes = [
        "events near you",
        "grab the keys",
    ]

    private var visibleSelections: [SCMixedSelection] {
        selections.filter { sel in
            guard let items = sel.items?.collection, !items.isEmpty else { return false }
            let lower = sel.title.lowercased()
            return !Self.hiddenPrefixes.contains { lower.hasPrefix($0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Home")
                    .font(.system(size: 24, weight: .bold))
                Text("Discover mixes, playlists, and recommendations")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await refreshFromNetwork() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isLoading)
            .help("Refresh Home")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && selections.isEmpty {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(0..<3, id: \.self) { _ in
                    carouselSkeleton
                }
            }
        } else if let errorMessage, visibleSelections.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button("Retry") { Task { await refreshFromNetwork() } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(visibleSelections) { selection in
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selection.title)
                                .font(.system(size: 17, weight: .bold))
                            if let desc = selection.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(selection.items?.collection ?? [], id: \.stableID) { playlist in
                                    PlaylistCard(playlist: playlist, app: app)
                                        .frame(width: 174)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private var carouselSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 210, height: 18)
                .shimmering()
            HStack(spacing: 16) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.quaternary)
                            .frame(width: 174, height: 174)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .frame(width: 130, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary.opacity(0.7))
                            .frame(width: 86, height: 10)
                    }
                    .shimmering()
                }
            }
        }
    }

    // MARK: - Stale-While-Revalidate

    private var cacheKey: String {
        "home:mixed:\(app.currentUser?.id ?? 0):v1"
    }

    private func loadStaleWhileRevalidate() async {
        if selections.isEmpty,
           let cached = await app.cache.load([SCMixedSelection].self, key: cacheKey),
           !cached.isEmpty {
            selections = cached
        }
        await refreshFromNetwork()
    }

    private func refreshFromNetwork() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await app.api.fetchMixedSelections(limit: 12)
            selections = fetched
            await app.cache.save(fetched, key: cacheKey)
        } catch {
            if selections.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Reusable square card for Playlists, Albums, and Home Mixes with instant Liquid Glass Play button.
struct PlaylistCard: View {
    let playlist: SCPlaylist
    @Bindable var app: AppController

    @State private var isHovered = false
    @State private var isStartingPlayback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                let side = geo.size.width
                ZStack {
                    CachedArtwork(url: playlist.resolvedArtworkURL(size: .large), size: side, cornerRadius: 10)

                    if isHovered || isStartingPlayback {
                        Button(action: playNow) {
                            Group {
                                if isStartingPlayback {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .offset(x: 1.5)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .modifier(CardPlayGlass())
                        .scaleEffect(isHovered ? 1.04 : 0.96)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(playlist.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(duration: 0.22, bounce: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            app.router.navigate(to: .playlist(playlist))
        }
        .contextMenu {
            Button("Play", systemImage: "play.fill", action: playNow)
            Button("Open", systemImage: "music.note.list") {
                app.router.navigate(to: .playlist(playlist))
            }
            if let url = playlist.permalinkURL {
                Divider()
                Button("Copy Link", systemImage: "link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                Button("Open on SoundCloud", systemImage: "safari") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func playNow() {
        guard !isStartingPlayback else { return }
        let ready = playlist.hydratedTracks
        if let first = ready.first, playlist.missingTrackIDs.isEmpty {
            app.audio.play(track: first, inContext: ready, contextTitle: playlist.title)
            return
        }
        isStartingPlayback = true
        Task {
            defer { isStartingPlayback = false }
            if let resolved = try? await app.api.resolveTracks(for: playlist), let first = resolved.first {
                app.audio.play(track: first, inContext: resolved, contextTitle: playlist.title)
            }
        }
    }
}

private struct CardPlayGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        }
    }
}

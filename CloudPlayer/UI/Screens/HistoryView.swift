import SwiftUI

/// Native Listening History screen backed by `/me/play-history/tracks`.
struct HistoryView: View {
    @Bindable var app: AppController

    @AppStorage("cp.viewMode.history") private var viewModeRaw: String = TrackListDisplayMode.compact.rawValue
    @State private var tracks: [SCTrack] = []
    @State private var nextHref: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    private var viewMode: TrackListDisplayMode {
        TrackListDisplayMode(rawValue: viewModeRaw) ?? .compact
    }

    private var displayedTracks: [SCTrack] {
        deduplicate(app.sessionHistory + tracks)
    }

    private let tileColumns = [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("History")
                    .font(.system(size: 24, weight: .bold))
                Text("Recently played tracks")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            LiquidIconPicker(
                options: TrackListDisplayMode.allCases,
                selection: Binding(
                    get: { viewMode },
                    set: { viewModeRaw = $0.rawValue }
                ),
                symbol: \.symbol,
                label: \.label
            )

            if !displayedTracks.isEmpty {
                Button {
                    if let first = displayedTracks.first {
                        app.audio.play(track: first, inContext: displayedTracks, contextTitle: "History")
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .liquidGlassButton(prominent: true)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && displayedTracks.isEmpty {
            if viewMode == .tiles {
                TileGridSkeleton()
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(0..<14, id: \.self) { _ in
                        TrackRowSkeleton(waveformMode: viewMode == .waveform)
                    }
                }
            }
        } else if let errorMessage, displayedTracks.isEmpty {
            VStack(spacing: 10) {
                Text(errorMessage).font(.system(size: 13)).foregroundStyle(.secondary)
                Button("Retry") { Task { await refreshFromNetwork() } }.liquidGlassButton(prominent: true)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        } else if displayedTracks.isEmpty {
            Text("No listening history yet.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            switch viewMode {
            case .tiles:
                LazyVGrid(columns: tileColumns, spacing: 20) {
                    ForEach(displayedTracks) { track in
                        NativeMediaTile(track: track, app: app) {
                            app.audio.play(track: track, inContext: displayedTracks, contextTitle: "History")
                        }
                        .onAppear { maybeLoadMore(currentTrack: track) }
                    }
                }
            case .compact, .waveform:
                LazyVStack(spacing: viewMode == .waveform ? 4 : 2) {
                    ForEach(displayedTracks) { track in
                        NativeTrackRow(
                            track: track,
                            app: app,
                            mode: viewMode,
                            onPlay: {
                                app.audio.play(track: track, inContext: displayedTracks, contextTitle: "History")
                            },
                            onArtistTap: { user in
                                app.router.navigate(to: .user(user))
                            }
                        )
                        .onAppear { maybeLoadMore(currentTrack: track) }
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

    private var cacheKey: String {
        "history:\(app.currentUser?.id ?? 0):v1"
    }

    private func loadStaleWhileRevalidate() async {
        if tracks.isEmpty, let cached = await app.cache.load([SCTrack].self, key: cacheKey), !cached.isEmpty {
            tracks = cached
        }
        await refreshFromNetwork()
    }

    private func refreshFromNetwork() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await app.api.fetchPlayHistory(limit: 50)
            let fetched = deduplicate(page.collection.compactMap(\.track))
            tracks = fetched
            nextHref = page.nextHref
            await app.cache.save(fetched, key: cacheKey)
        } catch {
            if tracks.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func maybeLoadMore(currentTrack: SCTrack) {
        guard let nextHref, !isLoadingMore,
              let idx = tracks.firstIndex(where: { $0.id == currentTrack.id }),
              idx >= tracks.count - 8 else { return }

        Task {
            isLoadingMore = true
            defer { isLoadingMore = false }
            if let page = try? await app.api.fetchPlayHistory(nextHref: nextHref) {
                let existing = Set(tracks.map(\.id))
                let unique = deduplicate(page.collection.compactMap(\.track)).filter { !existing.contains($0.id) }
                tracks.append(contentsOf: unique)
                self.nextHref = page.nextHref
            }
        }
    }

    private func deduplicate(_ items: [SCTrack]) -> [SCTrack] {
        var seen = Set<Int>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

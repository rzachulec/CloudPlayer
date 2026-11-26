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
            NativeMainShell(app: app, onMini: onMini, onSignOut: onSignOut)
        }
    }
}

private struct NativeMainShell: View {
    @Bindable var app: AppController
    var onMini: () -> Void
    var onSignOut: () -> Void

    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        let sidebarBinding = Binding<NativeSidebarItem?>(
            get: { app.router.selectedSidebar },
            set: { item in
                if let item { app.router.selectSidebar(item) }
            }
        )

        NavigationSplitView(columnVisibility: $columns) {
            List(selection: sidebarBinding) {
                Section {
                    Label(NativeSidebarItem.home.title, systemImage: NativeSidebarItem.home.symbol)
                        .tag(NativeSidebarItem.home)
                }
                Section("Library") {
                    ForEach(NativeSidebarItem.library) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) {
                if let toast = app.toast {
                    NativeToastView(toast: toast) { app.toast = nil }
                        .padding(10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.32), value: app.toast)
        } detail: {
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    routeView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if app.audio.queueVisible {
                        Divider()
                        UpNextSidebar(app: app)
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
            .frame(minWidth: 520, minHeight: 500)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: toggleSidebar) {
                        Label("Toggle Sidebar", systemImage: "sidebar.left")
                    }
                    .help("Show or Hide Sidebar (⌃⌘S)")
                }
                ToolbarItemGroup(placement: .navigation) {
                    Button { app.router.goBack() } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .disabled(!app.router.canGoBack)
                    .help("Back (⌘[)")

                    Button { app.router.goForward() } label: {
                        Label("Forward", systemImage: "chevron.right")
                    }
                    .disabled(!app.router.canGoForward)
                    .help("Forward (⌘])")
                }
                ToolbarItem(placement: .principal) {
                    ToolbarSearchField(prompt: "Search SoundCloud") { query in
                        app.router.search(query)
                    }
                    .frame(width: 340)
                }
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.flexible)
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        if let user = app.currentUser {
                            Text(user.displayName)
                            Divider()
                            Button("Profile") { app.router.navigate(to: .user(user)) }
                        }
                        if let url = URL(string: "https://soundcloud.com/settings") {
                            Button("SoundCloud Settings (Browser)") { NSWorkspace.shared.open(url) }
                        }
                        Divider()
                        Button("Sign Out…", role: .destructive, action: onSignOut)
                    } label: {
                        Label("Account", systemImage: "person.crop.circle")
                    }
                    .menuIndicator(.hidden)
                    .help("Account")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cpToggleSidebar)) { _ in
            toggleSidebar()
        }
    }

    @ViewBuilder
    private var routeView: some View {
        switch app.router.current {
        case .likes:
            LikesView(app: app)
        case .home:
            MilestonePlaceholderView(title: "Home", symbol: "house", milestone: "Milestone 4")
        case .history:
            MilestonePlaceholderView(title: "History", symbol: "clock", milestone: "Milestone 4")
        case .playlists:
            MilestonePlaceholderView(title: "Playlists", symbol: "music.note.list", milestone: "Milestone 5")
        case .albums:
            MilestonePlaceholderView(title: "Albums", symbol: "square.stack", milestone: "Milestone 5")
        case .stations:
            MilestonePlaceholderView(title: "Stations", symbol: "dot.radiowaves.left.and.right", milestone: "Milestone 5")
        case .following:
            MilestonePlaceholderView(title: "Following", symbol: "person.2", milestone: "Milestone 5")
        case .search(let query):
            MilestonePlaceholderView(title: "Search: “\(query)”", symbol: "magnifyingglass", milestone: "Milestone 5")
        case .track(let track):
            MilestonePlaceholderView(title: track.title, symbol: "waveform", milestone: "Milestone 6")
        case .user(let user):
            MilestonePlaceholderView(title: user.displayName, symbol: "person.crop.circle", milestone: "Milestone 6")
        }
    }

    private func toggleSidebar() {
        withAnimation {
            columns = columns == .detailOnly ? .all : .detailOnly
        }
    }
}

private struct MilestonePlaceholderView: View {
    let title: String
    let symbol: String
    let milestone: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            Text("Scheduled for \(milestone)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct UpNextSidebar: View {
    @Bindable var app: AppController

    var body: some View {
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
                        ForEach(app.audio.queue.contextQueue.prefix(50)) { t in
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
            app.audio.play(track: track, inContext: app.audio.queue.contextQueue, contextTitle: app.audio.queue.contextTitle)
        }
    }
}

private struct NativeToastView: View {
    let toast: NativeToast
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let url = toast.artworkURL {
                CachedArtwork(url: url, size: 34, cornerRadius: 6)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.tint)
            }
            Text(toast.text)
                .font(.system(size: 12))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .modifier(NativeToastGlass())
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
    }
}

private struct NativeToastGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        }
    }
}

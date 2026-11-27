import AppKit
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

    @AppStorage("cp.followNowPlaying") private var followNowPlaying = true
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var preQueueWindowWidth: (original: CGFloat, expanded: CGFloat)?

    var body: some View {
        let sidebarBinding = Binding<NativeSidebarItem?>(
            get: { app.router.selectedSidebar },
            set: { item in
                if let item { app.router.selectSidebar(item) }
            }
        )

        ZStack {
            NavigationSplitView(columnVisibility: $columns) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
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

                    if let toast = app.toast {
                        NativeToastView(toast: toast) { app.toast = nil }
                            .padding(10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(10)
                    }
                }
                .animation(.spring(duration: 0.32), value: app.toast)

                Divider()
                    .opacity(0.45)

                SidebarProfileFooter(app: app, onSignOut: onSignOut)
            }
            .navigationSplitViewColumnWidth(min: 145, ideal: 165, max: 220)
        } detail: {
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    routeView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if app.audio.queueVisible {
                        Divider()
                        QueueDrawerView(app: app)
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
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .padding(.trailing, app.audio.queueVisible ? 320 : 0)
                .animation(.easeOut(duration: 0.22), value: app.audio.queueVisible)
            }
            .frame(minWidth: app.audio.queueVisible ? 880 : 560, minHeight: 440)
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
                    .frame(minWidth: 160, idealWidth: 260, maxWidth: 340)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cpToggleSidebar)) { _ in
            toggleSidebar()
        }
        .onChange(of: app.audio.currentTrack) { oldTrack, newTrack in
            app.prefetchAdjacentTracks()
            if app.isFocusMode, let newTrack {
                app.focusTrack = newTrack
            }
            guard followNowPlaying,
                  let newTrack,
                  case .track(let viewingTrack) = app.router.current,
                  viewingTrack.id != newTrack.id,
                  oldTrack?.id == viewingTrack.id else { return }
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.44)) {
                app.router.replaceCurrent(with: .track(newTrack))
            }
        }
        .onChange(of: app.audio.queueVisible) { _, visible in
            adjustWindowForQueue(visible: visible)
        }
        }
        .coordinateSpace(name: "cpRootWindow")
    }

    @ViewBuilder
    private var routeView: some View {
        switch app.router.current {
        case .home:
            HomeView(app: app)
        case .likes:
            LikesView(app: app)
        case .playlists:
            LibraryCollectionsView(kind: .playlists, app: app)
        case .albums:
            LibraryCollectionsView(kind: .albums, app: app)
        case .stations:
            StationsView(app: app)
        case .following:
            FollowingView(app: app)
        case .history:
            HistoryView(app: app)
        case .search(let query):
            SearchView(query: query, app: app)
        case .playlist(let playlist):
            CollectionDetailView(playlist: playlist, app: app)
        case .track(let track):
            let dir = app.audio.lastTransitionDirection
            ZStack {
                TrackDetailView(track: track, app: app)
                    .id(track.id)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: dir == .next ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: dir == .next ? .leading : .trailing).combined(with: .opacity)
                        )
                    )
            }
            .clipped()
        case .user(let user):
            ProfileView(user: user, app: app)
        case .settings:
            SettingsView(app: app, onSignOut: onSignOut)
        }
    }

    private func toggleSidebar() {
        withAnimation {
            columns = columns == .detailOnly ? .all : .detailOnly
        }
    }

    /// Expands the main window when opening Up Next at narrow widths so the detail view and
    /// player bar stay uncluttered, and restores the prior width on close if not manually resized.
    private func adjustWindowForQueue(visible: Bool) {
        guard let window = NSApp.windows.first(where: { $0.frameAutosaveName == "MainWindowNative" }) ?? NSApp.mainWindow,
              !window.styleMask.contains(.fullScreen) else {
            return
        }

        if visible {
            let sidebarAllowance: CGFloat = columns == .detailOnly ? 0 : 165
            let desiredMinWidth = sidebarAllowance + 560 + 320
            let screenVisible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            let targetWidth = min(desiredMinWidth, screenVisible?.width ?? desiredMinWidth)

            guard window.frame.width < targetWidth else {
                preQueueWindowWidth = nil
                return
            }

            var frame = window.frame
            let originalWidth = frame.width
            frame.size.width = targetWidth
            if let screenVisible, frame.maxX > screenVisible.maxX {
                frame.origin.x = max(screenVisible.minX, screenVisible.maxX - frame.size.width)
            }
            preQueueWindowWidth = (original: originalWidth, expanded: frame.size.width)
            window.setFrame(frame, display: true, animate: true)
        } else if let saved = preQueueWindowWidth {
            preQueueWindowWidth = nil
            if abs(window.frame.width - saved.expanded) < 6 {
                var frame = window.frame
                frame.size.width = saved.original
                window.setFrame(frame, display: true, animate: true)
            }
        }
    }
}

/// Lower-left sidebar user profile footer: click opens your profile, right-click opens the account menu.
private struct SidebarProfileFooter: View {
    @Bindable var app: AppController
    var onSignOut: () -> Void
    @State private var isHovered = false

    private var isViewingOwnProfile: Bool {
        guard let me = app.currentUser, case .user(let u) = app.router.current else { return false }
        return u.id == me.id
    }

    var body: some View {
        Button {
            if let user = app.currentUser {
                app.router.navigate(to: .user(user))
            }
        } label: {
            HStack(spacing: 9) {
                LazyImage(url: app.currentUser?.avatarURL(size: .small)) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Circle().fill(.quaternary)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                .frame(width: 26, height: 26)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))

                Text(app.currentUser?.displayName ?? app.sessionStore.session?.username ?? "Account")
                    .font(.system(size: 12.5, weight: isViewingOwnProfile ? .semibold : .medium))
                    .foregroundStyle(isViewingOwnProfile ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isViewingOwnProfile ? Color.accentColor.opacity(0.14) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let user = app.currentUser {
                Button("Profile", systemImage: "person.crop.circle") {
                    app.router.navigate(to: .user(user))
                }
            }
            Button("Settings…", systemImage: "gearshape") {
                app.router.navigate(to: .settings)
            }
            if let url = URL(string: "https://soundcloud.com/settings") {
                Button("SoundCloud Settings (Browser)", systemImage: "safari") {
                    NSWorkspace.shared.open(url)
                }
            }
            Divider()
            Button("Sign Out…", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: onSignOut)
        }
        .help("Open Profile (right-click for Settings & Sign Out)")
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

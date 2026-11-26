import SwiftUI
import WebKit

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, likes, playlists, albums, stations, following, history

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .likes: "Likes"
        case .playlists: "Playlists"
        case .albums: "Albums"
        case .stations: "Stations"
        case .following: "Following"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .likes: "heart"
        case .playlists: "music.note.list"
        case .albums: "square.stack"
        case .stations: "dot.radiowaves.left.and.right"
        case .following: "person.2"
        case .history: "clock"
        }
    }

    var path: String {
        switch self {
        case .home: "/discover"
        case .likes: "/you/likes"
        case .playlists: "/you/sets"
        case .albums: "/you/albums"
        case .stations: "/you/stations"
        case .following: "/you/following"
        case .history: "/you/history"
        }
    }

    static let library: [SidebarItem] = [.likes, .playlists, .albums, .stations, .following, .history]

    static func matching(_ path: String) -> SidebarItem? {
        let p = path.split(separator: "?").first.map(String.init) ?? path
        if p == "/" || p == "/discover" { return .home }
        return allCases.first { $0 != .home && p.hasPrefix($0.path) }
    }
}

extension Notification.Name {
    static let cpFocusSearch = Notification.Name("cpFocusSearch")
    static let cpToggleSidebar = Notification.Name("cpToggleSidebar")
}

struct MainView: View {
    @ObservedObject var player: WebPlayer
    var onMini: () -> Void
    var onSignOut: () -> Void

    /// Narrowest the page area can get: SoundCloud's inner layouts (e.g. playlist pages) need 960px.
    static let minDetailWidth: CGFloat = 960   // SoundCloud's smallest designed layout width
    static let minHeight: CGFloat = 600

    @State private var selection: SidebarItem? = .home
    /// Bound so the sidebar can always be brought back (toolbar button, ⌃⌘S) after it has
    /// been collapsed, e.g. by dragging the divider all the way in.
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        switch player.auth {
        case .signedIn:
            library
        case .signedOut:
            SignInView(player: player)
        case .unknown:   // checking the cookie store: a moment, so just an empty window
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()
                .frame(minWidth: SignInView.minWidth, minHeight: SignInView.minHeight)
        }
    }

    private var library: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $selection) {
                Section {
                    Label(SidebarItem.home.title, systemImage: SidebarItem.home.symbol).tag(SidebarItem.home)
                }
                Section("Library") {
                    ForEach(SidebarItem.library) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
            .safeAreaInset(edge: .bottom) {
                if let toast = player.toast {
                    ToastView(toast: toast) { player.toast = nil }
                        .padding(10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: player.toast)
        } detail: {
            ZStack(alignment: .bottom) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let swipe = player.pageSwipe
                    let dir: CGFloat = swipe?.direction == .previous ? -1 : 1
                    let incomingHidden = swipe != nil && swipe?.incomingReady == false
                    let webOffset: CGFloat = incomingHidden ? dir * w * 0.32 : 0
                    let snapOffset: CGFloat = swipe?.outgoingExited == true ? -dir * w : 0

                    ZStack {
                        Color(nsColor: .textBackgroundColor)
                        WebViewHost(webView: player.webView)
                            .overlay(alignment: .topLeading) {
                                ZStack(alignment: .topLeading) {
                                    Color.clear
                                    if let hp = player.hoverPlay {
                                        HoverPlayButton(
                                            isPlaying: hp.isPlaying,
                                            size: hp.size,
                                            onHoverChange: { player.isHoveringPlayButton = $0 },
                                            action: { player.triggerHoverPlay() }
                                        )
                                        .offset(x: hp.x - hp.size / 2, y: hp.y - hp.size / 2)
                                        .id("\(hp.x),\(hp.y)")
                                        .transition(.opacity)
                                    }
                                }
                                .clipped()
                                .allowsHitTesting(player.hoverPlay != nil)
                                .animation(.easeOut(duration: 0.1), value: player.hoverPlay.map { "\($0.x),\($0.y)" })
                            }
                            .offset(x: webOffset)
                            .opacity(incomingHidden ? 0 : 1)

                        if let swipe {
                            Image(nsImage: swipe.snapshot)
                                .resizable()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .offset(x: snapOffset)
                                .opacity(swipe.outgoingExited ? 0.35 : 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .clipped()
                }
                // Floating capsule player (Apple Music style). When Up Next is open it
                // re-centres on the remaining page width (the queue column is 340pt).
                PlayerBar(player: player, onMini: onMini)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                    .padding(.trailing, player.state.queueVisible ? 340 : 0)
                    .animation(.easeOut(duration: 0.25), value: player.state.queueVisible)
            }
            .frame(minWidth: Self.minDetailWidth, minHeight: Self.minHeight)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: toggleSidebar) { Label("Toggle Sidebar", systemImage: "sidebar.left") }
                        .help("Show or Hide Sidebar (⌃⌘S)")
                }
                ToolbarItemGroup(placement: .navigation) {
                    Button { player.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                        .disabled(!player.canGoBack)
                        .help("Back")
                    Button { player.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                        .disabled(!player.canGoForward)
                        .help("Forward")
                }
                ToolbarItem(placement: .principal) {   // centred in the toolbar
                    ToolbarSearchField(prompt: "Search SoundCloud") { player.search($0) }
                        .frame(width: 360)
                }
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.flexible)   // pushes the account menu to the trailing edge
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Profile") { player.open(player.profilePath) }
                            .disabled(player.profilePath.isEmpty)
                        Button("Settings") { player.open("/settings") }
                        Divider()
                        Button("Sign Out…", action: onSignOut)
                    } label: {
                        Label("Account", systemImage: "person.crop.circle")
                    }
                    .menuIndicator(.hidden)
                    .help("Account")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cpToggleSidebar)) { _ in toggleSidebar() }
        .onChange(of: selection) { _, item in
            guard let item, SidebarItem.matching(player.currentPath) != item else { return }
            player.open(item.path)
        }
        .onChange(of: player.currentPath) { _, path in
            let item = SidebarItem.matching(path)
            if item != selection { selection = item }
        }
    }
}

/// Signed out: an otherwise empty window with SoundCloud's own sign-in form (restyled, see
/// Theme.authCSS) in the middle. No sidebar, toolbar or player until there is a session.
struct SignInView: View {
    @ObservedObject var player: WebPlayer

    static let minWidth: CGFloat = 520
    static let minHeight: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .padding(.bottom, 4)
                Text("Welcome to CloudPlayer")
                    .font(.system(size: 22, weight: .bold))
                Text("Sign in with your SoundCloud account to start listening.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 22)

            // The shared web view (it must never be recreated), showing only the sign-in form.
            ZStack {
                WebViewHost(webView: player.webView)
                    .opacity(player.signInReady ? 1 : 0)
                if !player.signInReady {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 400)
            .frame(minHeight: 360, maxHeight: 540)
            .animation(.easeOut(duration: 0.25), value: player.signInReady)

            Spacer(minLength: 12)
            Text("Unofficial. Not affiliated with or endorsed by SoundCloud.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
        .frame(minWidth: Self.minWidth, minHeight: Self.minHeight)
    }
}

extension MainView {
    private func toggleSidebar() {
        withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
    }
}

/// SoundCloud's notifications as a small card at the bottom of the sidebar. Click to dismiss.
struct ToastView: View {
    let toast: Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let url = toast.artworkURL {
                Artwork(url: url, size: 38, cornerRadius: 6)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20)).foregroundStyle(.tint)
            }
            Text(toast.text)
                .font(.system(size: 12))
                .lineSpacing(2)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: 58)
        .modifier(ToastBackground())
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(toast.text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ToastBackground: ViewModifier {
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

/// Native NSSearchField for the toolbar: Return searches, ⌘F (Edit ▸ Search) focuses it.
struct ToolbarSearchField: NSViewRepresentable {
    let prompt: String
    let onSubmit: (String) -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsWholeSearchString = true      // act on Return, not on every keystroke
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        context.coordinator.observe(field)
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSubmit: onSubmit) }

    final class Coordinator: NSObject {
        var onSubmit: (String) -> Void
        private var token: NSObjectProtocol?
        init(onSubmit: @escaping (String) -> Void) { self.onSubmit = onSubmit }

        @objc func submit(_ sender: NSSearchField) {
            let q = sender.stringValue.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty { onSubmit(q) }
        }

        func observe(_ field: NSSearchField) {
            token = NotificationCenter.default.addObserver(forName: .cpFocusSearch, object: nil, queue: .main) { [weak field] _ in
                guard let field else { return }
                field.window?.makeFirstResponder(field)
            }
        }

        deinit { token.map(NotificationCenter.default.removeObserver) }
    }
}

/// Hosts the single shared WKWebView (it must never be recreated: it is the audio engine).
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Native macOS 26 Liquid Glass play/pause button floated over the currently hovered tile.
private struct HoverPlayButton: View {
    let isPlaying: Bool
    let size: CGFloat
    let onHoverChange: (Bool) -> Void
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .offset(x: isPlaying ? 0 : size * 0.03)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(HoverPlayGlass())
        .modifier(PointingHandCursor())
        .scaleEffect(hovering ? 1.05 : 1.0)
        .animation(.spring(duration: 0.2, bounce: 0.25), value: hovering)
        .onHover { over in
            hovering = over
            onHoverChange(over)
        }
        .onDisappear { onHoverChange(false) }
    }
}

private struct HoverPlayGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
    }
}

private struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.link)
        } else {
            content
        }
    }
}

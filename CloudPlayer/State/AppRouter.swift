import Foundation
import Observation

enum NativeSidebarItem: String, CaseIterable, Identifiable, Hashable, Sendable {
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

    var route: NativeRoute {
        switch self {
        case .home: .home
        case .likes: .likes
        case .playlists: .playlists
        case .albums: .albums
        case .stations: .stations
        case .following: .following
        case .history: .history
        }
    }

    static let library: [NativeSidebarItem] = [.likes, .playlists, .albums, .stations, .following, .history]
}

enum NativeRoute: Hashable, Sendable {
    case home
    case likes
    case playlists
    case albums
    case stations
    case following
    case history
    case search(String)
    case track(SCTrack)
    case playlist(SCPlaylist)
    case user(SCUser)
    case settings

    var sidebarItem: NativeSidebarItem? {
        switch self {
        case .home: .home
        case .likes: .likes
        case .playlists: .playlists
        case .albums: .albums
        case .stations: .stations
        case .following: .following
        case .history: .history
        case .search, .track, .playlist, .user, .settings: nil
        }
    }
}

/// Typed navigation router with full browser-style Back/Forward history.
@MainActor
@Observable
final class AppRouter {
    private(set) var current: NativeRoute
    private(set) var backStack: [NativeRoute] = []
    private(set) var forwardStack: [NativeRoute] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var selectedSidebar: NativeSidebarItem? { current.sidebarItem }

    init(initial: NativeRoute = .likes) {
        self.current = initial
    }

    func navigate(to route: NativeRoute) {
        guard route != current else { return }
        backStack.append(current)
        if backStack.count > 100 { backStack.removeFirst(backStack.count - 100) }
        forwardStack.removeAll()
        current = route
    }

    /// Replaces the current route without adding a history entry (used when Track Detail follows Now Playing).
    func replaceCurrent(with route: NativeRoute) {
        guard route != current else { return }
        current = route
    }

    func selectSidebar(_ item: NativeSidebarItem) {
        navigate(to: item.route)
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        navigate(to: .search(trimmed))
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(current)
        current = prev
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(current)
        current = next
    }

    func reset(to route: NativeRoute = .likes) {
        backStack.removeAll()
        forwardStack.removeAll()
        current = route
    }
}

import Foundation

enum PlaybackRepeatMode: String, Codable, Equatable, Sendable {
    case none
    case one
    case all

    var next: PlaybackRepeatMode {
        switch self {
        case .none: .all
        case .all: .one
        case .one: .none
        }
    }
}

enum PreviousTrackAction: Equatable, Sendable {
    case none
    case restartCurrent
    case switchTo(SCTrack)
}

/// Pure-Swift value-type playback queue state machine.
///
/// Separates explicitly queued tracks (`userUpNext`) from the active listening context
/// (`contextQueue`, e.g., Likes or a Playlist) and lazy related tracks (`autoplayQueue`).
struct PlaybackQueue: Equatable, Sendable {
    private(set) var history: [SCTrack] = []
    private(set) var current: SCTrack?
    private(set) var userUpNext: [SCTrack] = []
    private(set) var contextQueue: [SCTrack] = []
    private(set) var autoplayQueue: [SCTrack] = []
    private(set) var contextTitle: String?

    private(set) var shuffle: Bool = false
    private(set) var repeatMode: PlaybackRepeatMode = .none
    var autoplayEnabled: Bool = true

    /// Preserves the original unshuffled context so toggling shuffle off restores order cleanly.
    private var unshuffledContext: [SCTrack] = []
    private var fullContextSnapshot: [SCTrack] = []

    var nextUpPreview: SCTrack? {
        if let first = userUpNext.first { return first }
        if let first = contextQueue.first { return first }
        if repeatMode == .all, let first = fullContextSnapshot.first { return first }
        if autoplayEnabled, let first = autoplayQueue.first { return first }
        return nil
    }

    var upcomingCount: Int {
        userUpNext.count + contextQueue.count + (autoplayEnabled ? autoplayQueue.count : 0)
    }

    /// Starts playing `track` within `context` (e.g., clicking row N in Likes or a Playlist).
    mutating func play(track: SCTrack, inContext context: [SCTrack], contextTitle: String? = nil) {
        if let prev = current, prev.id != track.id {
            history.append(prev)
            if history.count > 200 { history.removeFirst(history.count - 200) }
        }
        self.current = track
        self.contextTitle = contextTitle
        self.autoplayQueue = []
        self.fullContextSnapshot = context.isEmpty ? [track] : context

        let remaining: [SCTrack]
        if let idx = context.firstIndex(where: { $0.id == track.id }) {
            remaining = Array(context.dropFirst(idx + 1))
        } else {
            remaining = context.filter { $0.id != track.id }
        }
        self.unshuffledContext = remaining
        self.contextQueue = shuffle ? remaining.shuffled() : remaining
    }

    /// Starts a shuffled session from `tracks`.
    mutating func playShuffled(tracks: [SCTrack], contextTitle: String? = nil) {
        guard !tracks.isEmpty else { return }
        shuffle = true
        let shuffled = tracks.shuffled()
        let first = shuffled[0]
        if let prev = current, prev.id != first.id {
            history.append(prev)
        }
        current = first
        self.contextTitle = contextTitle
        autoplayQueue = []
        fullContextSnapshot = tracks
        unshuffledContext = tracks.filter { $0.id != first.id }
        contextQueue = Array(shuffled.dropFirst())
    }

    mutating func enqueueNext(_ track: SCTrack) {
        userUpNext.insert(track, at: 0)
    }

    mutating func enqueueLater(_ track: SCTrack) {
        userUpNext.append(track)
    }

    mutating func setAutoplayTracks(_ tracks: [SCTrack]) {
        let existingIDs = Set(([current].compactMap { $0 } + history + userUpNext + contextQueue).map(\.id))
        autoplayQueue = tracks.filter { !existingIDs.contains($0.id) }
    }

    mutating func advance(manual: Bool) -> SCTrack? {
        if !manual, repeatMode == .one, let current {
            return current
        }
        if let prev = current {
            history.append(prev)
            if history.count > 200 { history.removeFirst(history.count - 200) }
        }

        if !userUpNext.isEmpty {
            let next = userUpNext.removeFirst()
            current = next
            return next
        }

        if !contextQueue.isEmpty {
            let next = contextQueue.removeFirst()
            unshuffledContext.removeAll { $0.id == next.id }
            current = next
            return next
        }

        if repeatMode == .all, !fullContextSnapshot.isEmpty {
            let pool = shuffle ? fullContextSnapshot.shuffled() : fullContextSnapshot
            let next = pool[0]
            current = next
            unshuffledContext = Array(fullContextSnapshot.dropFirst())
            contextQueue = Array(pool.dropFirst())
            return next
        }

        if autoplayEnabled, !autoplayQueue.isEmpty {
            let next = autoplayQueue.removeFirst()
            current = next
            return next
        }

        return nil
    }

    mutating func previous(currentPosition: Double) -> PreviousTrackAction {
        guard let cur = current else { return .none }
        if currentPosition > 3.5 || history.isEmpty {
            return .restartCurrent
        }
        let prev = history.removeLast()
        contextQueue.insert(cur, at: 0)
        unshuffledContext.insert(cur, at: 0)
        current = prev
        return .switchTo(prev)
    }

    mutating func toggleShuffle() {
        shuffle.toggle()
        if shuffle {
            contextQueue = unshuffledContext.shuffled()
        } else {
            contextQueue = unshuffledContext
        }
    }

    mutating func cycleRepeat() {
        repeatMode = repeatMode.next
    }

    mutating func moveUserUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        moveElements(in: &userUpNext, fromOffsets: source, toOffset: destination)
    }

    mutating func removeUserUpNext(at offsets: IndexSet) {
        for idx in offsets.sorted(by: >) where userUpNext.indices.contains(idx) {
            userUpNext.remove(at: idx)
        }
    }

    mutating func removeFromContext(at offsets: IndexSet) {
        for idx in offsets.sorted(by: >) where contextQueue.indices.contains(idx) {
            let removed = contextQueue.remove(at: idx)
            unshuffledContext.removeAll { $0.id == removed.id }
        }
    }

    mutating func clearUpcoming() {
        userUpNext.removeAll()
        contextQueue.removeAll()
        unshuffledContext.removeAll()
        autoplayQueue.removeAll()
    }

    private func moveElements(in array: inout [SCTrack], fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().compactMap { array.indices.contains($0) ? array[$0] : nil }
        for idx in source.sorted(by: >) where array.indices.contains(idx) {
            array.remove(at: idx)
        }
        let adjustedDest = destination - source.filter { $0 < destination }.count
        let clamped = min(max(adjustedDest, 0), array.count)
        array.insert(contentsOf: moving, at: clamped)
    }
}
